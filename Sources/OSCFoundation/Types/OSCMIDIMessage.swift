import Foundation

/// A 4-byte MIDI message used in OSC messages (type tag `m`).
///
/// The wire format is 4 bytes in order: port ID, status byte, data byte 1, data byte 2.
public struct OSCMIDIMessage: Equatable, Hashable, Sendable {
    /// The MIDI port ID.
    public let port: UInt8
    /// The MIDI status byte (e.g., note on, note off, control change).
    public let status: UInt8
    /// The first MIDI data byte.
    public let data1: UInt8
    /// The second MIDI data byte.
    public let data2: UInt8

    /// Creates an OSC MIDI message.
    ///
    /// - Parameters:
    ///   - port: MIDI port ID.
    ///   - status: MIDI status byte.
    ///   - data1: First data byte.
    ///   - data2: Second data byte.
    public init(port: UInt8, status: UInt8, data1: UInt8, data2: UInt8) {
        self.port = port
        self.status = status
        self.data1 = data1
        self.data2 = data2
    }
}

extension OSCMIDIMessage: OSCArgumentConvertible {
    public var oscArgument: OSCArgument { .midi(self) }
}
