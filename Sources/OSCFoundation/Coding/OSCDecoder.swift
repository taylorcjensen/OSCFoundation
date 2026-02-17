import Foundation

/// Errors that can occur during OSC packet decoding.
public enum OSCDecodeError: Error, Equatable {
    /// The data is too short for the expected structure.
    case truncatedData
    /// A string field is missing its null terminator.
    case unterminatedString
    /// The type tag string is missing or malformed.
    case missingTypeTag
    /// An unrecognized type tag character was encountered.
    case unknownTypeTag(Character)
    /// The packet data does not start with `/` or `#bundle`.
    case invalidPacket
    /// A bundle element's declared size exceeds the available data.
    case invalidBundleElement
    /// An array close bracket `]` was found without a matching open `[`.
    case unmatchedArrayClose
}

/// Decodes binary OSC data into typed Swift values per the OSC 1.0 specification.
public enum OSCDecoder {
    /// Decodes binary data into an ``OSCPacket``.
    ///
    /// Messages are identified by a leading `/` byte.
    /// Bundles are identified by the `#bundle\0` header.
    ///
    /// - Parameter data: The raw OSC data to decode.
    /// - Returns: The decoded packet.
    /// - Throws: ``OSCDecodeError`` if the data is malformed.
    public static func decode(_ data: Data) throws -> OSCPacket {
        guard !data.isEmpty else {
            throw OSCDecodeError.truncatedData
        }

        if data[data.startIndex] == 0x2F { // '/'
            return .message(try decodeMessage(data))
        } else if data[data.startIndex] == 0x23 { // '#'
            return .bundle(try decodeBundle(data))
        } else {
            throw OSCDecodeError.invalidPacket
        }
    }

    /// Decodes binary data into an ``OSCMessage``.
    ///
    /// - Parameter data: The raw message data.
    /// - Returns: The decoded message.
    /// - Throws: ``OSCDecodeError`` if the data is malformed.
    public static func decodeMessage(_ data: Data) throws -> OSCMessage {
        var offset = data.startIndex

        // Address pattern
        let address = try readPaddedString(data, offset: &offset)
        guard address.hasPrefix("/") else {
            throw OSCDecodeError.invalidPacket
        }

        // Type tag string
        guard offset < data.endIndex else {
            // Message with no type tag string (no arguments) is valid
            return try OSCMessage(address)
        }

        let typeTagString = try readPaddedString(data, offset: &offset)
        guard typeTagString.hasPrefix(",") else {
            throw OSCDecodeError.missingTypeTag
        }

        let typeTags = Array(typeTagString.dropFirst())

        // Arguments (recursive to handle arrays)
        var tagIndex = typeTags.startIndex
        let arguments = try readArguments(tags: typeTags, tagIndex: &tagIndex, data: data, offset: &offset)

        return try OSCMessage(address, arguments: arguments)
    }

    /// Decodes binary data into an ``OSCBundle``.
    ///
    /// - Parameter data: The raw bundle data.
    /// - Returns: The decoded bundle.
    /// - Throws: ``OSCDecodeError`` if the data is malformed.
    public static func decodeBundle(_ data: Data) throws -> OSCBundle {
        guard data.count >= 16 else {
            throw OSCDecodeError.truncatedData
        }

        // Validate #bundle\0 header
        let header: [UInt8] = [0x23, 0x62, 0x75, 0x6E, 0x64, 0x6C, 0x65, 0x00]
        guard data[data.startIndex..<data.startIndex + 8].elementsEqual(header) else {
            throw OSCDecodeError.invalidPacket
        }

        var offset = data.startIndex + 8

        // Time tag
        let timeTag = OSCTimeTag(rawValue: try readUInt64(data, offset: &offset))

        // Elements
        var elements: [OSCPacket] = []
        while offset < data.endIndex {
            guard offset + 4 <= data.endIndex else {
                throw OSCDecodeError.truncatedData
            }
            let elementSize = Int(try readInt32(data, offset: &offset))
            guard elementSize > 0, offset + elementSize <= data.endIndex else {
                throw OSCDecodeError.invalidBundleElement
            }
            let elementData = data[offset ..< offset + elementSize]
            let element = try decode(Data(elementData))
            elements.append(element)
            offset += elementSize
        }

        return OSCBundle(timeTag: timeTag, elements: elements)
    }

    // MARK: - Internal Helpers

    /// Recursively reads arguments from type tags, handling `[` / `]` for arrays.
    static func readArguments(
        tags: [Character],
        tagIndex: inout Array<Character>.Index,
        data: Data,
        offset: inout Data.Index
    ) throws -> [OSCArgument] {
        var arguments: [OSCArgument] = []

        while tagIndex < tags.endIndex {
            let tag = tags[tagIndex]
            if tag == "]" {
                // End of current array level -- consumed by caller
                return arguments
            }
            tagIndex += 1

            if tag == "[" {
                // Start of array: recurse to read until matching "]"
                let elements = try readArguments(tags: tags, tagIndex: &tagIndex, data: data, offset: &offset)
                guard tagIndex < tags.endIndex, tags[tagIndex] == "]" else {
                    throw OSCDecodeError.unmatchedArrayClose
                }
                tagIndex += 1 // consume the "]"
                arguments.append(.array(elements))
            } else {
                let argument = try readArgument(tag: tag, data: data, offset: &offset)
                arguments.append(argument)
            }
        }

        return arguments
    }

