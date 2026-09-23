import Testing
import MicMuteCore

@MainActor
@Suite struct MuteStateTests {
    final class Recorder {
        var applied: [Bool] = []
        var changes: [MuteState.Change] = []
    }

    func make(muted: Bool = false) -> (MuteState, Recorder) {
        let recorder = Recorder()
        let state = MuteState(initiallyMuted: muted) { recorder.applied.append($0) }
        state.addObserver { recorder.changes.append($0) }
        return (state, recorder)
    }

    @Test func toggleAppliesAndNotifies() {
        let (state, rec) = make()
        state.toggle()
        #expect(state.effectiveMuted)
        #expect(rec.applied == [true])
        #expect(rec.changes == [.init(snapshot: .init(muted: true, pttActive: false), mutedChanged: true, viaPTT: false)])
        state.toggle()
        #expect(rec.applied == [true, false])
    }

    @Test func setMutedToSameValueDoesNothing() {
        let (state, rec) = make(muted: true)
        state.setMuted(true)
        #expect(rec.applied.isEmpty)
        #expect(rec.changes.isEmpty)
    }

    @Test func pushToTalkUnmutesWhileHeld() {
        let (state, rec) = make(muted: true)
        state.pttBegin(source: "hotkey")
        #expect(!state.effectiveMuted)
        #expect(state.pttActive)
        state.pttEnd(source: "hotkey")
        #expect(state.effectiveMuted)
        #expect(rec.applied == [false, true])
        #expect(rec.changes.allSatisfy { $0.viaPTT })
    }

    @Test func pushToTalkWhileLiveOnlyReportsPTTFlag() {
        let (state, rec) = make(muted: false)
        state.pttBegin(source: "hotkey")
        #expect(rec.applied.isEmpty)
        #expect(rec.changes == [.init(snapshot: .init(muted: false, pttActive: true), mutedChanged: false, viaPTT: true)])
    }

    @Test func overlappingSourcesKeepMicLiveUntilLastRelease() {
        let (state, _) = make(muted: true)
        state.pttBegin(source: "hotkey")
        state.pttBegin(source: "deck")
        state.pttEnd(source: "hotkey")
        #expect(!state.effectiveMuted)
        state.pttEnd(source: "deck")
        #expect(state.effectiveMuted)
    }

    @Test func endingUnknownSourceIsNoOp() {
        let (state, rec) = make(muted: true)
        state.pttEnd(source: "nobody")
        #expect(rec.changes.isEmpty)
    }
}
