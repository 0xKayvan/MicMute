import Testing
import MicMuteCore

/// Relaunching after MicMute was force-quit or crashed, i.e. without `applicationWillTerminate` unmuting.
@MainActor
@Suite struct RelaunchRecoveryTests {
    let audio = FakeAudioSystem()

    /// A run that persists its record (into Preferences, in the app) via `sink`.
    func persisting(_ mic: MicController, into sink: @escaping (MuteRecord) -> Void) -> MicController {
        mic.onRecordChange = sink
        return mic
    }

    /// The process dies: nothing unmutes and nothing listens any more.
    func forceQuit() {
        audio.onChange = nil
    }

    @Test func forceQuitWhileMutedResumesMutedEvenAfterAnAppRaisedAVolume() {
        audio.add(1, name: "Built-in")
        audio.add(2, name: "RØDE", canMute: false, volume: 0.42)
        var record: MuteRecord?
        let first = persisting(MicController(audio: audio), into: { record = $0 })
        first.apply(muted: true)
        forceQuit()
        // While MicMute isn't running, a browser's auto-gain raises the RØDE.
        audio.externallySet(2, volume: 20.0 / 255)

        let relaunched = MicController(audio: audio, record: record)
        #expect(relaunched.startsMuted)
    }

    @Test func unmutingAfterRelaunchRestoresPreCrashLevels() {
        audio.add(1, name: "Built-in")
        audio.add(2, name: "RØDE", canMute: false, volume: 0.42)
        var record: MuteRecord?
        let first = persisting(MicController(audio: audio), into: { record = $0 })
        first.apply(muted: true)
        forceQuit()
        audio.externallySet(2, volume: 20.0 / 255)

        let relaunched = MicController(audio: audio, record: record)
        relaunched.apply(muted: true) // as the app does when it starts muted
        #expect(audio.devices[2]?.volume == 0)
        relaunched.apply(muted: false)
        #expect(audio.devices[1]?.muted == false)
        #expect(audio.devices[2]?.volume == 0.42)
    }

    @Test func cleanQuitRelaunchesLive() {
        audio.add(1, name: "Built-in")
        audio.add(2, name: "RØDE", canMute: false, volume: 0.42)
        var record: MuteRecord?
        let first = persisting(MicController(audio: audio), into: { record = $0 })
        first.apply(muted: true)
        first.apply(muted: false) // applicationWillTerminate
        forceQuit()

        let relaunched = MicController(audio: audio, record: record)
        #expect(!relaunched.startsMuted)
        #expect(audio.devices[1]?.muted == false)
        #expect(audio.devices[2]?.volume == 0.42)
    }

    @Test func withoutARecordStartsMutedOnlyIfEveryMicAlreadyIs() {
        audio.add(1, name: "Built-in", muted: true)
        audio.add(2, name: "USB", muted: true)
        #expect(MicController(audio: audio, record: nil).startsMuted)
        audio.externallySet(2, muted: false)
        #expect(!MicController(audio: audio, record: nil).startsMuted)
    }

    @Test func deviceUnpluggedWhileMutedIsRestoredWhenItReturnsAfterARelaunch() {
        audio.add(1, name: "Built-in")
        audio.add(2, name: "RØDE", canMute: false, volume: 0.6)
        var record: MuteRecord?
        let first = persisting(MicController(audio: audio), into: { record = $0 })
        first.apply(muted: true)
        audio.remove(2)
        first.apply(muted: false)
        forceQuit()

        let relaunched = MicController(audio: audio, record: record)
        #expect(!relaunched.startsMuted)
        // CoreAudio brings it back at the volume it had when unplugged (0).
        audio.add(2, name: "RØDE", canMute: false, volume: 0)
        #expect(audio.devices[2]?.volume == 0.6)
    }

    @Test func deviceRestoredOnReplugIsDroppedFromTheRecord() {
        audio.add(1, name: "RØDE", canMute: false, volume: 0.6)
        var record: MuteRecord?
        let mic = persisting(MicController(audio: audio), into: { record = $0 })
        mic.apply(muted: true)
        audio.remove(1)
        mic.apply(muted: false)
        #expect(record?.savedVolumes == ["uid-1": 0.6])
        audio.add(1, name: "RØDE", canMute: false, volume: 0)
        // Restored now; a later relaunch must not restore it again over newer changes.
        #expect(record == MuteRecord())
    }

    @Test func recordIsPersistedOnlyWhenItChanges() {
        audio.add(1, name: "RØDE", canMute: false, volume: 0.42)
        var writes = 0
        let mic = persisting(MicController(audio: audio), into: { _ in writes += 1 })
        mic.apply(muted: true)
        let afterMute = writes
        #expect(afterMute >= 1)
        // An app fighting the mute: MicMute re-mutes, but there's nothing new to persist.
        for _ in 0..<5 { audio.externallySet(1, volume: 20.0 / 255) }
        #expect(writes == afterMute)
    }
}
