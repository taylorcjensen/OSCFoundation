import Testing
@testable import OSCFoundation
import Foundation
import Network

@Suite("OSC UDP Peer")
struct OSCUDPPeerTests {

    @Test("Start and stop")
    func startAndStop() async throws {
        let peer = OSCUDPPeer(port: 0)
        try await peer.start()
        let port = await peer.listeningPort
        #expect(port != nil)
        #expect(port! > 0)
        await peer.stop()
        // Idempotent stop
        await peer.stop()
    }

    @Test("Two peers communicate bidirectionally")
    func twoPeersBidirectional() async throws {
        let peerA = OSCUDPPeer(port: 0)
        let peerB = OSCUDPPeer(port: 0)
        try await peerA.start()
        try await peerB.start()
        let portA = await peerA.listeningPort!
        let portB = await peerB.listeningPort!

        // B listens for a message from A
        let receiveBTask = Task { () -> OSCPacket? in
            for await incoming in await peerB.packets {
                return incoming.packet
            }
            return nil
        }

        // A sends to B
        let msgAtoB = try OSCMessage("/from/a", arguments: [Int32(1)])
        try await peerA.send(msgAtoB, to: "127.0.0.1", port: portB)

        let resultB = await withTaskGroup(of: OSCPacket?.self) { group in
            group.addTask { await receiveBTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                receiveBTask.cancel()
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

        guard case .message(let receivedByB) = resultB else {
            Issue.record("Peer B did not receive message from A")
            await peerA.stop()
            await peerB.stop()
            return
        }
        #expect(receivedByB == msgAtoB)

        // A listens for a message from B
        let receiveATask = Task { () -> OSCPacket? in
            for await incoming in await peerA.packets {
                return incoming.packet
            }
            return nil
        }

        // B sends to A
        let msgBtoA = try OSCMessage("/from/b", arguments: [Int32(2)])
        try await peerB.send(msgBtoA, to: "127.0.0.1", port: portA)

        let resultA = await withTaskGroup(of: OSCPacket?.self) { group in
            group.addTask { await receiveATask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                receiveATask.cancel()
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

        guard case .message(let receivedByA) = resultA else {
            Issue.record("Peer A did not receive message from B")
            await peerA.stop()
            await peerB.stop()
            return
        }
        #expect(receivedByA == msgBtoA)

        await peerA.stop()
        await peerB.stop()
    }

    @Test("Reply to sender endpoint")
    func replyToSender() async throws {
        let peerA = OSCUDPPeer(port: 0)
        let peerB = OSCUDPPeer(port: 0)
        try await peerA.start()
        try await peerB.start()
        let portB = await peerB.listeningPort!

        // B waits for an incoming packet to capture the sender endpoint
        let incomingTask = Task { () -> OSCUDPPeer.IncomingPacket? in
            for await incoming in await peerB.packets {
                return incoming
            }
            return nil
        }

        // A sends to B
        try await peerA.send(try OSCMessage("/ping"), to: "127.0.0.1", port: portB)

        let incoming = await withTaskGroup(of: OSCUDPPeer.IncomingPacket?.self) { group in
            group.addTask { await incomingTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                incomingTask.cancel()
                return nil
            }
            for await r in group {
                if r != nil { group.cancelAll(); return r }
            }
            return nil
        }

        guard let incoming else {
            Issue.record("Peer B did not receive packet from A")
            await peerA.stop()
            await peerB.stop()
            return
        }

        // B replies to A using the sender endpoint
        let reply = try OSCMessage("/pong", arguments: [Int32(42)])
        try await peerB.send(.message(reply), to: incoming.sender)

        await peerA.stop()
        await peerB.stop()
    }

    @Test("Send message convenience method")
    func sendMessageConvenience() async throws {
        let peerA = OSCUDPPeer(port: 0)
        let peerB = OSCUDPPeer(port: 0)
        try await peerA.start()
        try await peerB.start()
        let portB = await peerB.listeningPort!

        let receiveTask = Task { () -> OSCPacket? in
            for await incoming in await peerB.packets {
                return incoming.packet
            }
            return nil
        }

        // Use the OSCMessage convenience overload (not wrapping in .message)
        let msg = try OSCMessage("/convenience", arguments: [Int32(7)])
        try await peerA.send(msg, to: "127.0.0.1", port: portB)

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
            Issue.record("Peer B did not receive message sent via convenience method")
            await peerA.stop()
            await peerB.stop()
            return
        }
        #expect(received == msg)

        await peerA.stop()
        await peerB.stop()
    }

    @Test("Listening port returns valid ephemeral port")
    func listeningPortEphemeral() async throws {
        let peer = OSCUDPPeer(port: 0)

        // Before start, listeningPort should be nil
        let portBeforeStart = await peer.listeningPort
        #expect(portBeforeStart == nil)

        try await peer.start()
        let port = await peer.listeningPort
        #expect(port != nil)
        #expect(port! > 0)

        // Ephemeral ports are typically above 1023
        #expect(port! > 1023)

        await peer.stop()
    }

    @Test("Send to unknown sender throws unknownSender")
    func sendToUnknownSender() async throws {
        let peer = OSCUDPPeer(port: 0)
        try await peer.start()

        let unknownSender = OSCUDPPeer.SenderEndpoint(
            endpoint: NWEndpoint.hostPort(host: .ipv4(.loopback), port: 9999)
        )
        let msg = try OSCMessage("/test")
        do {
            try await peer.send(.message(msg), to: unknownSender)
            Issue.record("Expected unknownSender error")
        } catch let error as OSCUDPError {
            #expect(error == .unknownSender)
        }

        await peer.stop()
    }

    @Test("Peer drops malformed packets and continues")
    func peerDropsMalformedPacket() async throws {
        let peer = OSCUDPPeer(port: 0)
        try await peer.start()
        let port = await peer.listeningPort!

        let receiveTask = Task { () -> OSCPacket? in
            for await incoming in await peer.packets {
                return incoming.packet
            }
            return nil
        }

        // Send malformed data via raw NWConnection
        let rawConn = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .udp
        )

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            nonisolated(unsafe) var resumed = false
            rawConn.stateUpdateHandler = { state in
                guard !resumed else { return }
                if case .ready = state {
                    resumed = true
                    continuation.resume()
                }
            }
            rawConn.start(queue: DispatchQueue(label: "test.raw.udp.peer"))
        }

        // Send garbage bytes (not valid OSC)
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF])
        rawConn.send(content: garbage, completion: .contentProcessed { _ in })

