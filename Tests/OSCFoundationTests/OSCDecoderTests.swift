import Testing
@testable import OSCFoundation
import Foundation

@Suite("OSCDecoder")
struct OSCDecoderTests {
    @Test("Decode simple message with no arguments")
    func decodeNoArgs() throws {
        let data = Data([
            0x2F, 0x74, 0x65, 0x73, 0x74, 0x00, 0x00, 0x00, // /test\0\0\0
            0x2C, 0x00, 0x00, 0x00,                           // ,\0\0\0
        ])
        let packet = try OSCDecoder.decode(data)
        guard case .message(let msg) = packet else {
            Issue.record("Expected message, got bundle")
            return
        }
        #expect(msg.addressPattern == "/test")
        #expect(msg.arguments.isEmpty)
    }

    @Test("Decode message with int32")
    func decodeInt32() throws {
        let data = Data([
            0x2F, 0x76, 0x00, 0x00,             // /v\0\0
            0x2C, 0x69, 0x00, 0x00,             // ,i\0\0
            0x00, 0x00, 0x01, 0x00,             // 256 big-endian
        ])
        let msg = try OSCDecoder.decodeMessage(data)
        #expect(msg.arguments == [.int32(256)])
    }

    @Test("Decode message with float32")
    func decodeFloat32() throws {
        let data = Data([
            0x2F, 0x66, 0x00, 0x00,             // /f\0\0
            0x2C, 0x66, 0x00, 0x00,             // ,f\0\0
            0x3F, 0x80, 0x00, 0x00,             // 1.0 IEEE 754
        ])
        let msg = try OSCDecoder.decodeMessage(data)
        #expect(msg.arguments == [.float32(1.0)])
    }

    @Test("Decode message with string")
    func decodeString() throws {
        let data = Data([
            0x2F, 0x73, 0x00, 0x00,             // /s\0\0
            0x2C, 0x73, 0x00, 0x00,             // ,s\0\0
            0x68, 0x69, 0x00, 0x00,             // hi\0\0
        ])
        let msg = try OSCDecoder.decodeMessage(data)
        #expect(msg.arguments == [.string("hi")])
    }

    @Test("Decode message with blob")
    func decodeBlob() throws {
        let data = Data([
            0x2F, 0x62, 0x00, 0x00,             // /b\0\0
            0x2C, 0x62, 0x00, 0x00,             // ,b\0\0
            0x00, 0x00, 0x00, 0x02,             // blob size = 2
            0xDE, 0xAD, 0x00, 0x00,             // blob data + padding
        ])
        let msg = try OSCDecoder.decodeMessage(data)
        #expect(msg.arguments == [.blob(Data([0xDE, 0xAD]))])
    }

    @Test("Decode message with boolean/nil/impulse types")
    func decodeNoPayloadTypes() throws {
        let data = Data([
            0x2F, 0x78, 0x00, 0x00,                         // /x\0\0
            0x2C, 0x54, 0x46, 0x4E, 0x49, 0x00, 0x00, 0x00, // ,TFNI\0\0\0
        ])
        let msg = try OSCDecoder.decodeMessage(data)
        #expect(msg.arguments == [.true, .false, .nil, .impulse])
    }

    @Test("Decode message with time tag argument")
    func decodeTimeTag() throws {
        let data = Data([
            0x2F, 0x74, 0x00, 0x00,             // /t\0\0
            0x2C, 0x74, 0x00, 0x00,             // ,t\0\0
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x01,             // immediately = 1
        ])
        let msg = try OSCDecoder.decodeMessage(data)
        #expect(msg.arguments == [.timeTag(.immediately)])
    }

    @Test("Decode bundle")
    func decodeBundle() throws {
        // Encode a bundle, then decode it
        let original = OSCBundle(timeTag: .immediately, elements: [
            .message(try OSCMessage("/a", arguments: [Int32(42)])),
        ])
        let encoded = try OSCEncoder.encode(original)
        let packet = try OSCDecoder.decode(encoded)

        guard case .bundle(let bundle) = packet else {
            Issue.record("Expected bundle")
            return
        }
        #expect(bundle.timeTag == .immediately)
        #expect(bundle.elements.count == 1)

        guard case .message(let msg) = bundle.elements[0] else {
            Issue.record("Expected message element")
            return
        }
        #expect(msg.addressPattern == "/a")
        #expect(msg.arguments == [.int32(42)])
    }

