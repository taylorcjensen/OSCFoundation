import Testing
@testable import OSCFoundation
import Foundation

@Suite("PLHFramer")
struct PLHFramerTests {
    @Test("Frame prepends 4-byte big-endian length")
    func frameBasic() {
        let payload = Data([0x01, 0x02, 0x03])
        let framed = PLHFramer.frame(payload)

        #expect(framed.count == 7) // 4 header + 3 payload

        // Length = 3 in big-endian
        #expect(Array(framed[0 ..< 4]) == [0x00, 0x00, 0x00, 0x03])
        #expect(Array(framed[4 ..< 7]) == [0x01, 0x02, 0x03])
    }

    @Test("Frame empty data")
    func frameEmpty() {
        let framed = PLHFramer.frame(Data())
        #expect(framed.count == 4)
        #expect(Array(framed) == [0x00, 0x00, 0x00, 0x00])
    }

    @Test("Deframer extracts single complete packet")
    func deframeSingle() {
        var deframer = PLHFramer.Deframer()

        // Frame a 3-byte payload
        let framed = PLHFramer.frame(Data([0xAA, 0xBB, 0xCC]))
        deframer.push(framed)

        let packet = deframer.nextPacket()
        #expect(packet == Data([0xAA, 0xBB, 0xCC]))
        #expect(deframer.nextPacket() == nil) // no more
    }

    @Test("Deframer handles partial delivery")
    func deframePartial() {
        var deframer = PLHFramer.Deframer()

        let framed = PLHFramer.frame(Data([0x01, 0x02, 0x03, 0x04]))
        // 8 bytes total: [0x00, 0x00, 0x00, 0x04, 0x01, 0x02, 0x03, 0x04]

        // Feed first 3 bytes (partial header)
        deframer.push(Data(framed[0 ..< 3]))
        #expect(deframer.nextPacket() == nil)

        // Feed next 3 bytes (rest of header + partial payload)
        deframer.push(Data(framed[3 ..< 6]))
        #expect(deframer.nextPacket() == nil)

        // Feed remaining 2 bytes
        deframer.push(Data(framed[6 ..< 8]))
        let packet = deframer.nextPacket()
        #expect(packet == Data([0x01, 0x02, 0x03, 0x04]))
    }

    @Test("Deframer handles multiple packets in one chunk")
    func deframeMultiPacket() {
        var deframer = PLHFramer.Deframer()

        let frame1 = PLHFramer.frame(Data([0xAA]))
        let frame2 = PLHFramer.frame(Data([0xBB, 0xCC]))

        // Push both frames at once
        var combined = frame1
        combined.append(frame2)
        deframer.push(combined)

        let packets = deframer.drainPackets()
        #expect(packets.count == 2)
        #expect(packets[0] == Data([0xAA]))
        #expect(packets[1] == Data([0xBB, 0xCC]))
    }

    @Test("Deframer leaves trailing partial data intact")
    func deframeTrailingPartial() {
        var deframer = PLHFramer.Deframer()

        let frame1 = PLHFramer.frame(Data([0x11]))
        let frame2Partial = Data([0x00, 0x00, 0x00, 0x03, 0x22]) // header says 3 bytes, only 1 delivered

        var combined = frame1
        combined.append(frame2Partial)
        deframer.push(combined)

        // First packet should be extractable
        #expect(deframer.nextPacket() == Data([0x11]))
        // Second packet is incomplete
        #expect(deframer.nextPacket() == nil)
        // Buffer still holds the partial frame
        #expect(deframer.bufferedByteCount == 5)

        // Complete the second frame
        deframer.push(Data([0x33, 0x44]))
        #expect(deframer.nextPacket() == Data([0x22, 0x33, 0x44]))
    }

    @Test("Buffered byte count tracks correctly")
    func bufferedByteCount() {
        var deframer = PLHFramer.Deframer()
        #expect(deframer.bufferedByteCount == 0)

        deframer.push(Data([0x00, 0x00]))
        #expect(deframer.bufferedByteCount == 2)

        deframer.push(Data([0x00, 0x01, 0xFF]))
        // Now has header [0,0,0,1] + payload [0xFF] = 5 bytes, one complete packet
        let packet = deframer.nextPacket()
        #expect(packet == Data([0xFF]))
        #expect(deframer.bufferedByteCount == 0)
    }

    @Test("Deframer with real OSC message through full pipeline")
    func deframeRealOSC() throws {
        var deframer = PLHFramer.Deframer()

        let message = try OSCMessage("/eos/out/active/chan", arguments: [Int32(1)])
        let encoded = try OSCEncoder.encode(message)
        let framed = PLHFramer.frame(encoded)

        deframer.push(framed)
        guard let packetData = deframer.nextPacket() else {
            Issue.record("Expected packet data")
            return
        }

        let decoded = try OSCDecoder.decode(packetData)
        guard case .message(let msg) = decoded else {
            Issue.record("Expected message")
            return
        }

        #expect(msg == message)
    }
}
