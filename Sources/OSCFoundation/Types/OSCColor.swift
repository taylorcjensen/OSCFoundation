import Foundation

/// A 32-bit RGBA color value used in OSC messages (type tag `r`).
///
/// Each component is an unsigned 8-bit value (0-255). The wire format is
/// 4 bytes in order: red, green, blue, alpha.
public struct OSCColor: Equatable, Hashable, Sendable {
    /// The red component (0-255).
    public let red: UInt8
    /// The green component (0-255).
    public let green: UInt8
    /// The blue component (0-255).
    public let blue: UInt8
    /// The alpha component (0-255).
    public let alpha: UInt8

    /// Creates an OSC color from RGBA components.
    ///
    /// - Parameters:
    ///   - red: Red component (0-255).
    ///   - green: Green component (0-255).
    ///   - blue: Blue component (0-255).
    ///   - alpha: Alpha component (0-255).
    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

extension OSCColor: OSCArgumentConvertible {
    public var oscArgument: OSCArgument { .color(self) }
}