    /// Reads a null-terminated, 4-byte-aligned string from the data.
    static func readPaddedString(_ data: Data, offset: inout Data.Index) throws -> String {
        guard let nullIndex = data[offset...].firstIndex(of: 0) else {
            throw OSCDecodeError.unterminatedString
        }

        let stringData = data[offset ..< nullIndex]
        guard let string = String(data: stringData, encoding: .utf8) else {
            throw OSCDecodeError.unterminatedString
        }

        // Advance past the string + null + padding to 4-byte boundary
        let rawLength = nullIndex - offset + 1 // includes null byte
        let paddedLength = rawLength + ((4 - (rawLength % 4)) % 4)
        offset += paddedLength

        return string
    }

    /// Reads a single argument of the given type tag from the data.
    static func readArgument(tag: Character, data: Data, offset: inout Data.Index) throws -> OSCArgument {
        switch tag {
        case "i":
            return .int32(try readInt32(data, offset: &offset))
        case "f":
            return .float32(try readFloat32(data, offset: &offset))
        case "s":
            return .string(try readPaddedString(data, offset: &offset))
        case "b":
            return .blob(try readBlob(data, offset: &offset))
        case "t":
            return .timeTag(OSCTimeTag(rawValue: try readUInt64(data, offset: &offset)))
        case "h":
            return .int64(try readInt64(data, offset: &offset))
        case "d":
            return .float64(try readFloat64(data, offset: &offset))
        case "c":
            return .char(try readChar(data, offset: &offset))
        case "r":
            return .color(try readColor(data, offset: &offset))
        case "m":
            return .midi(try readMIDI(data, offset: &offset))
        case "S":
            return .symbol(try readPaddedString(data, offset: &offset))
        case "T":
            return .true
        case "F":
            return .false
        case "N":
            return .nil
        case "I":
            return .impulse
        default:
            throw OSCDecodeError.unknownTypeTag(tag)
        }
    }

    /// Reads a 32-bit big-endian signed integer.
    static func readInt32(_ data: Data, offset: inout Data.Index) throws -> Int32 {
        guard offset + 4 <= data.endIndex else {
            throw OSCDecodeError.truncatedData
        }
        let value = UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
        offset += 4
        return Int32(bitPattern: value)
    }

    /// Reads a 32-bit big-endian float.
    static func readFloat32(_ data: Data, offset: inout Data.Index) throws -> Float {
        guard offset + 4 <= data.endIndex else {
            throw OSCDecodeError.truncatedData
        }
        let value = UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
        offset += 4
        return Float(bitPattern: value)
    }

    /// Reads a 64-bit big-endian unsigned integer.
    static func readUInt64(_ data: Data, offset: inout Data.Index) throws -> UInt64 {
        guard offset + 8 <= data.endIndex else {
            throw OSCDecodeError.truncatedData
        }
        let hi = UInt64(data[offset]) << 56
            | UInt64(data[offset + 1]) << 48
            | UInt64(data[offset + 2]) << 40
            | UInt64(data[offset + 3]) << 32
        let lo = UInt64(data[offset + 4]) << 24
            | UInt64(data[offset + 5]) << 16
            | UInt64(data[offset + 6]) << 8
            | UInt64(data[offset + 7])
        let value = hi | lo
        offset += 8
        return value
    }

    /// Reads a 64-bit big-endian signed integer.
    static func readInt64(_ data: Data, offset: inout Data.Index) throws -> Int64 {
        let raw = try readUInt64(data, offset: &offset)
        return Int64(bitPattern: raw)
    }

    /// Reads a 64-bit big-endian double.
    static func readFloat64(_ data: Data, offset: inout Data.Index) throws -> Double {
        let raw = try readUInt64(data, offset: &offset)
        return Double(bitPattern: raw)
    }

    /// Reads a character from 4 bytes (ASCII value in the last byte).
    ///
    /// The OSC spec defines char as "an ASCII character sent as 32 bits."
    /// Bytes >= 128 are rejected as invalid.
    ///
    /// - Throws: ``OSCDecodeError/invalidPacket`` if the byte is not ASCII.
    static func readChar(_ data: Data, offset: inout Data.Index) throws -> Character {
        guard offset + 4 <= data.endIndex else {
            throw OSCDecodeError.truncatedData
        }
        let byte = data[offset + 3]
        guard byte < 128 else {
            throw OSCDecodeError.invalidPacket
        }
        offset += 4
        return Character(UnicodeScalar(byte))
    }

    /// Reads a 4-byte RGBA color.
    static func readColor(_ data: Data, offset: inout Data.Index) throws -> OSCColor {
        guard offset + 4 <= data.endIndex else {
            throw OSCDecodeError.truncatedData
        }
        let color = OSCColor(
            red: data[offset],
            green: data[offset + 1],
            blue: data[offset + 2],
            alpha: data[offset + 3]
        )
        offset += 4
        return color
    }

    /// Reads a 4-byte MIDI message.
    static func readMIDI(_ data: Data, offset: inout Data.Index) throws -> OSCMIDIMessage {
        guard offset + 4 <= data.endIndex else {
            throw OSCDecodeError.truncatedData
        }
        let midi = OSCMIDIMessage(
            port: data[offset],
            status: data[offset + 1],
            data1: data[offset + 2],
            data2: data[offset + 3]
        )
        offset += 4
        return midi
    }

    /// Reads a blob (4-byte size prefix + data padded to 4-byte boundary).
    static func readBlob(_ data: Data, offset: inout Data.Index) throws -> Data {
        let size = Int(try readInt32(data, offset: &offset))
        guard size >= 0, offset + size <= data.endIndex else {
            throw OSCDecodeError.truncatedData
        }
        let blobData = Data(data[offset ..< offset + size])
        let paddedSize = size + ((4 - (size % 4)) % 4)
        offset += paddedSize
        return blobData
    }
}
