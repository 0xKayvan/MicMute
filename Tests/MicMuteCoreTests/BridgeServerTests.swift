import Foundation
import Network
import Testing
@testable import MicMuteCore

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

    struct TimedOut: Error {}

    @Test func rejectsHandshakesCarryingAnOriginHeader() async throws {
        let server = BridgeServer(
            port: 0,
            initialState: BridgeMessage.state(.init(muted: true, pttActive: false)),
            queue: DispatchQueue(label: "bridge-origin-test")
        )
        let port = try await startServer(server)
        defer { server.stop() }

        var request = URLRequest(url: URL(string: "ws://127.0.0.1:\(port)")!)
        request.setValue("https://example.com", forHTTPHeaderField: "Origin")
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()

        // A regression (handshake accepted) delivers the initial state; bound the wait so it fails instead of hanging.
        let outcome: Result<URLSessionWebSocketTask.Message, Error> = await withTaskGroup(of: Result<URLSessionWebSocketTask.Message, Error>.self) { group in
            group.addTask {
                do { return .success(try await task.receive()) } catch { return .failure(error) }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return .failure(TimedOut())
            }
            let first = await group.next()!
            group.cancelAll()
            task.cancel()
            return first
        }
        switch outcome {
        case .success(let message): Issue.record("Origin handshake was accepted: \(String(describing: text(message)))")
        case .failure(let error): #expect(!(error is TimedOut), "Origin handshake neither failed nor succeeded in time")
        }
    }

    /// Raw TCP client: sends `chunks` with a pause between them, returns what the server sent back
    /// (or nil if nothing arrived within the timeout).
    func rawExchange(port: UInt16, chunks: [String]) async -> String? {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let queue = DispatchQueue(label: "raw-client")
        connection.start(queue: queue)
        defer { connection.cancel() }
        for (index, chunk) in chunks.enumerated() {
            if index > 0 { try? await Task.sleep(nanoseconds: 200_000_000) }
            connection.send(content: Data(chunk.utf8), completion: .idempotent)
        }
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                        continuation.resume(returning: data.map { String(decoding: $0, as: UTF8.self) })
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return nil
            }
            let first = await group.next()!
            group.cancelAll()
            connection.cancel()
            return first
        }
    }

    @Test func completesHandshakeSplitAcrossTCPReads() async throws {
        let server = BridgeServer(
            port: 0,
            initialState: BridgeMessage.state(.init(muted: true, pttActive: false)),
            queue: DispatchQueue(label: "bridge-split-test")
        )
        let port = try await startServer(server)
        defer { server.stop() }

        let head = "GET / HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            + "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
        let split = head.index(head.startIndex, offsetBy: 40)
        let response = await rawExchange(port: port, chunks: [String(head[..<split]), String(head[split...])])
        #expect(response?.hasPrefix("HTTP/1.1 101") == true, "got \(String(describing: response))")
    }

    @Test func rejectsOriginHeaderArrivingInALaterTCPRead() async throws {
        let server = BridgeServer(
            port: 0,
            initialState: BridgeMessage.state(.init(muted: true, pttActive: false)),
            queue: DispatchQueue(label: "bridge-split-origin-test")
        )
        let port = try await startServer(server)
        defer { server.stop() }

        let response = await rawExchange(port: port, chunks: [
            "GET / HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n",
            "Origin: https://example.com\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n",
        ])
        #expect(response?.hasPrefix("HTTP/1.1 101") != true, "Origin handshake was accepted: \(String(describing: response))")
    }

    @Test func originGuardVerdicts() {
        func verdict(_ head: String) -> OriginGuard.Verdict { OriginGuard.verdict(for: Data(head.utf8)) }
        let node = "GET / HTTP/1.1\r\nhost: 127.0.0.1\r\nupgrade: websocket\r\n\r\n"
        #expect(verdict(node) == .allow)
        #expect(verdict("GET / HTTP/1.1\r\nHost: x\r\nOrigin: https://example.com\r\n\r\n") == .reject)
        #expect(verdict("GET / HTTP/1.1\r\nhost: x\r\norigin: null\r\n\r\n") == .reject)
        #expect(verdict("GET / HTTP/1.1\r\nX-Origin-Hint: a\r\n\r\n") == .allow)
        #expect(verdict("GET / HTTP/1.1\r\nHost: x\r\nOri") == .needMoreData)
        #expect(OriginGuard.verdict(for: Data(repeating: 65, count: OriginGuard.maximumHeadLength)) == .reject)
    }
}
