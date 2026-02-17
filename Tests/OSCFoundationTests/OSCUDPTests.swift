import Testing
@testable import OSCFoundation
import Foundation
import Network

@Suite("OSC UDP")
struct OSCUDPTests {

    @Test("UDP client send without error")
    func clientSend() async throws {
        // Start a real server so we have a port to send to
        let server = OSCUDPServer(port: 0)
        try await server.start()
        let port = await server.listeningPort!

        let client = OSCUDPClient(host: "127.0.0.1", port: port)
        try await client.send(try OSCMessage("/test", arguments: [Int32(1)]))
        await client.close()
        await server.stop()
    }

    @Test("UDP client close is idempotent")
    func clientCloseIdempotent() async {
        let client = OSCUDPClient(host: "127.0.0.1", port: 9999)
        await client.close()
        await client.close()
    }

    @Test("UDP server start and stop")
    func serverStartStop() async throws {
        let server = OSCUDPServer(port: 0)
        try await server.start()
        let port = await server.listeningPort
        #expect(port != nil)
        #expect(port! > 0)
        await server.stop()
        await server.stop() // idempotent
    }

    @Test("UDP server receives multiple packets from same sender")
    func multiplePacketsFromSameSender() async throws {
        let server = OSCUDPServer(port: 0)
        try await server.start()
        let port = await server.listeningPort!

        let messageCount = 3
        let receiveTask = Task { () -> [OSCPacket] in
            var received: [OSCPacket] = []
            for await incoming in await server.packets {
                received.append(incoming.packet)
                if received.count >= messageCount { break }
            }
            return received
        }

        let client = OSCUDPClient(host: "127.0.0.1", port: port)
        for i in 0..<messageCount {
            try await client.send(try OSCMessage("/multi/\(i)", arguments: [Int32(i)]))
            // Small delay so datagrams arrive in order
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let result = await withTaskGroup(of: [OSCPacket].self) { group in
            group.addTask { await receiveTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                receiveTask.cancel()
                return []
            }
            for await result in group {
                if result.count == messageCount {
                    group.cancelAll()
                    return result
                }
            }
            return []
        }

        #expect(result.count == messageCount, "Expected \(messageCount) packets, got \(result.count)")
        // UDP does not guarantee ordering -- verify set membership instead
        let addresses = result.compactMap { packet -> String? in
            if case .message(let msg) = packet { return msg.addressPattern }
            return nil
        }
        #expect(Set(addresses) == Set((0..<messageCount).map { "/multi/\($0)" }))

        await client.close()
        await server.stop()
    }

    @Test("UDP client-server round-trip")
    func clientServerRoundTrip() async throws {
        let server = OSCUDPServer(port: 0)
        try await server.start()
        let port = await server.listeningPort!

        let receiveTask = Task { () -> OSCPacket? in
            for await incoming in await server.packets {
                return incoming.packet
            }
            return nil
        }

        let client = OSCUDPClient(host: "127.0.0.1", port: port)
        let msg = try OSCMessage("/udp/test", arguments: [Int32(42)])
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
            Issue.record("Expected message packet, got \(String(describing: result))")
            await client.close()
            await server.stop()
            return
        }
        #expect(received == msg)

        await client.close()
        await server.stop()
    }

    @Test("UDP server reply to sender")
    func serverReply() async throws {
        let server = OSCUDPServer(port: 0)
        try await server.start()
        let port = await server.listeningPort!

        // Capture the sender endpoint from the first received packet
        let receiveTask = Task { () -> OSCUDPServer.IncomingPacket? in
            for await incoming in await server.packets {
                return incoming
            }
            return nil
        }

        // Send from the client to the server
        let client = OSCUDPClient(host: "127.0.0.1", port: port)
        try await client.send(try OSCMessage("/hello"))

        // Wait for server to receive the packet
        let incoming = await withTaskGroup(of: OSCUDPServer.IncomingPacket?.self) { group in
            group.addTask { await receiveTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                receiveTask.cancel()
                return nil
            }
            for await r in group { if r != nil { group.cancelAll(); return r } }
            return nil
        }

        guard let incoming else {
            Issue.record("Server did not receive packet")
            await client.close()
            await server.stop()
            return
        }

        // Reply to the sender -- exercises the send(_:to:) path
        let reply = try OSCMessage("/reply", arguments: [Int32(99)])
        try await server.send(.message(reply), to: incoming.sender)

        await client.close()
        await server.stop()
    }

    @Test("SenderEndpoint hash and equality")
    func senderEndpointHashEquality() async throws {
        let server = OSCUDPServer(port: 0)
        try await server.start()
        let port = await server.listeningPort!

        // Collect sender endpoints from multiple messages
        let endpointTask = Task { () -> [OSCUDPServer.SenderEndpoint] in
            var endpoints: [OSCUDPServer.SenderEndpoint] = []
            for await incoming in await server.packets {
                endpoints.append(incoming.sender)
                if endpoints.count >= 2 { break }
            }
            return endpoints
        }

        let client = OSCUDPClient(host: "127.0.0.1", port: port)
        try await client.send(try OSCMessage("/a"))
        try await Task.sleep(nanoseconds: 50_000_000)
        try await client.send(try OSCMessage("/b"))

        let endpoints = await withTaskGroup(of: [OSCUDPServer.SenderEndpoint].self) { group in
            group.addTask { await endpointTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                endpointTask.cancel()
                return []
            }
            for await r in group {
                if r.count >= 2 { group.cancelAll(); return r }
            }
            return []
        }

        if endpoints.count >= 2 {
            // Same client should produce equal sender endpoints
            #expect(endpoints[0] == endpoints[1])
            #expect(endpoints[0].hashValue == endpoints[1].hashValue)
        }

        await client.close()
        await server.stop()
    }

    @Test("Send to unknown sender throws unknownSender")
    func sendToUnknownSender() async throws {
        let server = OSCUDPServer(port: 0)
        try await server.start()

        let unknownSender = OSCUDPServer.SenderEndpoint(
            endpoint: NWEndpoint.hostPort(host: .ipv4(.loopback), port: 9999)
        )
        let msg = try OSCMessage("/test")
        do {
            try await server.send(.message(msg), to: unknownSender)
            Issue.record("Expected unknownSender error")
        } catch let error as OSCUDPError {
            #expect(error == .unknownSender)
        }

        await server.stop()
    }
}
