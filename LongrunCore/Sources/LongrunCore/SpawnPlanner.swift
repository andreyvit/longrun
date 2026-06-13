import Foundation

public enum LaunchError: Error, Equatable {
    case emptyCommand
    case invalidCommand  // e.g. an unterminated quote in exec mode
}

/// Turns a `Configuration` into a `SpawnRequest` — the launch-mode dispatch.
public enum SpawnPlanner {
    public static func plan(
        configuration: Configuration,
        baseEnvironment: [String: String],
        helperURL: URL,
        columns: Int = 80,
        rows: Int = 24
    ) throws -> SpawnRequest {
        let command = configuration.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { throw LaunchError.emptyCommand }

        let executablePath: String
        let arguments: [String]
        switch configuration.launchMode {
        case .exec:
            // The helper's execvp resolves a bare argv[0] via the child's PATH
            // (and relative paths against the chdir'd cwd), so no pre-resolution.
            let argv: [String]
            do { argv = try CommandLineSplitter.split(command) }
            catch { throw LaunchError.invalidCommand }
            guard let first = argv.first else { throw LaunchError.emptyCommand }
            executablePath = first
            arguments = Array(argv.dropFirst())
        case .loginShell:
            executablePath = baseEnvironment["SHELL"] ?? "/bin/zsh"
            arguments = ["-l", "-c", command]
        case .bash:
            executablePath = "/bin/bash"
            arguments = ["-l", "-c", command]
        }

        // Config overrides win over the base login environment.
        var environment = baseEnvironment
        for entry in configuration.environment { environment[entry.key] = entry.value }

        let home = baseEnvironment["HOME"] ?? NSHomeDirectory()
        let workingDirectory = expandWorkingDirectory(configuration.workingDirectory, home: home)

        return SpawnRequest(
            executablePath: executablePath, arguments: arguments, environment: environment,
            workingDirectory: workingDirectory, helperURL: helperURL, columns: columns, rows: rows)
    }

    /// Empty → home; a leading `~` expands against home (P33).
    static func expandWorkingDirectory(_ workingDirectory: String, home: String) -> String {
        if workingDirectory.isEmpty || workingDirectory == "~" { return home }
        if workingDirectory.hasPrefix("~/") { return home + String(workingDirectory.dropFirst()) }
        return workingDirectory
    }
}
