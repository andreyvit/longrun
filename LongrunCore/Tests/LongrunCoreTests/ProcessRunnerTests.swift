import Foundation
import Testing
@testable import LongrunCore

@Suite(.timeLimit(.minutes(1))) struct ProcessRunnerTests {

    /// The real C helper, compiled once via clang from the single source of
    /// truth so `swift test` exercises the production ctty logic.
    static let helperURL: URL = buildHelper()

    private static func buildHelper() -> URL {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()  // LongrunCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // LongrunCore
            .deletingLastPathComponent()  // repo root
        let source = repoRoot.appending(path: "longrun-spawn-helper/main.c")
        let out = FileManager.default.temporaryDirectory.appending(path: "longrun-spawn-helper-\(UUID().uuidString)")
        let clang = Process()
        clang.executableURL = URL(filePath: "/usr/bin/clang")
        clang.arguments = ["-O2", "-o", out.path, source.path]
        try! clang.run()
        clang.waitUntilExit()
        precondition(clang.terminationStatus == 0, "failed to compile spawn helper at \(source.path)")
        return out
    }

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
        // _exit(127)s. (ST8 will additionally assert ProcessExit == .code(127).)
        let out = try await run("/nonexistent/longrun-binary-xyz", [])
        #expect(out.contains("failed to exec"))
        #expect(out.contains("/nonexistent/longrun-binary-xyz"))
    }
}
