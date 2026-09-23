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

    /// `port` is read from arbitrary threads (e.g. from inside `onStatusChange`,
    /// which runs on `queue`, as well as from callers outside `queue`), so it is
    /// guarded by its own lock rather than by `queue` to avoid a `queue.sync`
    /// deadlock when read from `queue` itself.
    private let portLock = NSLock()
    private var boundPort: UInt16?

    public init(port: UInt16 = defaultPort, initialState: Data, queue: DispatchQueue = .main) {
        requestedPort = port
        currentState = initialState
        self.queue = queue
    }

    public var port: UInt16? {
        portLock.lock()
        defer { portLock.unlock() }
        return boundPort
    }

    public func start() throws {
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        // Below WebSocket, above TCP: refuses browser handshakes (see OriginGuard).
        parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolFramer.Options(definition: OriginGuard.definition), at: 1)
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        // Bind to 127.0.0.1 explicitly (not *:port) in addition to the loopback interface filter.
        let port = requestedPort == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: requestedPort)!
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        let listener = try NWListener(using: parameters)

        queue.async { [self] in
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self else { return }
                switch state {
                case .ready:
                    setBoundPort(listener?.port?.rawValue)
                    onStatusChange?(true)
                case .failed(let error):
                    log.error("Bridge listener failed: \(error.localizedDescription)")
                    onStatusChange?(false)
                    listener?.cancel()
                default:
                    break
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        }
    }

    public func stop() {
        queue.async { [self] in
            Array(connections.keys).forEach(drop)
            listener?.cancel()
            listener = nil
            setBoundPort(nil)
        }
    }

    private func setBoundPort(_ value: UInt16?) {
        portLock.lock()
        boundPort = value
        portLock.unlock()
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
