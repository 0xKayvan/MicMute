import Testing
import MicMuteCore

@MainActor
@Suite struct MicControllerTests {
    @Test func mutesAndUnmutesViaMuteProperty() {
        let audio = FakeAudioSystem()
        audio.add(1)
        let mic = MicController(audio: audio)
        mic.apply(muted: true)
        #expect(audio.devices[1]?.muted == true)
        mic.apply(muted: false)
        #expect(audio.devices[1]?.muted == false)
    }

    @Test func fallsBackToVolumeAndRestoresIt() {
        let audio = FakeAudioSystem()
        audio.add(1, canMute: false, volume: 0.7)
        let mic = MicController(audio: audio)
        mic.apply(muted: true)
        #expect(audio.devices[1]?.volume == 0)
        mic.apply(muted: false)
        #expect(audio.devices[1]?.volume == 0.7)
    }

    @Test func unmutingZeroVolumeDeviceWithNothingSavedSetsFullVolume() {
        let audio = FakeAudioSystem()
        audio.add(1, canMute: false, volume: 0)
        let mic = MicController(audio: audio)
        mic.apply(muted: true)
        mic.apply(muted: false)
        #expect(audio.devices[1]?.volume == 1)
    }

    @Test func mutesDevicePluggedInWhileMuted() {
        let audio = FakeAudioSystem()
        audio.add(1)
        let mic = MicController(audio: audio)
        mic.apply(muted: true)
        audio.add(2, name: "USB Mic")
        #expect(audio.devices[2]?.muted == true)
    }

    @Test func reMutesDeviceUnmutedExternallyWhileMuted() {
        let audio = FakeAudioSystem()
        audio.add(1)
        let mic = MicController(audio: audio)
        mic.apply(muted: true)
        audio.externallySet(1, muted: false)
        #expect(audio.devices[1]?.muted == true)
    }

    @Test func externalVolumeRaiseWhileMutedIsZeroedAndRestoredLater() {
        let audio = FakeAudioSystem()
        audio.add(1, canMute: false, volume: 0.5)
        let mic = MicController(audio: audio)
        mic.apply(muted: true)
        audio.externallySet(1, volume: 0.9)
        #expect(audio.devices[1]?.volume == 0)
        mic.apply(muted: false)
        #expect(audio.devices[1]?.volume == 0.9)
    }

    @Test func leavesExternalChangesAloneWhileUnmuted() {
        let audio = FakeAudioSystem()
        audio.add(1)
        let mic = MicController(audio: audio)
        mic.apply(muted: false)
        audio.externallySet(1, muted: true)
        #expect(audio.devices[1]?.muted == true)
    }

    @Test func muteControlDeviceUnpluggedWhileMutedComesBackLive() {
        let audio = FakeAudioSystem()
        audio.add(1)
        audio.add(2, name: "USB Mic")
        let mic = MicController(audio: audio)
        mic.apply(muted: true)
        audio.remove(2)
        mic.apply(muted: false)
        // CoreAudio restores the last (muted) state on replug.
        audio.add(2, name: "USB Mic", muted: true)
        #expect(audio.devices[2]?.muted == false)
        // Forgotten once restored: a later external mute is left alone.
        audio.externallySet(2, muted: true)
        #expect(audio.devices[2]?.muted == true)
    }

    @Test func volumeDeviceUnpluggedWhileMutedComesBackAtSavedVolume() {
        let audio = FakeAudioSystem()
        audio.add(1)
        audio.add(2, name: "USB Mic", canMute: false, volume: 0.6)
        let mic = MicController(audio: audio)
        mic.apply(muted: true)
        #expect(audio.devices[2]?.volume == 0)
        audio.remove(2)
        mic.apply(muted: false)
        audio.add(2, name: "USB Mic", canMute: false, volume: 0)
        #expect(audio.devices[2]?.volume == 0.6)
        audio.externallySet(2, volume: 0)
        #expect(audio.devices[2]?.volume == 0)
    }

    @Test func externallyMutedDeviceWasNeverRecordedSoReplugLeavesItAlone() {
        let audio = FakeAudioSystem()
        let mic = MicController(audio: audio)
        mic.apply(muted: false)
        audio.add(1, muted: true)
        #expect(audio.devices[1]?.muted == true)
    }

    @Test func reportsDeviceStatuses() {
        let audio = FakeAudioSystem()
        audio.add(1, name: "Built-in")
        audio.add(2, name: "USB", canMute: false)
        audio.add(3, name: "Weird", canMute: false, canSetVolume: false)
        let mic = MicController(audio: audio)
        mic.apply(muted: true)
        #expect(mic.deviceStatuses == [
            DeviceStatus(name: "Built-in", method: .mute, isMuted: true),
            DeviceStatus(name: "USB", method: .volume, isMuted: true),
            DeviceStatus(name: "Weird", method: .unsupported, isMuted: false),
        ])
        #expect(mic.deviceStatuses.map(\.summary) == [
            "Built-in — Muted",
            "USB — Muted (via volume)",
            "Weird — ⚠︎ can't mute",
        ])
    }

    @Test func allMutedIgnoresUnsupportedDevices() {
        let audio = FakeAudioSystem()
        audio.add(1)
        audio.add(2, canMute: false, canSetVolume: false)
        let mic = MicController(audio: audio)
        #expect(!mic.allMuted)
        audio.externallySet(1, muted: true)
        #expect(mic.allMuted)
    }

    @Test func allMutedIsFalseWithNoControllableDevices() {
        let audio = FakeAudioSystem()
        audio.add(1, canMute: false, canSetVolume: false)
        #expect(!MicController(audio: audio).allMuted)
    }
}
