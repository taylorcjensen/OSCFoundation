import Foundation

/// A protocol that allows native Swift types to be converted into OSC arguments.
///
/// Conforming types can be passed directly to ``OSCMessage`` initializers
/// without manual wrapping in ``OSCArgument``.
public protocol OSCArgumentConvertible {
    /// Converts this value to an ``OSCArgument``.
    var oscArgument: OSCArgument { get }
}

/// A single argument in an OSC message.
///
/// Covers all required types from OSC 1.0 plus the common extended types
/// (True, False, Nil, Impulse, int64, float64, char, color, MIDI, array)
/// from the OSC 1.1 type tag additions that most implementations support.
public enum OSCArgument: Equatable, Sendable {
    /// 32-bit big-endian signed integer (type tag `i`).
    case int32(Int32)
    /// 32-bit big-endian IEEE 754 float (type tag `f`).
    case float32(Float)
    /// Null-terminated, 4-byte-aligned UTF-8 string (type tag `s`).
    case string(String)
    /// Length-prefixed binary blob (type tag `b`).
    case blob(Data)
    /// Boolean true (type tag `T`). No payload bytes.
    case `true`
    /// Boolean false (type tag `F`). No payload bytes.
    case `false`
    /// Nil / no value (type tag `N`). No payload bytes.
    case `nil`
    /// Impulse / infinitum / bang (type tag `I`). No payload bytes.
    case impulse
    /// NTP time tag (type tag `t`).
    case timeTag(OSCTimeTag)
    /// 64-bit big-endian signed integer (type tag `h`).
    case int64(Int64)
    /// 64-bit big-endian IEEE 754 double (type tag `d`).
    case float64(Double)
    /// A single ASCII character sent as 4 bytes (type tag `c`).
    case char(Character)
    /// A 32-bit RGBA color (type tag `r`).
    case color(OSCColor)
    /// A 4-byte MIDI message (type tag `m`).
    case midi(OSCMIDIMessage)
    /// An alternate string / symbol (type tag `S`).
    ///
    /// Wire format is identical to a regular string (null-terminated, padded),
    /// but uses type tag `S` instead of `s`. Used by SuperCollider, Pure Data,
    /// and other implementations to distinguish symbols from general strings.
    case symbol(String)
    /// An ordered array of arguments (type tags `[` ... `]`).
    case array([OSCArgument])

    /// The single-character OSC type tag for this argument.
    ///
    /// For arrays, returns `[` -- the encoder handles emitting matching `]`.
    public var typeTag: Character {
        switch self {
        case .int32: "i"
        case .float32: "f"
        case .string: "s"
        case .blob: "b"
        case .true: "T"
        case .false: "F"
        case .nil: "N"
        case .impulse: "I"
        case .timeTag: "t"
        case .int64: "h"
        case .float64: "d"
        case .char: "c"
        case .color: "r"
        case .midi: "m"
        case .symbol: "S"
        case .array: "["
        }
    }
}

// MARK: - OSCArgumentConvertible Conformances

extension Int32: OSCArgumentConvertible {
    public var oscArgument: OSCArgument { .int32(self) }
}

extension Int: OSCArgumentConvertible {
    public var oscArgument: OSCArgument {
        if let i32 = Int32(exactly: self) {
            return .int32(i32)
        }
        return .int64(Int64(self))
    }
}

extension Int64: OSCArgumentConvertible {
    public var oscArgument: OSCArgument { .int64(self) }
}

extension Float: OSCArgumentConvertible {
    public var oscArgument: OSCArgument { .float32(self) }
}

extension Double: OSCArgumentConvertible {
    public var oscArgument: OSCArgument { .float64(self) }
}

extension String: OSCArgumentConvertible {
    public var oscArgument: OSCArgument { .string(self) }
}

extension Data: OSCArgumentConvertible {
    public var oscArgument: OSCArgument { .blob(self) }
}

extension Bool: OSCArgumentConvertible {
    public var oscArgument: OSCArgument { self ? .true : .false }
}

extension OSCTimeTag: OSCArgumentConvertible {
    public var oscArgument: OSCArgument { .timeTag(self) }
}

extension Character: OSCArgumentConvertible {
    public var oscArgument: OSCArgument {
        precondition(asciiValue != nil, "OSC char type requires an ASCII character, got '\(self)'")
        return .char(self)
    }
}

extension OSCArgument: OSCArgumentConvertible {
    public var oscArgument: OSCArgument { self }
}
