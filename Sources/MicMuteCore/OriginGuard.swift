import Foundation
import Network

/// Refuses WebSocket handshakes that carry an `Origin` header.
///
/// Browsers always send `Origin` on WebSocket handshakes; the Stream Deck plugin (Node) sends
/// none. Refusing any Origin keeps web pages from driving the bridge via ws://127.0.0.1.
///
/// This sits below the WebSocket protocol and inspects the raw HTTP request head, because
/// `NWProtocolWebSocket.Options.setClientRequestHandler` returning `.reject` only answers
/// HTTP 400: the connection still becomes `.ready` and incoming frames are still delivered.
/// Failing the connection here stops it before the WebSocket layer ever sees it.
final class OriginGuard: NWProtocolFramerImplementation {
    static let label = "MicMuteOriginGuard"
    static let definition = NWProtocolFramer.Definition(implementation: OriginGuard.self)

    /// Upper bound on the request head we are willing to buffer before giving up.
    static let maximumHeadLength = 16 * 1024

    enum Verdict: Equatable {
        case needMoreData, allow, reject
    }

    /// Decides from the bytes received so far. Pure, for testing.
    static func verdict(for bytes: Data) -> Verdict {
        guard let end = bytes.range(of: Data("\r\n\r\n".utf8)) else {
            return bytes.count >= maximumHeadLength ? .reject : .needMoreData
        }
        guard let head = String(data: bytes[..<end.lowerBound], encoding: .utf8) else { return .reject }
        let hasOrigin = head.components(separatedBy: "\r\n").dropFirst().contains { line in
            guard let colon = line.firstIndex(of: ":") else { return false }
            return line[..<colon].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Origin") == .orderedSame
        }
        return hasOrigin ? .reject : .allow
    }

    /// Request bytes consumed so far; handed up to the WebSocket layer once allowed.
    private var head = Data()

    init(framer: NWProtocolFramer.Instance) {}

    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult {
        // The server never writes before it has read the request, so output needs no checks.
        framer.passThroughOutput()
        return .ready
    }

    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        // Consume (not peek) each chunk: parseInput only ever shows the first segment when
        // nothing is consumed, so a request split across TCP reads would otherwise never complete.
        while true {
            var chunk = Data()
            let parsed = framer.parseInput(minimumIncompleteLength: 1, maximumLength: Self.maximumHeadLength - head.count) { buffer, _ in
                guard let buffer, !buffer.isEmpty else { return 0 }
                chunk = Data(buffer)
                return buffer.count
            }
            guard parsed, !chunk.isEmpty else { return 0 } // wait for more bytes
            head.append(chunk)
            switch Self.verdict(for: head) {
            case .allow:
                // Hand the request (plus any frames pipelined after it) up, then get out of the way.
                framer.deliverInput(data: head, message: NWProtocolFramer.Message(instance: framer), isComplete: false)
                head = Data()
                framer.passThroughInput()
                return 0
            case .reject:
                framer.markFailed(error: .posix(.ECONNREFUSED))
                return 0
            case .needMoreData:
                continue
            }
        }
    }

    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int, isComplete: Bool) {
        try? framer.writeOutputNoCopy(length: messageLength)
    }

    func wakeup(framer: NWProtocolFramer.Instance) {}
    func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
    func cleanup(framer: NWProtocolFramer.Instance) {}
}
