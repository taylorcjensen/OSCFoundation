import Testing
@testable import OSCFoundation

@Suite("OSCTimeTag")
struct OSCTimeTagTests {
    @Test("Immediately has raw value 1")
    func immediately() {
        #expect(OSCTimeTag.immediately.rawValue == 1)
    }

    @Test("Seconds and fraction extraction")
    func components() {
        // Upper 32 bits = 100, lower 32 bits = 500
        let tag = OSCTimeTag(seconds: 100, fraction: 500)
        #expect(tag.seconds == 100)
        #expect(tag.fraction == 500)
    }

    @Test("Raw value round-trips through components")
    func rawValueRoundTrip() {
        let raw: UInt64 = 0x0000_0064_0000_01F4 // seconds=100, fraction=500
        let tag = OSCTimeTag(rawValue: raw)
        let reconstructed = OSCTimeTag(seconds: tag.seconds, fraction: tag.fraction)
        #expect(tag.rawValue == reconstructed.rawValue)
    }

    @Test("Zero time tag")
    func zero() {
        let tag = OSCTimeTag(rawValue: 0)
        #expect(tag.seconds == 0)
        #expect(tag.fraction == 0)
    }

    @Test("Maximum values")
    func maxValues() {
        let tag = OSCTimeTag(seconds: .max, fraction: .max)
        #expect(tag.rawValue == UInt64.max)
    }
}
