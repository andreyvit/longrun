import Foundation

/// The real spawn helper, compiled once via clang from its single C source, so
/// tests exercise the production controlling-terminal logic without an app
/// bundle. Shared by ProcessRunner and RunSession tests.
enum SpawnHelperFixture {
    static let url: URL = build()

    private static func build() -> URL {
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
}
