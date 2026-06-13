import Foundation

/// Runs output matching off the main actor. Owns the stateful
/// `AnsiLineAssembler` + `OutputMatcher` (so chunks are processed in order),
/// and because it's an actor a pathological user regex (catastrophic
/// backtracking) spins this executor instead of freezing the UI — RunSession
/// `await`s it, suspending (not blocking) the main actor. See the ReDoS
/// decision in the task spec.
actor MatchingPipeline {
    private var assembler = AnsiLineAssembler()
    private var matcher: OutputMatcher

    init(rules: [NotificationRule], cooldown: Duration) {
        matcher = OutputMatcher(rules: rules, cooldown: cooldown)
    }

    /// Strip ANSI from `chunk`, assemble lines, and return any rule matches.
    func process(_ chunk: Data, at now: ContinuousClock.Instant) -> [MatchEvent] {
        var events: [MatchEvent] = []
        for line in assembler.feed(chunk) {
            events += matcher.match(line, at: now)
        }
        return events
    }
}
