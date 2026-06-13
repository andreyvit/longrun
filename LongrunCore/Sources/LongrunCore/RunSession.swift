import Foundation
import Observation
import os

/// The per-configuration model: owns a `ProcessRunner`, drives its lifecycle,
/// tracks the displayed `state`, buffers output for the terminal, and routes
/// matches / unexpected exits to a `NotificationSink`.
///
/// Lives in LongrunCore (not the app target) so the state machine stays
/// `swift test`-able; `@Observable` here is the `Observation` framework, not
/// SwiftUI, so the headless boundary holds. Automatic restart + the crash-loop
/// breaker are layered on in ST10.
@MainActor
@Observable
public final class RunSession {
    private static let log = Logger(subsystem: "com.tarantsov.Longrun", category: "RunSession")
    static let maxBufferBytes = 2 * 1024 * 1024  // tail-capped output for terminal replay
    static let defaultColumns = 80
    static let defaultRows = 24

    public let id: String
    /// The current configuration. AppModel updates it on edit; the running
    /// process keeps the config it started with — the next start picks up changes.
    public var configuration: Configuration
    public private(set) var state: ProcessState = .idle

    /// Live output for a single attached terminal view (set by TerminalPane,
    /// ST14): single-consumer, replace-don't-add, cleared on detach. The pane
    /// replays `bufferedOutput` on attach, then receives live chunks here.
    @ObservationIgnored public var onOutputChunk: ((Data) -> Void)?

    @ObservationIgnored private let baseEnvironment: [String: String]
    @ObservationIgnored private let helperURL: URL
    @ObservationIgnored private let sink: any NotificationSink
    @ObservationIgnored private var outputBuffer = Data()
    @ObservationIgnored private var runner: ProcessRunner?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var outputDrainTask: Task<Void, Never>?
    @ObservationIgnored private var manualStop = false
    @ObservationIgnored private var columns = RunSession.defaultColumns
    @ObservationIgnored private var rows = RunSession.defaultRows

    public init(
        configuration: Configuration,
        baseEnvironment: [String: String],
        helperURL: URL,
        sink: any NotificationSink = NoopNotificationSink()
    ) {
        self.id = configuration.id
        self.configuration = configuration
        self.baseEnvironment = baseEnvironment
        self.helperURL = helperURL
        self.sink = sink
    }

    public var isActive: Bool {
        switch state {
        case .running, .stopping, .restartPending: return true
        case .idle, .exited, .failed: return false
        }
    }

    /// The buffered output, for the terminal pane to replay on attach.
    public var bufferedOutput: Data { outputBuffer }

    // MARK: lifecycle

    public func start() {
        guard !isActive else { return }
        runTask?.cancel()
        outputDrainTask?.cancel()
        manualStop = false
        let config = configuration
        runTask = Task { await self.run(config) }
    }

    public func stop() async {
        guard isActive, let runner else { return }
        manualStop = true
        state = .stopping
        await runner.stop()
        // Wait for run() to finish (its waitForExit → handleExit settles the
        // state) so that, by the time stop() returns, the state is no longer
        // .stopping — otherwise restart()'s start() would race handleExit and
        // see .stopping (still active) and silently refuse to relaunch.
        await runTask?.value
    }

    public func restart() async {
        await stop()
        start()
    }

    /// Forward a terminal-view resize to the running process.
    public func resize(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        runner?.resize(columns: columns, rows: rows)
    }

    private func run(_ config: Configuration) async {
        let request: SpawnRequest
        do {
            request = try SpawnPlanner.plan(
                configuration: config, baseEnvironment: baseEnvironment,
                helperURL: helperURL, columns: columns, rows: rows)
        } catch {
            recordLaunchFailure(error)
            return
        }

        let runner: ProcessRunner
        do {
            runner = try ProcessRunner(request)
        } catch {
            recordLaunchFailure(error)
            return
        }
        self.runner = runner
        outputBuffer.removeAll(keepingCapacity: true)
        state = .running

        // Off-main matching, only when there's something to match for.
        let pipeline: MatchingPipeline? =
            config.notificationRules.contains { $0.enabled && !$0.pattern.isEmpty }
            ? MatchingPipeline(rules: config.notificationRules, cooldown: OutputMatcher.defaultCooldown)
            : nil

        let id = self.id
        let sink = self.sink
        outputDrainTask = Task { @MainActor [weak self] in
            for await chunk in runner.output {
                let events = await pipeline?.process(chunk, at: ContinuousClock.now) ?? []
                guard let self else { continue }
                self.append(chunk)
                self.onOutputChunk?(chunk)
                for event in events {
                    sink.didMatch(configID: id, ruleID: event.ruleID, line: event.line)
                }
            }
        }

        let exit = await runner.waitForExit()
        handleExit(exit, config: config)
        // outputDrainTask keeps draining until EOF (which may trail the exit);
        // it's cancelled on the next start().
    }

    private func handleExit(_ exit: ProcessExit, config: Configuration) {
        runner = nil
        if manualStop {
            state = .idle
            return
        }
        state = .exited(exit)
        Self.log.notice("session \(self.id, privacy: .public) exited unexpectedly")
        if config.notifyOnUnexpectedExit {
            sink.didExitUnexpectedly(configID: id, exit: exit)
        }
    }

    private func recordLaunchFailure(_ error: Error) {
        let message: String
        switch error {
        case LaunchError.emptyCommand: message = "longrun: no command configured\n"
        case LaunchError.invalidCommand: message = "longrun: invalid command (check quoting)\n"
        default: message = "longrun: failed to launch: \(error)\n"
        }
        Self.log.error("session \(self.id, privacy: .public) launch failed: \(message, privacy: .public)")
        let data = Data(message.utf8)
        append(data)
        onOutputChunk?(data)
        state = .exited(.code(127))
    }

    private func append(_ chunk: Data) {
        outputBuffer.append(chunk)
        if outputBuffer.count > Self.maxBufferBytes {
            outputBuffer.removeFirst(outputBuffer.count - Self.maxBufferBytes)
        }
    }
}
