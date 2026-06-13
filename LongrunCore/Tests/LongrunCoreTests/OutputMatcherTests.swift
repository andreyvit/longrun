import Testing
@testable import LongrunCore

@Suite struct OutputMatcherTests {

    private func rule(_ id: String, _ pattern: String, enabled: Bool = true) -> NotificationRule {
        NotificationRule(id: id, pattern: pattern, enabled: enabled)
    }

    private let t0 = ContinuousClock().now

    // MARK: rule selection

    @Test func matchesAnEnabledRuleAnywhereInTheLine() {
        var m = OutputMatcher(rules: [rule("r", "panic:")])
        #expect(m.match("goroutine panic: boom", at: t0).map(\.ruleID) == ["r"])
        #expect(m.match("all good", at: t0).isEmpty)
    }

    @Test func skipsDisabledRules() {
        var m = OutputMatcher(rules: [rule("r", "panic:", enabled: false)])
        #expect(m.isEmpty)
        #expect(m.match("panic: x", at: t0).isEmpty)
    }

    @Test func skipsEmptyPatterns() {
        var m = OutputMatcher(rules: [rule("r", "")])
        #expect(m.isEmpty)
        #expect(m.match("anything", at: t0).isEmpty)
    }

    @Test func skipsUncompilablePatternsWithoutCrashing() {
        var m = OutputMatcher(rules: [rule("bad", "[unterminated"), rule("good", "ok")])
        #expect(m.match("[unterminated and ok", at: t0).map(\.ruleID) == ["good"])
    }

    @Test func multipleRulesBothFireOnOneLine() {
        var both = OutputMatcher(rules: [rule("a", "foo"), rule("b", "bar")])
        #expect(Set(both.match("foo and bar", at: t0).map(\.ruleID)) == ["a", "b"])

        // Fresh matcher so the previous fire's cooldown doesn't interfere.
        var one = OutputMatcher(rules: [rule("a", "foo"), rule("b", "bar")])
        #expect(one.match("only foo", at: t0).map(\.ruleID) == ["a"])
    }

    @Test func emptyRuleSetIsEmptyAndMatchesNothing() {
        var m = OutputMatcher(rules: [])
        #expect(m.isEmpty)
        #expect(m.match("x", at: t0).isEmpty)
    }

    // MARK: regex semantics

    @Test func startAnchorWorks() {
        var m = OutputMatcher(rules: [rule("r", "^ERROR")])
        #expect(m.match("ERROR: bad", at: t0).map(\.ruleID) == ["r"])
        #expect(m.match("an ERROR happened", at: t0).isEmpty)
    }

    @Test func endAnchorWorks() {
        var m = OutputMatcher(rules: [rule("r", "done$")])
        #expect(m.match("build done", at: t0).map(\.ruleID) == ["r"])
        #expect(m.match("done building", at: t0).isEmpty)
    }

    @Test func matchingIsCaseSensitiveUnlessFlagged() {
        var sensitive = OutputMatcher(rules: [rule("r", "error")])
        #expect(sensitive.match("ERROR", at: t0).isEmpty)

        var insensitive = OutputMatcher(rules: [rule("r", "(?i)error")])
        #expect(insensitive.match("ERROR", at: t0).map(\.ruleID) == ["r"])
    }

    // MARK: cooldown

    @Test func cooldownSuppressesWithinWindowAndFiresAfter() {
        var m = OutputMatcher(rules: [rule("r", "x")], cooldown: .seconds(10))
        #expect(m.match("x", at: t0).map(\.ruleID) == ["r"])                       // fires
        #expect(m.match("x", at: t0.advanced(by: .seconds(5))).isEmpty)            // cooled
        #expect(m.match("x", at: t0.advanced(by: .seconds(9))).isEmpty)            // still cooled (just below)
        #expect(m.match("x", at: t0.advanced(by: .seconds(10))).map(\.ruleID) == ["r"])  // window elapsed → fires
        #expect(m.match("x", at: t0.advanced(by: .seconds(12))).isEmpty)           // cooled again
    }

    @Test func cooldownIsPerRuleIndependent() {
        var m = OutputMatcher(rules: [rule("a", "aa"), rule("b", "bb")], cooldown: .seconds(10))
        #expect(m.match("aa", at: t0).map(\.ruleID) == ["a"])               // a fires, a cooling
        #expect(m.match("bb", at: t0.advanced(by: .seconds(1))).map(\.ruleID) == ["b"])  // b still fires
        #expect(m.match("aa", at: t0.advanced(by: .seconds(2))).isEmpty)    // a still cooling
    }

    @Test func firstOfABatchFiresAndRestCoolAtSameInstant() {
        var m = OutputMatcher(rules: [rule("r", "spam")], cooldown: .seconds(10))
        // Same instant (a single feed of many matching lines).
        #expect(m.match("spam 1", at: t0).map(\.line) == ["spam 1"])
        #expect(m.match("spam 2", at: t0).isEmpty)
        #expect(m.match("spam 3", at: t0).isEmpty)
    }
}
