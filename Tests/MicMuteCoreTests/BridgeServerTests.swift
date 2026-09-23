import Foundation
import Testing
import MicMuteCore

@Suite struct BridgeServerTests {
    struct StartFailed: Error {}

    func startServer(_ server: BridgeServer) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            server.onStatusChange = { listening in
                server.onStatusChange = nil
                if listening, let port = server.port {
                    continuation.resume(returning: port)
                } else {
                    continuation.resume(throwing: StartFailed())
                }
            }
            do { try server.start() } catch { continuation.resume(throwing: error) }
        }
    }

    func text(_ message: URLSessionWebSocketTask.Message) -> String? {
        if case .string(let value) = message { return value }
        return nil
    }

    @Test func sendsStateForwardsCommandsAndReportsDisconnect() async throws {
        let server = BridgeServer(
            port: 0,
            initialState: BridgeMessage.state(.init(muted: true, pttActive: false)),
            queue: DispatchQueue(label: "bridge-test")
        )
        let (commands, commandSink) = AsyncStream.makeStream(of: BridgeCommand.self)
        let (disconnects, disconnectSink) = AsyncStream.makeStream(of: Void.self)
        server.onCommand = { command, _ in commandSink.yield(command) }
        server.onClientDisconnected = { _ in disconnectSink.yield() }

        let port = try await startServer(server)
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
        task.resume()

        #expect(text(try await task.receive()) == #"{"muted":true,"pttActive":false,"type":"state"}"#)

        try await task.send(.string(#"{"type":"toggle"}"#))
        var commandIterator = commands.makeAsyncIterator()
        #expect(await commandIterator.next() == .toggle)

        server.broadcast(BridgeMessage.state(.init(muted: false, pttActive: false)))
        #expect(text(try await task.receive()) == #"{"muted":false,"pttActive":false,"type":"state"}"#)

        try await task.send(.string(#"{"type":"get"}"#))
        #expect(text(try await task.receive()) == #"{"muted":false,"pttActive":false,"type":"state"}"#)

        task.cancel(with: .normalClosure, reason: nil)
        var disconnectIterator = disconnects.makeAsyncIterator()
        #expect(await disconnectIterator.next() != nil)

        // A second client that is never explicitly closed should still be
        // reported as disconnected once the server stops.
        let task2 = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
        task2.resume()
        _ = try await task2.receive() // wait for the initial state push, confirming the server has accepted it

        server.stop()
        #expect(await disconnectIterator.next() != nil)
    }
}
