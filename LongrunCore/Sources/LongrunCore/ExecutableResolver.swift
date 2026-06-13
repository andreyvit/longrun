import Foundation

/// Resolves a command name to a path `posix_spawn` can exec.
public enum ExecutableResolver {
    /// - A name containing `/` is returned as-is: it's an explicit path, and
    ///   the OS resolves it at spawn time against the child's working directory
    ///   (which we don't know here).
    /// - A bare name is searched on the PROVIDED env's PATH — not the calling
    ///   process's PATH, which is what `posix_spawnp` would wrongly use (a GUI
    ///   app's PATH is launchd's anemic one). Returns the first existing,
    ///   non-directory, executable match, or nil for a clean "command not found".
    public static func resolve(_ command: String, env: [String: String]) -> String? {
        guard !command.isEmpty else { return nil }
        if command.contains("/") { return command }

        let path = env["PATH"] ?? "/usr/bin:/bin"
        let fm = FileManager.default
        // Empty PATH elements are skipped, not treated as cwd: the POSIX
        // "empty means cwd" rule is a known footgun and would resolve against
        // the WRONG directory here anyway (our cwd, not the child's).
        for dir in path.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = String(dir) + "/" + command
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate, isDirectory: &isDir), !isDir.boolValue,
               fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
