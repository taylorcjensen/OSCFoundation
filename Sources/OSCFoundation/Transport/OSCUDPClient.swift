import Foundation
import Network

/// An actor that sends OSC packets over UDP.
///
/// Uses `NWConnection` with `.udp` protocol. The connection is lazily
/// created on the first send. No framing is applied -- each packet is
/// sent as a single UDP datagram.
///
/// Enable ``isIPv4BroadcastEnabled`` to send to broadcast addresses
/// (e.g., `255.255.255.255` or `192.168.1.255`).
///
/// ```swift
/// let client = OSCUDPClient(host: "192.168.1.100", port: 8000)
/// try await client.send(OSCMessage("/eos/ping"))
/// client.close()
/// ```
public actor OSCUDPClient {
    private let host: String
    private let port: UInt16
    private let isIPv4BroadcastEnabled: Bool
    private var connection: NWConnection?

    /// Creates a UDP client targeting the given host and port.
    ///
    /// Does not open a connection until the first send.
    ///
    /// - Parameters:
    ///   - host: The hostname or IP address.
    ///   - port: The UDP port number. Must be greater than 0.
    ///   - isIPv4BroadcastEnabled: When `true`, allows sending to
    ///     broadcast addresses. Enables local endpoint reuse so
    ///     multiple processes can share the port. Defaults to `false`.
    public init(host: String, port: UInt16, isIPv4BroadcastEnabled: Bool = false) {
        precondition(port > 0, "Port must be greater than 0")
        self.host = host
        self.port = port
        self.isIPv4BroadcastEnabled = isIPv4BroadcastEnabled
    }

    /// Sends an OSC packet as a single UDP datagram.
    ///
    /// The connection is lazily created on the first call.
    ///
    /// - Parameter packet: The packet to send.
    /// - Throws: If the send fails.
    public func send(_ packet: OSCPacket) async throws {
        let conn = ensureConnection()
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

    /// Sends an OSC message as a single UDP datagram.
    ///
    /// Convenience wrapper that wraps the message in a packet.
    ///
    /// - Parameter message: The message to send.
    /// - Throws: If the send fails.
    public func send(_ message: OSCMessage) async throws {
        try await send(.message(message))
    }

    /// Closes the UDP connection and releases resources.
    ///
    /// Safe to call multiple times.
    public func close() {
        connection?.cancel()
        connection = nil
    }

    // MARK: - Private

    private func ensureConnection() -> NWConnection {
        if let connection { return connection }
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let params = NWParameters.udp
        if isIPv4BroadcastEnabled {
            params.allowLocalEndpointReuse = true
        }
        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        conn.start(queue: DispatchQueue(label: "com.oscfoundation.udp.client"))
        self.connection = conn
        return conn
    }
}
