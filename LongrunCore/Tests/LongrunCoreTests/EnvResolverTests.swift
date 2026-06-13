import Foundation
import Testing
@testable import LongrunCore

@Suite struct EnvResolverTests {

    // MARK: parseEnvironment (pure)

    @Test func parsesNulSeparatedPairs() {
        let env = EnvResolver.parseEnvironment(Data("A=1\u{0}B=two words\u{0}".utf8))
        #expect(env == ["A": "1", "B": "two words"])
    }

    @Test func preservesNewlinesInValues() {
        let env = EnvResolver.parseEnvironment(Data("M=line1\nline2\u{0}".utf8))
        #expect(env["M"] == "line1\nline2")
    }

    @Test func discardsNoiseBeforeMarker() {
        let raw = "Welcome to your shell!\nMOTD\(EnvResolver.marker)PATH=/clean\u{0}"
        let env = EnvResolver.parseEnvironment(Data(raw.utf8))
        #expect(env == ["PATH": "/clean"])
    }

    @Test func skipsEntriesWithoutKeyOrEquals() {
        let env = EnvResolver.parseEnvironment(Data("PATH=/x\u{0}garbageline\u{0}=novalue\u{0}Y=2\u{0}".utf8))
        #expect(env == ["PATH": "/x", "Y": "2"])
    }

    @Test func emptyDataParsesToEmpty() {
        #expect(EnvResolver.parseEnvironment(Data()).isEmpty)
    }

    // MARK: capture + resolved (fixture shells)

    @Test func captureReadsMarkerDelimitedEnv() async throws {
        try await withFixtureShell(
            "printf '%s' '\(EnvResolver.marker)'; printf 'FOO=bar\\0BAZ=multi\\nline\\0PX=/x:/y\\0'\n"
        ) { shell in
            let env = await EnvResolver.capture(
                executableURL: shell, arguments: ["-l", "-c", "ignored"], timeout: .seconds(5)
            )
            #expect(env?["FOO"] == "bar")
            #expect(env?["BAZ"] == "multi\nline")
            #expect(env?["PX"] == "/x:/y")
        }
    }

    @Test func captureTimesOutAndReturnsNil() async throws {
        try await withFixtureShell("exec sleep 30\n") { shell in
            let env = await EnvResolver.capture(
                executableURL: shell, arguments: ["-l", "-c", "ignored"], timeout: .milliseconds(500)
            )
            #expect(env == nil)
        }
    }

    @Test func captureReturnsPromptlyDespiteOrphanHoldingPipe() async throws {
        // Regression: a login profile that backgrounds a process inheriting
        // stdout used to hang the read forever past the SIGKILL. The timeout
        // must close our read end and return — not wait for the orphan.
        try await withFixtureShell("sleep 10 & exec sleep 10\n") { shell in
            let clock = ContinuousClock()
            let start = clock.now
            let env = await EnvResolver.capture(
                executableURL: shell, arguments: ["-l", "-c", "ignored"], timeout: .milliseconds(500)
            )
            let elapsed = clock.now - start
            #expect(env == nil)
            #expect(elapsed < .seconds(5))  // well under the orphan's 10s
        }
    }

    @Test func captureReturnsNilOnNonzeroExit() async throws {
        try await withFixtureShell(
            "printf '%s' '\(EnvResolver.marker)'; printf 'A=1\\0'; exit 3\n"
        ) { shell in
            let env = await EnvResolver.capture(
                executableURL: shell, arguments: ["-l", "-c", "ignored"], timeout: .seconds(5)
            )
            #expect(env == nil)
        }
    }

    @Test func captureReturnsNilOnEmptyOutput() async throws {
        try await withFixtureShell("exit 0\n") { shell in
            let env = await EnvResolver.capture(
                executableURL: shell, arguments: ["-l", "-c", "ignored"], timeout: .seconds(5)
            )
            #expect(env == nil)
        }
    }

    @Test func resolvedFallsBackToCanonicalPathOnTimeout() async throws {
        try await withFixtureShell("exec sleep 30\n") { shell in
            let resolver = EnvResolver(shellPath: shell.path, timeout: .milliseconds(500))
            let env = await resolver.resolved()
            #expect(env["PATH"] == EnvResolver.fallbackPATH)
            #expect(env["TERM"] == "xterm-256color")
        }
    }

    @Test func resolvedAddsTerminalDefaultsWithoutClobbering() async throws {
        // Fixture supplies LANG but not TERM/COLORTERM.
        try await withFixtureShell(
            "printf '%s' '\(EnvResolver.marker)'; printf 'FOO=bar\\0LANG=en_GB.UTF-8\\0'\n"
        ) { shell in
            let resolver = EnvResolver(shellPath: shell.path, timeout: .seconds(5))
            let env = await resolver.resolved()
            #expect(env["FOO"] == "bar")
            #expect(env["LANG"] == "en_GB.UTF-8")        // user's value kept
            #expect(env["TERM"] == "xterm-256color")     // added
            #expect(env["COLORTERM"] == "truecolor")     // added
        }
    }

    @Test func resolvedCachesResult() async throws {
        try await withFixtureShell(
            "printf '%s' '\(EnvResolver.marker)'; printf 'FOO=bar\\0'\n"
        ) { shell in
            let resolver = EnvResolver(shellPath: shell.path, timeout: .seconds(5))
            let first = await resolver.resolved()
            let second = await resolver.resolved()
            #expect(first == second)
            #expect(first["FOO"] == "bar")
        }
    }

    // MARK: helper

    /// Write an executable `#!/bin/sh` script with the given body to a temp dir
    /// and hand its URL to `test`. The dir is removed afterward.
    private func withFixtureShell(_ body: String, _ test: (URL) async throws -> Void) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("envtest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let script = dir.appendingPathComponent("shell")
        try ("#!/bin/sh\n" + body).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try await test(script)
    }
}
