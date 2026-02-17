import Testing
@testable import OSCFoundation
import Foundation

@Suite("Extended Types")
struct ExtendedTypesTests {

    // MARK: - Type Tags

    @Test("int64 type tag is h")
    func int64TypeTag() {
        #expect(OSCArgument.int64(42).typeTag == "h")
    }

    @Test("float64 type tag is d")
    func float64TypeTag() {
        #expect(OSCArgument.float64(3.14).typeTag == "d")
    }

    @Test("char type tag is c")
    func charTypeTag() {
        #expect(OSCArgument.char("A").typeTag == "c")
    }

    @Test("color type tag is r")
    func colorTypeTag() {
        let color = OSCColor(red: 255, green: 0, blue: 128, alpha: 255)
        #expect(OSCArgument.color(color).typeTag == "r")
    }

    @Test("midi type tag is m")
    func midiTypeTag() {
        let midi = OSCMIDIMessage(port: 0, status: 0x90, data1: 60, data2: 127)
        #expect(OSCArgument.midi(midi).typeTag == "m")
    }

    // MARK: - Int64

    @Test("Int64 conforms to OSCArgumentConvertible")
    func int64Convertible() {
        let value: Int64 = 123_456_789_012
        #expect(value.oscArgument == .int64(123_456_789_012))
    }

    @Test("Encode int64")
    func encodeInt64() throws {
        let msg = try OSCMessage("/h", arguments: [Int64(256)])
        let data = try OSCEncoder.encode(msg)

        // "/h" = 4 bytes (padded)
        // ",h" = 4 bytes (padded)
        // int64 = 8
        // Total: 16
        #expect(data.count == 16)

        let intBytes = Array(data[8 ..< 16])
        // 256 big-endian in 8 bytes
        #expect(intBytes == [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00])
    }

    @Test("Decode int64")
    func decodeInt64() throws {
        let data = Data([
            0x2F, 0x68, 0x00, 0x00,             // /h\0\0
            0x2C, 0x68, 0x00, 0x00,             // ,h\0\0
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x01, 0x00,             // 256 big-endian int64
        ])
        let msg = try OSCDecoder.decodeMessage(data)
        #expect(msg.arguments == [.int64(256)])
    }

    @Test("Round-trip int64 edge cases")
    func roundTripInt64() throws {
        for value: Int64 in [.min, .max, 0, -1, 1] {
            let msg = try OSCMessage("/h", arguments: [OSCArgument.int64(value)])
            let encoded = try OSCEncoder.encode(msg)
            let decoded = try OSCDecoder.decodeMessage(encoded)
            #expect(decoded.arguments == [.int64(value)])
        }
    }

    // MARK: - Float64

    @Test("Encode float64")
    func encodeFloat64() throws {
        let msg = try OSCMessage("/d", arguments: [OSCArgument.float64(1.0)])
        let data = try OSCEncoder.encode(msg)

        // "/d" = 4 bytes (padded)
        // ",d" = 4 bytes (padded)
        // float64 = 8
        // Total: 16
        #expect(data.count == 16)

        // IEEE 754 double 1.0 = 0x3FF0000000000000
        let doubleBytes = Array(data[8 ..< 16])
        #expect(doubleBytes == [0x3F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    @Test("Decode float64")
    func decodeFloat64() throws {
        let data = Data([
            0x2F, 0x64, 0x00, 0x00,             // /d\0\0
            0x2C, 0x64, 0x00, 0x00,             // ,d\0\0
            0x3F, 0xF0, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,             // 1.0 double
        ])
        let msg = try OSCDecoder.decodeMessage(data)
        #expect(msg.arguments == [.float64(1.0)])
    }

    @Test("Round-trip float64 edge cases")
    func roundTripFloat64() throws {
        let values: [Double] = [0.0, -0.0, 1.0, -1.0, .infinity, -.infinity, .greatestFiniteMagnitude]
        for value in values {
            let msg = try OSCMessage("/d", arguments: [OSCArgument.float64(value)])
            let encoded = try OSCEncoder.encode(msg)
            let decoded = try OSCDecoder.decodeMessage(encoded)
            #expect(decoded.arguments == [.float64(value)])
        }
    }

    @Test("Round-trip float64 NaN")
    func roundTripFloat64NaN() throws {
        let msg = try OSCMessage("/d", arguments: [OSCArgument.float64(.nan)])
        let encoded = try OSCEncoder.encode(msg)
        let decoded = try OSCDecoder.decodeMessage(encoded)
        guard case .float64(let result) = decoded.arguments.first else {
            Issue.record("Expected float64")
            return
        }
        #expect(result.isNaN)
    }

    // MARK: - Char

    @Test("Encode char")
    func encodeChar() throws {
        let msg = try OSCMessage("/c", arguments: [OSCArgument.char("A")])
        let data = try OSCEncoder.encode(msg)

        // "/c" = 4 bytes (padded)
        // ",c" = 4 bytes (padded)
        // char = 4 bytes (ASCII in last byte)
        // Total: 12
        #expect(data.count == 12)

        let charBytes = Array(data[8 ..< 12])
        #expect(charBytes == [0x00, 0x00, 0x00, 0x41]) // 'A' = 0x41
    }

    @Test("Decode char")
    func decodeChar() throws {
        let data = Data([
            0x2F, 0x63, 0x00, 0x00,             // /c\0\0
            0x2C, 0x63, 0x00, 0x00,             // ,c\0\0
            0x00, 0x00, 0x00, 0x41,             // 'A'
        ])
        let msg = try OSCDecoder.decodeMessage(data)
        #expect(msg.arguments == [.char("A")])
    }

    @Test("Round-trip char ASCII range")
    func roundTripChar() throws {
        let chars: [Character] = ["A", "z", "0", " ", "~"]
        for ch in chars {
            let msg = try OSCMessage("/c", arguments: [OSCArgument.char(ch)])
            let encoded = try OSCEncoder.encode(msg)
            let decoded = try OSCDecoder.decodeMessage(encoded)
            #expect(decoded.arguments == [.char(ch)])
        }
    }

    @Test("Decoding non-ASCII char byte throws invalidPacket")
    func nonASCIICharThrows() {
        // Byte 0x80 is outside ASCII range (0-127)
        let data = Data([
            0x2F, 0x63, 0x00, 0x00,             // /c\0\0
            0x2C, 0x63, 0x00, 0x00,             // ,c\0\0
            0x00, 0x00, 0x00, 0x80,             // non-ASCII byte
        ])
        #expect(throws: OSCDecodeError.invalidPacket) {
            try OSCDecoder.decodeMessage(data)
        }
    }

