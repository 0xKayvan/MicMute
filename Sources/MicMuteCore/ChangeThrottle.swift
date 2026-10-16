import Foundation

/// Coalesces bursts of change requests and runs `action` at most once per `interval`: on the next
/// main-queue turn when idle, otherwise as soon as `interval` has passed since the last run.
/// A request is never dropped, so the last change of a burst is always acted on.
@MainActor
public final class ChangeThrottle {
    public typealias Schedule = (_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Void

    private let interval: TimeInterval
    private let now: () -> TimeInterval
    private let schedule: Schedule
    private let action: () -> Void
    private var lastRun: TimeInterval?
    private var pending = false

    public init(
        interval: TimeInterval,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        schedule: @escaping Schedule = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(work) }
        },
        action: @escaping () -> Void
    ) {
        self.interval = interval
        self.now = now
        self.schedule = schedule
        self.action = action
    }

    public func request() {
        guard !pending else { return }
        pending = true
        let delay = lastRun.map { max(0, $0 + interval - now()) } ?? 0
        schedule(delay) { [weak self] in self?.run() }
    }

    private func run() {
        // Cleared first so a request made by `action` itself schedules the next run.
        pending = false
        lastRun = now()
        action()
    }
}
