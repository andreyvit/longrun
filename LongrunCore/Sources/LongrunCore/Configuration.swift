import Foundation

/// How a configuration's command is turned into a running process.
public enum LaunchMode: String, Codable, Sendable, CaseIterable {
    /// Split the command into argv and exec directly, using the cached
    /// login-shell environment. The default — no shell profile side effects.
    case exec
    /// Run the command as a one-liner through the user's login shell
    /// (`$SHELL -l -c`).
    case loginShell
    /// Run the command as a one-liner through `bash -l -c`.
    case bash
}

/// What to do when a configuration's process exits.
public enum RestartPolicy: String, Codable, Sendable, CaseIterable {
    /// Relaunch 1s after any exit that wasn't a manual stop (subject to the
    /// crash-loop breaker).
    case always
    /// Never relaunch automatically.
    case never
}

/// One environment-variable override, applied on top of the resolved base
/// environment. Kept as an ordered list (not a map) so the settings UI
/// preserves the user's order.
public struct EnvEntry: Codable, Sendable, Equatable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    private enum CodingKeys: String, CodingKey { case key, value }

    /// Tolerant decode: a missing or wrong-typed field defaults to "" so one
    /// malformed entry degrades to an editable blank rather than throwing and
    /// taking the whole environment array down with it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? c.decodeIfPresent(String.self, forKey: .key)) ?? ""
        value = (try? c.decodeIfPresent(String.self, forKey: .value)) ?? ""
    }
}

/// One output-matching rule: when an ANSI-stripped output line matches
/// `pattern`, post a notification (if `enabled`).
public struct NotificationRule: Codable, Sendable, Equatable, Identifiable {
    /// Stable identity for SwiftUI lists and per-rule notification cooldowns.
    public var id: String
    public var pattern: String
    public var enabled: Bool

    public init(id: String = UUID().uuidString, pattern: String = "", enabled: Bool = true) {
        self.id = id
        self.pattern = pattern
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey { case id, pattern, enabled }

    /// Tolerant decode: missing/wrong-typed fields default (and a missing id
    /// gets a fresh one) so a hand-edited rule can't throw the array out.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        pattern = (try? c.decodeIfPresent(String.self, forKey: .pattern)) ?? ""
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
    }
}

/// One thing to keep running. Persisted as a single human-readable JSON file
/// whose name (`<id>.json`) is the configuration's identity — see `ConfigStore`.
/// `id` is therefore intentionally excluded from the JSON body.
public struct Configuration: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var command: String
    public var launchMode: LaunchMode
    public var workingDirectory: String
    public var environment: [EnvEntry]
    public var autostart: Bool
    public var restartPolicy: RestartPolicy
    public var notificationRules: [NotificationRule]
    public var notifyOnUnexpectedExit: Bool

    /// New-configuration defaults (spec P32).
    public init(
        id: String = UUID().uuidString,
        name: String = "New Configuration",
        command: String = "",
        launchMode: LaunchMode = .exec,
        workingDirectory: String = "",
        environment: [EnvEntry] = [],
        autostart: Bool = false,
        restartPolicy: RestartPolicy = .always,
        notificationRules: [NotificationRule] = [],
        notifyOnUnexpectedExit: Bool = true
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.launchMode = launchMode
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.autostart = autostart
        self.restartPolicy = restartPolicy
        self.notificationRules = notificationRules
        self.notifyOnUnexpectedExit = notifyOnUnexpectedExit
    }

    // `id` is omitted: identity lives in the filename, not the JSON body.
    private enum CodingKeys: String, CodingKey {
        case name, command, launchMode, workingDirectory, environment
        case autostart, restartPolicy, notificationRules, notifyOnUnexpectedExit
    }

    /// Tolerant decode: every field falls back to its default when absent OR
    /// present with the wrong type, and an unrecognized
    /// `launchMode`/`restartPolicy` string falls back too — a single hand-edit
    /// typo (a `1` for a bool, a quoted bool, a malformed rule) must not discard
    /// the whole configuration. Unknown JSON keys are ignored for free. `id` is
    /// a placeholder here; `ConfigStore` overwrites it from the filename.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID().uuidString
        name = Self.lenient(c, .name, default: "New Configuration")
        command = Self.lenient(c, .command, default: "")
        launchMode = Self.decodeEnum(c, .launchMode, default: .exec)
        workingDirectory = Self.lenient(c, .workingDirectory, default: "")
        environment = Self.lenient(c, .environment, default: [])
        autostart = Self.lenient(c, .autostart, default: false)
        restartPolicy = Self.decodeEnum(c, .restartPolicy, default: .always)
        notificationRules = Self.lenient(c, .notificationRules, default: [])
        notifyOnUnexpectedExit = Self.lenient(c, .notifyOnUnexpectedExit, default: true)
    }

    /// Decode any field, falling back to `default` when the key is absent or
    /// the value is present but the wrong type (instead of throwing).
    private static func lenient<T: Decodable>(
        _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys, default fallback: T
    ) -> T {
        (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }

    /// Decode a string-backed enum, falling back to `default` on a missing,
    /// wrong-typed, or unrecognized value instead of throwing.
    private static func decodeEnum<E: RawRepresentable>(
        _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys, default fallback: E
    ) -> E where E.RawValue == String {
        guard let raw = try? c.decodeIfPresent(String.self, forKey: key) else { return fallback }
        return E(rawValue: raw) ?? fallback
    }
}
