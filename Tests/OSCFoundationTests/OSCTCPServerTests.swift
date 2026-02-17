import Testing
@testable import OSCFoundation
import Foundation
import Network

@Suite("OSCTCPServer")
struct OSCTCPServerTests {

    @Test("Server start and stop")
    func startStop() async throws {
        let server = OSCTCPServer(port: 0)
        try await server.start()
        let port = await server.listeningPort
        #expect(port != nil)
        #expect(port! > 0)
        let connections = await server.activeConnections
        #expect(connections.isEmpty)
        await server.stop()
    }

    @Test("Client connects and sends packet to server")
    func clientToServer() async throws {
        let server = OSCTCPServer(port: 0)
        try await server.start()
        let port = await server.listeningPort!

        let receiveTask = Task { () -> OSCPacket? in
            for await incoming in await server.packets {
                return incoming.packet
            }
            return nil
        }

        let connectTask = Task { () -> Bool in
            for await event in await server.connectionEvents {
                if case .connected = event { return true }
            }
            return false
        }

        let client = OSCTCPClient(host: "127.0.0.1", port: port)
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

        let serverGotConnect = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await connectTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                connectTask.cancel()
                return false
            }
            for await result in group {
                if result {
                    group.cancelAll()
                    return true
                }
            }
            return false
        }
        #expect(serverGotConnect)

        let msg = try OSCMessage("/tcp/server/test", arguments: [Int32(99), "hello"])
        try await client.send(msg)

        let result = await withTaskGroup(of: OSCPacket?.self) { group in
            group.addTask { await receiveTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                receiveTask.cancel()
                return nil
            }
            for await result in group {
                if result != nil {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }

        guard case .message(let received) = result else {
            Issue.record("Expected message, got \(String(describing: result))")
            await client.disconnect()
            await server.stop()
            return
        }
        #expect(received == msg)

        await client.disconnect()
        await server.stop()
    }

    @Test("Server sends packet to client")
    func serverToClient() async throws {
        let server = OSCTCPServer(port: 0)
        try await server.start()
        let port = await server.listeningPort!

        let connIDTask = Task { () -> OSCTCPServer.ConnectionID? in
            for await event in await server.connectionEvents {
                if case .connected(let id) = event { return id }
            }
            return nil
        }

        let client = OSCTCPClient(host: "127.0.0.1", port: port)
        let clientReceiveTask = Task { () -> OSCPacket? in
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
        _ = await stateTask.value

        let connID = await withTaskGroup(of: OSCTCPServer.ConnectionID?.self) { group in
            group.addTask { await connIDTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                connIDTask.cancel()
                return nil
            }
            for await result in group {
                if result != nil {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }

        guard let connID else {
            Issue.record("No connection ID received")
            await client.disconnect()
            await server.stop()
            return
        }

        let msg = try OSCMessage("/from/server", arguments: ["response"])
        try await server.send(.message(msg), to: connID)

        let result = await withTaskGroup(of: OSCPacket?.self) { group in
            group.addTask { await clientReceiveTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                clientReceiveTask.cancel()
                return nil
            }
            for await result in group {
                if result != nil {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }

        guard case .message(let received) = result else {
            Issue.record("Expected message, got \(String(describing: result))")
            await client.disconnect()
            await server.stop()
            return
        }
        #expect(received == msg)

        await client.disconnect()
        await server.stop()
    }

    @Test("Server broadcast sends to all clients")
    func broadcast() async throws {
        let server = OSCTCPServer(port: 0)
        try await server.start()
        let port = await server.listeningPort!

        let client1 = OSCTCPClient(host: "127.0.0.1", port: port)
        let client2 = OSCTCPClient(host: "127.0.0.1", port: port)

        let recv1 = Task { () -> OSCPacket? in
            for await packet in await client1.packets { return packet }
            return nil
        }
        let recv2 = Task { () -> OSCPacket? in
            for await packet in await client2.packets { return packet }
            return nil
        }

        let state1 = Task {
            for await state in await client1.stateUpdates {
                if state == .connected { return }
            }
        }
        let state2 = Task {
            for await state in await client2.stateUpdates {
                if state == .connected { return }
            }
        }

        await client1.connect()
        await client2.connect()
        await state1.value
        await state2.value

        // Small delay to let server register both connections
        try await Task.sleep(nanoseconds: 100_000_000)

        let connections = await server.activeConnections
        #expect(connections.count == 2)

        let msg = try OSCMessage("/broadcast", arguments: [Int32(1)])
        try await server.broadcast(.message(msg))

        let result1 = await withTaskGroup(of: OSCPacket?.self) { group in
            group.addTask { await recv1.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                recv1.cancel()
                return nil
            }
            for await r in group { if r != nil { group.cancelAll(); return r } }
            return nil
        }
        let result2 = await withTaskGroup(of: OSCPacket?.self) { group in
            group.addTask { await recv2.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                recv2.cancel()
                return nil
            }
            for await r in group { if r != nil { group.cancelAll(); return r } }
            return nil
        }

        if case .message(let m1) = result1 { #expect(m1 == msg) }
        else { Issue.record("Client 1 did not receive broadcast") }

        if case .message(let m2) = result2 { #expect(m2 == msg) }
        else { Issue.record("Client 2 did not receive broadcast") }

        await client1.disconnect()
        await client2.disconnect()
        await server.stop()
    }

    @Test("Disconnect removes connection")
    func disconnectConnection() async throws {
        let server = OSCTCPServer(port: 0)
        try await server.start()
        let port = await server.listeningPort!

        let connIDTask = Task { () -> OSCTCPServer.ConnectionID? in
            for await event in await server.connectionEvents {
                if case .connected(let id) = event { return id }
            }
            return nil
        }

        let client = OSCTCPClient(host: "127.0.0.1", port: port)
        let stateTask = Task {
            for await state in await client.stateUpdates {
                if state == .connected { return }
            }
        }
        await client.connect()
        await stateTask.value

        let connID = await withTaskGroup(of: OSCTCPServer.ConnectionID?.self) { group in
            group.addTask { await connIDTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                connIDTask.cancel()
                return nil
            }
            for await r in group { if r != nil { group.cancelAll(); return r } }
            return nil
        }

        guard let connID else {
            Issue.record("No connection ID")
            await server.stop()
            return
        }

        var connections = await server.activeConnections
        #expect(connections.contains(connID))

        await server.disconnect(connID)
        connections = await server.activeConnections
        #expect(!connections.contains(connID))

        await client.disconnect()
        await server.stop()
    }

    @Test("Send to unknown connection throws")
    func sendToUnknownConnection() async throws {
        let server = OSCTCPServer(port: 0)
        try await server.start()

        let unknownID = OSCTCPServer.ConnectionID(id: 9999)
        let msg = try OSCMessage("/test")
        do {
            try await server.send(.message(msg), to: unknownID)
            Issue.record("Expected error")
        } catch {
            // Expected
        }

        await server.stop()
    }

    @Test("SLIP framing end-to-end")
    func slipFramingEndToEnd() async throws {
        let server = OSCTCPServer(port: 0, framing: .slip)
        try await server.start()
        let port = await server.listeningPort!

        let receiveTask = Task { () -> OSCPacket? in
            for await incoming in await server.packets {
                return incoming.packet
            }
            return nil
        }

        let client = OSCTCPClient(host: "127.0.0.1", port: port, framing: .slip)
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

        // Small delay to let server register the connection
        try await Task.sleep(nanoseconds: 100_000_000)

        let msg = try OSCMessage("/slip/test", arguments: [Int32(42), "slip-works"])
        try await client.send(msg)

        let result = await withTaskGroup(of: OSCPacket?.self) { group in
            group.addTask { await receiveTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                receiveTask.cancel()
                return nil
            }
            for await result in group {
                if result != nil {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }

        guard case .message(let received) = result else {
            Issue.record("Expected message, got \(String(describing: result))")
            await client.disconnect()
            await server.stop()
            return
        }
        #expect(received == msg)

        await client.disconnect()
        await server.stop()
    }

    @Test("Start on occupied port throws")
    func startOnOccupiedPort() async throws {
        let server1 = OSCTCPServer(port: 0)
        try await server1.start()
        let port = await server1.listeningPort!

        let server2 = OSCTCPServer(port: port)
        do {
            try await server2.start()
            Issue.record("Expected error starting on occupied port")
            await server2.stop()
        } catch {
            // Expected -- port is already in use
        }

        await server1.stop()
    }

    @Test("ConnectionID description format")
    func connectionIDDescription() {
        let id = OSCTCPServer.ConnectionID(id: 42)
        #expect(String(describing: id) == "Connection(42)")
    }

    @Test("Server drops malformed packets and continues")
    func serverDropsMalformedPacket() async throws {
        let server = OSCTCPServer(port: 0)
        try await server.start()
        let port = await server.listeningPort!

        let receiveTask = Task { () -> OSCPacket? in
            for await incoming in await server.packets {
                return incoming.packet
            }
            return nil
        }

        // Connect a raw NWConnection to bypass OSC encoding
        let conn = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            nonisolated(unsafe) var resumed = false
            conn.stateUpdateHandler = { state in
                guard !resumed else { return }
                if case .ready = state {
                    resumed = true
                    continuation.resume()
                }
            }
            conn.start(queue: DispatchQueue(label: "test.raw.tcp"))
        }

        // Send PLH-framed garbage (not valid OSC)
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let malformedFrame = TCPDeframer.frame(garbage, using: .plh)
        conn.send(content: malformedFrame, completion: .contentProcessed { _ in })

        // Small delay, then send a valid PLH-framed OSC message
        try await Task.sleep(nanoseconds: 100_000_000)
        let validOSC = try OSCEncoder.encode(try OSCMessage("/valid", arguments: [Int32(1)]))
        let validFrame = TCPDeframer.frame(validOSC, using: .plh)
        conn.send(content: validFrame, completion: .contentProcessed { _ in })

        // Server should receive the valid packet (malformed one was dropped)
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
            Issue.record("Server should have received valid message after dropping malformed one")
            conn.cancel()
            await server.stop()
            return
        }
        #expect(received.addressPattern == "/valid")

        conn.cancel()
        await server.stop()
    }

    @Test("Server detects client disconnect")
    func clientDisconnectDetected() async throws {
        let server = OSCTCPServer(port: 0)
        try await server.start()
        let port = await server.listeningPort!

        let disconnectTask = Task { () -> Bool in
            for await event in await server.connectionEvents {
                if case .disconnected = event { return true }
            }
            return false
        }

        let client = OSCTCPClient(host: "127.0.0.1", port: port)
        let stateTask = Task {
            for await state in await client.stateUpdates {
                if state == .connected { return }
            }
        }
        await client.connect()
        await stateTask.value

        // Small delay to let server register the connection
        try await Task.sleep(nanoseconds: 100_000_000)

        // Disconnect the client -- server should detect it
        await client.disconnect()

        let gotDisconnect = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await disconnectTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                disconnectTask.cancel()
                return false
            }
            for await result in group {
                if result {
                    group.cancelAll()
                    return true
                }
            }
            return false
        }

        #expect(gotDisconnect)
        await server.stop()
    }
}
