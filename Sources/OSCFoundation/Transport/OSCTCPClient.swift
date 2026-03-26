import Foundation
import Network

/// An actor that manages a TCP connection for sending and receiving OSC packets.
///
/// Supports both PLH (Packet Length Header) and SLIP framing. PLH is the default
/// and is used by ETC Eos consoles on port 3032.
///
/// Malformed packets that fail decoding are silently dropped, which is standard
/// OSC behavior. Only successfully decoded packets appear in ``packets``.
///
/// ```swift
/// let client = OSCTCPClient(host: "192.168.1.100", port: 3032)
/// try await client.connect()
///
/// for await packet in client.packets {
///     // Handle incoming OSC packets
/// }
/// ```
public actor OSCTCPClient {
    private let host: String
    private let port: UInt16
    private let framing: TCPFraming
    private let connectionTimeout: Int?
    private let enableKeepalive: Bool
    private let keepaliveIdle: Int
    private let keepaliveInterval: Int
    private let keepaliveCount: Int
    private var connection: NWConnection?
    private var deframer: TCPDeframer
    private var isReceiving = false

    private var packetContinuation: AsyncStream<OSCPacket>.Continuation?
    private var stateContinuation: AsyncStream<ConnectionState>.Continuation?

    /// An asynchronous stream of decoded OSC packets received from the connection.
    public let packets: AsyncStream<OSCPacket>

    /// An asynchronous stream of connection state changes.
    public let stateUpdates: AsyncStream<ConnectionState>

    /// The current connection state.
    public private(set) var state: ConnectionState = .disconnected

    /// Creates a TCP client targeting the given host and port.
    ///
    /// Does not connect automatically -- call ``connect()`` to initiate.
    ///
    /// - Parameters:
    ///   - host: The hostname or IP address.
    ///   - port: The TCP port number (default 3032 for Eos). Must be greater than 0.
    ///   - framing: The TCP framing protocol to use (default `.plh`).
    ///   - connectionTimeout: Optional TCP connect timeout in seconds. If set,
    ///     the connection attempt will enter `.waiting` when the timeout elapses.
    ///   - enableKeepalive: Whether to enable TCP keepalive probes.
    ///   - keepaliveIdle: Idle time in seconds before the first keepalive probe.
    ///   - keepaliveInterval: Seconds between keepalive probes.
    ///   - keepaliveCount: Number of failed keepalive probes before giving up.
    public init(
        host: String,
        port: UInt16 = 3032,
        framing: TCPFraming = .plh,
        connectionTimeout: Int? = nil,
        enableKeepalive: Bool = false,
        keepaliveIdle: Int = 15,
        keepaliveInterval: Int = 5,
        keepaliveCount: Int = 3
    ) {
        precondition(port > 0, "Port must be greater than 0")
        if let connectionTimeout {
            precondition(connectionTimeout > 0, "Connection timeout must be greater than 0")
        }
        precondition(keepaliveIdle > 0, "Keepalive idle must be greater than 0")
        precondition(keepaliveInterval > 0, "Keepalive interval must be greater than 0")
        precondition(keepaliveCount > 0, "Keepalive count must be greater than 0")
        self.host = host
        self.port = port
        self.framing = framing
        self.connectionTimeout = connectionTimeout
        self.enableKeepalive = enableKeepalive
        self.keepaliveIdle = keepaliveIdle
        self.keepaliveInterval = keepaliveInterval
        self.keepaliveCount = keepaliveCount
        self.deframer = TCPDeframer(framing: framing)

        var packetCont: AsyncStream<OSCPacket>.Continuation!
        self.packets = AsyncStream { packetCont = $0 }
        self.packetContinuation = packetCont

        var stateCont: AsyncStream<ConnectionState>.Continuation!
        self.stateUpdates = AsyncStream { stateCont = $0 }
        self.stateContinuation = stateCont
    }

    /// Initiates the TCP connection.
    ///
    /// Connection state changes are emitted via ``stateUpdates``.
    public func connect() {
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let tcpOptions = NWProtocolTCP.Options()
        if let connectionTimeout {
            tcpOptions.connectionTimeout = connectionTimeout
        }
        if enableKeepalive {
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = keepaliveIdle
            tcpOptions.keepaliveInterval = keepaliveInterval
            tcpOptions.keepaliveCount = keepaliveCount
        }
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        let connection = NWConnection(host: nwHost, port: nwPort, using: parameters)
        self.connection = connection

        updateState(.connecting)

        connection.stateUpdateHandler = { [weak self] nwState in
            guard let self else { return }
            Task {
                await self.handleStateUpdate(nwState)
            }
        }

        connection.start(queue: DispatchQueue(label: "com.oscfoundation.tcp"))
    }

    /// Sends an OSC packet over the connection.
    ///
    /// The packet is encoded and PLH-framed before transmission.
    ///
    /// - Parameter packet: The packet to send.
    /// - Throws: ``OSCTCPError/notConnected`` if not in the connected state.
    public func send(_ packet: OSCPacket) throws {
        guard let connection, state == .connected else {
            throw OSCTCPError.notConnected
        }

        let encoded = try OSCEncoder.encode(packet)
        let framed = TCPDeframer.frame(encoded, using: framing)

        connection.send(content: framed, completion: .contentProcessed { _ in })
    }

    /// Sends an OSC message over the connection.
    ///
    /// Convenience wrapper around ``send(_:)-7k9fz`` that wraps the message in a packet.
    ///
    /// - Parameter message: The message to send.
    /// - Throws: ``OSCTCPError/notConnected`` if not in the connected state.
    public func send(_ message: OSCMessage) throws {
        try send(.message(message))
    }

    /// Closes the connection and finishes the packet/state streams.
    public func disconnect() {
        connection?.cancel()
        connection = nil
        isReceiving = false
        deframer = TCPDeframer(framing: framing)
        updateState(.disconnected)
        packetContinuation?.finish()
        stateContinuation?.finish()
        packetContinuation = nil
        stateContinuation = nil
    }

    // MARK: - Private

    func handleStateUpdate(_ nwState: NWConnection.State) {
        switch nwState {
        case .ready:
            updateState(.connected)
            if !isReceiving {
                startReceiving()
            }
        case .failed(let error):
            isReceiving = false
            updateState(.failed(error.localizedDescription))
            connection?.cancel()
            connection = nil
        case .cancelled:
            isReceiving = false
            updateState(.disconnected)
        case .preparing, .setup:
            updateState(.connecting)
        case .waiting(let error):
            updateState(.waiting(error.localizedDescription))
        @unknown default:
            break
        }
    }

    private func updateState(_ newState: ConnectionState) {
        state = newState
        stateContinuation?.yield(newState)
    }

    private func startReceiving() {
        guard let connection else { return }
        isReceiving = true
        receiveNext(on: connection)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            Task {
                if let content {
                    await self.handleReceivedData(content)
                }
                if isComplete || error != nil {
                    await self.disconnect()
                } else {
                    await self.receiveNext(on: connection)
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        deframer.push(data)
        for packetData in deframer.drainPackets() {
            do {
                let packet = try OSCDecoder.decode(packetData)
                packetContinuation?.yield(packet)
            } catch {
                // Malformed packets are intentionally dropped per OSC convention.
            }
        }
    }
}

/// Errors specific to the OSC TCP transport.
public enum OSCTCPError: Error {
    /// Attempted to send on a connection that is not in the connected state.
    case notConnected
}
