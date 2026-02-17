import Testing
@testable import OSCFoundation
import Foundation

@Suite("SLIPFramer")
struct SLIPFramerTests {

    @Test("Frame wraps data with END bytes")
    func frameBasic() {
        let data = Data([0x01, 0x02, 0x03])
        let framed = SLIPFramer.frame(data)

        #expect(framed.first == 0xC0) // leading END
        #expect(framed.last == 0xC0) // trailing END
        #expect(Array(framed) == [0xC0, 0x01, 0x02, 0x03, 0xC0])
    }

    @Test("Frame escapes END byte in data")
    func frameEscapesEND() {
        let data = Data([0xAA, 0xC0, 0xBB]) // contains END byte
        let framed = SLIPFramer.frame(data)

        // 0xC0 in data should become 0xDB 0xDC
        #expect(Array(framed) == [0xC0, 0xAA, 0xDB, 0xDC, 0xBB, 0xC0])
    }

    @Test("Frame escapes ESC byte in data")
    func frameEscapesESC() {
        let data = Data([0xAA, 0xDB, 0xBB]) // contains ESC byte
        let framed = SLIPFramer.frame(data)

        // 0xDB in data should become 0xDB 0xDD
        #expect(Array(framed) == [0xC0, 0xAA, 0xDB, 0xDD, 0xBB, 0xC0])
    }

    @Test("Frame empty data")
    func frameEmpty() {
        let framed = SLIPFramer.frame(Data())
        #expect(Array(framed) == [0xC0, 0xC0])
    }

    @Test("Deframe single complete packet")
    func deframeSinglePacket() {
        var deframer = SLIPFramer.Deframer()
        let framed = SLIPFramer.frame(Data([0x01, 0x02, 0x03]))
        deframer.push(framed)

        let packet = deframer.nextPacket()
        #expect(packet != nil)
        #expect(Array(packet!) == [0x01, 0x02, 0x03])
        #expect(deframer.nextPacket() == nil)
    }

    @Test("Deframe restores escaped bytes")
    func deframeEscapeSequences() {
        var deframer = SLIPFramer.Deframer()
        // Frame data containing both special bytes
        let data = Data([0xC0, 0xDB]) // END and ESC in payload
        let framed = SLIPFramer.frame(data)
        deframer.push(framed)

        let packet = deframer.nextPacket()
        #expect(packet != nil)
        #expect(Array(packet!) == [0xC0, 0xDB])
    }

    @Test("Deframe handles partial delivery")
    func deframePartialDelivery() {
        var deframer = SLIPFramer.Deframer()
        let framed = SLIPFramer.frame(Data([0x01, 0x02, 0x03, 0x04, 0x05]))

        // Split framed data in half
        let mid = framed.count / 2
        deframer.push(Data(framed.prefix(mid)))
        #expect(deframer.nextPacket() == nil) // not complete yet

        deframer.push(Data(framed.dropFirst(mid)))
        let packet = deframer.nextPacket()
        #expect(packet != nil)
        #expect(Array(packet!) == [0x01, 0x02, 0x03, 0x04, 0x05])
    }

    @Test("Deframe handles multiple packets in one chunk")
    func deframeMultiplePackets() {
        var deframer = SLIPFramer.Deframer()
        var combined = Data()
        combined.append(SLIPFramer.frame(Data([0x01])))
        combined.append(SLIPFramer.frame(Data([0x02])))
        combined.append(SLIPFramer.frame(Data([0x03])))

        deframer.push(combined)
        let packets = deframer.drainPackets()
        #expect(packets.count == 3)
        #expect(Array(packets[0]) == [0x01])
        #expect(Array(packets[1]) == [0x02])
        #expect(Array(packets[2]) == [0x03])
    }

    @Test("Empty packets between ENDs are ignored")
    func emptyPacketsBetweenENDs() {
        var deframer = SLIPFramer.Deframer()
        // Multiple ENDs in a row should not produce empty packets
        deframer.push(Data([0xC0, 0xC0, 0xC0, 0x01, 0x02, 0xC0, 0xC0, 0xC0]))
        let packets = deframer.drainPackets()
        #expect(packets.count == 1)
        #expect(Array(packets[0]) == [0x01, 0x02])
    }

    @Test("Round-trip frame/deframe")
    func roundTrip() {
        let original = Data([0x00, 0xC0, 0xDB, 0xFF, 0x42])
        var deframer = SLIPFramer.Deframer()
        deframer.push(SLIPFramer.frame(original))
        let packet = deframer.nextPacket()
        #expect(packet == original)
    }

    @Test("Round-trip with real OSC message")
    func roundTripOSC() throws {
        let msg = try OSCMessage("/test", arguments: [Int32(42), "hello"])
        let encoded = try OSCEncoder.encode(msg)

        var deframer = SLIPFramer.Deframer()
        deframer.push(SLIPFramer.frame(encoded))
        let packet = deframer.nextPacket()
        #expect(packet != nil)

        let decoded = try OSCDecoder.decode(packet!)
        guard case .message(let result) = decoded else {
            Issue.record("Expected message")
            return
        }
        #expect(result == msg)
    }

    @Test("Unknown escape sequence appends raw byte")
    func unknownEscapeSequence() {
        var deframer = SLIPFramer.Deframer()
        // ESC (0xDB) followed by 0x42 (not ESC_END or ESC_ESC) should append raw 0x42
        deframer.push(Data([0xC0, 0xDB, 0x42, 0xC0]))
        let packet = deframer.nextPacket()
        #expect(packet != nil)
        #expect(Array(packet!) == [0x42])
    }

    @Test("Buffered byte count tracks incomplete packet")
    func bufferedByteCount() {
        var deframer = SLIPFramer.Deframer()
        #expect(deframer.bufferedByteCount == 0)

        // Push leading END + some data but no trailing END
        deframer.push(Data([0xC0, 0x01, 0x02, 0x03]))
        #expect(deframer.bufferedByteCount == 3)
        #expect(deframer.nextPacket() == nil)

        // Complete the packet
        deframer.push(Data([0xC0]))
        #expect(deframer.bufferedByteCount == 0)
        #expect(deframer.nextPacket() != nil)
    }
}
