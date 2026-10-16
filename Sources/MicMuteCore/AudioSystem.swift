public typealias DeviceID = UInt32

/// Abstraction over the CoreAudio HAL so mute logic can be tested with a fake.
@MainActor
public protocol AudioSystem: AnyObject {
    /// Called (on the main queue) when the device list or any input device's mute/volume changes.
    /// A burst of changes may be coalesced into one call.
    var onChange: (() -> Void)? { get set }

    func inputDeviceIDs() -> [DeviceID]
    func name(of id: DeviceID) -> String
    func uid(of id: DeviceID) -> String

    func canSetMute(_ id: DeviceID) -> Bool
    func isMuted(_ id: DeviceID) -> Bool
    @discardableResult func setMuted(_ id: DeviceID, _ muted: Bool) -> Bool

    func canSetVolume(_ id: DeviceID) -> Bool
    func volume(_ id: DeviceID) -> Float
    @discardableResult func setVolume(_ id: DeviceID, _ volume: Float) -> Bool
}
