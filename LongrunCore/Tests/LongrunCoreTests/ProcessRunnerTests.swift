import Foundation
import Testing
@testable import LongrunCore

@Suite(.serialized, .timeLimit(.minutes(1))) struct ProcessRunnerTests {

    static var helperURL: URL { SpawnHelperFixture.url }

    private static let baseEnv = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TERM": "xterm"]

    /// Spawn a command and return all of its output as a string (the stream
    /// finishes on the child's EOF).
    private func run(
        _ executablePath: String, _ arguments: [String],
        env: [String: String] = baseEnv, cwd: String = "", columns: Int = 80, rows: Int = 24
    ) async throws -> String {
        let runner = try ProcessRunner(SpawnRequest(
            executablePath: executablePath, arguments: arguments, environment: env,
            workingDirectory: cwd, helperURL: Self.helperURL, columns: columns, rows: rows
        ))
        var data = Data()
        for await chunk in runner.output { data.append(chunk) }
        return String(decoding: data, as: UTF8.self)
    }

    @Test func capturesStdout() async throws {
        let out = try await run("/bin/sh", ["-c", "echo hello world"])
        #expect(out.contains("hello world"))
    }

    @Test func childStdoutIsATTY() async throws {
        let out = try await run("/bin/sh", ["-c", "test -t 1 && echo IS_A_TTY"])
        #expect(out.contains("IS_A_TTY"))
    }

    @Test func childHasControllingTerminal() async throws {
        // zsh does NOT self-attach a ctty, so opening /dev/tty succeeds only
        // because the helper acquired the controlling terminal for the session.
        let out = try await run("/bin/zsh", ["-c", ": > /dev/tty && echo HAS_CTTY || echo NO_CTTY"])
        #expect(out.contains("HAS_CTTY"))
        #expect(!out.contains("NO_CTTY"))
    }

    @Test func initialWindowSizeIsDelivered() async throws {
        let out = try await run("/bin/sh", ["-c", "stty size"], columns: 120, rows: 40)
        #expect(out.contains("40 120"))  // stty prints "rows cols"
    }

    @Test func honorsWorkingDirectory() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "lr-cwd-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let out = try await run("/bin/sh", ["-c", "pwd"], cwd: dir.path)
        // /var symlinks to /private/var; the unique component survives realpath.
        #expect(out.contains(dir.lastPathComponent))
    }

    @Test func passesEnvironmentToChild() async throws {
        var env = Self.baseEnv
        env["LONGRUN_TEST"] = "value-7f3a"
        let out = try await run("/bin/sh", ["-c", "echo $LONGRUN_TEST"], env: env)
        #expect(out.contains("value-7f3a"))
    }

    @Test func reassemblesOutputSplitAcrossReads() async throws {
        // ~580 KB — well over the 64 KB read size, so multiple read() events
        // fire and must reassemble in order.
        let out = try await run("/bin/sh", ["-c", "seq 1 100000"])
        let numbers = out.split(whereSeparator: \.isNewline).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        #expect(numbers.first == 1)
        #expect(numbers.last == 100000)
        #expect(numbers.count == 100000)
    }

    @Test func capturesStderr() async throws {
        // stderr is duped to the same slave PTY, so it surfaces in output.
        let out = try await run("/bin/sh", ["-c", "echo to-stderr >&2"])
        #expect(out.contains("to-stderr"))
    }

    @Test func capturesOutputWithNoTrailingNewline() async throws {
        let out = try await run("/bin/sh", ["-c", "printf no-newline-here"])
        #expect(out == "no-newline-here")
    }

    @Test func childGatesColorOnIsatty() async throws {
        // A real program emits ANSI color only when stdout is a TTY; under the
        // PTY it is, so the escape must appear.
        let out = try await run("/bin/sh", ["-c", #"test -t 1 && printf '\033[31mRED\033[0m'"#])
        #expect(out.contains("\u{1B}[31m"))
        #expect(out.contains("RED"))
    }

    @Test func streamFinishesWhenChildExits() async throws {
        // If the stream didn't finish on EOF this would hang past the suite's
        // time limit; reaching the assertion proves termination.
        let out = try await run("/bin/sh", ["-c", "echo done"])
        #expect(out.contains("done"))
    }

    @Test func missingExecutableReportsAndFinishes() async throws {
        // The helper's execvp fails; it writes a diagnostic to the PTY and
        // _exit(127)s.
        let runner = try makeRunner("/nonexistent/longrun-binary-xyz", [])
        var data = Data()
        for await chunk in runner.output { data.append(chunk) }
        let out = String(decoding: data, as: UTF8.self)
        #expect(out.contains("failed to exec"))
        #expect(await runner.waitForExit() == .code(127))
    }

    // MARK: ST8 — exit detection + teardown

    private func makeRunner(
        _ executablePath: String, _ arguments: [String],
        env: [String: String] = baseEnv, cwd: String = "", columns: Int = 80, rows: Int = 24
    ) throws -> ProcessRunner {
        try ProcessRunner(SpawnRequest(
            executablePath: executablePath, arguments: arguments, environment: env,
            workingDirectory: cwd, helperURL: Self.helperURL, columns: columns, rows: rows))
    }

    @Test func decodeExitHandlesCodesAndSignals() {
        #expect(ProcessRunner.decodeExit(42 << 8) == .code(42))       // exit 42
        #expect(ProcessRunner.decodeExit(0) == .code(0))              // exit 0
        #expect(ProcessRunner.decodeExit(SIGKILL) == .signal(SIGKILL))
        #expect(ProcessRunner.decodeExit(SIGTERM) == .signal(SIGTERM))
    }

    @Test func exitCodeIsDecoded() async throws {
        let runner = try makeRunner("/bin/sh", ["-c", "exit 42"])
        #expect(await runner.waitForExit() == .code(42))
    }

    @Test func terminationSignalIsDecoded() async throws {
        let runner = try makeRunner("/bin/sh", ["-c", "sleep 100"])
        await runner.stop()  // SIGTERM, honored well before the grace SIGKILL
        #expect(await runner.waitForExit() == .signal(SIGTERM))
    }

    @Test func outputDrainsAndExitCodeBothAvailable() async throws {
        let runner = try makeRunner("/bin/sh", ["-c", "echo hi; exit 7"])
        var data = Data()
        for await chunk in runner.output { data.append(chunk) }
        #expect(String(decoding: data, as: UTF8.self).contains("hi"))
        #expect(await runner.waitForExit() == .code(7))
    }

    @Test func ignoredSIGTERMEscalatesToSIGKILL() async throws {
        // The leader loops in-process (bash control flow) with the ignore-trap
        // in effect, so SIGTERM can't end it — only the grace SIGKILL can.
        // It prints READY *after* installing the trap, so we don't SIGTERM it
        // before the trap is in place (which would just kill it on default TERM).
        let runner = try makeRunner(
            "/bin/sh", ["-c", "trap '' TERM; printf READY; while true; do sleep 0.05; done"])
        await waitForMarker(runner, "READY")
        let start = ContinuousClock.now
        await runner.stop(grace: .milliseconds(300))  // SIGTERM ignored → SIGKILL after grace
        let elapsed = ContinuousClock.now - start
        let exit = await runner.waitForExit()
        #expect(exit == .signal(SIGKILL), "got \(exit)")
        #expect(elapsed >= .milliseconds(300))  // the grace was honored before escalating
    }

    @Test func multipleAwaitersAllReceiveTheExit() async throws {
        let runner = try makeRunner("/bin/sh", ["-c", "exit 5"])
        async let a = runner.waitForExit()
        async let b = runner.waitForExit()
        let (ra, rb) = await (a, b)
        #expect(ra == .code(5))
        #expect(rb == .code(5))
    }

    @Test func resizeAfterExitIsSafeNoOp() async throws {
        let runner = try makeRunner("/bin/sh", ["-c", "exit 0"])
        _ = await runner.waitForExit()
        runner.resize(columns: 100, rows: 50)  // must not crash
        #expect(runner.exitStatus == .code(0))
    }

    @Test func droppingRunnerCancelsReadSourceAndFinishesStream() async throws {
        // Proves deinit cancels the read source (closing the master, breaking
        // the handler's self-retain): the stream finishes because the runner
        // was dropped, NOT because the child exited — the child is still alive.
        let stream: AsyncStream<Data>
        let pid: pid_t
        do {
            let runner = try makeRunner("/bin/sh", ["-c", "sleep 30"])
            stream = runner.output  // a value type — does not retain the runner
            pid = runner.pid
        }  // runner dropped → deinit cancels the read source → stream finishes
        for await _ in stream {}  // would hang on the live child if deinit didn't cancel
        kill(-pid, SIGKILL)       // deinit doesn't kill (per contract); clean up the orphan
    }

    @Test func stopOnAlreadyExitedChildIsNoOp() async throws {
        let runner = try makeRunner("/bin/sh", ["-c", "exit 0"])
        _ = await runner.waitForExit()
        await runner.stop()  // must return immediately, not hang or crash
        #expect(runner.exitStatus == .code(0))
    }

    @Test func groupKillReapsGrandchildrenWithNoOrphans() async throws {
        let runner = try makeRunner("/bin/sh", ["-c", "sleep 100 & sleep 100 & wait"])
        let pgid = runner.pid
        try await Task.sleep(for: .milliseconds(200))  // let the backgrounded sleeps come up
        #expect(!processes(inGroup: pgid).isEmpty)     // sanity: the group is populated
        await runner.stop()
        #expect(await groupEmpties(pgid))              // SIGTERM took the whole group
    }

    @Test func resizeDeliversSIGWINCH() async throws {
        // The child exits on SIGWINCH (so the stream EOFs). Short sleeps mean
        // bash runs the deferred trap within ~0.1s of the signal rather than
        // waiting out a long sleep.
        let runner = try makeRunner(
            "/bin/sh", ["-c", "trap 'printf WINCH_GOT; exit 0' WINCH; printf READY; while true; do sleep 0.1; done"])
        var seen = ""
        var resized = false
        for await chunk in runner.output {
            seen += String(decoding: chunk, as: UTF8.self)
            if !resized && seen.contains("READY") {
                resized = true
                runner.resize(columns: 111, rows: 47)
            }
        }
        #expect(seen.contains("WINCH_GOT"))
    }

    /// Consume the output stream until `marker` appears (so the child has
    /// reached a known point — e.g. installed a signal trap).
    private func waitForMarker(_ runner: ProcessRunner, _ marker: String) async {
        var seen = ""
        for await chunk in runner.output {
            seen += String(decoding: chunk, as: UTF8.self)
            if seen.contains(marker) { return }
        }
    }

    // MARK: ps helpers

    private func groupEmpties(_ pgid: pid_t, within: Duration = .seconds(3)) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: within)
        while ContinuousClock.now < deadline {
            if processes(inGroup: pgid).isEmpty { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return processes(inGroup: pgid).isEmpty
    }

    /// pids whose process-group id is `pgid`, via `ps`.
    private func processes(inGroup pgid: pid_t) -> [Int32] {
        let p = Process()
        p.executableURL = URL(filePath: "/bin/ps")
        p.arguments = ["-ax", "-o", "pid=,pgid="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        var result: [Int32] = []
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let cols = line.split(whereSeparator: \.isWhitespace)
            if cols.count == 2, let pid = Int32(cols[0]), let g = Int32(cols[1]), g == pgid {
                result.append(pid)
            }
        }
        return result
    }
}
