import Foundation
import Network

/// An actor that accepts TCP connections and receives/sends OSC packets.
///
/// Supports both PLH and SLIP framing. Each connected client gets its own
/// deframer and receive loop. Decoded packets are yielded through the ``packets``
/// stream, and connection lifecycle events through ``connectionEvents``.
///
/// Malformed packets that fail decoding are silently dropped, which is standard
/// OSC behavior. Only successfully decoded packets appear in ``packets``.
///
/// ```swift
/// let server = OSCTCPServer(port: 3032)
/// try await server.start()
///
/// for await incoming in server.packets {
///     print("From \(incoming.connectionID): \(incoming.packet)")
/// }
/// ```
public actor OSCTCPServer {

    /// Identifies a connected TCP client.
    public struct ConnectionID: Sendable, Hashable, CustomStringConvertible {
        let id: UInt64

        public var description: String { "Connection(\(id))" }
    }

    /// A decoded packet along with its source connection.
    public struct IncomingPacket: Sendable {
        /// The decoded OSC packet.
        public let packet: OSCPacket
        /// The connection that sent this packet.
        public let connectionID: ConnectionID
    }

    /// Events related to client connections.
    public enum ConnectionEvent: Sendable {
        /// A new client has connected.
        case connected(ConnectionID)
        /// A client has disconnected.
        case disconnected(ConnectionID)
    }

    private let port: UInt16
    private let framing: TCPFraming
    private var listener: NWListener?
    private var connections: [ConnectionID: NWConnection] = [:]
    private var deframers: [ConnectionID: TCPDeframer] = [:]
    private var nextID: UInt64 = 0

    private var packetContinuation: AsyncStream<IncomingPacket>.Continuation?
    private var eventContinuation: AsyncStream<ConnectionEvent>.Continuation?

    /// An asynchronous stream of incoming decoded OSC packets.
    public let packets: AsyncStream<IncomingPacket>

    /// An asynchronous stream of connection lifecycle events.
    public let connectionEvents: AsyncStream<ConnectionEvent>

    /// The actual port the server is listening on.
    ///
    /// Useful when initialized with port 0 (OS-assigned ephemeral port).
    /// Returns `nil` if the server has not been started.
    public var listeningPort: UInt16? {
        listener?.port?.rawValue
    }

    /// The set of currently connected client IDs.
    public var activeConnections: Set<ConnectionID> {
        Set(connections.keys)
    }

    /// Creates a TCP server on the given port.
    ///
    /// Does not start listening until ``start()`` is called.
    ///
    /// - Parameters:
    ///   - port: The TCP port to listen on.
    ///   - framing: The TCP framing protocol to use (default `.plh`).
    public init(port: UInt16, framing: TCPFraming = .plh) {
        self.port = port
        self.framing = framing

        var packetCont: AsyncStream<IncomingPacket>.Continuation!
        self.packets = AsyncStream { packetCont = $0 }
        self.packetContinuation = packetCont

        var eventCont: AsyncStream<ConnectionEvent>.Continuation!
        self.connectionEvents = AsyncStream { eventCont = $0 }
        self.eventContinuation = eventCont
    }

    /// Starts listening for TCP connections.
    ///
    /// - Throws: If the listener cannot be created or fails to start.
    public func start() async throws {
        let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
        let listener = try NWListener(using: .tcp, on: nwPort)
        self.listener = listener

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Safe: NWListener delivers stateUpdateHandler callbacks on the
            // serial queue passed to start(queue:), preventing concurrent access.
            nonisolated(unsafe) var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume()
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    resumed = true
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task { await self.handleNewConnection(connection) }
            }

            listener.start(queue: DispatchQueue(label: "com.oscfoundation.tcp.server"))
        }
    }

    /// Sends an OSC packet to a specific connected client.
    ///
    /// - Parameters:
    ///   - packet: The packet to send.
    ///   - connectionID: The client to send to.
    /// - Throws: ``OSCTCPError/notConnected`` if the connection ID is unknown.
    public func send(_ packet: OSCPacket, to connectionID: ConnectionID) throws {
        guard let connection = connections[connectionID] else {
            throw OSCTCPError.notConnected
        }

        let encoded = try OSCEncoder.encode(packet)
        let framed = TCPDeframer.frame(encoded, using: framing)
        connection.send(content: framed, completion: .contentProcessed { _ in })
    }

    /// Sends an OSC packet to all connected clients.
    ///
    /// - Parameter packet: The packet to broadcast.
    /// - Throws: ``OSCEncodeError`` if the packet contains invalid data.
    public func broadcast(_ packet: OSCPacket) throws {
        let encoded = try OSCEncoder.encode(packet)
        let framed = TCPDeframer.frame(encoded, using: framing)
        for connection in connections.values {
            connection.send(content: framed, completion: .contentProcessed { _ in })
        }
    }

    /// Disconnects a specific client.
    ///
    /// - Parameter connectionID: The client to disconnect.
    public func disconnect(_ connectionID: ConnectionID) {
        connections[connectionID]?.cancel()
        connections.removeValue(forKey: connectionID)
        deframers.removeValue(forKey: connectionID)
        eventContinuation?.yield(.disconnected(connectionID))
    }

    /// Stops the server, disconnects all clients, and finishes streams.
    public func stop() {
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
        deframers.removeAll()
        listener?.cancel()
        listener = nil
        packetContinuation?.finish()
        eventContinuation?.finish()
        packetContinuation = nil
        eventContinuation = nil
    }

    // MARK: - Private

    private func handleNewConnection(_ connection: NWConnection) {
        let connID = ConnectionID(id: nextID)
        nextID += 1

        connections[connID] = connection
        deframers[connID] = TCPDeframer(framing: framing)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task {
                switch state {
                case .cancelled, .failed:
                    await self.cleanupConnection(connID)
                default:
                    break
                }
            }
        }

        connection.start(queue: DispatchQueue(label: "com.oscfoundation.tcp.server.conn.\(connID.id)"))
        eventContinuation?.yield(.connected(connID))
        startReceiving(for: connID)
    }

    private func cleanupConnection(_ connID: ConnectionID) {
        guard connections.removeValue(forKey: connID) != nil else { return }
        deframers.removeValue(forKey: connID)
        eventContinuation?.yield(.disconnected(connID))
    }

    private func startReceiving(for connID: ConnectionID) {
        guard let connection = connections[connID] else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            Task {
                if let content {
                    await self.handleReceivedData(content, from: connID)
                }
                if isComplete || error != nil {
                    await self.cleanupConnection(connID)
                } else {
                    await self.startReceiving(for: connID)
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data, from connID: ConnectionID) {
        deframers[connID]?.push(data)
        guard let packets = deframers[connID]?.drainPackets() else { return }
        for packetData in packets {
            do {
                let packet = try OSCDecoder.decode(packetData)
                packetContinuation?.yield(IncomingPacket(packet: packet, connectionID: connID))
            } catch {
                // Malformed packets are intentionally dropped per OSC convention.
            }
        }
    }
}
