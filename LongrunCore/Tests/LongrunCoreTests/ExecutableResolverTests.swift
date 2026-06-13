import Foundation
import Testing
@testable import LongrunCore

@Suite struct ExecutableResolverTests {

    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bintest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    private func makeExecutable(_ url: URL) {
        FileManager.default.createFile(
            atPath: url.path, contents: Data("#!/bin/sh\n".utf8),
            attributes: [.posixPermissions: 0o755])
    }

    @Test func findsBareNameOnProvidedPath() throws {
        try withTempDir { dir in
            let tool = dir.appendingPathComponent("mytool")
            makeExecutable(tool)
            let env = ["PATH": dir.path]
            #expect(ExecutableResolver.resolve("mytool", env: env) == tool.path)
        }
    }

    @Test func returnsNilWhenNotFound() throws {
        try withTempDir { dir in
            #expect(ExecutableResolver.resolve("no-such-cmd-xyz", env: ["PATH": dir.path]) == nil)
        }
    }

    @Test func searchesPathInOrderFirstMatchWins() throws {
        try withTempDir { d1 in
            try withTempDir { d2 in
                makeExecutable(d2.appendingPathComponent("tool"))
                let env = ["PATH": "\(d1.path):\(d2.path)"]
                #expect(ExecutableResolver.resolve("tool", env: env) == d2.appendingPathComponent("tool").path)

                makeExecutable(d1.appendingPathComponent("tool"))  // now also in d1 → prefer d1
                #expect(ExecutableResolver.resolve("tool", env: env) == d1.appendingPathComponent("tool").path)
            }
        }
    }

    @Test func slashPathReturnedAsIs() {
        #expect(ExecutableResolver.resolve("/usr/bin/env", env: [:]) == "/usr/bin/env")
        #expect(ExecutableResolver.resolve("./app", env: [:]) == "./app")
        #expect(ExecutableResolver.resolve("sub/app", env: ["PATH": "/bin"]) == "sub/app")
    }

    @Test func emptyCommandIsNil() {
        #expect(ExecutableResolver.resolve("", env: ["PATH": "/bin"]) == nil)
    }

    @Test func nonExecutableFileIsSkipped() throws {
        try withTempDir { dir in
            FileManager.default.createFile(
                atPath: dir.appendingPathComponent("tool").path, contents: Data("x".utf8),
                attributes: [.posixPermissions: 0o644])
            #expect(ExecutableResolver.resolve("tool", env: ["PATH": dir.path]) == nil)
        }
    }

    @Test func executableDirectoryIsSkipped() throws {
        try withTempDir { dir in
            // A directory named like the command (dirs are typically +x/searchable).
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent("tool"), withIntermediateDirectories: true)
            #expect(ExecutableResolver.resolve("tool", env: ["PATH": dir.path]) == nil)
        }
    }

    @Test func emptyPathElementsAreSkipped() throws {
        try withTempDir { dir in
            makeExecutable(dir.appendingPathComponent("tool"))
            // Leading, doubled, and trailing empty elements must be ignored,
            // not resolved against cwd.
            let env = ["PATH": "::\(dir.path):"]
            #expect(ExecutableResolver.resolve("tool", env: env) == dir.appendingPathComponent("tool").path)
        }
    }

    @Test func defaultPathFindsSystemBinaries() {
        // No PATH provided → default /usr/bin:/bin.
        #expect(ExecutableResolver.resolve("sh", env: [:]) == "/bin/sh")
    }
}
