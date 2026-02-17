import Testing
@testable import OSCFoundation
import Foundation

@Suite("Array Type Tags")
struct ArrayTypeTests {

    @Test("Simple array encode/decode")
    func simpleArray() throws {
        let msg = try OSCMessage("/arr", arguments: [
            OSCArgument.array([.int32(1), .int32(2), .int32(3)]),
        ])
        let encoded = try OSCEncoder.encode(msg)
        let decoded = try OSCDecoder.decodeMessage(encoded)
        #expect(decoded == msg)
    }

    @Test("Array type tag string format")
    func arrayTypeTags() throws {
        let msg = try OSCMessage("/arr", arguments: [
            Int32(1),
            OSCArgument.array([.string("a"), .int32(2)]),
            Float(3.0),
        ])
        let encoded = try OSCEncoder.encode(msg)

        // Read back the type tag string from the encoded data
        // Address "/arr" = 4 + 1 null = 5, padded to 8
        // Type tags should be ",i[si]f" = 7 + 1 null = 8
        let typeTagData = encoded[8 ..< 16]
        let typeTagString = String(data: Data(typeTagData), encoding: .utf8)!
            .replacingOccurrences(of: "\0", with: "")
        #expect(typeTagString == ",i[si]f")
    }

    @Test("Empty array")
    func emptyArray() throws {
        let msg = try OSCMessage("/arr", arguments: [
            OSCArgument.array([]),
        ])
        let encoded = try OSCEncoder.encode(msg)
        let decoded = try OSCDecoder.decodeMessage(encoded)
        #expect(decoded == msg)
    }

    @Test("Nested arrays")
    func nestedArrays() throws {
        let inner = OSCArgument.array([.int32(10), .int32(20)])
        let outer = OSCArgument.array([.string("start"), inner, .string("end")])
        let msg = try OSCMessage("/nested", arguments: [outer])

        let encoded = try OSCEncoder.encode(msg)
        let decoded = try OSCDecoder.decodeMessage(encoded)
        #expect(decoded == msg)
    }

    @Test("Mixed arguments and arrays")
    func mixedArgsAndArrays() throws {
        let msg = try OSCMessage("/mix", arguments: [
            Int32(1),
            OSCArgument.array([.float32(2.0), .string("inside")]),
            "after",
            OSCArgument.array([.int32(3)]),
        ])
        let encoded = try OSCEncoder.encode(msg)
        let decoded = try OSCDecoder.decodeMessage(encoded)
        #expect(decoded == msg)
    }

    @Test("Array with no-payload types")
    func arrayWithNoPayloadTypes() throws {
        let msg = try OSCMessage("/flags", arguments: [
            OSCArgument.array([.true, .false, .nil, .impulse]),
        ])
        let encoded = try OSCEncoder.encode(msg)
        let decoded = try OSCDecoder.decodeMessage(encoded)
        #expect(decoded == msg)
    }

    @Test("Array with extended types")
    func arrayWithExtendedTypes() throws {
        let color = OSCColor(red: 255, green: 0, blue: 0, alpha: 255)
        let midi = OSCMIDIMessage(port: 0, status: 0x90, data1: 60, data2: 100)
        let msg = try OSCMessage("/ext", arguments: [
            OSCArgument.array([
                .int64(999),
                .float64(2.718),
                .char("Z"),
                .color(color),
                .midi(midi),
            ]),
        ])
        let encoded = try OSCEncoder.encode(msg)
        let decoded = try OSCDecoder.decodeMessage(encoded)
        #expect(decoded == msg)
    }

    @Test("Multiple arrays side by side")
    func multipleArrays() throws {
        let msg = try OSCMessage("/multi", arguments: [
            OSCArgument.array([.int32(1), .int32(2)]),
            OSCArgument.array([.string("a"), .string("b")]),
        ])
        let encoded = try OSCEncoder.encode(msg)
        let decoded = try OSCDecoder.decodeMessage(encoded)
        #expect(decoded == msg)
    }

    @Test("Deeply nested arrays")
    func deeplyNested() throws {
        let deep = OSCArgument.array([
            .array([
                .array([.int32(42)]),
            ]),
        ])
        let msg = try OSCMessage("/deep", arguments: [deep])
        let encoded = try OSCEncoder.encode(msg)
        let decoded = try OSCDecoder.decodeMessage(encoded)
        #expect(decoded == msg)
    }
}
