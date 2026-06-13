import Foundation
import os

/// Resolves the environment a child process should start from.
///
/// GUI apps inherit launchd's anemic `PATH`, so we capture the user's
/// login-shell environment once (`$SHELL -l -c env`) and cache it. The capture
/// can be slow or even hang on a pathological shell profile, so it runs off the
/// main actor with a hard timeout and a sane fallback — it must never freeze
/// the UI.
public actor EnvResolver {
    private static let log = Logger(subsystem: "com.tarantsov.Longrun", category: "EnvResolver")

    /// Printed before the env dump so we can discard profile noise that lands
    /// on stdout ahead of it (VS Code's marker approach).
    static let marker = "__LONGRUN_ENV_8f3a2b__"

    /// PATH used when capture fails — covers Homebrew (Intel + Apple Silicon)
    /// and the system locations.
    static let fallbackPATH = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    private let shellPath: String
    private let timeout: Duration
    private var cached: [String: String]?

    public init(shellPath: String? = nil, timeout: Duration = .seconds(10)) {
        self.shellPath = shellPath ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.timeout = timeout
    }

    /// The resolved login-shell environment plus terminal defaults, captured
    /// once and cached. Returns the fallback environment if capture fails or
    /// times out.
    public func resolved() async -> [String: String] {
        if let cached { return cached }

        let command = "printf %s '\(Self.marker)'; exec /usr/bin/env -0"
        let captured = await Self.capture(
            executableURL: URL(fileURLWithPath: shellPath),
            arguments: ["-l", "-c", command],
            timeout: timeout
        )
        var env: [String: String]
        if let captured {
            env = captured
        } else {
            // Observable per the debuggability lens — a wrong PATH from a silent
            // fallback is otherwise undiagnosable. No env contents are logged.
            Self.log.notice("login-shell env capture failed; using fallback environment with canonical PATH")
            env = Self.fallbackEnvironment()
        }

        // A child under a PTY should see a sane terminal env. Set only if the
        // login env didn't already provide them — don't clobber the user's.
        if env["TERM"] == nil { env["TERM"] = "xterm-256color" }
        if env["COLORTERM"] == nil { env["COLORTERM"] = "truecolor" }
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }

        cached = env
        return env
    }

    /// `ProcessInfo`'s environment with PATH forced to the canonical list.
    static func fallbackEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = fallbackPATH
        return env
    }

    /// Spawn `executableURL` with `arguments`, read its stdout to EOF, and parse
    /// the marker-delimited NUL-separated environment. Returns nil on launch
    /// failure, nonzero/signalled exit (incl. the timeout SIGKILL), or empty
    /// output. Runs entirely off the calling executor.
    static func capture(executableURL: URL, arguments: [String], timeout: Duration) async -> [String: String]? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: runBlocking(executableURL: executableURL, arguments: arguments, timeout: timeout))
            }
        }
    }

    private static func runBlocking(executableURL: URL, arguments: [String], timeout: Duration) -> [String: String]? {
        // Own the pipe via raw fds and read it with poll()'s own deadline. A
        // backgrounded grandchild from the login profile can keep the write end
        // open past the SIGKILL (a plain readDataToEndOfFile would hang there
        // forever); poll bounds the wait without ever closing the fd from
        // another thread — which would risk an fd-recycling race in this
        // multi-threaded app. Every fd touch stays on this one thread.
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else {
            log.error("env capture: pipe() failed")
            return nil
        }
        let readFD = fds[0], writeFD = fds[1]

        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = arguments
        proc.standardOutput = FileHandle(fileDescriptor: writeFD, closeOnDealloc: false)
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            close(readFD); close(writeFD)
            log.error("env capture: failed to launch \(executableURL.path, privacy: .public)")
            return nil
        }
        close(writeFD)  // parent never writes; only the child should hold the write end
        let pid = proc.processIdentifier

        let deadline = DispatchTime.now().uptimeNanoseconds &+ UInt64(timeout.seconds * 1e9)
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 64 * 1024)
        var timedOut = false
        let interest = Int16(POLLIN | POLLHUP)
        readLoop: while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { timedOut = true; break }
            let remainingMs = Int32(clamping: (deadline - now) / 1_000_000)
            var pfd = pollfd(fd: readFD, events: Int16(POLLIN), revents: 0)
            let pr = poll(&pfd, 1, max(remainingMs, 1))
            if pr == 0 { timedOut = true; break }
            if pr < 0 { if errno == EINTR { continue }; break }
            guard pfd.revents & interest != 0 else { break }  // POLLERR / POLLNVAL
            let n = read(readFD, &buf, buf.count)
            if n > 0 { data.append(contentsOf: buf[0..<n]) }
            else if n == 0 { break }                 // EOF — child closed the write end
            else if errno == EINTR { continue }
            else { break }                            // read error
        }
        if timedOut { kill(pid, SIGKILL) }
        close(readFD)
        proc.waitUntilExit()  // reaps `proc` only — never waits on the orphan

        guard !timedOut else {
            log.notice("env capture timed out")
            return nil
        }
        guard proc.terminationReason == .exit else {
            log.notice("env capture was signalled")
            return nil
        }
        guard proc.terminationStatus == 0 else {
            log.notice("env capture exited with status \(proc.terminationStatus)")
            return nil
        }
        guard !data.isEmpty else {
            log.notice("env capture produced no output")
            return nil
        }
        let env = parseEnvironment(data)
        if env.isEmpty { log.notice("env capture produced no parseable environment") }
        return env.isEmpty ? nil : env
    }

    /// Parse the capture output: discard everything up to and including the
    /// marker (profile noise), then split on NUL and keep `KEY=VALUE` pairs
    /// with a non-empty key. Values may legitimately contain newlines.
    static func parseEnvironment(_ data: Data) -> [String: String] {
        let payload: Data
        if let range = data.range(of: Data(marker.utf8)) {
            payload = data.subdata(in: range.upperBound..<data.endIndex)
        } else {
            payload = data
        }

        var env: [String: String] = [:]
        for entry in payload.split(separator: 0) {
            let s = String(decoding: entry, as: UTF8.self)
            guard let eq = s.firstIndex(of: "="), eq != s.startIndex else { continue }
            env[String(s[..<eq])] = String(s[s.index(after: eq)...])
        }
        return env
    }
}

private extension Duration {
    /// The duration as seconds, for `DispatchQueue.asyncAfter`.
    var seconds: Double {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
