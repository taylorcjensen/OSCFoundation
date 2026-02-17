import Testing
@testable import OSCFoundation
import Foundation

@Suite("OSCMessage")
struct OSCMessageTests {
    @Test("Basic message creation")
    func basicCreation() throws {
        let msg = try OSCMessage("/test")
        #expect(msg.addressPattern == "/test")
        #expect(msg.arguments.isEmpty)
    }

    @Test("Message with typed arguments")
    func typedArguments() throws {
        let msg = try OSCMessage("/eos/cmd", arguments: [
            Int32(1),
            Float(0.5),
            "hello",
            Data([0xFF]),
            true,
        ])
        #expect(msg.arguments.count == 5)
        #expect(msg.arguments[0] == .int32(1))
        #expect(msg.arguments[1] == .float32(0.5))
        #expect(msg.arguments[2] == .string("hello"))
        #expect(msg.arguments[3] == .blob(Data([0xFF])))
        #expect(msg.arguments[4] == .true)
    }

    @Test("Address parts splits correctly")
    func addressParts() throws {
        let msg = try OSCMessage("/eos/out/cmd")
        #expect(msg.addressParts == ["eos", "out", "cmd"])
    }

    @Test("Root address gives empty parts")
    func rootAddress() throws {
        let msg = try OSCMessage("/")
        #expect(msg.addressParts.isEmpty)
    }

    @Test("Equatable conformance")
    func equatable() throws {
        let a = try OSCMessage("/test", arguments: [Int32(42)])
        let b = try OSCMessage("/test", arguments: [Int32(42)])
        let c = try OSCMessage("/test", arguments: [Int32(99)])
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Invalid address pattern throws")
    func invalidAddressPattern() {
        #expect(throws: OSCEncodeError.invalidAddressPattern) {
            try OSCMessage("no-slash")
        }
    }
}