    @Test("Empty data throws truncatedData")
    func emptyData() {
        #expect(throws: OSCDecodeError.truncatedData) {
            try OSCDecoder.decode(Data())
        }
    }

    @Test("Invalid packet start byte throws")
    func invalidStart() {
        #expect(throws: OSCDecodeError.invalidPacket) {
            try OSCDecoder.decode(Data([0x41, 0x42, 0x43, 0x44]))
        }
    }

    @Test("Unknown type tag throws")
    func unknownTypeTag() {
        let data = Data([
            0x2F, 0x78, 0x00, 0x00,             // /x\0\0
            0x2C, 0x5A, 0x00, 0x00,             // ,Z\0\0 (Z is not a valid type tag)
        ])
        #expect(throws: OSCDecodeError.unknownTypeTag("Z")) {
            try OSCDecoder.decodeMessage(data)
        }
    }

    @Test("Round-trip: encode then decode preserves message")
    func roundTripMessage() throws {
        let original = try OSCMessage("/eos/newcmd", arguments: [
            "Chan 1 Full Enter",
            Int32(42),
            Float(0.75),
            true,
            false,
            Data([0x01, 0x02, 0x03]),
        ])

        let encoded = try OSCEncoder.encode(original)
        let decoded = try OSCDecoder.decode(encoded)

        guard case .message(let msg) = decoded else {
            Issue.record("Expected message")
            return
        }
        #expect(msg == original)
    }

    @Test("Round-trip: bundle with multiple messages")
    func roundTripBundle() throws {
        let original = OSCBundle(
            timeTag: OSCTimeTag(seconds: 1000, fraction: 0),
            elements: [
                .message(try OSCMessage("/a", arguments: [Int32(1)])),
                .message(try OSCMessage("/b", arguments: ["hello"])),
                .message(try OSCMessage("/c")),
            ]
        )

        let encoded = try OSCEncoder.encode(original)
        let decoded = try OSCDecoder.decode(encoded)

        guard case .bundle(let bundle) = decoded else {
            Issue.record("Expected bundle")
            return
        }
        #expect(bundle == original)
    }

    @Test("Round-trip: nested bundles")
    func roundTripNestedBundle() throws {
        let inner = OSCBundle(timeTag: .immediately, elements: [
            .message(try OSCMessage("/inner")),
        ])
        let outer = OSCBundle(
            timeTag: OSCTimeTag(seconds: 500, fraction: 100),
            elements: [
                .bundle(inner),
                .message(try OSCMessage("/outer")),
            ]
        )

        let encoded = try OSCEncoder.encode(outer)
        let decoded = try OSCDecoder.decode(encoded)

        guard case .bundle(let result) = decoded else {
            Issue.record("Expected bundle")
            return
        }
        #expect(result == outer)
    }

    // MARK: - Truncated Argument Payloads

    @Test("Truncated int32 payload throws truncatedData")
    func truncatedInt32Payload() {
        // Type tag says `i` but only 2 bytes of payload follow
        let data = Data([
            0x2F, 0x78, 0x00, 0x00,             // /x\0\0
            0x2C, 0x69, 0x00, 0x00,             // ,i\0\0
            0x00, 0x01,                           // only 2 bytes, need 4
        ])
        #expect(throws: OSCDecodeError.truncatedData) {
            try OSCDecoder.decodeMessage(data)
        }
    }

    @Test("Truncated int64 payload throws truncatedData")
    func truncatedInt64Payload() {
        // Type tag says `h` but only 4 bytes of payload follow
        let data = Data([
            0x2F, 0x78, 0x00, 0x00,             // /x\0\0
            0x2C, 0x68, 0x00, 0x00,             // ,h\0\0
            0x00, 0x00, 0x00, 0x01,             // only 4 bytes, need 8
        ])
        #expect(throws: OSCDecodeError.truncatedData) {
            try OSCDecoder.decodeMessage(data)
        }
    }

    @Test("Truncated blob payload throws truncatedData")
    func truncatedBlobPayload() {
        // Blob declares size 10 but only 2 bytes of blob data follow
        let data = Data([
            0x2F, 0x78, 0x00, 0x00,             // /x\0\0
            0x2C, 0x62, 0x00, 0x00,             // ,b\0\0
            0x00, 0x00, 0x00, 0x0A,             // blob size = 10
            0xDE, 0xAD,                           // only 2 bytes of data
        ])
        #expect(throws: OSCDecodeError.truncatedData) {
            try OSCDecoder.decodeMessage(data)
        }
    }

    @Test("Negative blob size throws truncatedData")
    func negativeBlobSize() {
        // Blob declares size -1 (0xFFFFFFFF as int32)
        let data = Data([
            0x2F, 0x78, 0x00, 0x00,             // /x\0\0
            0x2C, 0x62, 0x00, 0x00,             // ,b\0\0
            0xFF, 0xFF, 0xFF, 0xFF,             // blob size = -1
        ])
        #expect(throws: OSCDecodeError.truncatedData) {
            try OSCDecoder.decodeMessage(data)
        }
    }

    // MARK: - String Errors

    @Test("Unterminated address string throws unterminatedString")
    func unterminatedAddress() {
        // Address with no null terminator
        let data = Data([0x2F, 0x78, 0x79, 0x7A]) // /xyz with no null
        #expect(throws: OSCDecodeError.unterminatedString) {
            try OSCDecoder.decodeMessage(data)
        }
    }

    @Test("Unterminated string argument throws unterminatedString")
    func unterminatedStringArgument() {
        // Valid address + type tag, but string argument has no null
        let data = Data([
            0x2F, 0x78, 0x00, 0x00,             // /x\0\0
            0x2C, 0x73, 0x00, 0x00,             // ,s\0\0
            0x41, 0x42, 0x43, 0x44,             // "ABCD" with no null
        ])
        #expect(throws: OSCDecodeError.unterminatedString) {
            try OSCDecoder.decodeMessage(data)
        }
    }

    @Test("Type tag string without comma prefix throws missingTypeTag")
    func missingCommaPrefix() {
        // Address is valid, but type tag string doesn't start with ','
        let data = Data([
            0x2F, 0x78, 0x00, 0x00,             // /x\0\0
            0x69, 0x00, 0x00, 0x00,             // "i\0\0\0" -- missing comma
        ])
        #expect(throws: OSCDecodeError.missingTypeTag) {
            try OSCDecoder.decodeMessage(data)
        }
    }

    // MARK: - Array Errors

    @Test("Unmatched array open bracket throws unmatchedArrayClose")
    func unmatchedArrayOpen() {
        // Type tag string ,[i -- open bracket, int32, but no closing ]
        let data = Data([
            0x2F, 0x78, 0x00, 0x00,             // /x\0\0
            0x2C, 0x5B, 0x69, 0x00,             // ,[i\0
            0x00, 0x00, 0x00, 0x01,             // int32 = 1
        ])
        #expect(throws: OSCDecodeError.unmatchedArrayClose) {
            try OSCDecoder.decodeMessage(data)
        }
    }

    // MARK: - Bundle Errors

    @Test("Truncated bundle header throws truncatedData")
    func truncatedBundle() {
        // Starts with # but less than 16 bytes total
        let data = Data([0x23, 0x62, 0x75, 0x6E, 0x64, 0x6C, 0x65, 0x00])
        #expect(throws: OSCDecodeError.truncatedData) {
            try OSCDecoder.decodeBundle(data)
        }
    }

    @Test("Bundle element size exceeding data throws invalidBundleElement")
    func bundleElementSizeTooLarge() {
        var data = Data()
        // #bundle\0 header
        data.append(contentsOf: [0x23, 0x62, 0x75, 0x6E, 0x64, 0x6C, 0x65, 0x00])
        // Time tag (8 bytes of zeros)
        data.append(contentsOf: [UInt8](repeating: 0, count: 8))
        // Element size = 9999 (way too large)
        data.append(contentsOf: [0x00, 0x00, 0x27, 0x0F])

        #expect(throws: OSCDecodeError.invalidBundleElement) {
            try OSCDecoder.decodeBundle(data)
        }
    }

    @Test("Bundle with zero-size element throws invalidBundleElement")
    func bundleZeroSizeElement() {
        var data = Data()
        // #bundle\0 header
        data.append(contentsOf: [0x23, 0x62, 0x75, 0x6E, 0x64, 0x6C, 0x65, 0x00])
        // Time tag (8 bytes of zeros)
        data.append(contentsOf: [UInt8](repeating: 0, count: 8))
        // Element size = 0
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        #expect(throws: OSCDecodeError.invalidBundleElement) {
            try OSCDecoder.decodeBundle(data)
        }
    }

    @Test("Bundle with truncated element size prefix throws truncatedData")
    func bundleTruncatedElementSize() {
        var data = Data()
        // #bundle\0 header
        data.append(contentsOf: [0x23, 0x62, 0x75, 0x6E, 0x64, 0x6C, 0x65, 0x00])
        // Time tag (8 bytes of zeros)
        data.append(contentsOf: [UInt8](repeating: 0, count: 8))
        // Only 2 bytes where 4-byte size prefix is expected
        data.append(contentsOf: [0x00, 0x01])

        #expect(throws: OSCDecodeError.truncatedData) {
            try OSCDecoder.decodeBundle(data)
        }
    }

    // MARK: - Round-Trip Tests

    @Test("Round-trip: message with all argument types")
    func roundTripAllTypes() throws {
        let original = try OSCMessage("/all", arguments: [
            Int32(-1),
            Float(3.14),
            "test string",
            Data([0xCA, 0xFE]),
            OSCArgument.true,
            OSCArgument.false,
            OSCArgument.nil,
            OSCArgument.impulse,
            OSCTimeTag(seconds: 99, fraction: 88),
        ])

        let encoded = try OSCEncoder.encode(original)
        let decoded = try OSCDecoder.decode(encoded)

        guard case .message(let msg) = decoded else {
            Issue.record("Expected message")
            return
        }
        #expect(msg == original)
    }

    // MARK: - Coverage Gap Tests

    @Test("Address not starting with / throws invalidPacket")
    func addressWithoutSlash() {
        // Craft data where the string parses but doesn't start with /
        let data = Data([
            0x66, 0x6F, 0x6F, 0x00,             // "foo\0" (not starting with /)
        ])
        #expect(throws: OSCDecodeError.invalidPacket) {
            try OSCDecoder.decodeMessage(data)
        }
    }

    @Test("Message with address only and no type tag data")
    func messageNoTypeTagData() throws {
        // Minimal message: just "/x\0\0" (4 bytes) -- valid message with no arguments
        let data = Data([
            0x2F, 0x78, 0x00, 0x00,             // /x\0\0
        ])
        let msg = try OSCDecoder.decodeMessage(data)
        #expect(msg.addressPattern == "/x")
        #expect(msg.arguments.isEmpty)
    }

    @Test("Invalid UTF-8 in string throws unterminatedString")
    func invalidUTF8String() {
        // Craft data with invalid UTF-8 bytes as the address
        let data = Data([
            0xFF, 0xFE, 0x00, 0x00,             // invalid UTF-8 + null
        ])
        #expect(throws: OSCDecodeError.unterminatedString) {
            try OSCDecoder.decodeMessage(data)
        }
    }

    @Test("Truncated float32 payload throws truncatedData")
    func truncatedFloat32Payload() {
        let data = Data([
            0x2F, 0x78, 0x00, 0x00,             // /x\0\0
            0x2C, 0x66, 0x00, 0x00,             // ,f\0\0
            0x00, 0x01,                           // only 2 bytes, need 4
        ])
        #expect(throws: OSCDecodeError.truncatedData) {
            try OSCDecoder.decodeMessage(data)
        }
    }

    @Test("Truncated char payload throws truncatedData")
    func truncatedCharPayload() {
        let data = Data([
            0x2F, 0x78, 0x00, 0x00,             // /x\0\0
            0x2C, 0x63, 0x00, 0x00,             // ,c\0\0
            0x00, 0x01,                           // only 2 bytes, need 4
        ])
        #expect(throws: OSCDecodeError.truncatedData) {
            try OSCDecoder.decodeMessage(data)
        }
    }

    @Test("Truncated color payload throws truncatedData")
    func truncatedColorPayload() {
        let data = Data([
            0x2F, 0x78, 0x00, 0x00,             // /x\0\0
            0x2C, 0x72, 0x00, 0x00,             // ,r\0\0
            0x00, 0x01,                           // only 2 bytes, need 4
        ])
        #expect(throws: OSCDecodeError.truncatedData) {
            try OSCDecoder.decodeMessage(data)
        }
    }

    @Test("Truncated MIDI payload throws truncatedData")
    func truncatedMIDIPayload() {
        let data = Data([
            0x2F, 0x78, 0x00, 0x00,             // /x\0\0
            0x2C, 0x6D, 0x00, 0x00,             // ,m\0\0
            0x00, 0x01,                           // only 2 bytes, need 4
        ])
        #expect(throws: OSCDecodeError.truncatedData) {
            try OSCDecoder.decodeMessage(data)
        }
    }
}
