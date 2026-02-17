import Foundation
import Network

/// An actor that manages OSC communication over UDP multicast.
///
/// Joins a multicast group and provides both sending and receiving of OSC
/// packets. All members of the same group and port will receive messages
/// sent to the group address.
///
/// Uses `NWConnectionGroup` with `NWMulticastGroup` from the Network
/// framework for multicast group membership and message delivery.
///
/// ```swift
/// let multicast = OSCUDPMulticast(group: "239.255.255.250", port: 9000)
/// try await multicast.start()
///
/// // Send to entire group
/// try await multicast.send(OSCMessage("/hello"))
///
/// // Receive from group
/// for await incoming in multicast.packets {
///     print("From \(incoming.sender): \(incoming.packet)")
/// }
///
/// multicast.stop()
/// ```
public actor OSCUDPMulticast {

    /// A decoded packet along with the endpoint that sent it.
    public struct IncomingPacket: Sendable {
        /// The decoded OSC packet.
        public let packet: OSCPacket
        /// The endpoint that sent this packet.
        public let sender: NWEndpoint
    }

    private let group: String
    private let port: UInt16
    private var connectionGroup: NWConnectionGroup?
    private var packetContinuation: AsyncStream<IncomingPacket>.Continuation?

    /// An asynchronous stream of incoming decoded OSC packets from the multicast group.
    public let packets: AsyncStream<IncomingPacket>

    /// Creates a multicast actor for the given group address and port.
    ///
    /// Does not join the multicast group until ``start()`` is called.
    ///
    /// - Parameters:
    ///   - group: The multicast group address (e.g., `"239.255.255.250"`).
    ///   - port: The UDP port number for the multicast group.
    public init(group: String, port: UInt16) {
        self.group = group
        self.port = port

        var cont: AsyncStream<IncomingPacket>.Continuation!
        self.packets = AsyncStream { cont = $0 }
        self.packetContinuation = cont
    }

    /// Joins the multicast group and begins receiving packets.
    ///
    /// Creates an `NWConnectionGroup` bound to the multicast group address
    /// and port, then awaits the `.ready` state before returning.
    ///
    /// - Throws: If the multicast group cannot be joined or the connection
    ///   group fails to start.
    public func start() async throws {
        let multicastGroup = try NWMulticastGroup(
            for: [.hostPort(host: NWEndpoint.Host(group), port: NWEndpoint.Port(rawValue: port)!)]
        )

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let connectionGroup = NWConnectionGroup(with: multicastGroup, using: params)
        self.connectionGroup = connectionGroup

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) var resumed = false
            connectionGroup.stateUpdateHandler = { state in
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
                case .waiting(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }

            connectionGroup.setReceiveHandler(
                maximumMessageSize: 65535,
                rejectOversizedMessages: false
            ) { [weak self] message, data, isComplete in
                guard let self, let data else { return }
                do {
                    let packet = try OSCDecoder.decode(data)
                    let sender = message.remoteEndpoint ?? .hostPort(
                        host: .ipv4(.any),
                        port: 0
                    )
                    Task {
                        await self.yieldPacket(
                            IncomingPacket(packet: packet, sender: sender)
                        )
                    }
                } catch {
                    // Malformed packets are intentionally dropped per OSC convention.
                }
            }

            connectionGroup.start(
                queue: DispatchQueue(label: "com.oscfoundation.udp.multicast")
            )
        }
    }

    /// Sends an OSC packet to the entire multicast group.
    ///
    /// Encodes the packet and sends it to all members of the group.
    /// Passing `nil` as the destination endpoint broadcasts to the group.
    ///
    /// - Parameter packet: The packet to send.
    /// - Throws: If encoding fails or the send operation fails.
    public func send(_ packet: OSCPacket) async throws {
        try await sendEncoded(packet, to: nil)
    }

    /// Sends an OSC message to the entire multicast group.
    ///
    /// Convenience wrapper that wraps the message in a packet.
    ///
    /// - Parameter message: The message to send.
    /// - Throws: If encoding fails or the send operation fails.
    public func send(_ message: OSCMessage) async throws {
        try await send(.message(message))
    }

    /// Sends an OSC packet to a specific member endpoint within the group.
    ///
    /// - Parameters:
    ///   - packet: The packet to send.
    ///   - member: The specific endpoint to send to.
    /// - Throws: If encoding fails or the send operation fails.
    public func send(_ packet: OSCPacket, to member: NWEndpoint) async throws {
        try await sendEncoded(packet, to: member)
    }

    /// Stops the multicast group and finishes the packet stream.
    ///
    /// Cancels the connection group and releases all resources.
    /// Safe to call multiple times.
    public func stop() {
        connectionGroup?.cancel()
        connectionGroup = nil
        packetContinuation?.finish()
        packetContinuation = nil
    }

    // MARK: - Private

    /// Encodes and sends an OSC packet, optionally to a specific endpoint.
    ///
    /// - Parameters:
    ///   - packet: The packet to encode and send.
    ///   - endpoint: The specific endpoint to send to, or `nil` for the entire group.
    /// - Throws: If encoding fails or the send operation fails.
    private func sendEncoded(_ packet: OSCPacket, to endpoint: NWEndpoint?) async throws {
        guard let connectionGroup else { return }
        let encoded = try OSCEncoder.encode(packet)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectionGroup.send(content: encoded, to: endpoint) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Yields an incoming packet to the stream continuation.
    ///
    /// - Parameter packet: The incoming packet to yield.
    private func yieldPacket(_ packet: IncomingPacket) {
        packetContinuation?.yield(packet)
    }
}
