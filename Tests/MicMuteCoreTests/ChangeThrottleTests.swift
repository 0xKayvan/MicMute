import Foundation
import Testing
import MicMuteCore

/// Virtual time for `ChangeThrottle`: scheduled work runs only when time is advanced past it.
@MainActor
final class ManualClock {
    private(set) var time: TimeInterval = 0
    private var scheduled: [(at: TimeInterval, work: @MainActor () -> Void)] = []

    func schedule(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        scheduled.append((time + delay, work))
    }

    /// Advances time by `seconds`, running due work in order (work may schedule more).
    func advance(by seconds: TimeInterval) {
        let end = time + seconds
        while let next = scheduled.indices.filter({ scheduled[$0].at <= end }).min(by: { scheduled[$0].at < scheduled[$1].at }) {
            let item = scheduled.remove(at: next)
            time = item.at
            item.work()
        }
        time = end
    }
}

@MainActor
@Suite struct ChangeThrottleTests {
    let clock = ManualClock()

    func makeThrottle(interval: TimeInterval = 0.1, action: @escaping () -> Void) -> ChangeThrottle {
        ChangeThrottle(interval: interval, now: { [clock] in clock.time },
                       schedule: { [clock] delay, work in clock.schedule(delay, work) }, action: action)
    }

    @Test func runsOnceForABurstOnTheNextTurn() {
        var runs = 0
        let throttle = makeThrottle { runs += 1 }
        for _ in 0..<5 { throttle.request() }
        #expect(runs == 0)
        clock.advance(by: 0)
        #expect(runs == 1)
    }

    @Test func defersARequestWithinTheIntervalUntilItEnds() {
        var runs = 0
        let throttle = makeThrottle { runs += 1 }
        throttle.request()
        clock.advance(by: 0.03)
        throttle.request()
        clock.advance(by: 0.06) // t = 0.09, still inside the interval
        #expect(runs == 1)
        clock.advance(by: 0.02) // t = 0.11
        #expect(runs == 2)
    }

    @Test func runsImmediatelyAgainOnceIdleForTheInterval() {
        var runs = 0
        let throttle = makeThrottle { runs += 1 }
        throttle.request()
        clock.advance(by: 0.5)
        throttle.request()
        clock.advance(by: 0)
        #expect(runs == 2)
    }

    @Test func requestFromInsideTheActionIsDeferredNotRecursive() {
        var runs = 0
        var throttle: ChangeThrottle!
        throttle = makeThrottle {
            runs += 1
            throttle.request() // e.g. our own write firing the listener again
        }
        throttle.request()
        clock.advance(by: 0)
        #expect(runs == 1)
        clock.advance(by: 0.1)
        #expect(runs == 2)
    }

    /// Another app writing every 10 ms, plus each run's own write notifying again.
    @Test func boundsTheRateUnderAContinuousFight() {
        var runs = 0
        var throttle: ChangeThrottle!
        throttle = makeThrottle {
            runs += 1
            throttle.request()
        }
        for _ in 0..<100 {
            throttle.request()
            clock.advance(by: 0.01)
        }
        #expect(runs <= 11)
        #expect(runs >= 9)
    }
}
