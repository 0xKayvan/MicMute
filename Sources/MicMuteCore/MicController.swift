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
    /// Volume-fallback devices MicMute zeroed, by UID, with the volume to restore.
    private var savedVolumes: [String: Float] = [:]
    /// UIDs of devices MicMute muted via their mute control and has not yet unmuted.
    /// Survives unplugging: CoreAudio restores a device's last mute/volume on replug, so a
    /// device that left while muted is unmuted/restored when it returns after the user unmuted.
    private var mutedUIDs: Set<String> = []
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
        if desiredMuted {
            audio.inputDeviceIDs().forEach { apply(true, to: $0) }
        } else {
            // Only devices MicMute itself muted and never got to restore (e.g. unplugged while
            // muted); anything else the user muted externally is left alone.
            audio.inputDeviceIDs()
                .filter { let uid = audio.uid(of: $0); return mutedUIDs.contains(uid) || savedVolumes[uid] != nil }
                .forEach { apply(false, to: $0) }
        }
    }

    private func apply(_ muted: Bool, to id: DeviceID) {
        if audio.canSetMute(id) {
            let uid = audio.uid(of: id)
            if muted {
                if !audio.isMuted(id), audio.setMuted(id, true) { mutedUIDs.insert(uid) }
            } else {
                // Forget before writing: the write re-enters enforce() via onChange.
                mutedUIDs.remove(uid)
                if audio.isMuted(id), !audio.setMuted(id, false) { mutedUIDs.insert(uid) }
            }
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
        let uid = audio.uid(of: id)
        if let saved = savedVolumes.removeValue(forKey: uid) {
            // Forget before writing (the write re-enters enforce()); keep it if the write fails.
            if !audio.setVolume(id, saved) { savedVolumes[uid] = saved }
        } else if audio.volume(id) == 0 {
            audio.setVolume(id, 1)
        }
    }
}
