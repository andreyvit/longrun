import Foundation
import os

/// How a child process ended.
public enum ProcessExit: Equatable, Sendable {
    case code(Int32)    // exited with this status
    case signal(Int32)  // terminated by this signal
}

/// Everything ProcessRunner needs to spawn one process. The command has already
/// been resolved (executable path, argv, environment) by the caller — this
/// layer is purely about spawning it under a PTY.
public struct SpawnRequest: Sendable {
    public var executablePath: String       // absolute / slash path the child execs
    public var arguments: [String]          // argv after the program name
    public var environment: [String: String]
    public var workingDirectory: String     // "" = inherit (helper won't chdir)
    public var helperURL: URL               // the bundled longrun-spawn-helper
    public var columns: Int
    public var rows: Int

    public init(
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: String = "",
        helperURL: URL,
        columns: Int = 80,
        rows: Int = 24
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.helperURL = helperURL
        self.columns = columns
        self.rows = rows
    }
}

public enum ProcessRunnerError: Error, Equatable {
    case ptyOpenFailed(Int32)
    case spawnFailed(Int32)  // posix_spawn errno
}

/// Spawns one child process under a pseudo-terminal, streams its output, detects
/// its exit, and tears down its process group on `stop()`.
///
/// The caller MUST `stop()` a runner before dropping it: `deinit` releases the
/// PTY/sources but does not kill the child (the zero-orphans guarantee is
/// enforced by RunSession / quit teardown calling `stop()`).
public final class ProcessRunner: @unchecked Sendable {
    // @unchecked: every stored property is an immutable `let` pointing at a
    // thread-safe object (the NSLock-guarded ExitNotifier, the dispatch sources,
    // the Sendable AsyncStream), and the methods only touch those — so it's safe
    // to use across actors even though `Sendable` can't be auto-verified through
    // the dispatch-source types.
    private static let log = Logger(subsystem: "com.tarantsov.Longrun", category: "ProcessRunner")
    private static let readChunkSize = 64 * 1024
    /// Bounds the output buffer (~16 MB at full chunks). Under a sustained flood
    /// with a slow consumer the oldest chunks drop rather than risk OOM — the
    /// terminal scrollback and the matcher both tolerate that, and a flood is
    /// degenerate. True kernel-backpressure is a deferred refinement.
    private static let maxBufferedChunks = 256
    public static let defaultStopGrace: Duration = .seconds(5)
    private static let stopPollInterval: Duration = .milliseconds(20)

    /// The child's pid, which is also its process-group id (it's a session
    /// leader). `stop()` group-kills `-pid`.
    public let pid: pid_t
    /// The PTY master. Closed by the read source's cancel handler on EOF.
    private let master: Int32
    public let output: AsyncStream<Data>

    private let readSource: DispatchSourceRead
    private let exitSource: DispatchSourceProcess
    private let exitNotifier = ExitNotifier()

