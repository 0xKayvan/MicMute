import CoreAudio
import Foundation
import os

/// CoreAudio HAL implementation of `AudioSystem`. Listener callbacks arrive on the main queue and are
/// coalesced into at most one `onChange` per `changeInterval`, so an app rewriting a property in a
/// tight loop (e.g. browser auto-gain raising a volume-muted mic) can't swamp the main thread.
///
/// Mute/volume use the input scope's main element when it is settable, otherwise each input channel
/// element (1...n) that is settable — some USB interfaces only expose per-channel controls.
@MainActor
public final class CoreAudioSystem: AudioSystem {
    public static let changeInterval: TimeInterval = 0.1

    public var onChange: (() -> Void)?

    private let log = Logger(subsystem: "xyz.kayvan.micmute", category: "audio")
    /// Devices with mute/volume listeners.
    private var watchedDevices: Set<DeviceID> = []
    /// Devices with an input-scope stream-configuration listener (every device, input or not).
    private var streamWatchedDevices: Set<DeviceID> = []
    /// Set when a pending change may have added or removed input devices.
    private var needsRescan = false
    private lazy var throttle = ChangeThrottle(interval: Self.changeInterval) { [weak self] in self?.handleChanges() }
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] count, addresses in
        let rescan = UnsafeBufferPointer(start: addresses, count: Int(count)).contains {
            $0.mSelector == kAudioHardwarePropertyDevices || $0.mSelector == kAudioDevicePropertyStreamConfiguration
        }
        MainActor.assumeIsolated { self?.changeReported(rescan: rescan) }
    }

    public init() {
        var address = Self.address(kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal)
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        if status != noErr { log.error("Device list listener failed: \(status)") }
        watchInputDevices()
    }

    public func inputDeviceIDs() -> [DeviceID] {
        allDeviceIDs().filter { inputChannelCount($0) > 0 }
    }

    public func name(of id: DeviceID) -> String {
        string(id, kAudioObjectPropertyName) ?? "Unknown device"
    }

    public func uid(of id: DeviceID) -> String {
        string(id, kAudioDevicePropertyDeviceUID) ?? "device-\(id)"
    }

    public func canSetMute(_ id: DeviceID) -> Bool {
        !settableElements(id, kAudioDevicePropertyMute).isEmpty
    }

    public func isMuted(_ id: DeviceID) -> Bool {
        let elements = settableElements(id, kAudioDevicePropertyMute)
        return !elements.isEmpty && elements.allSatisfy {
            (read(id, kAudioDevicePropertyMute, element: $0) as UInt32?) == 1
        }
    }

    @discardableResult
    public func setMuted(_ id: DeviceID, _ muted: Bool) -> Bool {
        let elements = settableElements(id, kAudioDevicePropertyMute)
        let value: UInt32 = muted ? 1 : 0
        return !elements.isEmpty && elements.allSatisfy { write(id, kAudioDevicePropertyMute, element: $0, value: value) }
    }

    public func canSetVolume(_ id: DeviceID) -> Bool {
        !settableElements(id, kAudioDevicePropertyVolumeScalar).isEmpty
    }

    public func volume(_ id: DeviceID) -> Float {
        settableElements(id, kAudioDevicePropertyVolumeScalar)
            .compactMap { read(id, kAudioDevicePropertyVolumeScalar, element: $0) as Float32? }
            .max() ?? 0
    }

    @discardableResult
    public func setVolume(_ id: DeviceID, _ volume: Float) -> Bool {
        let elements = settableElements(id, kAudioDevicePropertyVolumeScalar)
        return !elements.isEmpty && elements.allSatisfy {
            write(id, kAudioDevicePropertyVolumeScalar, element: $0, value: Float32(volume))
        }
    }

    /// The loudest floor among the elements `setVolume` writes.
    public func volumeFloorDecibels(_ id: DeviceID) -> Float? {
        settableElements(id, kAudioDevicePropertyVolumeScalar)
            .compactMap { decibelRange(id, element: $0)?.mMinimum }
            .max()
            .map(Float.init)
    }

    // MARK: - Change listening

    private func changeReported(rescan: Bool) {
        needsRescan = needsRescan || rescan
        throttle.request()
    }

    private func handleChanges() {
        // Mute/volume changes can't add devices; only rescan (it queries every device) when needed.
        if needsRescan {
            needsRescan = false
            watchInputDevices()
        }
        onChange?()
    }

    /// Adds mute/volume listeners to input devices we haven't seen yet, and a stream-configuration
    /// listener to every device so one whose input stream appears later (e.g. Bluetooth switching
    /// to its mic profile) is picked up. Listeners on removed devices disappear with the device,
    /// so we only need to forget their IDs; a device that merely loses its input stream keeps
    /// its listeners and stays in `watchedDevices`, avoiding duplicate registrations.
    private func watchInputDevices() {
        let all = Set(allDeviceIDs())
        for id in all.subtracting(streamWatchedDevices) {
            var address = Self.address(kAudioDevicePropertyStreamConfiguration)
            let status = AudioObjectAddPropertyListenerBlock(id, &address, .main, listener)
            if status != noErr { log.error("Stream configuration listener on device \(id) failed: \(status)") }
        }
        streamWatchedDevices = all

        let inputs = Set(inputDeviceIDs())
        for id in inputs.subtracting(watchedDevices) {
            for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar] {
                var address = Self.address(selector, element: kAudioObjectPropertyElementWildcard)
                AudioObjectAddPropertyListenerBlock(id, &address, .main, listener)
            }
        }
        watchedDevices = watchedDevices.intersection(all).union(inputs)
    }

    // MARK: - HAL helpers

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeInput,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func allDeviceIDs() -> [DeviceID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = Self.address(kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size)
        guard sizeStatus == noErr else {
            log.error("Getting device list size failed: \(sizeStatus)")
            return []
        }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids)
        guard status == noErr else {
            log.error("Getting device list failed: \(status)")
            return []
        }
        return ids
    }

    private func inputChannelCount(_ id: DeviceID) -> Int {
        var address = Self.address(kAudioDevicePropertyStreamConfiguration)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw)
        guard status == noErr else {
            log.error("Getting stream configuration for device \(id) failed: \(status)")
            return 0
        }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func settableElements(_ id: DeviceID, _ selector: AudioObjectPropertySelector) -> [AudioObjectPropertyElement] {
        if isSettable(id, selector, kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
        let channels = inputChannelCount(id)
        guard channels > 0 else { return [] }
        return (1...channels).map { AudioObjectPropertyElement($0) }.filter { isSettable(id, selector, $0) }
    }

    private func isSettable(_ id: DeviceID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> Bool {
        var address = Self.address(selector, element: element)
        guard AudioObjectHasProperty(id, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
    }

    private func read<T: Numeric & BitwiseCopyable>(_ id: DeviceID, _ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> T? {
        var address = Self.address(selector, element: element)
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        guard status == noErr else {
            log.error("Getting property \(selector) element \(element) on device \(id) failed: \(status)")
            return nil
        }
        return value
    }

    private func decibelRange(_ id: DeviceID, element: AudioObjectPropertyElement) -> AudioValueRange? {
        var address = Self.address(kAudioDevicePropertyVolumeRangeDecibels, element: element)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var range = AudioValueRange()
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &range)
        guard status == noErr else {
            log.error("Getting volume dB range element \(element) on device \(id) failed: \(status)")
            return nil
        }
        return range
    }

    private func write<T: Numeric & BitwiseCopyable>(_ id: DeviceID, _ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement, value: T) -> Bool {
        var address = Self.address(selector, element: element)
        var value = value
        let status = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
        if status != noErr { log.error("Setting property \(selector) on device \(id) failed: \(status)") }
        return status == noErr
    }

    private func string(_ id: DeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = Self.address(selector, scope: kAudioObjectPropertyScopeGlobal)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
