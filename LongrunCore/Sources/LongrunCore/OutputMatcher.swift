/// One rule fired against one output line.
public struct MatchEvent: Equatable, Sendable {
    public let ruleID: String
    public let line: String

    public init(ruleID: String, line: String) {
        self.ruleID = ruleID
        self.line = line
    }
}

/// Matches a configuration's notification rules against assembled output lines,
/// with a per-rule cooldown so a pattern that matches every line can't flood
/// notifications (spec P23). Built from `[NotificationRule]`; lines come from
/// `AnsiLineAssembler`.
public struct OutputMatcher {
    public static let defaultCooldown: Duration = .seconds(30)

    private struct CompiledRule {
        let id: String
        let regex: Regex<AnyRegexOutput>
    }

    private let rules: [CompiledRule]
    private let cooldown: Duration
    private var lastFire: [String: ContinuousClock.Instant] = [:]

    public init(rules: [NotificationRule], cooldown: Duration = OutputMatcher.defaultCooldown) {
        self.cooldown = cooldown
        // Skip disabled rules, empty patterns (would match every line), and
        // patterns that don't compile — an invalid regex must never crash
        // matching, it just goes inert (P9).
        self.rules = rules.compactMap { rule in
            guard rule.enabled, !rule.pattern.isEmpty, let regex = try? Regex(rule.pattern) else { return nil }
            return CompiledRule(id: rule.id, regex: regex)
        }
    }

    /// True when there are no active rules — lets the caller skip matching
    /// entirely for a configuration with nothing to watch for.
    public var isEmpty: Bool { rules.isEmpty }

    /// Returns a `MatchEvent` for each active rule that matches `line` and is
    /// not currently in cooldown. `now` is supplied by the caller (the clock is
    /// injected by parameter) so cooldown behavior is deterministically testable.
    ///
    /// > Important: the patterns are user-written, and Swift's `Regex` engine
    /// > backtracks with no timeout — a pathological pattern (e.g. `(a+)+$`) can
    /// > take a very long time on a single line. The caller (RunSession) MUST
    /// > run matching off the main actor so a bad pattern can't freeze the UI.
    public mutating func match(_ line: String, at now: ContinuousClock.Instant) -> [MatchEvent] {
        var events: [MatchEvent] = []
        for rule in rules where line.contains(rule.regex) {
            if let last = lastFire[rule.id], last.duration(to: now) < cooldown {
                continue  // still cooling down; suppress without extending the window
            }
            lastFire[rule.id] = now
            events.append(MatchEvent(ruleID: rule.id, line: line))
        }
        return events
    }
}