        // Wait for peer to process and drop the malformed packet
        try await Task.sleep(nanoseconds: 100_000_000)

        // Now send a valid message via OSCUDPClient
        let client = OSCUDPClient(host: "127.0.0.1", port: port)
        try await client.send(try OSCMessage("/valid", arguments: [Int32(1)]))

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
            Issue.record("Peer should have received valid message after dropping malformed one")
            rawConn.cancel()
            await client.close()
            await peer.stop()
            return
        }
        #expect(received.addressPattern == "/valid")

        rawConn.cancel()
        await client.close()
        await peer.stop()
    }

    @Test("Outbound connection is reused for same destination")
    func outboundConnectionReuse() async throws {
        let peerA = OSCUDPPeer(port: 0)
        let peerB = OSCUDPPeer(port: 0)
        try await peerA.start()
        try await peerB.start()
        let portB = await peerB.listeningPort!

        let receiveTask = Task { () -> Int in
            var count = 0
            for await _ in await peerB.packets {
                count += 1
                if count >= 2 { break }
            }
            return count
        }

        // Send twice to the same destination -- second send reuses cached connection
        try await peerA.send(try OSCMessage("/first"), to: "127.0.0.1", port: portB)
        try await Task.sleep(nanoseconds: 50_000_000)
        try await peerA.send(try OSCMessage("/second"), to: "127.0.0.1", port: portB)

        let count = await withTaskGroup(of: Int.self) { group in
            group.addTask { await receiveTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                receiveTask.cancel()
                return 0
            }
            for await result in group {
                if result >= 2 { group.cancelAll(); return result }
            }
            return 0
        }

        #expect(count >= 2)

        await peerA.stop()
        await peerB.stop()
    }

    @Test("Start on occupied port throws")
    func startOnOccupiedPort() async throws {
        // OSCUDPServer does NOT set allowLocalEndpointReuse, so it binds
        // the port exclusively. A peer trying to bind the same port should fail.
        let server = OSCUDPServer(port: 0)
        try await server.start()
        let port = await server.listeningPort!

        let peer = OSCUDPPeer(port: port)
        do {
            try await peer.start()
            Issue.record("Expected error starting on occupied port")
            await peer.stop()
        } catch {
            // Expected -- port is already in use
        }

        await server.stop()
    }
}
