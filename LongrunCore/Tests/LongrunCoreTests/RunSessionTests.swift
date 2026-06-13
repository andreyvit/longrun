import Foundation
import Testing
@testable import LongrunCore

/// Captures sink events; safe to read from the test (MainActor) while RunSession
/// writes from the MainActor too — the lock is belt-and-suspenders.
final class RecordingSink: NotificationSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _matches: [(ruleID: String, line: String)] = []
    private var _exits: [ProcessExit] = []

    func didMatch(configID: String, ruleID: String, line: String) {
        lock.lock(); _matches.append((ruleID, line)); lock.unlock()
    }
    func didExitUnexpectedly(configID: String, exit: ProcessExit) {
        lock.lock(); _exits.append(exit); lock.unlock()
    }
    var matches: [(ruleID: String, line: String)] { lock.lock(); defer { lock.unlock() }; return _matches }
    var unexpectedExits: [ProcessExit] { lock.lock(); defer { lock.unlock() }; return _exits }
}

@MainActor final class OutputBox {
    private var data = Data()
    func append(_ chunk: Data) { data.append(chunk) }
    var text: String { String(decoding: data, as: UTF8.self) }
}

@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct RunSessionTests {
    // exec mode with `sh -c …` runs a non-interactive, non-login shell — no
    // profile sourcing, so deterministic (unlike the loginShell/bash modes).
    let baseEnv = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(),
                   "SHELL": "/bin/zsh", "TERM": "xterm"]

    func makeSession(
        _ command: String, notifyOnExit: Bool = true,
        rules: [NotificationRule] = [], sink: any NotificationSink = NoopNotificationSink()
    ) -> RunSession {
        var config = Configuration(command: command)
        config.launchMode = .exec
        config.notifyOnUnexpectedExit = notifyOnExit
        config.notificationRules = rules
        return RunSession(configuration: config, baseEnvironment: baseEnv,
                          helperURL: SpawnHelperFixture.url, sink: sink)
    }

    /// Poll until `predicate` holds or the deadline passes (the engine is async).
    func waitUntil(_ predicate: () -> Bool, within: Duration = .seconds(10)) async {
        let deadline = ContinuousClock.now.advanced(by: within)
        while !predicate() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func startThenCleanExitReachesExitedZero() async {
        let session = makeSession("sh -c 'exit 0'")
        session.start()
        await waitUntil { session.state == .exited(.code(0)) }
        #expect(session.state == .exited(.code(0)))
    }

    @Test func matchingLineRoutesToSink() async {
        let sink = RecordingSink()
        let session = makeSession(
            "sh -c 'echo PANIC: boom; exit 0'",
            rules: [NotificationRule(id: "r", pattern: "PANIC:", enabled: true)], sink: sink)
        session.start()
        await waitUntil { !sink.matches.isEmpty }
        #expect(sink.matches.first?.ruleID == "r")
        #expect(sink.matches.first?.line.contains("PANIC: boom") == true)
    }

    @Test func unexpectedExitNotifiesWhenToggleOn() async {
        let sink = RecordingSink()
        let session = makeSession("sh -c 'exit 3'", notifyOnExit: true, sink: sink)
        session.start()
        await waitUntil { !sink.unexpectedExits.isEmpty }
        #expect(sink.unexpectedExits == [.code(3)])
    }

    @Test func unexpectedExitDoesNotNotifyWhenToggleOff() async {
        let sink = RecordingSink()
        let session = makeSession("sh -c 'exit 3'", notifyOnExit: false, sink: sink)
        session.start()
        await waitUntil { if case .exited = session.state { return true }; return false }
        #expect(sink.unexpectedExits.isEmpty)
    }

    @Test func manualStopReachesIdleWithNoUnexpectedNotification() async {
        let sink = RecordingSink()
        let session = makeSession("sh -c 'sleep 100'", sink: sink)
        session.start()
        await waitUntil { session.state == .running }
        await session.stop()
        #expect(session.state == .idle)
        #expect(sink.unexpectedExits.isEmpty)
    }

    /// Number of lines a child appended to a counter file — proves how many
    /// times the process actually ran.
    private func runCount(_ url: URL) -> Int {
        (try? String(contentsOf: url, encoding: .utf8))?
            .split(whereSeparator: \.isNewline).count ?? 0
    }

    private func tempCounter() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "lr-run-\(UUID().uuidString)")
    }

    @Test func restartFromExitedRunsAgain() async {
        let counter = tempCounter()
        defer { try? FileManager.default.removeItem(at: counter) }
        let session = makeSession("sh -c 'echo run >> \(counter.path); exit 0'")
        session.start()
        await waitUntil { self.runCount(counter) == 1 }
        await session.restart()
        await waitUntil { self.runCount(counter) == 2 }
        #expect(runCount(counter) == 2)  // the process actually ran twice
    }

    @Test func restartFromRunningRelaunches() async {
        // Regression: restart() from a RUNNING process must relaunch, not race
        // stop()/handleExit and silently refuse the new start().
        let counter = tempCounter()
        defer { try? FileManager.default.removeItem(at: counter) }
        let session = makeSession("sh -c 'echo run >> \(counter.path); sleep 100'")
        session.start()
        await waitUntil { self.runCount(counter) == 1 }   // run 1 up and sleeping
        await session.restart()                            // restart from .running
        await waitUntil { self.runCount(counter) == 2 }    // run 2 actually executed
        #expect(runCount(counter) == 2)
        await session.stop()
    }

    @Test func startWhileRunningIsANoOp() async {
        let counter = tempCounter()
        defer { try? FileManager.default.removeItem(at: counter) }
        let session = makeSession("sh -c 'echo run >> \(counter.path); sleep 100'")
        session.start()
        await waitUntil { self.runCount(counter) == 1 && session.state == .running }
        session.start()  // already running → guarded no-op (no second spawn)
        session.start()
        #expect(runCount(counter) == 1)
        await session.stop()
    }

    @Test func onOutputChunkReceivesLiveOutput() async {
        let session = makeSession("sh -c 'echo live-output; exit 0'")
        let received = OutputBox()
        session.onOutputChunk = { received.append($0) }
        session.start()
        await waitUntil { received.text.contains("live-output") }
        #expect(received.text.contains("live-output"))
    }

    @Test func emptyCommandRecordsLaunchFailure() async {
        let session = makeSession("   ")
        session.start()
        await waitUntil { if case .exited = session.state { return true }; return false }
        #expect(session.state == .exited(.code(127)))
        #expect(String(decoding: session.bufferedOutput, as: UTF8.self).contains("no command configured"))
    }

    @Test func outputBufferCapsAtMax() async {
        // ~3 MB of output through the PTY; the tail buffer must cap at ~2 MB.
        let session = makeSession("sh -c 'yes longrun | head -c 3000000'")
        session.start()
        await waitUntil({ if case .exited = session.state { return true }; return false }, within: .seconds(30))
        #expect(session.bufferedOutput.count == RunSession.maxBufferBytes)
    }
}
