import Foundation
import Network

/// An actor that provides bidirectional OSC communication over UDP on a single port.
///
/// Combines the receive capability of ``OSCUDPServer`` with the ability to send
/// to arbitrary endpoints, making it ideal for peer-to-peer OSC communication
/// where both sides send and receive on the same port.
///
/// Incoming packets are yielded through the ``packets`` stream. Outbound packets
/// can be sent to any host/port, or directly back to a sender using their
/// ``SenderEndpoint``.
///
/// ```swift
/// let peer = OSCUDPPeer(port: 8000)
/// try await peer.start()
///
/// // Send to a known destination
/// try await peer.send(OSCMessage("/hello"), to: "192.168.1.100", port: 9000)
///
/// // Receive and reply
/// for await incoming in peer.packets {
///     try await peer.send(.message(OSCMessage("/reply")), to: incoming.sender)
/// }
/// ```
public actor OSCUDPPeer {

    /// Identifies the sender of a received packet.
    public typealias SenderEndpoint = OSCUDPServer.SenderEndpoint

    /// A decoded packet along with its sender.
    public typealias IncomingPacket = OSCUDPServer.IncomingPacket

    private let port: UInt16
    private var listener: NWListener?
    private var packetContinuation: AsyncStream<IncomingPacket>.Continuation?
    private var activeConnections: [SenderEndpoint: NWConnection] = [:]
    private var outboundConnections: [String: NWConnection] = [:]

    /// The actual port the peer is listening on.
    ///
    /// Useful when initialized with port 0 (OS-assigned ephemeral port).
    /// Returns `nil` if the peer has not been started.
    public var listeningPort: UInt16? {
        listener?.port?.rawValue
    }

    /// An asynchronous stream of incoming decoded OSC packets.
    public let packets: AsyncStream<IncomingPacket>

    /// Creates a UDP peer on the given port.
    ///
    /// Does not start listening until ``start()`` is called.
    ///
    /// - Parameter port: The UDP port to bind for both sending and receiving.
    public init(port: UInt16) {
        self.port = port

        var cont: AsyncStream<IncomingPacket>.Continuation!
        self.packets = AsyncStream { cont = $0 }
        self.packetContinuation = cont
    }

    /// Starts listening for UDP datagrams on the configured port.
    ///
    /// - Throws: If the listener cannot be created or fails to start.
    public func start() async throws {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
        let listener = try NWListener(using: params, on: nwPort)
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
                let sender = SenderEndpoint(endpoint: connection.endpoint)
                connection.start(queue: DispatchQueue(label: "com.oscfoundation.udp.peer.conn"))
                Task {
                    await self.trackConnection(connection, sender: sender)
                    await self.startReceiving(connection: connection, sender: sender)
                }
            }

            listener.start(queue: DispatchQueue(label: "com.oscfoundation.udp.peer"))
        }
    }

    /// Sends an OSC packet to the specified host and port.
    ///
    /// Creates and caches an outbound `NWConnection` per unique destination.
    /// Subsequent sends to the same destination reuse the cached connection.
    ///
    /// - Parameters:
    ///   - packet: The packet to send.
    ///   - host: The destination hostname or IP address.
    ///   - port: The destination UDP port.
    /// - Throws: If encoding or sending fails.
    public func send(_ packet: OSCPacket, to host: String, port: UInt16) async throws {
        let conn = ensureOutboundConnection(host: host, port: port)
        let encoded = try OSCEncoder.encode(packet)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: encoded, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Sends an OSC message to the specified host and port.
    ///
    /// Convenience wrapper that wraps the message in a packet.
    ///
    /// - Parameters:
    ///   - message: The message to send.
    ///   - host: The destination hostname or IP address.
    ///   - port: The destination UDP port.
    /// - Throws: If encoding or sending fails.
    public func send(_ message: OSCMessage, to host: String, port: UInt16) async throws {
        try await send(.message(message), to: host, port: port)
    }

    /// Sends an OSC packet back to a known sender.
    ///
    /// Uses the existing per-flow connection that the listener created for
    /// the given sender. This is the correct approach for UDP replies --
    /// the listener already maintains a virtual connection per unique source.
    ///
    /// - Parameters:
    ///   - packet: The packet to send.
    ///   - sender: The endpoint to reply to, obtained from an ``IncomingPacket``.
    /// - Throws: ``OSCUDPError/unknownSender`` if no connection exists for the sender,
    ///   or if the send fails.
    public func send(_ packet: OSCPacket, to sender: SenderEndpoint) async throws {
        guard let conn = activeConnections[sender] else {
            throw OSCUDPError.unknownSender
        }
        let encoded = try OSCEncoder.encode(packet)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: encoded, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Stops the peer, cancels all connections, and finishes the packet stream.
    ///
    /// Safe to call multiple times.
    public func stop() {
        for connection in activeConnections.values {
            connection.cancel()
        }
        activeConnections.removeAll()
        for connection in outboundConnections.values {
            connection.cancel()
        }
        outboundConnections.removeAll()
        listener?.cancel()
        listener = nil
        packetContinuation?.finish()
        packetContinuation = nil
    }

    // MARK: - Private

    private func trackConnection(_ connection: NWConnection, sender: SenderEndpoint) {
        activeConnections[sender] = connection
    }

    private func untrackConnection(sender: SenderEndpoint) {
        activeConnections.removeValue(forKey: sender)
    }

    private func ensureOutboundConnection(host: String, port: UInt16) -> NWConnection {
        let key = "\(host):\(port)"
        if let existing = outboundConnections[key] { return existing }
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        conn.start(queue: DispatchQueue(label: "com.oscfoundation.udp.peer.conn"))
        outboundConnections[key] = conn
        return conn
    }

    private func startReceiving(connection: NWConnection, sender: SenderEndpoint) {
        guard packetContinuation != nil else {
            connection.cancel()
            return
        }
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            Task {
                if let data {
                    do {
                        let packet = try OSCDecoder.decode(data)
                        await self.packetContinuation?.yield(IncomingPacket(packet: packet, sender: sender))
                    } catch {
                        // Malformed packets are intentionally dropped per OSC convention.
                    }
                }
                if error != nil {
                    connection.cancel()
                    await self.untrackConnection(sender: sender)
                } else {
                    await self.startReceiving(connection: connection, sender: sender)
                }
            }
        }
    }
}
