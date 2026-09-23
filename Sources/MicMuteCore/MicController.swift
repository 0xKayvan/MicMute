public enum MuteMethod: Equatable, Sendable {
    case mute, volume, unsupported
}

public struct DeviceStatus: Equatable, Sendable {
    public let name: String
    public let method: MuteMethod
    public let isMuted: Bool

    public init(name: String, method: MuteMethod, isMuted: Bool) {
        self.name = name
        self.method = method
        self.isMuted = isMuted
    }

    public var summary: String {
        let state = isMuted ? "Muted" : "Live"
        switch method {
        case .mute: return "\(name) — \(state)"
        case .volume: return "\(name) — \(state) (via volume)"
        case .unsupported: return "\(name) — ⚠︎ can't mute"
        }
    }
}

/// Applies the desired mute state to every input device and keeps it applied while muted.
/// Devices without a mute control are muted by setting input volume to 0 and restoring it later.
@MainActor
public final class MicController {
    private let audio: AudioSystem
    private var savedVolumes: [String: Float] = [:]
    public private(set) var desiredMuted = false

    public init(audio: AudioSystem) {
        self.audio = audio
        audio.onChange = { [weak self] in self?.enforce() }
    }

    public func apply(muted: Bool) {
        desiredMuted = muted
        audio.inputDeviceIDs().forEach { apply(muted, to: $0) }
    }

    public var deviceStatuses: [DeviceStatus] {
        audio.inputDeviceIDs().map { id in
            let name = audio.name(of: id)
            if audio.canSetMute(id) { return DeviceStatus(name: name, method: .mute, isMuted: audio.isMuted(id)) }
            if audio.canSetVolume(id) { return DeviceStatus(name: name, method: .volume, isMuted: audio.volume(id) == 0) }
            return DeviceStatus(name: name, method: .unsupported, isMuted: false)
        }
    }

    /// True when at least one device can be muted and every such device currently is.
    public var allMuted: Bool {
        let controllable = deviceStatuses.filter { $0.method != .unsupported }
        return !controllable.isEmpty && controllable.allSatisfy(\.isMuted)
    }

    private func enforce() {
        guard desiredMuted else { return }
        audio.inputDeviceIDs().forEach { apply(true, to: $0) }
    }

    private func apply(_ muted: Bool, to id: DeviceID) {
        if audio.canSetMute(id) {
            if audio.isMuted(id) != muted { audio.setMuted(id, muted) }
        } else if audio.canSetVolume(id) {
            muted ? muteByVolume(id) : unmuteByVolume(id)
        }
    }

    private func muteByVolume(_ id: DeviceID) {
        let current = audio.volume(id)
        guard current > 0 else { return }
        savedVolumes[audio.uid(of: id)] = current
        audio.setVolume(id, 0)
    }

    private func unmuteByVolume(_ id: DeviceID) {
        if let saved = savedVolumes.removeValue(forKey: audio.uid(of: id)) {
            audio.setVolume(id, saved)
        } else if audio.volume(id) == 0 {
            audio.setVolume(id, 1)
        }
    }
}
