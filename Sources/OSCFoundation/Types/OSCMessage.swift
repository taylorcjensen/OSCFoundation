import Foundation

/// An OSC message consisting of an address pattern and zero or more arguments.
///
/// The address pattern must begin with `/`. Arguments are typed values
/// that are encoded according to the OSC 1.0 wire format.
///
/// ```swift
/// let msg = OSCMessage("/eos/cmd", arguments: ["Chan 1 Full Enter"])
/// ```
public struct OSCMessage: Equatable, Sendable {
    /// The OSC address pattern (e.g., `/eos/cmd`).
    ///
    /// Always starts with `/`.
    public let addressPattern: String

    /// The address pattern split on `/`, excluding the leading empty component.
    ///
    /// For `/eos/cmd`, this returns `["eos", "cmd"]`.
    public var addressParts: [String] {
        addressPattern.split(separator: "/").map(String.init)
    }

    /// The typed arguments carried by this message.
    public let arguments: [OSCArgument]

    /// Creates an OSC message.
    ///
    /// - Parameters:
    ///   - addressPattern: The OSC address (must start with `/`).
    ///   - arguments: Values conforming to ``OSCArgumentConvertible``.
    /// - Throws: ``OSCEncodeError/invalidAddressPattern`` if the address does not start with `/`.
    public init(_ addressPattern: String, arguments: [any OSCArgumentConvertible] = []) throws {
        guard addressPattern.hasPrefix("/") else {
            throw OSCEncodeError.invalidAddressPattern
        }
        self.addressPattern = addressPattern
        self.arguments = arguments.map { $0.oscArgument }
    }
}
