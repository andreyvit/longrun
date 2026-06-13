import Foundation
import Testing
@testable import LongrunCore

@Suite struct SpawnPlannerTests {
    private let helperURL = URL(filePath: "/tmp/longrun-helper")  // not exec'd during planning
    private let baseEnv = [
        "PATH": "/usr/bin:/bin", "HOME": "/Users/test", "SHELL": "/bin/zsh", "TERM": "xterm",
    ]

    private func config(
        _ command: String, mode: LaunchMode = .exec, cwd: String = "", env: [EnvEntry] = []
    ) -> Configuration {
        var c = Configuration(command: command)
        c.launchMode = mode
        c.workingDirectory = cwd
        c.environment = env
        return c
    }

    private func plan(_ command: String, mode: LaunchMode = .exec, cwd: String = "", env: [EnvEntry] = []) throws -> SpawnRequest {
        try SpawnPlanner.plan(
            configuration: config(command, mode: mode, cwd: cwd, env: env),
            baseEnvironment: baseEnv, helperURL: helperURL)
    }

    @Test func execModeSplitsCommandIntoArgv() throws {
        let r = try plan("go run ./cmd/lifebase")
        #expect(r.executablePath == "go")
        #expect(r.arguments == ["run", "./cmd/lifebase"])
    }

    @Test func execModeKeepsQuotedArgsTogether() throws {
        let r = try plan("tool --flag='a b c'")
        #expect(r.executablePath == "tool")
        #expect(r.arguments == ["--flag=a b c"])
    }

    @Test func loginShellModePassesCommandToShell() throws {
        let r = try plan("npm start && echo done", mode: .loginShell)
        #expect(r.executablePath == "/bin/zsh")
        #expect(r.arguments == ["-l", "-c", "npm start && echo done"])
    }

    @Test func loginShellModeDefaultsShellWhenAbsent() throws {
        let c = config("x", mode: .loginShell)
        let r = try SpawnPlanner.plan(configuration: c, baseEnvironment: ["HOME": "/h"], helperURL: helperURL)
        #expect(r.executablePath == "/bin/zsh")
    }

    @Test func bashModeUsesBinBash() throws {
        let r = try plan("x", mode: .bash)
        #expect(r.executablePath == "/bin/bash")
        #expect(r.arguments == ["-l", "-c", "x"])
    }

    @Test func configEnvOverridesWinOverBase() throws {
        let r = try plan("x", env: [EnvEntry(key: "PATH", value: "/custom"), EnvEntry(key: "FOO", value: "bar")])
        #expect(r.environment["PATH"] == "/custom")        // override wins
        #expect(r.environment["FOO"] == "bar")             // added
        #expect(r.environment["HOME"] == "/Users/test")    // base kept
    }

    @Test func workingDirectoryExpansion() throws {
        #expect(try plan("x", cwd: "").workingDirectory == "/Users/test")        // empty → home
        #expect(try plan("x", cwd: "~").workingDirectory == "/Users/test")
        #expect(try plan("x", cwd: "~/dev/app").workingDirectory == "/Users/test/dev/app")
        #expect(try plan("x", cwd: "/abs/path").workingDirectory == "/abs/path")
    }

    @Test func emptyCommandThrows() {
        #expect(throws: LaunchError.emptyCommand) { try plan("   ") }
    }

    @Test func unterminatedQuoteThrows() {
        #expect(throws: LaunchError.invalidCommand) { try plan("echo 'unterminated") }
    }
}
