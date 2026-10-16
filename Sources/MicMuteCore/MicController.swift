import Foundation

public enum MuteMethod: Equatable, Sendable {
    case mute, volume, unsupported
}

/// Why a device MicMute mutes may still be heard.
public enum MuteWarning: Equatable, Sendable {
    /// Volume 0 still passes sound, e.g. a USB mic whose input range is 0…+40 dB.
    case notSilentAtZeroVolume
    /// Another app keeps undoing the mute, e.g. a browser call's auto-gain raising the volume.
    case contested
}

public struct DeviceStatus: Equatable, Sendable {
    public let name: String
    public let method: MuteMethod
    public let isMuted: Bool
    public let warnings: [MuteWarning]

    public init(name: String, method: MuteMethod, isMuted: Bool, warnings: [MuteWarning] = []) {
        self.name = name
        self.method = method
        self.isMuted = isMuted
        self.warnings = warnings
    }

    public var summary: String {
        let state = isMuted ? "Muted" : "Live"
        let base: String
        switch method {
        case .mute: base = "\(name) — \(state)"
        case .volume: base = "\(name) — \(state) (via volume)"
        case .unsupported: return "\(name) — ⚠︎ can't mute"
        }
        guard !warnings.isEmpty else { return base }
        return base + " ⚠︎ " + warnings.map(explanation).joined(separator: "; ")
    }

    private func explanation(_ warning: MuteWarning) -> String {
        switch warning {
        case .notSilentAtZeroVolume: "not silent at volume 0"
        case .contested: method == .volume ? "another app keeps raising its volume" : "another app keeps unmuting it"
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
    /// Times of recent re-mutes (devices something else un-muted while muted), by UID.
    private var reMuteTimes: [String: [TimeInterval]] = [:]
    /// UIDs of devices another app keeps un-muting; cleared once they stay muted for `contestWindow`.
    private var contestedUIDs: Set<String> = []
    private var contestExpiryScheduled = false
    /// Whether volume 0 silences a volume-fallback device, by UID (only devices that report a floor).
    private var silentAtZeroVolume: [String: Bool] = [:]
    public private(set) var desiredMuted = false
    /// True while muted and at least one device may still be heard (see `MuteWarning`).
    public private(set) var hasMuteWarnings = false
    /// Called when `hasMuteWarnings` changes.
    public var onWarningsChanged: (() -> Void)?
    private let now: () -> TimeInterval
    private let schedule: ChangeThrottle.Schedule

    public init(
        audio: AudioSystem,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        schedule: @escaping ChangeThrottle.Schedule = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(work) }
        }
    ) {
        self.audio = audio
        self.now = now
        self.schedule = schedule
        audio.onChange = { [weak self] in self?.enforce() }
    }

    /// This many re-mutes of one device within `contestWindow` mean another app is fighting the
    /// mute; fewer are a one-off change by a person or an app.
    private static let contestThreshold = 3
    private static let contestWindow: TimeInterval = 2
    /// Gain at volume 0 at or below this counts as silent: speech ends up under a call's noise floor.
    private static let silentFloorDecibels: Float = -60

    public func apply(muted: Bool) {
        desiredMuted = muted
        // Contests are about the current mute; a new state starts clean.
        reMuteTimes = [:]
        contestedUIDs = []
        audio.inputDeviceIDs().forEach { apply(muted, to: $0) }
        refreshMuteWarnings()
    }

    public var deviceStatuses: [DeviceStatus] {
        audio.inputDeviceIDs().map { id in
            let method = method(of: id)
            let isMuted = switch method {
            case .mute: audio.isMuted(id)
            case .volume: audio.volume(id) == 0
            case .unsupported: false
            }
            return DeviceStatus(name: audio.name(of: id), method: method, isMuted: isMuted,
                                warnings: warnings(for: id, method: method))
        }
    }

    /// True when at least one device can be muted and every such device currently is.
    public var allMuted: Bool {
        let controllable = deviceStatuses.filter { $0.method != .unsupported }
        return !controllable.isEmpty && controllable.allSatisfy(\.isMuted)
    }

