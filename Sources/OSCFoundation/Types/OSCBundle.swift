import Foundation

/// An OSC bundle containing a time tag and one or more OSC packets.
///
/// Bundles allow multiple messages (or nested bundles) to be delivered
/// atomically with a shared timestamp. This implementation supports
/// both encoding and decoding.
public struct OSCBundle: Equatable, Sendable {
    /// The `#bundle\0` identifier bytes.
    static let header = "#bundle\0"

    /// The time at which the bundle's contents should be dispatched.
    public let timeTag: OSCTimeTag

    /// The packets (messages or nested bundles) contained in this bundle.
    public let elements: [OSCPacket]

    /// Creates an OSC bundle.
    ///
    /// - Parameters:
    ///   - timeTag: When to dispatch the bundle contents.
    ///   - elements: The messages or nested bundles to include.
    public init(timeTag: OSCTimeTag = .immediately, elements: [OSCPacket]) {
        self.timeTag = timeTag
        self.elements = elements
    }
}
