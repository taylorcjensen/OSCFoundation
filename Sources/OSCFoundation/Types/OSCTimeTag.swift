import Foundation

/// An OSC time tag representing an NTP-format timestamp.
///
/// The raw value is a 64-bit unsigned integer where the upper 32 bits are
/// seconds since January 1, 1900 and the lower 32 bits are fractional seconds.
/// The special value `1` (0x0000000000000001) means "immediately".
public struct OSCTimeTag: Equatable, Hashable, Sendable {
    /// The raw 64-bit NTP timestamp value.
    public let rawValue: UInt64

    /// Seconds between Unix epoch (1970-01-01) and NTP epoch (1900-01-01).
    private static let ntpEpochOffset: UInt64 = 2_208_988_800

    /// Creates a time tag from a raw NTP timestamp.
    ///
    /// - Parameter rawValue: The 64-bit NTP timestamp.
    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    /// A time tag meaning "process immediately".
    ///
    /// Per the OSC spec, this is the value `1` (0x0000000000000001).
    public static let immediately = OSCTimeTag(rawValue: 1)

    /// The seconds portion (upper 32 bits) of the NTP timestamp.
    public var seconds: UInt32 {
        UInt32(rawValue >> 32)
    }

    /// The fractional-seconds portion (lower 32 bits) of the NTP timestamp.
    public var fraction: UInt32 {
        UInt32(rawValue & 0xFFFF_FFFF)
    }

    /// Creates a time tag from separate seconds and fraction components.
    ///
    /// - Parameters:
    ///   - seconds: Seconds since January 1, 1900.
    ///   - fraction: Fractional seconds (1/2^32 of a second per unit).
    public init(seconds: UInt32, fraction: UInt32) {
        self.rawValue = (UInt64(seconds) << 32) | UInt64(fraction)
    }

    /// Creates a time tag from a `Date`.
    ///
    /// Converts the Unix timestamp to NTP seconds and fractional seconds.
    ///
    /// - Parameter date: The date to convert.
    public init(date: Date) {
        let unixTime = date.timeIntervalSince1970
        let ntpSeconds = unixTime + Double(Self.ntpEpochOffset)
        let wholeSeconds = UInt32(ntpSeconds)
        let fractionalPart = ntpSeconds - Double(wholeSeconds)
        let fraction = UInt32(fractionalPart * Double(UInt32.max))
        self.init(seconds: wholeSeconds, fraction: fraction)
    }

    /// Converts this time tag to a `Date`, if it represents an actual timestamp.
    ///
    /// Returns `nil` for the special ``immediately`` value, since it does not
    /// represent a specific point in time.
    public var date: Date? {
        if self == .immediately { return nil }
        let ntpSeconds = Double(seconds) + Double(fraction) / Double(UInt32.max)
        let unixSeconds = ntpSeconds - Double(Self.ntpEpochOffset)
        return Date(timeIntervalSince1970: unixSeconds)
    }
}
