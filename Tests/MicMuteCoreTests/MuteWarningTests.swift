import Testing
import MicMuteCore

/// Warnings for mics MicMute reports as muted that may still be heard.
@MainActor
@Suite struct MuteWarningTests {
    let audio = FakeAudioSystem()
    let clock = ManualClock()

    func makeController() -> MicController {
        MicController(audio: audio, now: { [clock] in clock.time }, schedule: { [clock] in clock.schedule($0, $1) })
    }

    /// Another app (e.g. a browser call's auto-gain) raising a volume-muted mic every 250 ms.
    func raiseVolume(of id: DeviceID, times: Int) {
        for _ in 0..<times {
            audio.externallySet(id, volume: 20.0 / 255)
            clock.advance(by: 0.25)
        }
    }

    func warnings(_ mic: MicController, _ name: String) -> [MuteWarning] {
        mic.deviceStatuses.first { $0.name == name }?.warnings ?? []
    }

    // MARK: - Volume floor

    @Test func volumeDeviceWhoseLowestVolumeIsAudibleIsNotSilent() {
        audio.add(1, name: "RØDE", canMute: false, volumeFloor: 0) // range 0…+40 dB
        audio.add(2, name: "Quiet USB", canMute: false, volumeFloor: -40)
        let mic = makeController()
        #expect(warnings(mic, "RØDE") == [.notSilentAtZeroVolume])
        #expect(warnings(mic, "Quiet USB") == [.notSilentAtZeroVolume])
    }

    @Test func silentOrUnreportedVolumeFloorHasNoWarning() {
        audio.add(1, name: "Deep", canMute: false, volumeFloor: -96)
        audio.add(2, name: "Silent", canMute: false, volumeFloor: -.infinity)
        audio.add(3, name: "Unknown", canMute: false, volumeFloor: nil)
        let mic = makeController()
        #expect(mic.deviceStatuses.allSatisfy { $0.warnings.isEmpty })
    }

    @Test func muteControlDeviceIgnoresItsVolumeFloor() {
        audio.add(1, name: "Built-in", canMute: true, volumeFloor: 0)
        #expect(warnings(makeController(), "Built-in").isEmpty)
    }

    @Test func hasMuteWarningsOnlyWhileMutedWithAnAudibleDevice() {
        audio.add(1, name: "Built-in")
        audio.add(2, name: "RØDE", canMute: false, volumeFloor: 0)
        let mic = makeController()
        var notifications = 0
        mic.onWarningsChanged = { notifications += 1 }
        #expect(!mic.hasMuteWarnings)
        mic.apply(muted: true)
        #expect(mic.hasMuteWarnings)
        #expect(notifications == 1)
        mic.apply(muted: false)
        #expect(!mic.hasMuteWarnings)
        #expect(notifications == 2)
    }

    @Test func mutedWithOnlySilentDevicesHasNoMuteWarnings() {
        audio.add(1, name: "Built-in")
        audio.add(2, name: "Deep", canMute: false, volumeFloor: -96)
        let mic = makeController()
        mic.apply(muted: true)
        #expect(!mic.hasMuteWarnings)
    }

    // MARK: - Contested devices

    @Test func appRepeatedlyRaisingAVolumeMutedMicIsContestedUntilItStops() {
        audio.add(1, name: "USB", canMute: false, volume: 0.5)
        let mic = makeController()
        var notifications = 0
        mic.onWarningsChanged = { notifications += 1 }
        mic.apply(muted: true)
        raiseVolume(of: 1, times: 3)
        #expect(warnings(mic, "USB") == [.contested])
        #expect(mic.hasMuteWarnings)
        // Stays contested for as long as the app keeps at it.
        for _ in 0..<20 {
            raiseVolume(of: 1, times: 1)
            #expect(warnings(mic, "USB") == [.contested])
        }
        #expect(notifications == 1)
        clock.advance(by: 5)
        #expect(warnings(mic, "USB").isEmpty)
        #expect(!mic.hasMuteWarnings)
        #expect(notifications == 2)
        // MicMute kept the mic muted throughout.
        #expect(audio.devices[1]?.volume == 0)
    }

    @Test func oneOrTwoExternalChangesAreNotAContest() {
        audio.add(1, name: "USB", canMute: false, volume: 0.5)
        let mic = makeController()
        mic.apply(muted: true)
        raiseVolume(of: 1, times: 2)
        #expect(warnings(mic, "USB").isEmpty)
        #expect(!mic.hasMuteWarnings)
    }

    @Test func reMutingDifferentDevicesDoesNotAddUpToAContest() {
        let mic = makeController()
        mic.apply(muted: true)
        for id: DeviceID in 1...4 {
            audio.add(id, name: "Mic \(id)")
            clock.advance(by: 0.25)
        }
        #expect(mic.deviceStatuses.allSatisfy { $0.warnings.isEmpty })
    }

    @Test func appRepeatedlyUnmutingAMuteControlMicIsContested() {
        audio.add(1, name: "Built-in")
        let mic = makeController()
        mic.apply(muted: true)
        for _ in 0..<3 {
            audio.externallySet(1, muted: false)
            clock.advance(by: 0.25)
        }
        #expect(warnings(mic, "Built-in") == [.contested])
        #expect(audio.devices[1]?.muted == true)
    }

    @Test func unmutingEndsAContest() {
        audio.add(1, name: "USB", canMute: false, volume: 0.5)
        let mic = makeController()
        mic.apply(muted: true)
        raiseVolume(of: 1, times: 3)
        mic.apply(muted: false)
        #expect(warnings(mic, "USB").isEmpty)
        #expect(!mic.hasMuteWarnings)
    }

    // MARK: - Menu text

    @Test func summariesExplainWarnings() {
        audio.add(1, name: "Built-in")
        audio.add(2, name: "RØDE", canMute: false, volume: 0.42, volumeFloor: 0)
        let mic = makeController()
        mic.apply(muted: true)
        #expect(mic.deviceStatuses.map(\.summary) == [
            "Built-in — Muted",
            "RØDE — Muted (via volume) ⚠︎ not silent at volume 0",
        ])
        raiseVolume(of: 2, times: 3)
        for _ in 0..<3 {
            audio.externallySet(1, muted: false)
            clock.advance(by: 0.25)
        }
        #expect(mic.deviceStatuses.map(\.summary) == [
            "Built-in — Muted ⚠︎ another app keeps unmuting it",
            "RØDE — Muted (via volume) ⚠︎ not silent at volume 0; another app keeps raising its volume",
        ])
    }
}
