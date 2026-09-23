import MicMuteCore

/// In-memory AudioSystem. Mutations fire `onChange` synchronously, like a CoreAudio listener would.
@MainActor
final class FakeAudioSystem: AudioSystem {
    struct Device {
        var name: String
        var canMute: Bool
        var canSetVolume: Bool
        var muted = false
        var volume: Float = 1
    }

    var devices: [DeviceID: Device] = [:]
    var onChange: (() -> Void)?

    func add(_ id: DeviceID, name: String = "Mic", canMute: Bool = true, canSetVolume: Bool = true, muted: Bool = false, volume: Float = 1) {
        devices[id] = Device(name: name, canMute: canMute, canSetVolume: canSetVolume, muted: muted, volume: volume)
        onChange?()
    }

    /// Simulates unplugging a device.
    func remove(_ id: DeviceID) {
        devices[id] = nil
        onChange?()
    }

    /// Simulates another app or the user changing the device outside MicMute.
    func externallySet(_ id: DeviceID, muted: Bool? = nil, volume: Float? = nil) {
        if let muted { devices[id]?.muted = muted }
        if let volume { devices[id]?.volume = volume }
        onChange?()
    }

    func inputDeviceIDs() -> [DeviceID] { devices.keys.sorted() }
    func name(of id: DeviceID) -> String { devices[id]?.name ?? "" }
    func uid(of id: DeviceID) -> String { "uid-\(id)" }

    func canSetMute(_ id: DeviceID) -> Bool { devices[id]?.canMute ?? false }
    func isMuted(_ id: DeviceID) -> Bool { devices[id]?.muted ?? false }
    func setMuted(_ id: DeviceID, _ muted: Bool) -> Bool {
        guard canSetMute(id) else { return false }
        devices[id]?.muted = muted
        onChange?()
        return true
    }

    func canSetVolume(_ id: DeviceID) -> Bool { devices[id]?.canSetVolume ?? false }
    func volume(_ id: DeviceID) -> Float { devices[id]?.volume ?? 0 }
    func setVolume(_ id: DeviceID, _ volume: Float) -> Bool {
        guard canSetVolume(id) else { return false }
        devices[id]?.volume = volume
        onChange?()
        return true
    }
}
