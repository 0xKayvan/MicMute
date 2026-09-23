import Foundation
import Testing
import MicMuteCore

@Suite struct BridgeProtocolTests {
    func parse(_ json: String) -> BridgeCommand? { BridgeCommand.parse(Data(json.utf8)) }

    @Test func parsesAllCommands() {
        #expect(parse(#"{"type":"toggle"}"#) == .toggle)
        #expect(parse(#"{"type":"mute"}"#) == .mute)
        #expect(parse(#"{"type":"unmute"}"#) == .unmute)
        #expect(parse(#"{"type":"get"}"#) == .get)
        #expect(parse(#"{"type":"ptt","down":true}"#) == .ptt(down: true))
        #expect(parse(#"{"type":"ptt","down":false}"#) == .ptt(down: false))
    }

    @Test func rejectsMalformedInput() {
        #expect(parse("not json") == nil)
        #expect(parse(#"{"type":"explode"}"#) == nil)
        #expect(parse(#"{"type":"ptt"}"#) == nil)
        #expect(parse(#"{"kind":"toggle"}"#) == nil)
    }

    @Test func encodesStateWithSortedKeys() {
        let data = BridgeMessage.state(.init(muted: true, pttActive: false))
        #expect(String(decoding: data, as: UTF8.self) == #"{"muted":true,"pttActive":false,"type":"state"}"#)
    }
}

@MainActor
@Suite struct CommandRouterTests {
    @Test func routesCommandsToState() {
        let state = MuteState(initiallyMuted: false) { _ in }
        let router = CommandRouter(state: state)
        router.handle(.toggle, from: "a")
        #expect(state.isMuted)
        router.handle(.unmute, from: "a")
        #expect(!state.isMuted)
        router.handle(.mute, from: "a")
        #expect(state.isMuted)
        router.handle(.ptt(down: true), from: "a")
        #expect(!state.effectiveMuted)
        router.handle(.ptt(down: false), from: "a")
        #expect(state.effectiveMuted)
    }

    @Test func releasesPTTWhenClientDisconnects() {
        let state = MuteState(initiallyMuted: true) { _ in }
        let router = CommandRouter(state: state)
        router.handle(.ptt(down: true), from: "a")
        router.clientDisconnected("a")
        #expect(state.effectiveMuted)
    }
}