    // MARK: - OSCColor

    @Test("OSCColor struct construction")
    func colorConstruction() {
        let color = OSCColor(red: 255, green: 128, blue: 0, alpha: 200)
        #expect(color.red == 255)
        #expect(color.green == 128)
        #expect(color.blue == 0)
        #expect(color.alpha == 200)
    }

    @Test("OSCColor equatable and hashable")
    func colorEquatable() {
        let a = OSCColor(red: 1, green: 2, blue: 3, alpha: 4)
        let b = OSCColor(red: 1, green: 2, blue: 3, alpha: 4)
        let c = OSCColor(red: 1, green: 2, blue: 3, alpha: 5)
        #expect(a == b)
        #expect(a != c)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("OSCColor conforms to OSCArgumentConvertible")
    func colorConvertible() {
        let color = OSCColor(red: 10, green: 20, blue: 30, alpha: 40)
        #expect(color.oscArgument == .color(color))
    }

    @Test("Encode color")
    func encodeColor() throws {
        let color = OSCColor(red: 0xFF, green: 0x00, blue: 0x80, alpha: 0xCC)
        let msg = try OSCMessage("/r", arguments: [OSCArgument.color(color)])
        let data = try OSCEncoder.encode(msg)

        // "/r" = 4 bytes, ",r" = 4 bytes, color = 4 bytes = 12
        #expect(data.count == 12)
        let colorBytes = Array(data[8 ..< 12])
        #expect(colorBytes == [0xFF, 0x00, 0x80, 0xCC])
    }

    @Test("Decode color")
    func decodeColor() throws {
        let data = Data([
            0x2F, 0x72, 0x00, 0x00,             // /r\0\0
            0x2C, 0x72, 0x00, 0x00,             // ,r\0\0
            0xFF, 0x00, 0x80, 0xCC,             // color RGBA
        ])
        let msg = try OSCDecoder.decodeMessage(data)
        let expected = OSCColor(red: 0xFF, green: 0x00, blue: 0x80, alpha: 0xCC)
        #expect(msg.arguments == [.color(expected)])
    }

    @Test("Round-trip color")
    func roundTripColor() throws {
        let color = OSCColor(red: 42, green: 100, blue: 200, alpha: 0)
        let msg = try OSCMessage("/r", arguments: [OSCArgument.color(color)])
        let encoded = try OSCEncoder.encode(msg)
        let decoded = try OSCDecoder.decodeMessage(encoded)
        #expect(decoded.arguments == [.color(color)])
    }

    // MARK: - OSCMIDIMessage

    @Test("OSCMIDIMessage struct construction")
    func midiConstruction() {
        let midi = OSCMIDIMessage(port: 1, status: 0x90, data1: 60, data2: 127)
        #expect(midi.port == 1)
        #expect(midi.status == 0x90)
        #expect(midi.data1 == 60)
        #expect(midi.data2 == 127)
    }

    @Test("OSCMIDIMessage equatable and hashable")
    func midiEquatable() {
        let a = OSCMIDIMessage(port: 0, status: 0x90, data1: 60, data2: 127)
        let b = OSCMIDIMessage(port: 0, status: 0x90, data1: 60, data2: 127)
        let c = OSCMIDIMessage(port: 0, status: 0x80, data1: 60, data2: 127)
        #expect(a == b)
        #expect(a != c)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("OSCMIDIMessage conforms to OSCArgumentConvertible")
    func midiConvertible() {
        let midi = OSCMIDIMessage(port: 0, status: 0x90, data1: 60, data2: 100)
        #expect(midi.oscArgument == .midi(midi))
    }

    @Test("Encode MIDI")
    func encodeMIDI() throws {
        let midi = OSCMIDIMessage(port: 0x01, status: 0x90, data1: 0x3C, data2: 0x7F)
        let msg = try OSCMessage("/m", arguments: [OSCArgument.midi(midi)])
        let data = try OSCEncoder.encode(msg)

        // "/m" = 4 bytes, ",m" = 4 bytes, midi = 4 bytes = 12
        #expect(data.count == 12)
        let midiBytes = Array(data[8 ..< 12])
        #expect(midiBytes == [0x01, 0x90, 0x3C, 0x7F])
    }

    @Test("Decode MIDI")
    func decodeMIDI() throws {
        let data = Data([
            0x2F, 0x6D, 0x00, 0x00,             // /m\0\0
            0x2C, 0x6D, 0x00, 0x00,             // ,m\0\0
            0x01, 0x90, 0x3C, 0x7F,             // MIDI message
        ])
        let msg = try OSCDecoder.decodeMessage(data)
        let expected = OSCMIDIMessage(port: 0x01, status: 0x90, data1: 0x3C, data2: 0x7F)
        #expect(msg.arguments == [.midi(expected)])
    }

    @Test("Round-trip MIDI")
    func roundTripMIDI() throws {
        let midi = OSCMIDIMessage(port: 0, status: 0xB0, data1: 7, data2: 100)
        let msg = try OSCMessage("/m", arguments: [OSCArgument.midi(midi)])
        let encoded = try OSCEncoder.encode(msg)
        let decoded = try OSCDecoder.decodeMessage(encoded)
        #expect(decoded.arguments == [.midi(midi)])
    }

    // MARK: - Symbol (type tag S)

    @Test("symbol type tag is S")
    func symbolTypeTag() {
        #expect(OSCArgument.symbol("foo").typeTag == "S")
    }

    @Test("Encode and decode symbol round-trip")
    func roundTripSymbol() throws {
        let msg = try OSCMessage("/sym", arguments: [OSCArgument.symbol("default")])
        let encoded = try OSCEncoder.encode(msg)
        let decoded = try OSCDecoder.decodeMessage(encoded)
        #expect(decoded.arguments == [.symbol("default")])
    }

    @Test("Symbol and string with same content are not equal")
    func symbolNotEqualToString() {
        #expect(OSCArgument.symbol("foo") != OSCArgument.string("foo"))
    }

    @Test("Decode symbol from raw bytes")
    func decodeSymbol() throws {
        let data = Data([
            0x2F, 0x53, 0x00, 0x00,             // /S\0\0
            0x2C, 0x53, 0x00, 0x00,             // ,S\0\0
            0x68, 0x69, 0x00, 0x00,             // "hi\0" padded
        ])
        let msg = try OSCDecoder.decodeMessage(data)
        #expect(msg.arguments == [.symbol("hi")])
    }

    // MARK: - Bundle Header Validation

    @Test("Malformed bundle header throws invalidPacket")
    func malformedBundleHeaderThrows() {
        // "#bundel\0" (typo -- e and l swapped)
        var data = Data([0x23, 0x62, 0x75, 0x6E, 0x64, 0x65, 0x6C, 0x00])
        // Append 8 bytes of time tag to meet minimum size
        data.append(contentsOf: [UInt8](repeating: 0, count: 8))
        #expect(throws: OSCDecodeError.invalidPacket) {
            try OSCDecoder.decodeBundle(data)
        }
    }

    // MARK: - Mixed extended types

    @Test("Round-trip message with all extended types")
    func roundTripAllExtended() throws {
        let color = OSCColor(red: 1, green: 2, blue: 3, alpha: 4)
        let midi = OSCMIDIMessage(port: 0, status: 0x90, data1: 60, data2: 100)
        let original = try OSCMessage("/ext", arguments: [
            OSCArgument.int64(Int64.max),
            OSCArgument.float64(3.14159265358979),
            OSCArgument.char("X"),
            OSCArgument.color(color),
            OSCArgument.midi(midi),
            Int32(42),
            Float(1.0),
            "hello",
        ])

        let encoded = try OSCEncoder.encode(original)
        let decoded = try OSCDecoder.decodeMessage(encoded)
        #expect(decoded == original)
    }
}
