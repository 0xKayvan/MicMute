/// Applies bridge commands to MuteState. Each client is its own push-to-talk source,
/// so a client that disconnects mid-hold releases only its own hold.
@MainActor
public final class CommandRouter {
    private let state: MuteState

    public init(state: MuteState) {
        self.state = state
    }

    public func handle(_ command: BridgeCommand, from client: AnyHashable) {
        switch command {
        case .toggle: state.toggle()
        case .mute: state.setMuted(true)
        case .unmute: state.setMuted(false)
        case .ptt(let down): down ? state.pttBegin(source: client) : state.pttEnd(source: client)
        case .get: break // BridgeServer answers with the current state itself.
        }
    }

    public func clientDisconnected(_ client: AnyHashable) {
        state.pttEnd(source: client)
    }
}
