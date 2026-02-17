import Testing
@testable import OSCFoundation
import Foundation

@Suite("OSCTimeTag Date Conversion")
struct OSCTimeTagDateTests {

    @Test("immediately returns nil date")
    func immediatelyNilDate() {
        #expect(OSCTimeTag.immediately.date == nil)
    }

    @Test("Known NTP epoch date")
    func ntpEpochDate() {
        // NTP epoch is January 1, 1900 at 00:00:00 UTC
        // seconds = 0, fraction = 0 gives rawValue = 0
        // But rawValue 0 is not .immediately (which is 1), so it should give a date
        let tag = OSCTimeTag(seconds: 0, fraction: 0)
        // rawValue 0 is not .immediately (which is rawValue 1)
        // NTP epoch = 1900-01-01 00:00:00 UTC
        // Unix epoch = 1970-01-01 00:00:00 UTC
        // Difference = 2,208,988,800 seconds
        let date = tag.date!
        let expected = Date(timeIntervalSince1970: -2_208_988_800)
        let diff = abs(date.timeIntervalSince1970 - expected.timeIntervalSince1970)
        #expect(diff < 0.001)
    }

    @Test("Unix epoch as NTP time")
    func unixEpochDate() {
        // Unix epoch (1970-01-01) = NTP seconds 2,208,988,800
        let tag = OSCTimeTag(seconds: 2_208_988_800, fraction: 0)
        let date = tag.date!
        let diff = abs(date.timeIntervalSince1970)
        #expect(diff < 0.001)
    }

    @Test("Round-trip Date conversion within tolerance")
    func roundTripDate() {
        // Use a known date: 2024-01-15 12:00:00 UTC
        let original = Date(timeIntervalSince1970: 1_705_320_000)
        let tag = OSCTimeTag(date: original)
        let recovered = tag.date!

        let diff = abs(original.timeIntervalSince1970 - recovered.timeIntervalSince1970)
        // Should be within 1ms (fractional precision is ~0.23ns per unit)
        #expect(diff < 0.001)
    }

    @Test("Round-trip current date")
    func roundTripCurrentDate() {
        let original = Date()
        let tag = OSCTimeTag(date: original)
        let recovered = tag.date!

        let diff = abs(original.timeIntervalSince1970 - recovered.timeIntervalSince1970)
        #expect(diff < 0.001)
    }

    @Test("Date init produces correct NTP seconds")
    func dateInitNTPSeconds() {
        // Unix timestamp 0 should produce NTP seconds 2,208,988,800
        let date = Date(timeIntervalSince1970: 0)
        let tag = OSCTimeTag(date: date)
        #expect(tag.seconds == 2_208_988_800)
    }

    @Test("Fractional seconds preserved")
    func fractionalSeconds() {
        // Create a date with 0.5 seconds fractional part
        let date = Date(timeIntervalSince1970: 1_000_000_000.5)
        let tag = OSCTimeTag(date: date)

        // fraction should be approximately UInt32.max / 2
        let halfMax = UInt32.max / 2
        let diff = abs(Int64(tag.fraction) - Int64(halfMax))
        // Allow some rounding tolerance
        #expect(diff < 10)
    }
}
