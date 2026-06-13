import Foundation

public enum ConfigStoreError: Error, Equatable {
    case writeFailed(String)
    case renameFailed(String, Int32)
}

/// Persists configurations as one human-readable JSON file per configuration,
/// `<id>.json`, under a directory (default
/// `~/Library/Application Support/Longrun/Configurations`). The filename stem
/// is the configuration's identity; the JSON body carries everything else.
///
/// Files are written user-only (0600) because environment overrides may hold
/// secrets, and the directory is created 0700.
public struct ConfigStore {
    public let directoryURL: URL

    private static let dirPermissions: NSNumber = 0o700
    private static let filePermissions: NSNumber = 0o600

    /// - Parameter directoryURL: where configuration files live. Pass a custom
    ///   directory in tests; the default is the app-support location.
    public init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directoryURL = appSupport
                .appendingPathComponent("Longrun", isDirectory: true)
                .appendingPathComponent("Configurations", isDirectory: true)
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Readable, stable diffs for hand-editing and version control.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Load every configuration in the directory. Files that fail to parse are
    /// skipped (a single malformed hand-edit must not break loading the rest).
    /// Order is unspecified — the app owns ordering separately (UserDefaults).
    public func loadAll() throws -> [Configuration] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directoryURL.path) else { return [] }
        let files = try fm.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        var result: [Configuration] = []
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  var config = try? JSONDecoder().decode(Configuration.self, from: data)
            else { continue }
            config.id = file.deletingPathExtension().lastPathComponent
            result.append(config)
        }
        return result
    }

    /// Create or overwrite a configuration's file. Writes a 0600 temp file in
    /// the (0700) directory, then atomically renames it over the destination —
    /// so the destination path is never momentarily world-readable, even on
    /// first create (env overrides may hold secrets).
    public func save(_ configuration: Configuration) throws {
        try ensureDirectory()
        let data = try Self.makeEncoder().encode(configuration)
        let url = fileURL(for: configuration.id)
        let fm = FileManager.default
        let tmp = directoryURL.appendingPathComponent(".\(configuration.id).\(UUID().uuidString).tmp")
        guard fm.createFile(
            atPath: tmp.path, contents: data,
            attributes: [.posixPermissions: Self.filePermissions]
        ) else {
            throw ConfigStoreError.writeFailed(configuration.id)
        }
        // rename(2) replaces the destination atomically; the moved file keeps
        // the temp's 0600 permissions.
        guard rename(tmp.path, url.path) == 0 else {
            let err = errno
            try? fm.removeItem(at: tmp)
            throw ConfigStoreError.renameFailed(configuration.id, err)
        }
    }

    /// Remove a configuration's file. No-op if it doesn't exist.
    public func delete(id: String) throws {
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func fileURL(for id: String) -> URL {
        directoryURL.appendingPathComponent("\(id).json")
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.dirPermissions]
        )
    }
}
