import Testing
@testable import OSCFoundation
import Foundation
import Network

@Suite("OSCTCPClient")
struct OSCTCPClientTests {
    @Test("Connection state starts disconnected")
    func initialState() async {
        let client = OSCTCPClient(host: "127.0.0.1", port: 9999)
        let state = await client.state
        #expect(state == .disconnected)
    }

    @Test("Send before connect throws notConnected")
    func sendBeforeConnect() async throws {
        let client = OSCTCPClient(host: "127.0.0.1", port: 9999)
        do {
            try await client.send(try OSCMessage("/test"))
            Issue.record("Expected notConnected error")
        } catch let error as OSCTCPError {
            #expect(error == .notConnected)
        }
    }

    @Test("Full TCP round-trip with local listener")
    func tcpRoundTrip() async throws {
        let server = TestServer()
        let port = try await server.start()

        let client = OSCTCPClient(host: "127.0.0.1", port: port)

        // Start listening for packets BEFORE connecting so we don't miss anything
        let receiveTask = Task { () -> OSCPacket? in
            for await packet in await client.packets {
                return packet
            }
            return nil
        }

        // Start listening for connection state
        let stateTask = Task {
            for await state in await client.stateUpdates {
                if state == .connected { return true }
                if case .failed = state { return false }
            }
            return false
        }

        await client.connect()

        let connected = await stateTask.value
        #expect(connected)

        // Send a message
        let message = try OSCMessage("/test/roundtrip", arguments: [Int32(42), "hello"])
        try await client.send(.message(message))

        // Wait for the echoed packet
        // Add a timeout by racing against a sleep
        let result = await withTaskGroup(of: OSCPacket?.self) { group in
            group.addTask {
                await receiveTask.value
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                receiveTask.cancel()
                return nil
            }
            // Return first non-nil result, or nil on timeout
            for await result in group {
                if result != nil {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }

        guard case .message(let received) = result else {
            Issue.record("Expected message packet, got \(String(describing: result))")
            await client.disconnect()
            await server.stop()
            return
        }
        #expect(received == message)

        await client.disconnect()
        await server.stop()
    }

    @Test("Client drops malformed packets and continues")
    func clientDropsMalformedPacket() async throws {
        let server = MalformedThenValidServer()
        let port = try await server.start()

        let client = OSCTCPClient(host: "127.0.0.1", port: port)

        // Listen for packets before connecting
        let receiveTask = Task { () -> OSCPacket? in
            for await packet in await client.packets {
                return packet
            }
            return nil
        }

        let stateTask = Task {
            for await state in await client.stateUpdates {
                if state == .connected { return true }
                if case .failed = state { return false }
            }
            return false
        }

        await client.connect()
        let connected = await stateTask.value
        #expect(connected)

        // The server sends malformed data then valid data upon connection.
        // Client should drop the malformed packet and yield the valid one.
        let result = await withTaskGroup(of: OSCPacket?.self) { group in
            group.addTask { await receiveTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                receiveTask.cancel()
                return nil
            }
            for await r in group {
                if r != nil { group.cancelAll(); return r }
            }
            return nil
        }

        guard case .message(let received) = result else {
            Issue.record("Client should have received valid message after dropping malformed one")
            await client.disconnect()
            await server.stop()
            return
        }
        #expect(received.addressPattern == "/valid")

        await client.disconnect()
        await server.stop()
    }
}

// MARK: - Test Server

/// A simple TCP server that echoes back any data it receives.
private actor TestServer {
    private var listener: NWListener?

    /// Starts the server on an OS-assigned port and returns the port number.
    func start() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: 0)
        self.listener = listener

        return try await withCheckedThrowingContinuation { continuation in
            // Safe: NWListener delivers stateUpdateHandler callbacks on the
            // serial queue passed to start(queue:), preventing concurrent access.
            nonisolated(unsafe) var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue {
                        resumed = true
                        continuation.resume(returning: port)
                    }
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

            listener.newConnectionHandler = { serverConn in
                serverConn.start(queue: DispatchQueue(label: "test.server.conn"))
                Self.echoConnection(serverConn)
            }

            listener.start(queue: DispatchQueue(label: "test.server.listener"))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Reads one chunk and echoes it back. Runs entirely on the NWConnection's queue.
    private static nonisolated func echoConnection(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
            if let data {
                conn.send(content: data, completion: .contentProcessed { _ in })
            }
        }
    }
}

/// A TCP server that sends malformed PLH data followed by a valid OSC message.
private actor MalformedThenValidServer {
    private var listener: NWListener?

    func start() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: 0)
        self.listener = listener

        return try await withCheckedThrowingContinuation { continuation in
            nonisolated(unsafe) var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue {
                        resumed = true
                        continuation.resume(returning: port)
                    }
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default: break
                }
            }

            listener.newConnectionHandler = { conn in
                conn.start(queue: DispatchQueue(label: "test.malformed.conn"))
                Self.sendMalformedThenValid(conn)
            }

            listener.start(queue: DispatchQueue(label: "test.malformed"))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Sends a malformed PLH frame followed by a valid OSC message.
    private static nonisolated func sendMalformedThenValid(_ conn: NWConnection) {
        // Malformed: PLH-framed garbage bytes
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let malformedFrame = TCPDeframer.frame(garbage, using: .plh)
        conn.send(content: malformedFrame, completion: .contentProcessed { _ in
            // Valid: PLH-framed OSC message
            let validOSC = try! OSCEncoder.encode(try! OSCMessage("/valid"))
            let validFrame = TCPDeframer.frame(validOSC, using: .plh)
            conn.send(content: validFrame, completion: .contentProcessed { _ in })
        })
    }
}
