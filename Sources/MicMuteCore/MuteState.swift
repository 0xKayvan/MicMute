/// Single source of truth for whether the microphones should be muted.
/// Every trigger (status item, hotkeys, Stream Deck) goes through here.
@MainActor
public final class MuteState {
    public struct Snapshot: Equatable, Sendable {
        public let muted: Bool
        public let pttActive: Bool

        public init(muted: Bool, pttActive: Bool) {
            self.muted = muted
            self.pttActive = pttActive
        }
    }

    public struct Change: Equatable, Sendable {
        public let snapshot: Snapshot
        public let mutedChanged: Bool
        public let viaPTT: Bool

        public init(snapshot: Snapshot, mutedChanged: Bool, viaPTT: Bool) {
            self.snapshot = snapshot
            self.mutedChanged = mutedChanged
            self.viaPTT = viaPTT
        }
    }

    /// The user's toggle state, ignoring push-to-talk.
    public private(set) var isMuted: Bool
    private var pttSources: Set<AnyHashable> = []
    private let apply: (Bool) -> Void
    private var observers: [(Change) -> Void] = []

    public init(initiallyMuted: Bool, apply: @escaping (Bool) -> Void) {
        isMuted = initiallyMuted
        self.apply = apply
    }

    public var pttActive: Bool { !pttSources.isEmpty }
    public var effectiveMuted: Bool { isMuted && !pttActive }
    public var snapshot: Snapshot { Snapshot(muted: effectiveMuted, pttActive: pttActive) }

    public func addObserver(_ observer: @escaping (Change) -> Void) {
        observers.append(observer)
    }

    public func toggle() { setMuted(!isMuted) }

    public func setMuted(_ muted: Bool) {
        update(viaPTT: false) { isMuted = muted }
    }

    public func pttBegin(source: AnyHashable) {
        update(viaPTT: true) { pttSources.insert(source) }
    }

    public func pttEnd(source: AnyHashable) {
        update(viaPTT: true) { pttSources.remove(source) }
    }

    private func update(viaPTT: Bool, _ mutate: () -> Void) {
        let before = snapshot
        mutate()
        let after = snapshot
        guard after != before else { return }
        let mutedChanged = after.muted != before.muted
        if mutedChanged { apply(after.muted) }
        let change = Change(snapshot: after, mutedChanged: mutedChanged, viaPTT: viaPTT)
        observers.forEach { $0(change) }
    }
}
