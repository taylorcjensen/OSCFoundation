import Foundation

/// A top-level OSC packet: either a single message or a bundle.
///
/// The wire format distinguishes packets by their first byte:
/// messages start with `/`, bundles start with `#`.
public enum OSCPacket: Equatable, Sendable {
    /// A single OSC message.
    case message(OSCMessage)
    /// An OSC bundle containing a time tag and nested packets.
    case bundle(OSCBundle)
}
