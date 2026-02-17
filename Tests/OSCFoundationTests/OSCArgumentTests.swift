import Testing
@testable import OSCFoundation
import Foundation

@Suite("OSCArgument")
struct OSCArgumentTests {
    @Test("Type tags are correct")
    func typeTags() {
        #expect(OSCArgument.int32(42).typeTag == "i")
        #expect(OSCArgument.float32(1.0).typeTag == "f")
        #expect(OSCArgument.string("hello").typeTag == "s")
        #expect(OSCArgument.blob(Data([1, 2, 3])).typeTag == "b")
        #expect(OSCArgument.true.typeTag == "T")
        #expect(OSCArgument.false.typeTag == "F")
        #expect(OSCArgument.nil.typeTag == "N")
        #expect(OSCArgument.impulse.typeTag == "I")
        #expect(OSCArgument.timeTag(.immediately).typeTag == "t")
    }

    @Test("Int32 conforms to OSCArgumentConvertible")
    func int32Convertible() {
        let value: Int32 = 42
        #expect(value.oscArgument == .int32(42))
    }

    @Test("Int conforms to OSCArgumentConvertible")
    func intConvertible() {
        let value: Int = 100
        #expect(value.oscArgument == .int32(100))
    }

    @Test("Int at Int32.max stays int32")
    func intAtInt32Max() {
        let value = Int(Int32.max)
        #expect(value.oscArgument == .int32(Int32.max))
    }

    @Test("Int above Int32.max promotes to int64")
    func intAboveInt32Max() {
        let value = Int(Int64(Int32.max) + 1)
        #expect(value.oscArgument == .int64(Int64(Int32.max) + 1))
    }

    @Test("Int at Int32.min stays int32")
    func intAtInt32Min() {
        let value = Int(Int32.min)
        #expect(value.oscArgument == .int32(Int32.min))
    }

    @Test("Int below Int32.min promotes to int64")
    func intBelowInt32Min() {
        let value = Int(Int64(Int32.min) - 1)
        #expect(value.oscArgument == .int64(Int64(Int32.min) - 1))
    }

    @Test("Float conforms to OSCArgumentConvertible")
    func floatConvertible() {
        let value: Float = 3.14
        #expect(value.oscArgument == .float32(3.14))
    }

    @Test("Double conforms to OSCArgumentConvertible (maps to float64)")
    func doubleConvertible() {
        let value: Double = 2.5
        #expect(value.oscArgument == .float64(2.5))
    }

    @Test("String conforms to OSCArgumentConvertible")
    func stringConvertible() {
        #expect("hello".oscArgument == .string("hello"))
    }

    @Test("Data conforms to OSCArgumentConvertible")
    func dataConvertible() {
        let data = Data([0x01, 0x02])
        #expect(data.oscArgument == .blob(Data([0x01, 0x02])))
    }

    @Test("Bool conforms to OSCArgumentConvertible")
    func boolConvertible() {
        #expect(true.oscArgument == .true)
        #expect(false.oscArgument == .false)
    }

    @Test("OSCTimeTag conforms to OSCArgumentConvertible")
    func timeTagConvertible() {
        let tag = OSCTimeTag.immediately
        #expect(tag.oscArgument == .timeTag(.immediately))
    }

    @Test("OSCArgument is its own convertible (identity)")
    func argumentIdentity() {
        let arg = OSCArgument.int32(99)
        #expect(arg.oscArgument == .int32(99))
    }

    @Test("Array type tag is open bracket")
    func arrayTypeTag() {
        #expect(OSCArgument.array([.int32(1)]).typeTag == "[")
    }
}
