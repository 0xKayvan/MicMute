import Foundation

/// Commands a bridge client (the Stream Deck plugin) can send.
public enum BridgeCommand: Equatable, Sendable {
    case toggle, mute, unmute, get
    case ptt(down: Bool)

    private struct Wire: Decodable {
        let type: String
        let down: Bool?
    }

    public static func parse(_ data: Data) -> BridgeCommand? {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        switch wire.type {
        case "toggle": return .toggle
        case "mute": return .mute
        case "unmute": return .unmute
        case "get": return .get
        case "ptt": return wire.down.map { .ptt(down: $0) }
        default: return nil
        }
    }
}

/// Messages the app sends to bridge clients.
public enum BridgeMessage {
    private struct State: Encodable {
        let type = "state"
        let muted: Bool
        let pttActive: Bool
    }

    public static func state(_ snapshot: MuteState.Snapshot) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(State(muted: snapshot.muted, pttActive: snapshot.pttActive))) ?? Data()
    }
}
