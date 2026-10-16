import Testing
import MicMuteCore

@MainActor
@Suite struct CoreAudioSystemTests {
    @Test func listsInputDevicesWithReadableProperties() {
        let audio = CoreAudioSystem()
        for id in audio.inputDeviceIDs() {
            #expect(!audio.uid(of: id).isEmpty)
            #expect(!audio.name(of: id).isEmpty)
            _ = audio.canSetMute(id)
            _ = audio.canSetVolume(id)
            _ = audio.volumeFloorDecibels(id)
            _ = audio.isMuted(id)
            #expect((0...1).contains(audio.volume(id)))
        }
    }
}
