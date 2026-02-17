import Foundation
import Network

/// Errors specific to OSC UDP operations.
public enum OSCUDPError: Error, Equatable {
    /// No active connection exists for the given sender endpoint.
    case unknownSender
}

/// An actor that listens for OSC packets over UDP.
///
/// Each received datagram is decoded and yielded through the ``packets`` stream
/// along with the sender's endpoint, enabling responses.
///
/// Malformed packets that fail decoding are silently dropped, which is standard
/// OSC behavior. Only successfully decoded packets appear in ``packets``.
///
/// ```swift
/// let server = OSCUDPServer(port: 8000)
/// try await server.start()
///
/// for await incoming in server.packets {
///     print("From \(incoming.sender): \(incoming.packet)")
/// }
/// ```
public actor OSCUDPServer {

    /// Identifies the sender of a received packet.
    ///
    /// An opaque wrapper around the network endpoint. Two packets from the
    /// same source will have equal `SenderEndpoint` values.
    public struct SenderEndpoint: Sendable, Hashable {
        let endpoint: NWEndpoint

        public func hash(into hasher: inout Hasher) {
            hasher.combine(String(describing: endpoint))
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            String(describing: lhs.endpoint) == String(describing: rhs.endpoint)
        }
    }

    /// A decoded packet along with its sender.
    public struct IncomingPacket: Sendable {
        /// The decoded OSC packet.
        public let packet: OSCPacket
        /// The endpoint that sent this packet.
        public let sender: SenderEndpoint
    }

    private let port: UInt16
    private var listener: NWListener?
    private var packetContinuation: AsyncStream<IncomingPacket>.Continuation?
    private var activeConnections: [SenderEndpoint: NWConnection] = [:]

    /// The actual port the server is listening on.
    ///
    /// Useful when initialized with port 0 (OS-assigned ephemeral port).
    /// Returns `nil` if the server has not been started.
    public var listeningPort: UInt16? {
        listener?.port?.rawValue
    }

    /// An asynchronous stream of incoming decoded OSC packets.
    public let packets: AsyncStream<IncomingPacket>

    /// Creates a UDP server on the given port.
    ///
    /// Does not start listening until ``start()`` is called.
    ///
    /// - Parameter port: The UDP port to listen on.
    public init(port: UInt16) {
        self.port = port

        var cont: AsyncStream<IncomingPacket>.Continuation!
        self.packets = AsyncStream { cont = $0 }
        self.packetContinuation = cont
    }

    /// Starts listening for UDP datagrams.
    ///
    /// - Throws: If the listener cannot be created or fails to start.
    public func start() async throws {
        let params = NWParameters.udp
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
                connection.start(queue: DispatchQueue(label: "com.oscfoundation.udp.server.conn"))
                Task {
                    await self.trackConnection(connection, sender: sender)
                    await self.startReceiving(connection: connection, sender: sender)
                }
            }

            listener.start(queue: DispatchQueue(label: "com.oscfoundation.udp.server"))
        }
    }

    /// Sends an OSC packet to a specific sender endpoint.
    ///
    /// Uses the existing per-flow connection that the listener created for
    /// the given sender. This is the correct approach for UDP -- the listener
    /// already maintains a virtual connection per unique source.
    ///
    /// - Parameters:
    ///   - packet: The packet to send.
    ///   - sender: The endpoint to send to.
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

    /// Stops the server and finishes the packet stream.
    ///
    /// Cancels all active per-peer connections and the listener itself.
    public func stop() {
        for connection in activeConnections.values {
            connection.cancel()
        }
        activeConnections.removeAll()
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
