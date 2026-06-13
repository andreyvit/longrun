/// The lifecycle state of a configuration's process, as shown in the sidebar.
public enum ProcessState: Equatable, Sendable {
    case idle             // never started, manually stopped, or exited cleanly (restart=Never)
    case running
    case stopping         // stop requested, awaiting exit
    case restartPending   // exited, awaiting the 1s relaunch (ST10)
    case exited(ProcessExit)
    case failed(ProcessExit)  // crash-loop breaker tripped (ST10)
}

/// Where a RunSession sends notification-worthy events. The real implementation
/// (`Notifier`, ST15) posts macOS notifications; the default does nothing.
public protocol NotificationSink: Sendable {
    func didMatch(configID: String, ruleID: String, line: String)
    func didExitUnexpectedly(configID: String, exit: ProcessExit)
}

public struct NoopNotificationSink: NotificationSink {
    public init() {}
    public func didMatch(configID: String, ruleID: String, line: String) {}
    public func didExitUnexpectedly(configID: String, exit: ProcessExit) {}
}