    private func enforce() {
        if desiredMuted {
            audio.inputDeviceIDs().forEach { id in
                if apply(true, to: id) { recordReMute(audio.uid(of: id)) }
            }
        } else {
            // Only devices MicMute itself muted and never got to restore (e.g. unplugged while
            // muted); anything else the user muted externally is left alone.
            audio.inputDeviceIDs()
                .filter { let uid = audio.uid(of: $0); return mutedUIDs.contains(uid) || savedVolumes[uid] != nil }
                .forEach { apply(false, to: $0) }
        }
        refreshMuteWarnings()
    }

    /// Returns whether it had to mute a device that wasn't muted.
    @discardableResult
    private func apply(_ muted: Bool, to id: DeviceID) -> Bool {
        if audio.canSetMute(id) {
            let uid = audio.uid(of: id)
            if muted {
                guard !audio.isMuted(id), audio.setMuted(id, true) else { return false }
                mutedUIDs.insert(uid)
                return true
            }
            // Forget before writing: the write re-enters enforce() via onChange.
            mutedUIDs.remove(uid)
            if audio.isMuted(id), !audio.setMuted(id, false) { mutedUIDs.insert(uid) }
        } else if audio.canSetVolume(id) {
            if muted { return muteByVolume(id) }
            unmuteByVolume(id)
        }
        return false
    }

    private func muteByVolume(_ id: DeviceID) -> Bool {
        let current = audio.volume(id)
        guard current > 0 else { return false }
        // Keep the level from before the mute: raises while muted (e.g. an app's auto-gain) aren't the user's.
        let uid = audio.uid(of: id)
        if savedVolumes[uid] == nil { savedVolumes[uid] = current }
        return audio.setVolume(id, 0)
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

    // MARK: - Warnings

    private func method(of id: DeviceID) -> MuteMethod {
        if audio.canSetMute(id) { return .mute }
        if audio.canSetVolume(id) { return .volume }
        return .unsupported
    }

    private func warnings(for id: DeviceID, method: MuteMethod) -> [MuteWarning] {
        guard method != .unsupported else { return [] }
        let uid = audio.uid(of: id)
        var warnings: [MuteWarning] = []
        if method == .volume, !isSilentAtZeroVolume(id, uid: uid) { warnings.append(.notSilentAtZeroVolume) }
        if contestedUIDs.contains(uid) { warnings.append(.contested) }
        return warnings
    }

    private func isSilentAtZeroVolume(_ id: DeviceID, uid: String) -> Bool {
        if let known = silentAtZeroVolume[uid] { return known }
        // No reported floor: don't warn, and ask again next time.
        guard let floor = audio.volumeFloorDecibels(id) else { return true }
        let silent = floor <= Self.silentFloorDecibels
        silentAtZeroVolume[uid] = silent
        return silent
    }

    private func refreshMuteWarnings() {
        let warned = desiredMuted && audio.inputDeviceIDs().contains { !warnings(for: $0, method: method(of: $0)).isEmpty }
        guard warned != hasMuteWarnings else { return }
        hasMuteWarnings = warned
        onWarningsChanged?()
    }

    private func recordReMute(_ uid: String) {
        let time = now()
        var times = reMuteTimes[uid, default: []].filter { time - $0 < Self.contestWindow }
        times.append(time)
        reMuteTimes[uid] = times
        if times.count >= Self.contestThreshold { contestedUIDs.insert(uid) }
        scheduleContestExpiry()
    }

    /// Checks again when the device that re-muted longest ago could next have gone quiet.
    private func scheduleContestExpiry() {
        guard !contestExpiryScheduled, let next = reMuteTimes.values.compactMap(\.last).min() else { return }
        contestExpiryScheduled = true
        schedule(max(0, next + Self.contestWindow - now())) { [weak self] in self?.expireContests() }
    }

    private func expireContests() {
        contestExpiryScheduled = false
        let time = now()
        reMuteTimes = reMuteTimes.compactMapValues { times in
            let recent = times.filter { time - $0 < Self.contestWindow }
            return recent.isEmpty ? nil : recent
        }
        contestedUIDs.formIntersection(reMuteTimes.keys)
        scheduleContestExpiry()
        refreshMuteWarnings()
    }
}
