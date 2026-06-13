import Foundation
import os

/// How a child process ended. Populated in ST8 (exit detection); defined here
/// because ProcessRunner owns the process.
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

/// Spawns one child process under a pseudo-terminal and streams its output.
///
/// Exit detection and group teardown are added in ST8; this class owns the pid
/// (== process-group id, since the child is a session leader) and the master fd
/// for those.
public final class ProcessRunner {
    private static let log = Logger(subsystem: "com.tarantsov.Longrun", category: "ProcessRunner")
    private static let readChunkSize = 64 * 1024
    /// Bounds the output buffer (~16 MB at full chunks). Under a sustained flood
    /// with a slow consumer the oldest chunks drop rather than risk OOM — the
    /// terminal scrollback and the matcher both tolerate that, and a flood is
    /// degenerate. True kernel-backpressure is a deferred refinement.
    private static let maxBufferedChunks = 256

    /// The child's pid, which is also its process-group id (it's a session
    /// leader). ST8 group-kills `-pid`.
    public let pid: pid_t
    /// The PTY master, kept for ST8 (resize / lifecycle). Closed by the read
    /// source's cancel handler on EOF.
    let master: Int32
    public let output: AsyncStream<Data>

    private let readSource: DispatchSourceRead

    public init(_ request: SpawnRequest) throws {
        let (pid, master) = try Self.spawn(request)
        self.pid = pid
        self.master = master

        var continuation: AsyncStream<Data>.Continuation!
        self.output = AsyncStream(bufferingPolicy: .bufferingNewest(Self.maxBufferedChunks)) {
            continuation = $0
        }
        let cont = continuation!

        let queue = DispatchQueue(label: "com.tarantsov.Longrun.ProcessRunner.read")
        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        let fd = master  // capture the fd, never self
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: Self.readChunkSize)
            let n = read(fd, &buffer, buffer.count)
            if n > 0 {
                cont.yield(Data(buffer[0..<n]))
            } else if n == 0 {
                source.cancel()  // EOF — the child closed (all copies of) the slave
            } else if errno != EAGAIN && errno != EINTR {
                Self.log.error("read error on PTY master (errno \(errno))")
                source.cancel()  // a real read error
            }
        }
        source.setCancelHandler {
            close(fd)
            cont.finish()
        }
        self.readSource = source
        source.activate()
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
        return (pid, master)
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
