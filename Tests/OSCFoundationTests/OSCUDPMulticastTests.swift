import Testing
@testable import OSCFoundation
import Foundation
import Network

@Suite("OSC UDP Multicast", .serialized)
struct OSCUDPMulticastTests {

    private let multicastGroup = "239.255.255.250"

    @Test("Start and stop")
    func startAndStop() async throws {
        let multicast = OSCUDPMulticast(group: multicastGroup, port: 19871)
        try await multicast.start()
        await multicast.stop()
        // Idempotent stop should not throw or crash
        await multicast.stop()
    }

    @Test("Send and receive within group")
    func sendAndReceive() async throws {
        // A single multicast group member can receive its own messages
        // via IP_MULTICAST_LOOP (enabled by default on macOS).
        let multicast = OSCUDPMulticast(group: multicastGroup, port: 19872)
        try await multicast.start()

        // Allow time for multicast group join to propagate
        try await Task.sleep(nanoseconds: 200_000_000)

        let receiveTask = Task { () -> OSCPacket? in
            for await incoming in await multicast.packets {
                return incoming.packet
            }
            return nil
        }

        let msg = try OSCMessage("/multicast/test")
        try await multicast.send(msg)

        let result = await withTaskGroup(of: OSCPacket?.self) { group in
            group.addTask { await receiveTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
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

        guard let result else {
            Issue.record("Did not receive a packet within the timeout")
            await multicast.stop()
            return
        }

        guard case .message(let received) = result else {
            Issue.record("Expected a message packet, got \(result)")
            await multicast.stop()
            return
        }

        #expect(received.addressPattern == "/multicast/test")

        await multicast.stop()
    }

    @Test("Round-trip content")
    func roundTripContent() async throws {
        // Uses multicast loopback to verify argument encoding/decoding round-trip.
        let multicast = OSCUDPMulticast(group: multicastGroup, port: 19873)
        try await multicast.start()

        // Allow time for multicast group join to propagate
        try await Task.sleep(nanoseconds: 200_000_000)

        let receiveTask = Task { () -> OSCPacket? in
            for await incoming in await multicast.packets {
                return incoming.packet
            }
            return nil
        }

        let msg = try OSCMessage("/osc/args", arguments: [
            Int32(42),
            Float(3.14),
            "hello multicast",
        ])
        try await multicast.send(msg)

        let result = await withTaskGroup(of: OSCPacket?.self) { group in
            group.addTask { await receiveTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
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
            Issue.record("Expected a message packet, got \(String(describing: result))")
            await multicast.stop()
            return
        }

        #expect(received.addressPattern == "/osc/args")
        #expect(received.arguments.count == 3)
        #expect(received.arguments[0] == .int32(42))
        #expect(received.arguments[1] == .float32(3.14))
        #expect(received.arguments[2] == .string("hello multicast"))

        await multicast.stop()
    }

    @Test("Send after stop returns silently")
    func sendAfterStop() async throws {
        let multicast = OSCUDPMulticast(group: multicastGroup, port: 19876)
        try await multicast.start()
        await multicast.stop()

        // Should not throw -- connectionGroup is nil, guard returns early
        try await multicast.send(try OSCMessage("/after/stop"))
    }

    @Test("Drops malformed packet and continues")
    func dropsMalformedPacket() async throws {
        let port: UInt16 = 19881
        let multicast = OSCUDPMulticast(group: multicastGroup, port: port)
        try await multicast.start()

        // Allow time for multicast group join to propagate
        try await Task.sleep(nanoseconds: 200_000_000)

        let receiveTask = Task { () -> OSCPacket? in
            for await incoming in await multicast.packets {
                return incoming.packet
            }
            return nil
        }

        // Send garbage bytes via a raw NWConnection targeting the multicast address
        let rawConn = NWConnection(
            host: NWEndpoint.Host(multicastGroup),
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
            rawConn.start(queue: DispatchQueue(label: "test.raw.multicast"))
        }

        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF])
        rawConn.send(content: garbage, completion: .contentProcessed { _ in })

        // Wait for the malformed packet to be processed and dropped
        try await Task.sleep(nanoseconds: 200_000_000)

        // Now send a valid message via the multicast actor
        let msg = try OSCMessage("/valid/after/garbage")
        try await multicast.send(msg)

        let result = await withTaskGroup(of: OSCPacket?.self) { group in
            group.addTask { await receiveTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
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
            Issue.record("Should have received valid message after dropping malformed one")
            rawConn.cancel()
            await multicast.stop()
            return
        }
        #expect(received.addressPattern == "/valid/after/garbage")

        rawConn.cancel()
        await multicast.stop()
    }

    @Test("Multiple packets round-trip")
    func multiplePacketsRoundTrip() async throws {
        let multicast = OSCUDPMulticast(group: multicastGroup, port: 19878)
        try await multicast.start()

        // Allow time for multicast group join to propagate
        try await Task.sleep(nanoseconds: 200_000_000)

        let messageCount = 3
        let receiveTask = Task { () -> [OSCPacket] in
            var received: [OSCPacket] = []
            for await incoming in await multicast.packets {
                received.append(incoming.packet)
                if received.count >= messageCount { break }
            }
            return received
        }

        for i in 0..<messageCount {
            try await multicast.send(try OSCMessage("/multi/\(i)", arguments: [Int32(i)]))
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
        let addresses = result.compactMap { packet -> String? in
            if case .message(let msg) = packet { return msg.addressPattern }
            return nil
        }
        #expect(Set(addresses) == Set((0..<messageCount).map { "/multi/\($0)" }))

        await multicast.stop()
    }

    @Test("Sender endpoint is populated on received packet")
    func senderEndpointPopulated() async throws {
        let multicast = OSCUDPMulticast(group: multicastGroup, port: 19879)
        try await multicast.start()

        // Allow time for multicast group join to propagate
        try await Task.sleep(nanoseconds: 200_000_000)

        let receiveTask = Task { () -> OSCUDPMulticast.IncomingPacket? in
            for await incoming in await multicast.packets {
                return incoming
            }
            return nil
        }

        try await multicast.send(try OSCMessage("/sender/check"))

        let incoming = await withTaskGroup(of: OSCUDPMulticast.IncomingPacket?.self) { group in
            group.addTask { await receiveTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
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

        guard let incoming else {
            Issue.record("Did not receive a packet within the timeout")
            await multicast.stop()
            return
        }

        // The sender should be a real endpoint, not the .ipv4(.any) fallback
        let senderDescription = String(describing: incoming.sender)
        #expect(!senderDescription.contains("0.0.0.0"), "Sender should not be the .ipv4(.any) fallback")

        await multicast.stop()
    }

    @Test("Send to specific member does not throw")
    func sendToSpecificMember() async throws {
        let port: UInt16 = 19874
        let multicast = OSCUDPMulticast(group: multicastGroup, port: port)
        try await multicast.start()

        // Allow time for multicast group join to propagate
        try await Task.sleep(nanoseconds: 200_000_000)

        let targetEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let msg = try OSCMessage("/targeted/send")
        // Verify that sending to a specific endpoint does not throw
        try await multicast.send(.message(msg), to: targetEndpoint)

        await multicast.stop()
    }
}
