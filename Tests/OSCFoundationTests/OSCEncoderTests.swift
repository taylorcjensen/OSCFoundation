import Testing
@testable import OSCFoundation
import Foundation

@Suite("OSCEncoder")
struct OSCEncoderTests {
    @Test("Encode simple message with no arguments")
    func encodeNoArgs() throws {
        let msg = try OSCMessage("/test")
        let data = try OSCEncoder.encode(msg)

        // "/test" = 5 bytes + 3 padding = 8
        // "," = 1 byte + 3 padding = 4
        // Total: 12
        #expect(data.count == 12)

        // Address: "/test\0" padded to 8 bytes
        let expected: [UInt8] = [
            0x2F, 0x74, 0x65, 0x73, 0x74, 0x00, 0x00, 0x00, // /test\0\0\0
            0x2C, 0x00, 0x00, 0x00,                           // ,\0\0\0
        ]
        #expect(Array(data) == expected)
    }

    @Test("Encode message with int32 argument")
    func encodeInt32() throws {
        let msg = try OSCMessage("/val", arguments: [Int32(256)])
        let data = try OSCEncoder.encode(msg)

        // "/val" = 4 + 1 null = 5, padded to 8
        // ",i" = 2 + 1 null = 3, padded to 4
        // int32 = 4
        // Total: 16
        #expect(data.count == 16)

        // Check the int32 value (big-endian 256 = 0x00000100)
        let intBytes = Array(data[12 ..< 16])
        #expect(intBytes == [0x00, 0x00, 0x01, 0x00])
    }

    @Test("Encode message with float32 argument")
    func encodeFloat32() throws {
        let msg = try OSCMessage("/f", arguments: [Float(1.0)])
        let data = try OSCEncoder.encode(msg)

        // "/f" = 2 + 1 null = 3, padded to 4
        // ",f" = 2 + 1 null = 3, padded to 4
        // float32 = 4
        // Total: 12
        #expect(data.count == 12)

        // IEEE 754 1.0 = 0x3F800000
        let floatBytes = Array(data[8 ..< 12])
        #expect(floatBytes == [0x3F, 0x80, 0x00, 0x00])
    }

    @Test("Encode message with string argument")
    func encodeString() throws {
        let msg = try OSCMessage("/s", arguments: ["hi"])
        let data = try OSCEncoder.encode(msg)

        // "/s" = 4 bytes (padded)
        // ",s" = 4 bytes (padded)
        // "hi" = 2 + 1 null = 3, padded to 4
        // Total: 12
        #expect(data.count == 12)

        let strBytes = Array(data[8 ..< 12])
        #expect(strBytes == [0x68, 0x69, 0x00, 0x00]) // hi\0\0
    }

    @Test("Encode message with blob argument")
    func encodeBlob() throws {
        let blob = Data([0xDE, 0xAD])
        let msg = try OSCMessage("/b", arguments: [blob])
        let data = try OSCEncoder.encode(msg)

        // "/b" = 4 bytes (padded)
        // ",b" = 4 bytes (padded)
        // blob size (4) + blob data (2) + padding (2) = 8
        // Total: 16
        #expect(data.count == 16)

        // Blob size = 2 (big-endian)
        #expect(Array(data[8 ..< 12]) == [0x00, 0x00, 0x00, 0x02])
        // Blob content + padding
        #expect(Array(data[12 ..< 16]) == [0xDE, 0xAD, 0x00, 0x00])
    }

    @Test("Encode message with boolean and nil arguments (no payload)")
    func encodeNoPayloadTypes() throws {
        let msg = try OSCMessage("/flags", arguments: [
            OSCArgument.true,
            OSCArgument.false,
            OSCArgument.nil,
            OSCArgument.impulse,
        ])
        let data = try OSCEncoder.encode(msg)

        // "/flags" = 6 + 1 null = 7, padded to 8
        // ",TFNI" = 5 + 1 null = 6, padded to 8
        // No argument payload
        // Total: 16
        #expect(data.count == 16)
    }

    @Test("Encode bundle")
    func encodeBundle() throws {
        let bundle = OSCBundle(timeTag: .immediately, elements: [
            .message(try OSCMessage("/a")),
        ])
        let data = try OSCEncoder.encode(bundle)

        // #bundle\0 = 8
        // time tag = 8
        // element size prefix = 4
        // element data: "/a" padded(4) + "," padded(4) = 8
        // Total: 28
        #expect(data.count == 28)

        // Verify #bundle header
        #expect(Array(data[0 ..< 8]) == [0x23, 0x62, 0x75, 0x6E, 0x64, 0x6C, 0x65, 0x00])

        // Verify time tag (immediately = 1, big-endian)
        #expect(Array(data[8 ..< 16]) == [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01])
    }

    @Test("String padding aligns to 4 bytes")
    func stringPaddingAlignment() {
        // 3-char string "abc" + null = 4 bytes (exactly aligned, no extra padding)
        let padded = OSCEncoder.encodePaddedString("abc")
        #expect(padded.count == 4)

        // 4-char string "abcd" + null = 5 bytes, padded to 8
        let padded2 = OSCEncoder.encodePaddedString("abcd")
        #expect(padded2.count == 8)

        // 1-char string "a" + null = 2 bytes, padded to 4
        let padded3 = OSCEncoder.encodePaddedString("a")
        #expect(padded3.count == 4)

        // Empty string "" + null = 1 byte, padded to 4
        let padded4 = OSCEncoder.encodePaddedString("")
        #expect(padded4.count == 4)
    }

    @Test("Encode non-ASCII char throws invalidCharacter")
    func encodeNonASCIIChar() {
        #expect(throws: OSCEncodeError.invalidCharacter("\u{FF}")) {
            try OSCEncoder.encodeChar("\u{FF}")
        }
    }
}
