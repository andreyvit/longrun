import Foundation
import Testing
@testable import LongrunCore

@Suite struct ConfigStoreTests {

    /// A ConfigStore rooted at a fresh temp directory, removed after the test.
    private func withTempStore(_ body: (ConfigStore, URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("longrun-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(ConfigStore(directoryURL: dir), dir)
    }

    @Test func saveThenLoadAllRoundTripsFullyIncludingId() throws {
        try withTempStore { store, _ in
            var c = Configuration(id: "tunnel", name: "ssh tunnel", command: "ssh -MN host")
            // Deliberately non-alphabetical so the round-trip pins env ORDER
            // through the store (whose encoder uses .sortedKeys for object keys).
            c.environment = [EnvEntry(key: "PORT", value: "8080"), EnvEntry(key: "DEBUG", value: "1")]
            c.notificationRules = [NotificationRule(id: "r1", pattern: "down", enabled: false)]
            try store.save(c)

            let loaded = try store.loadAll()
            #expect(loaded.count == 1)
            #expect(loaded.first == c)
        }
    }

    @Test func idComesFromFilenameNotJSON() throws {
        try withTempStore { store, dir in
            let c = Configuration(id: "original", name: "n")
            try store.save(c)
            // Rename the file: the id must follow the new filename on load.
            try FileManager.default.moveItem(
                at: dir.appendingPathComponent("original.json"),
                to: dir.appendingPathComponent("renamed.json")
            )
            let loaded = try store.loadAll()
            #expect(loaded.count == 1)
            #expect(loaded.first?.id == "renamed")
            #expect(loaded.first?.name == "n")
        }
    }

    @Test func loadAllSkipsUnparseableFiles() throws {
        try withTempStore { store, dir in
            try store.save(Configuration(id: "good", name: "good"))
            try Data("this is not json".utf8)
                .write(to: dir.appendingPathComponent("broken.json"))

            let loaded = try store.loadAll()
            #expect(loaded.count == 1)
            #expect(loaded.first?.id == "good")
        }
    }

    @Test func handMinimalJSONLoadsWithDefaults() throws {
        try withTempStore { store, dir in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(#"{ "command": "ngrok http 3000" }"#.utf8)
                .write(to: dir.appendingPathComponent("ngrok.json"))

            let loaded = try store.loadAll()
            #expect(loaded.count == 1)
            let c = try #require(loaded.first)
            #expect(c.id == "ngrok")
            #expect(c.command == "ngrok http 3000")
            #expect(c.launchMode == .exec)
            #expect(c.restartPolicy == .always)
        }
    }

    @Test func loadAllKeepsConfigWithWrongTypedField() throws {
        try withTempStore { store, dir in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // A 1-for-bool hand edit must NOT make the whole config vanish.
            try Data(#"{ "command": "x", "autostart": 1 }"#.utf8)
                .write(to: dir.appendingPathComponent("svc.json"))
            let loaded = try store.loadAll()
            #expect(loaded.count == 1)
            #expect(loaded.first?.command == "x")
            #expect(loaded.first?.autostart == false)
        }
    }

    @Test func savedFileIsUserOnlyReadable() throws {
        try withTempStore { store, dir in
            try store.save(Configuration(id: "secret", name: "n"))
            let perms = try FileManager.default.attributesOfItem(
                atPath: dir.appendingPathComponent("secret.json").path
            )[.posixPermissions] as? NSNumber
            #expect(perms?.int16Value == 0o600)
        }
    }

    @Test func directoryIsCreatedUserOnly() throws {
        try withTempStore { store, dir in
            try store.save(Configuration(id: "x", name: "n"))
            let perms = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? NSNumber
            #expect(perms?.int16Value == 0o700)
        }
    }

    @Test func deleteRemovesTheFile() throws {
        try withTempStore { store, dir in
            try store.save(Configuration(id: "doomed", name: "n"))
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("doomed.json").path))
            try store.delete(id: "doomed")
            #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("doomed.json").path))
            let remaining = try store.loadAll()
            #expect(remaining.isEmpty)
        }
    }

    @Test func deleteOfMissingIdIsNoOp() throws {
        try withTempStore { store, _ in
            try store.delete(id: "never-existed")  // must not throw
        }
    }

    @Test func loadAllOnMissingDirectoryReturnsEmpty() throws {
        try withTempStore { store, _ in
            let all = try store.loadAll()
            #expect(all.isEmpty)
        }
    }

    @Test func saveOverwritesExisting() throws {
        try withTempStore { store, _ in
            try store.save(Configuration(id: "c", name: "first"))
            try store.save(Configuration(id: "c", name: "second"))
            let loaded = try store.loadAll()
            #expect(loaded.count == 1)
            #expect(loaded.first?.name == "second")
        }
    }
}
