import Foundation

/// Errors that can occur during OSC packet encoding.
public enum OSCEncodeError: Error, Equatable {
    /// The address pattern does not start with `/`.
    case invalidAddressPattern
    /// A character argument is not valid ASCII.
    case invalidCharacter(Character)
}

/// Encodes OSC types to their binary wire format per the OSC 1.0 specification.
///
/// All multi-byte integers and floats are big-endian. Strings and blobs are
/// padded to 4-byte boundaries with null bytes.
public enum OSCEncoder {
    /// Encodes an ``OSCPacket`` (message or bundle) to binary data.
    ///
    /// - Parameter packet: The packet to encode.
    /// - Returns: The encoded binary data.
    /// - Throws: ``OSCEncodeError`` if the packet contains invalid data.
    public static func encode(_ packet: OSCPacket) throws -> Data {
        switch packet {
        case .message(let message):
            return try encode(message)
        case .bundle(let bundle):
            return try encode(bundle)
        }
    }

    /// Encodes an ``OSCMessage`` to binary data.
    ///
    /// The wire format is:
    /// 1. Address pattern (null-terminated, 4-byte aligned)
    /// 2. Type tag string starting with `,` (null-terminated, 4-byte aligned)
    /// 3. Argument payloads in order
    ///
    /// - Parameter message: The message to encode.
    /// - Returns: The encoded binary data.
    /// - Throws: ``OSCEncodeError`` if the message contains invalid data.
    public static func encode(_ message: OSCMessage) throws -> Data {
        var data = Data()

        // Address pattern
        data.append(encodePaddedString(message.addressPattern))

        // Type tag string (recursive to handle arrays)
        var tagChars: [Character] = [","]
        for argument in message.arguments {
            appendTypeTags(for: argument, to: &tagChars)
        }
        data.append(encodePaddedString(String(tagChars)))

        // Argument payloads
        for argument in message.arguments {
            data.append(try encodeArgument(argument))
        }

        return data
    }

    /// Encodes an ``OSCBundle`` to binary data.
    ///
    /// The wire format is:
    /// 1. `#bundle\0` header (8 bytes)
    /// 2. Time tag (8 bytes, big-endian)
    /// 3. For each element: 4-byte size prefix + encoded element data
    ///
    /// - Parameter bundle: The bundle to encode.
    /// - Returns: The encoded binary data.
    /// - Throws: ``OSCEncodeError`` if any element contains invalid data.
    public static func encode(_ bundle: OSCBundle) throws -> Data {
        var data = Data()

        // #bundle header (already 8 bytes, null-terminated and aligned)
        data.append(contentsOf: [0x23, 0x62, 0x75, 0x6E, 0x64, 0x6C, 0x65, 0x00])

        // Time tag
        data.append(encodeUInt64(bundle.timeTag.rawValue))

        // Elements
        for element in bundle.elements {
            let elementData = try encode(element)
            data.append(encodeInt32(Int32(elementData.count)))
            data.append(elementData)
        }

        return data
    }

    // MARK: - Internal Helpers

    /// Recursively appends type tag characters for an argument.
    ///
    /// For arrays, emits `[`, the tags for each element, then `]`.
    static func appendTypeTags(for argument: OSCArgument, to tags: inout [Character]) {
        switch argument {
        case .array(let elements):
            tags.append("[")
            for element in elements {
                appendTypeTags(for: element, to: &tags)
            }
            tags.append("]")
        default:
            tags.append(argument.typeTag)
        }
    }

    /// Encodes a single OSC argument's payload bytes.
    ///
    /// - Throws: ``OSCEncodeError/invalidCharacter(_:)`` if a char argument is not ASCII.
    static func encodeArgument(_ argument: OSCArgument) throws -> Data {
        switch argument {
        case .int32(let value):
            return encodeInt32(value)
        case .float32(let value):
            return encodeFloat32(value)
        case .string(let value):
            return encodePaddedString(value)
        case .blob(let value):
            return encodeBlob(value)
        case .timeTag(let value):
            return encodeUInt64(value.rawValue)
        case .int64(let value):
            return encodeInt64(value)
        case .float64(let value):
            return encodeFloat64(value)
        case .char(let value):
            return try encodeChar(value)
        case .color(let value):
            return encodeColor(value)
        case .midi(let value):
            return encodeMIDI(value)
        case .symbol(let value):
            return encodePaddedString(value)
        case .array(let elements):
            // Array brackets are in the type tag string only; payload is inline
            var data = Data()
            for element in elements {
                data.append(try encodeArgument(element))
            }
            return data
        case .true, .false, .nil, .impulse:
            // These types have no payload
            return Data()
        }
    }

    /// Encodes a string as null-terminated with padding to a 4-byte boundary.
    static func encodePaddedString(_ string: String) -> Data {
        var data = Data(string.utf8)
        data.append(0) // null terminator
        // Pad to 4-byte boundary
        let padding = (4 - (data.count % 4)) % 4
        data.append(contentsOf: [UInt8](repeating: 0, count: padding))
        return data
    }

    /// Encodes a 32-bit signed integer in big-endian format.
    static func encodeInt32(_ value: Int32) -> Data {
        var bigEndian = value.bigEndian
        return Data(bytes: &bigEndian, count: 4)
    }

    /// Encodes a 32-bit float in big-endian format.
    static func encodeFloat32(_ value: Float) -> Data {
        var bigEndian = value.bitPattern.bigEndian
        return Data(bytes: &bigEndian, count: 4)
    }

    /// Encodes a 64-bit unsigned integer in big-endian format.
    static func encodeUInt64(_ value: UInt64) -> Data {
        var bigEndian = value.bigEndian
        return Data(bytes: &bigEndian, count: 8)
    }

    /// Encodes a 64-bit signed integer in big-endian format.
    static func encodeInt64(_ value: Int64) -> Data {
        var bigEndian = value.bigEndian
        return Data(bytes: &bigEndian, count: 8)
    }

    /// Encodes a 64-bit double in big-endian format.
    static func encodeFloat64(_ value: Double) -> Data {
        var bigEndian = value.bitPattern.bigEndian
        return Data(bytes: &bigEndian, count: 8)
    }

    /// Encodes a character as 4 bytes with the ASCII value in the last byte.
    ///
    /// - Parameter value: An ASCII character.
    /// - Returns: 4-byte data with the ASCII value in the last byte.
    /// - Throws: ``OSCEncodeError/invalidCharacter(_:)`` if the character is not ASCII.
    static func encodeChar(_ value: Character) throws -> Data {
        guard let ascii = value.asciiValue else {
            throw OSCEncodeError.invalidCharacter(value)
        }
        return Data([0x00, 0x00, 0x00, ascii])
    }

    /// Encodes an ``OSCColor`` as 4 raw bytes (RGBA).
    static func encodeColor(_ value: OSCColor) -> Data {
        Data([value.red, value.green, value.blue, value.alpha])
    }

    /// Encodes an ``OSCMIDIMessage`` as 4 raw bytes.
    static func encodeMIDI(_ value: OSCMIDIMessage) -> Data {
        Data([value.port, value.status, value.data1, value.data2])
    }

    /// Encodes a blob as a 4-byte size prefix followed by data padded to 4-byte boundary.
    static func encodeBlob(_ data: Data) -> Data {
        var result = encodeInt32(Int32(data.count))
        result.append(data)
        let padding = (4 - (data.count % 4)) % 4
        result.append(contentsOf: [UInt8](repeating: 0, count: padding))
        return result
    }
}
