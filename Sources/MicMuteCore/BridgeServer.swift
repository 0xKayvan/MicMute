import Foundation
import Network
import os

/// Loopback-only WebSocket server the Stream Deck plugin connects to.
/// All state is confined to `queue`; callbacks are invoked on it too.
public final class BridgeServer {
    public static let defaultPort: UInt16 = 52836

    public var onCommand: ((BridgeCommand, ObjectIdentifier) -> Void)?
    public var onClientDisconnected: ((ObjectIdentifier) -> Void)?
    public var onStatusChange: ((Bool) -> Void)?

    private let log = Logger(subsystem: "xyz.kayvan.micmute", category: "bridge")
    private let requestedPort: UInt16
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var currentState: Data

    public init(port: UInt16 = defaultPort, initialState: Data, queue: DispatchQueue = .main) {
        requestedPort = port
        currentState = initialState
        self.queue = queue
    }

    public var port: UInt16? { listener?.port?.rawValue }

    public func start() throws {
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        let port = requestedPort == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: requestedPort)!
        let listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                onStatusChange?(true)
            case .failed(let error):
                log.error("Bridge listener failed: \(error.localizedDescription)")
                onStatusChange?(false)
                listener.cancel()
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    public func broadcast(_ state: Data) {
        queue.async { [self] in
            currentState = state
            connections.values.forEach { send(state, to: $0) }
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready: send(currentState, to: connection)
            case .failed, .cancelled: drop(id)
            default: break
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            if error != nil || metadata?.opcode == .close {
                drop(id)
                return
            }
            if let data, let command = BridgeCommand.parse(data) {
                if command == .get { send(currentState, to: connection) }
                onCommand?(command, id)
            }
            receive(on: connection)
        }
    }

    private func drop(_ id: ObjectIdentifier) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        connection.cancel()
        onClientDisconnected?(id)
    }

    private func send(_ data: Data, to connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "state", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }
}