    public init(_ request: SpawnRequest) throws {
        let (pid, master) = try Self.spawn(request)
        self.pid = pid
        self.master = master

        let queue = DispatchQueue(label: "com.tarantsov.Longrun.ProcessRunner")

        var continuation: AsyncStream<Data>.Continuation!
        self.output = AsyncStream(bufferingPolicy: .bufferingNewest(Self.maxBufferedChunks)) {
            continuation = $0
        }
        let cont = continuation!

        // Read the master into the bounded stream. Captures fd + continuation,
        // never self.
        let readSource = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        let fd = master
        readSource.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: Self.readChunkSize)
            let n = read(fd, &buffer, buffer.count)
            if n > 0 {
                cont.yield(Data(buffer[0..<n]))
            } else if n == 0 {
                readSource.cancel()  // EOF — the child closed (all copies of) the slave
            } else if errno != EAGAIN && errno != EINTR {
                Self.log.error("read error on PTY master (errno \(errno))")
                readSource.cancel()  // a real read error
            }
        }
        readSource.setCancelHandler {
            close(fd)
            cont.finish()
        }
        self.readSource = readSource

        // Detect the child's exit. Fires even if the child already exited (as
        // long as it's unreaped — we never reap elsewhere). Captures the
        // notifier + pid, never self.
        let exitSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        let notifier = exitNotifier
        let childPid = pid
        exitSource.setEventHandler {
            notifier.markReaping()  // before waitpid: the pid is about to be reaped (and reusable)
            var status: Int32 = 0
            waitpid(childPid, &status, 0)  // reap; returns immediately for an exited child
            let exit = Self.decodeExit(status)
            Self.log.notice("pid \(childPid) exited (\(String(describing: exit), privacy: .public))")
            notifier.complete(exit)
            exitSource.cancel()
        }
        self.exitSource = exitSource

        readSource.activate()
        exitSource.activate()
    }

    deinit {
        // Idempotent with the fire paths; closes the master and breaks the read
        // handler's self-retain if the runner is dropped before EOF/exit.
        readSource.cancel()
        exitSource.cancel()
    }

    // MARK: lifecycle

    /// The child's exit, or nil while it's still running.
    public var exitStatus: ProcessExit? { exitNotifier.current }

    /// Suspends until the child exits, returning how it ended.
    public func waitForExit() async -> ProcessExit {
        await exitNotifier.wait()
    }

    /// Update the terminal size (delivers SIGWINCH to the child via the ctty).
    public func resize(columns: Int, rows: Int) {
        guard exitNotifier.current == nil else { return }  // dead process: nothing to resize
        PTY.setWinSize(master, columns: columns, rows: rows)
    }

    /// SIGTERM the child's process group, wait up to `grace`, then SIGKILL if
    /// it's still alive. Group-kill catches grandchildren (e.g. `go run`'s
    /// child binary, wrapper shells). Safe to call after the child has exited.
    public func stop(grace: Duration = ProcessRunner.defaultStopGrace) async {
        if exitNotifier.isSettled { return }
        Self.log.notice("pid \(self.pid): SIGTERM to process group")
        terminateGroup(SIGTERM)
        if await settledWithin(grace) { return }
        Self.log.notice("pid \(self.pid): grace expired, SIGKILL to process group")
        terminateGroup(SIGKILL)
        _ = await exitNotifier.wait()  // SIGKILL is immediate; the exit source reaps
    }

    private func terminateGroup(_ signal: Int32) {
        if kill(-pid, signal) != 0 && errno == ESRCH {
            // The process group isn't formed yet (a brief window after spawn);
            // signal the pid directly.
            Self.log.notice("pid \(self.pid): process group not formed, signalling pid directly")
            _ = kill(pid, signal)
        }
    }

    /// Wait up to `grace` for the child to start exiting. Gates on
    /// `isSettled` (set *before* the reap) rather than the exit result, so the
    /// caller never escalates to SIGKILL after the pid has been reaped — by the
    /// time `settledWithin` returns false the child is provably still alive and
    /// its process group is still ours.
    private func settledWithin(_ grace: Duration) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: grace)
        while !exitNotifier.isSettled {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: Self.stopPollInterval)
        }
        return true
    }

    /// Decode a `waitpid` status into a `ProcessExit`. Valid only for a
    /// TERMINATED child (exited or signalled) — the status from `waitpid(…, 0)`
    /// reaped on a `.exit` event. We never request stops (no `WUNTRACED`), so a
    /// stopped status (whose low 7 bits are `0o177`) can't reach here; it would
    /// be mislabelled as `.signal(127)`. The `W*` macros aren't imported into
    /// Swift, so do the bit-twiddling by hand.
    static func decodeExit(_ status: Int32) -> ProcessExit {
        if status & 0o177 == 0 {
            return .code((status >> 8) & 0xff)
        } else {
            return .signal(status & 0o177)
        }
    }

    // MARK: spawn

    private static func spawn(_ request: SpawnRequest) throws -> (pid: pid_t, master: Int32) {
        let (master, slave): (Int32, Int32)
        do {
            (master, slave) = try PTY.open(columns: request.columns, rows: request.rows)
        } catch let PTY.PTYError.openFailed(err) {
            log.error("openpty failed (errno \(err))")
            throw ProcessRunnerError.ptyOpenFailed(err)
        }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_adddup2(&fileActions, slave, 0)
        posix_spawn_file_actions_adddup2(&fileActions, slave, 1)
        posix_spawn_file_actions_adddup2(&fileActions, slave, 2)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // SETSID: new session (so the helper's tty open acquires a ctty).
        // CLOEXEC_DEFAULT: nothing but the duped slave leaks into the child
        // (the master never reaches it). SETSIGDEF/SETSIGMASK: a clean signal
        // state for the child regardless of ours.
        let flags = Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT
                          | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        posix_spawnattr_setflags(&attributes, flags)
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)

        // argv = [helper, cwd, exe, args...]; the helper execvp's argv[2...].
        let argvStrings = [request.helperURL.path, request.workingDirectory, request.executablePath]
            + request.arguments
        let envStrings = request.environment.map { "\($0.key)=\($0.value)" }

        var pid: pid_t = 0
        let rc = withCStringArray(argvStrings) { argv in
            withCStringArray(envStrings) { envp in
                posix_spawn(&pid, request.helperURL.path, &fileActions, &attributes, argv, envp)
            }
        }
        // The parent doesn't write to or hold the slave; closing it means the
        // master sees EOF once the child closes its copies.
        close(slave)
        guard rc == 0 else {
            close(master)
            log.error("posix_spawn failed (errno \(rc)) for \(request.executablePath, privacy: .public)")
            throw ProcessRunnerError.spawnFailed(rc)
        }
        log.notice("spawned pid \(pid) for \(request.executablePath, privacy: .public)")
        return (pid, master)
    }
}

/// Stores a process's exit once and resumes anyone awaiting it. Thread-safe so
/// the exit-source queue and `waitForExit()` callers can both touch it.
private final class ExitNotifier: @unchecked Sendable {
    private let lock = NSLock()
    private var result: ProcessExit?
    private var reaping = false
    private var waiters: [CheckedContinuation<ProcessExit, Never>] = []

    var current: ProcessExit? {
        lock.lock(); defer { lock.unlock() }
        return result
    }

    /// True once the child is exiting — `reaping` is set BEFORE the `waitpid`
    /// reap, so a caller gating a group-kill on this never signals a pid that's
    /// already been reaped (and possibly recycled).
    var isSettled: Bool {
        lock.lock(); defer { lock.unlock() }
        return reaping || result != nil
    }

    /// Called at the very start of the exit handler, before reaping.
    func markReaping() {
        lock.lock(); defer { lock.unlock() }
        reaping = true
    }

    func complete(_ exit: ProcessExit) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }  // first completion wins
        result = exit
        let pending = waiters
        waiters = []
        lock.unlock()
        for waiter in pending { waiter.resume(returning: exit) }
    }

    func wait() async -> ProcessExit {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}

/// Marshal `[String]` into a NULL-terminated C string array for posix_spawn,
/// freeing the duplicated strings after `body` returns.
private func withCStringArray<R>(_ strings: [String], _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
    var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
    pointers.append(nil)
    defer { for p in pointers { free(p) } }  // free(NULL) is a no-op
    return pointers.withUnsafeBufferPointer { body($0.baseAddress!) }
}
