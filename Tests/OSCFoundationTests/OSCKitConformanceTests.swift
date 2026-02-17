//
//  OSCKitConformanceTests.swift
//  OSCFoundation
//
//  Reference byte vectors derived from orchetect/OSCKit test suite (MIT License)
//  Copyright (c) orchetect - https://github.com/orchetect/OSCKit
//  All test code is original, written against OSCFoundation's API.
//

import Foundation
import Testing
@testable import OSCFoundation

// MARK: - Priority 1: Wire Format

@Suite("OSCKit Conformance - Wire Format")
struct OSCKitConformance_WireFormat {
    /// "/testaddress" null-terminated and padded to 16 bytes.
    /// Shared by all message wire format tests.
    private let addr: [UInt8] = [
        0x2F, 0x74, 0x65, 0x73, 0x74, 0x61, 0x64, 0x64,
        0x72, 0x65, 0x73, 0x73, 0x00, 0x00, 0x00, 0x00,
    ]

    // MARK: - Core Types

    @Test("Empty message (no arguments)")
    func empty() throws {
        let bytes: [UInt8] = addr
            + [0x2C, 0x00, 0x00, 0x00] // ",\0\0\0"

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .message(let msg) = packet else {
            Issue.record("Expected message packet")
            return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.isEmpty)

        let reEncoded = try OSCEncoder.encode(msg)
        #expect(Array(reEncoded) == bytes)
    }

    @Test("Int32 argument")
    func int32() throws {
        let bytes: [UInt8] = addr
            + [0x2C, 0x69, 0x00, 0x00] // ",i\0\0"
            + [0x00, 0x00, 0x00, 0xFF] // 255 big-endian

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .message(let msg) = packet else {
            Issue.record("Expected message packet"); return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.count == 1)
        #expect(msg.arguments[0] == .int32(255))

        let reEncoded = try OSCEncoder.encode(msg)
        #expect(Array(reEncoded) == bytes)
    }

    @Test("Float32 argument")
    func float32() throws {
        let bytes: [UInt8] = addr
            + [0x2C, 0x66, 0x00, 0x00] // ",f\0\0"
            + [0x42, 0xF6, 0xE6, 0x66] // 123.45 big-endian

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .message(let msg) = packet else {
            Issue.record("Expected message packet"); return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.count == 1)
        #expect(msg.arguments[0] == .float32(123.45))

        let reEncoded = try OSCEncoder.encode(msg)
        #expect(Array(reEncoded) == bytes)
    }

    @Test("String argument")
    func string() throws {
        let bytes: [UInt8] = addr
            + [0x2C, 0x73, 0x00, 0x00] // ",s\0\0"
            + [0x54, 0x68, 0x69, 0x73, 0x20, 0x69, 0x73, 0x20,
               0x61, 0x6E, 0x20, 0x65, 0x78, 0x61, 0x6D, 0x70,
               0x6C, 0x65, 0x20, 0x73, 0x74, 0x72, 0x69, 0x6E,
               0x67, 0x2E, 0x00, 0x00] // "This is an example string.\0\0"

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .message(let msg) = packet else {
            Issue.record("Expected message packet"); return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.count == 1)
        #expect(msg.arguments[0] == .string("This is an example string."))

        let reEncoded = try OSCEncoder.encode(msg)
        #expect(Array(reEncoded) == bytes)
    }

    @Test("Blob argument")
    func blob() throws {
        let bytes: [UInt8] = addr
            + [0x2C, 0x62, 0x00, 0x00] // ",b\0\0"
            + [0x00, 0x00, 0x00, 0x03] // blob length = 3
            + [0x01, 0x02, 0x03, 0x00] // blob data + 1 byte padding

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .message(let msg) = packet else {
            Issue.record("Expected message packet"); return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.count == 1)
        #expect(msg.arguments[0] == .blob(Data([0x01, 0x02, 0x03])))

        let reEncoded = try OSCEncoder.encode(msg)
        #expect(Array(reEncoded) == bytes)
    }

    // MARK: - Extended Types

    @Test("Int64 argument")
    func int64() throws {
        let bytes: [UInt8] = addr
            + [0x2C, 0x68, 0x00, 0x00] // ",h\0\0"
            + [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF] // 255 big-endian

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .message(let msg) = packet else {
            Issue.record("Expected message packet"); return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.count == 1)
        #expect(msg.arguments[0] == .int64(255))

        let reEncoded = try OSCEncoder.encode(msg)
        #expect(Array(reEncoded) == bytes)
    }

    @Test("TimeTag argument")
    func timeTag() throws {
        let bytes: [UInt8] = addr
            + [0x2C, 0x74, 0x00, 0x00] // ",t\0\0"
            + [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF] // rawValue 255

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .message(let msg) = packet else {
            Issue.record("Expected message packet"); return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.count == 1)
        #expect(msg.arguments[0] == .timeTag(OSCTimeTag(rawValue: 255)))

        let reEncoded = try OSCEncoder.encode(msg)
        #expect(Array(reEncoded) == bytes)
    }

    @Test("Double (float64) argument")
    func float64() throws {
        let bytes: [UInt8] = addr
            + [0x2C, 0x64, 0x00, 0x00] // ",d\0\0"
            + [0x40, 0x5E, 0xDC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCD] // 123.45 big-endian

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .message(let msg) = packet else {
            Issue.record("Expected message packet"); return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.count == 1)
        #expect(msg.arguments[0] == .float64(123.45))

        let reEncoded = try OSCEncoder.encode(msg)
        #expect(Array(reEncoded) == bytes)
    }

    @Test("Symbol (alternate string, type tag S)")
    func symbol() throws {
        let bytes: [UInt8] = addr
            + [0x2C, 0x53, 0x00, 0x00] // ",S\0\0"
            + [0x54, 0x68, 0x69, 0x73, 0x20, 0x69, 0x73, 0x20,
               0x61, 0x6E, 0x20, 0x65, 0x78, 0x61, 0x6D, 0x70,
               0x6C, 0x65, 0x20, 0x73, 0x74, 0x72, 0x69, 0x6E,
               0x67, 0x2E, 0x00, 0x00] // "This is an example string.\0\0"

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .message(let msg) = packet else {
            Issue.record("Expected message packet"); return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.count == 1)
        #expect(msg.arguments[0] == .symbol("This is an example string."))

        let reEncoded = try OSCEncoder.encode(msg)
        #expect(Array(reEncoded) == bytes)
    }

    @Test("Character argument")
    func character() throws {
        let bytes: [UInt8] = addr
            + [0x2C, 0x63, 0x00, 0x00] // ",c\0\0"
            + [0x00, 0x00, 0x00, 0x61] // 'a' as ASCII 97, int32 big-endian

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .message(let msg) = packet else {
            Issue.record("Expected message packet"); return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.count == 1)
        #expect(msg.arguments[0] == .char("a"))

        let reEncoded = try OSCEncoder.encode(msg)
        #expect(Array(reEncoded) == bytes)
    }

    @Test("MIDI argument")
    func midi() throws {
        let bytes: [UInt8] = addr
            + [0x2C, 0x6D, 0x00, 0x00] // ",m\0\0"
            + [0x01, 0x02, 0x03, 0x04] // port, status, data1, data2

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .message(let msg) = packet else {
            Issue.record("Expected message packet"); return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.count == 1)
        #expect(msg.arguments[0] == .midi(OSCMIDIMessage(
            port: 0x01, status: 0x02, data1: 0x03, data2: 0x04
        )))

        let reEncoded = try OSCEncoder.encode(msg)
        #expect(Array(reEncoded) == bytes)
    }

    @Test("Bool arguments (True + False)")
    func boolTrueFalse() throws {
        let bytes: [UInt8] = addr
            + [0x2C, 0x54, 0x46, 0x00] // ",TF\0"

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .message(let msg) = packet else {
            Issue.record("Expected message packet"); return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.count == 2)
        #expect(msg.arguments[0] == .true)
        #expect(msg.arguments[1] == .false)

        let reEncoded = try OSCEncoder.encode(msg)
        #expect(Array(reEncoded) == bytes)
    }

    @Test("Null argument")
    func null() throws {
        let bytes: [UInt8] = addr
            + [0x2C, 0x4E, 0x00, 0x00] // ",N\0\0"

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .message(let msg) = packet else {
            Issue.record("Expected message packet"); return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.count == 1)
        #expect(msg.arguments[0] == .nil)

        let reEncoded = try OSCEncoder.encode(msg)
        #expect(Array(reEncoded) == bytes)
    }

    @Test("Impulse argument")
    func impulse() throws {
        let bytes: [UInt8] = addr
            + [0x2C, 0x49, 0x00, 0x00] // ",I\0\0"

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .message(let msg) = packet else {
            Issue.record("Expected message packet"); return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.count == 1)
        #expect(msg.arguments[0] == .impulse)

        let reEncoded = try OSCEncoder.encode(msg)
        #expect(Array(reEncoded) == bytes)
    }

    @Test("Array argument containing string and int32")
    func array() throws {
        let bytes: [UInt8] = addr
            + [0x2C, 0x5B, 0x73, 0x69, // ",[si"
               0x5D, 0x00, 0x00, 0x00] // "]\0\0\0"
            + [0x61, 0x62, 0x63, 0x00] // "abc\0"
            + [0x00, 0x00, 0x00, 0xFF] // 255 big-endian

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .message(let msg) = packet else {
            Issue.record("Expected message packet"); return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.count == 1)
        #expect(msg.arguments[0] == .array([.string("abc"), .int32(255)]))

        let reEncoded = try OSCEncoder.encode(msg)
        #expect(Array(reEncoded) == bytes)
    }

    // MARK: - Bundle Wire Format

    @Test("Empty bundle")
    func emptyBundle() throws {
        let bytes: [UInt8] = [
            0x23, 0x62, 0x75, 0x6E, 0x64, 0x6C, 0x65, 0x00, // "#bundle\0"
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,  // timeTag = 1
        ]

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .bundle(let bundle) = packet else {
            Issue.record("Expected bundle packet"); return
        }
        #expect(bundle.timeTag.rawValue == 1)
        #expect(bundle.elements.isEmpty)

        let reEncoded = try OSCEncoder.encode(bundle)
        #expect(Array(reEncoded) == bytes)
    }

    @Test("Bundle with single int32 message")
    func bundleWithMessage() throws {
        let bytes: [UInt8] = [
            // #bundle header
            0x23, 0x62, 0x75, 0x6E, 0x64, 0x6C, 0x65, 0x00,
            // timeTag = 1
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
            // element size = 24
            0x00, 0x00, 0x00, 0x18,
            // message: "/testaddress"
            0x2F, 0x74, 0x65, 0x73, 0x74, 0x61, 0x64, 0x64,
            0x72, 0x65, 0x73, 0x73, 0x00, 0x00, 0x00, 0x00,
            // ",i\0\0"
            0x2C, 0x69, 0x00, 0x00,
            // int32 = 255
            0x00, 0x00, 0x00, 0xFF,
        ]

        let packet = try OSCDecoder.decode(Data(bytes))
        guard case .bundle(let bundle) = packet else {
            Issue.record("Expected bundle packet"); return
        }
        #expect(bundle.timeTag.rawValue == 1)
        #expect(bundle.elements.count == 1)

        guard case .message(let msg) = bundle.elements.first else {
            Issue.record("Expected message element"); return
        }
        #expect(msg.addressPattern == "/testaddress")
        #expect(msg.arguments.count == 1)
        #expect(msg.arguments[0] == .int32(255))

        let reEncoded = try OSCEncoder.encode(bundle)
        #expect(Array(reEncoded) == bytes)
    }

    // MARK: - Decode Errors

    @Test("Invalid packet (no leading / or #)")
    func invalidPacket() {
        let bytes: [UInt8] = [0x00, 0x01, 0x02, 0x03]
        #expect(throws: OSCDecodeError.invalidPacket) {
            try OSCDecoder.decode(Data(bytes))
        }
    }

    @Test("Truncated message (address too short)")
    func truncatedMessage() {
        // Starts with / but truncated before null terminator
        let bytes: [UInt8] = [0x2F, 0x74, 0x65, 0x73]
        #expect(throws: (any Error).self) {
            try OSCDecoder.decode(Data(bytes))
        }
    }

    @Test("Truncated argument data")
    func truncatedArgument() {
        // Valid address + type tag for int32, but no int32 payload
        let bytes: [UInt8] = [
            0x2F, 0x61, 0x00, 0x00, // "/a\0\0"
            0x2C, 0x69, 0x00, 0x00, // ",i\0\0"
            // missing 4 bytes of int32 data
        ]
        #expect(throws: (any Error).self) {
            try OSCDecoder.decode(Data(bytes))
        }
    }
}

// MARK: - Priority 2: Pattern Matching

/// Pattern matching tests derived from OSCKit's Component Evaluate Tests.
/// OSCKit tests component-level matching; we wrap as single-component addresses
/// by prefixing both pattern and target with "/".
@Suite("OSCKit Conformance - Pattern Matching")
struct OSCKitConformance_PatternMatching {

    // MARK: - Literals

    @Test("Literal string matching")
    func literals() {
        #expect(OSCPatternMatch.matches(pattern: "/123", address: "/123"))
        #expect(!OSCPatternMatch.matches(pattern: "/123", address: "/ABC"))

        // Partial prefix/suffix does not match
        #expect(!OSCPatternMatch.matches(pattern: "/12", address: "/123"))
        #expect(!OSCPatternMatch.matches(pattern: "/1234", address: "/123"))
    }

    // MARK: - Star Wildcard (*)

    @Test("Star wildcard matches zero or more characters")
    func starWildcard() {
        #expect(OSCPatternMatch.matches(pattern: "/*", address: "/1"))
        #expect(OSCPatternMatch.matches(pattern: "/*", address: "/123"))
        #expect(OSCPatternMatch.matches(pattern: "/1*", address: "/123"))
        #expect(OSCPatternMatch.matches(pattern: "/12*", address: "/123"))
        #expect(OSCPatternMatch.matches(pattern: "/123*", address: "/123"))
        #expect(OSCPatternMatch.matches(pattern: "/*3", address: "/123"))
        #expect(OSCPatternMatch.matches(pattern: "/*23", address: "/123"))
        #expect(OSCPatternMatch.matches(pattern: "/*123", address: "/123"))
    }

    @Test("Multiple consecutive stars collapse to single wildcard")
    func starWildcardEdgeCases() {
        #expect(OSCPatternMatch.matches(pattern: "/***", address: "/1"))
        #expect(OSCPatternMatch.matches(pattern: "/****", address: "/123"))
    }

    // MARK: - Question Mark Wildcard (?)

    @Test("Question mark matches exactly one character")
    func questionWildcard() {
        #expect(OSCPatternMatch.matches(pattern: "/?", address: "/1"))
        #expect(!OSCPatternMatch.matches(pattern: "/?", address: "/123"))
        #expect(OSCPatternMatch.matches(pattern: "/???", address: "/123"))
        #expect(!OSCPatternMatch.matches(pattern: "/????", address: "/123"))
    }

    // MARK: - Bracket Expressions

    @Test("Bracket single character sets")
    func bracketSingleChars() {
        #expect(OSCPatternMatch.matches(pattern: "/[abc]", address: "/a"))
        #expect(OSCPatternMatch.matches(pattern: "/[abc]", address: "/c"))
        #expect(!OSCPatternMatch.matches(pattern: "/[abc]", address: "/d"))
    }

    @Test("Bracket character ranges")
    func bracketRange() {
        #expect(OSCPatternMatch.matches(pattern: "/[a-z]", address: "/a"))
        #expect(OSCPatternMatch.matches(pattern: "/[a-z]", address: "/z"))
        #expect(!OSCPatternMatch.matches(pattern: "/[b-y]", address: "/C"))
        #expect(!OSCPatternMatch.matches(pattern: "/[b-y]", address: "/z"))
        #expect(!OSCPatternMatch.matches(pattern: "/[b-y]", address: "/bb"))
        #expect(!OSCPatternMatch.matches(pattern: "/[b-y]", address: "/ab"))
        #expect(!OSCPatternMatch.matches(pattern: "/[b-y]", address: "/-"))
    }

    @Test("Bracket single-member range [b-b]")
    func bracketSingleMemberRange() {
        #expect(OSCPatternMatch.matches(pattern: "/[b-b]", address: "/b"))
        #expect(!OSCPatternMatch.matches(pattern: "/[b-b]", address: "/a"))
        #expect(!OSCPatternMatch.matches(pattern: "/[b-b]", address: "/c"))
    }

    @Test("Bracket invalid range [y-b] matches nothing")
    func bracketInvalidRange() {
        #expect(!OSCPatternMatch.matches(pattern: "/[y-b]", address: "/c"))
    }

    @Test("Bracket mixed ranges [a-z0-9]")
    func bracketMixedRanges() {
        #expect(OSCPatternMatch.matches(pattern: "/[a-z0-9]", address: "/a"))
        #expect(OSCPatternMatch.matches(pattern: "/[a-z0-9]", address: "/1"))
        #expect(!OSCPatternMatch.matches(pattern: "/[a-z0-9]", address: "/Z"))
    }

    @Test("Bracket mixed singles and ranges")
    func bracketMixedSinglesAndRanges() {
        #expect(OSCPatternMatch.matches(pattern: "/[a-z0-9XY]", address: "/a"))
        #expect(OSCPatternMatch.matches(pattern: "/[a-z0-9XY]", address: "/1"))
        #expect(OSCPatternMatch.matches(pattern: "/[a-z0-9XY]", address: "/X"))

        #expect(OSCPatternMatch.matches(pattern: "/[Xa-z0-9YZ]", address: "/X"))
        #expect(OSCPatternMatch.matches(pattern: "/[Xa-z0-9YZ]", address: "/Y"))
        #expect(OSCPatternMatch.matches(pattern: "/[Xa-z0-9YZ]", address: "/Z"))
        #expect(!OSCPatternMatch.matches(pattern: "/[Xa-z0-9YZ]", address: "/A"))
        #expect(!OSCPatternMatch.matches(pattern: "/[Xa-z0-9YZ]", address: "/-"))
    }

    @Test("Bracket edge cases with dashes at boundaries")
    func bracketDashEdgeCases() {
        // Leading dash is literal
        #expect(OSCPatternMatch.matches(pattern: "/[-z]", address: "/-"))
        #expect(OSCPatternMatch.matches(pattern: "/[-z]", address: "/z"))
        #expect(!OSCPatternMatch.matches(pattern: "/[-z]", address: "/a"))

        // Trailing dash is literal
        #expect(OSCPatternMatch.matches(pattern: "/[a-]", address: "/-"))
        #expect(OSCPatternMatch.matches(pattern: "/[a-]", address: "/a"))
        #expect(!OSCPatternMatch.matches(pattern: "/[a-]", address: "/b"))

        // Range followed by trailing dash
        #expect(OSCPatternMatch.matches(pattern: "/[b-y-]", address: "/b"))
        #expect(OSCPatternMatch.matches(pattern: "/[b-y-]", address: "/y"))
        #expect(OSCPatternMatch.matches(pattern: "/[b-y-]", address: "/-"))

        // Leading dash followed by range
        #expect(OSCPatternMatch.matches(pattern: "/[-b-y]", address: "/b"))
        #expect(OSCPatternMatch.matches(pattern: "/[-b-y]", address: "/y"))
        #expect(OSCPatternMatch.matches(pattern: "/[-b-y]", address: "/-"))
    }

    // MARK: - Bracket Negation [!...]

    @Test("Bracket negation with single chars [!abc]")
    func bracketNegationSingleChars() {
        #expect(!OSCPatternMatch.matches(pattern: "/[!abc]", address: "/a"))
        #expect(!OSCPatternMatch.matches(pattern: "/[!abc]", address: "/c"))
        #expect(OSCPatternMatch.matches(pattern: "/[!abc]", address: "/d"))
    }

    @Test("Bracket negation with range [!b-y]")
    func bracketNegationRange() {
        #expect(!OSCPatternMatch.matches(pattern: "/[!b-y]", address: "/b"))
        #expect(!OSCPatternMatch.matches(pattern: "/[!b-y]", address: "/y"))
        #expect(OSCPatternMatch.matches(pattern: "/[!b-y]", address: "/a"))
        #expect(OSCPatternMatch.matches(pattern: "/[!b-y]", address: "/z"))
        #expect(OSCPatternMatch.matches(pattern: "/[!b-y]", address: "/B"))
    }

    @Test("Bracket negation with single-member range [!b-b]")
    func bracketNegationSingleMemberRange() {
        #expect(!OSCPatternMatch.matches(pattern: "/[!b-b]", address: "/b"))
        #expect(OSCPatternMatch.matches(pattern: "/[!b-b]", address: "/a"))
        #expect(OSCPatternMatch.matches(pattern: "/[!b-b]", address: "/c"))
    }

    @Test("Bracket negation with mixed ranges [!a-z0-9]")
    func bracketNegationMixedRanges() {
        #expect(!OSCPatternMatch.matches(pattern: "/[!a-z0-9]", address: "/a"))
        #expect(!OSCPatternMatch.matches(pattern: "/[!a-z0-9]", address: "/1"))
        #expect(OSCPatternMatch.matches(pattern: "/[!a-z0-9]", address: "/A"))
    }

    @Test("Bracket negation edge cases")
    func bracketNegationEdgeCases() {
        // Invalid range in negation
        #expect(OSCPatternMatch.matches(pattern: "/[!y-b]", address: "/c"))

        // [!] with no exclusion set matches any single character
        #expect(OSCPatternMatch.matches(pattern: "/[!]", address: "/a"))

        // [!!] excludes '!'
        #expect(OSCPatternMatch.matches(pattern: "/[!!]", address: "/a"))
        #expect(!OSCPatternMatch.matches(pattern: "/[!!]", address: "/!"))

        // [!!a] excludes '!' and 'a'
        #expect(!OSCPatternMatch.matches(pattern: "/[!!a]", address: "/a"))
    }

    @Test("Bracket negation with mixed singles and ranges")
    func bracketNegationMixedSinglesAndRanges() {
        #expect(!OSCPatternMatch.matches(pattern: "/[!a-z0-9XY]", address: "/a"))
        #expect(!OSCPatternMatch.matches(pattern: "/[!a-z0-9XY]", address: "/1"))
        #expect(!OSCPatternMatch.matches(pattern: "/[!a-z0-9XY]", address: "/x"))
        #expect(!OSCPatternMatch.matches(pattern: "/[!a-z0-9XY]", address: "/X"))
        #expect(OSCPatternMatch.matches(pattern: "/[!a-z0-9XY]", address: "/A"))
        #expect(OSCPatternMatch.matches(pattern: "/[!a-z0-9XY]", address: "/Z"))
    }

    // MARK: - Brace Alternatives

    @Test("Brace alternatives {abc,def}")
    func braceAlternatives() {
        #expect(OSCPatternMatch.matches(pattern: "/{abc}", address: "/abc"))
        #expect(OSCPatternMatch.matches(pattern: "/{abc,def}", address: "/abc"))
        #expect(OSCPatternMatch.matches(pattern: "/{def,abc}", address: "/abc"))
        #expect(!OSCPatternMatch.matches(pattern: "/{def}", address: "/abc"))
        #expect(!OSCPatternMatch.matches(pattern: "/{def,ghi}", address: "/abc"))
    }

    @Test("Brace edge cases (empty alternatives)")
    func braceEdgeCases() {
        #expect(OSCPatternMatch.matches(pattern: "/{,abc}", address: "/abc"))
        #expect(OSCPatternMatch.matches(pattern: "/{abc,}", address: "/abc"))

        // Empty brace pair: {} matches empty component, which is "/"
        // These test that {,abc} and {abc,} don't match empty
        #expect(!OSCPatternMatch.matches(pattern: "/{,abc}", address: "/"))
        #expect(!OSCPatternMatch.matches(pattern: "/{abc,}", address: "/"))
    }

    @Test("Malformed braces treated as literals")
    func braceMalformed() {
        // Missing closing brace - treated as literal
        #expect(OSCPatternMatch.matches(
            pattern: "/{abc,def", address: "/{abc,def"
        ))
        #expect(!OSCPatternMatch.matches(pattern: "/{abc,def", address: "/abc"))
        #expect(!OSCPatternMatch.matches(pattern: "/{abc,def", address: "/def"))

        // Leading closing brace - treated as literal
        #expect(OSCPatternMatch.matches(
            pattern: "/}abc,def", address: "/}abc,def"
        ))
        #expect(!OSCPatternMatch.matches(pattern: "/}abc,def", address: "/abc"))

        // Double opening brace - treated as literal
        #expect(OSCPatternMatch.matches(
            pattern: "/{{abc,def", address: "/{{abc,def"
        ))
        #expect(!OSCPatternMatch.matches(pattern: "/{{abc,def", address: "/abc"))

        // Missing opening brace - treated as literal
        #expect(OSCPatternMatch.matches(
            pattern: "/abc,def}", address: "/abc,def}"
        ))
        #expect(!OSCPatternMatch.matches(pattern: "/abc,def}", address: "/abc"))
    }

    // MARK: - Combined Brackets and Braces

    @Test("Combined bracket and brace patterns")
    func bracketsAndBraces() {
        #expect(OSCPatternMatch.matches(
            pattern: "/[0-9]{def,abc}", address: "/1abc"
        ))
        #expect(!OSCPatternMatch.matches(
            pattern: "/[0-9]{def,abc}", address: "/1ABC"
        ))
        #expect(!OSCPatternMatch.matches(
            pattern: "/[0-9]{def,abc}", address: "/zabc"
        ))
        #expect(!OSCPatternMatch.matches(
            pattern: "/[0-9]{def,abc}", address: "/1abcz"
        ))
        #expect(!OSCPatternMatch.matches(
            pattern: "/[0-9]{def,abc}", address: "/1"
        ))
        #expect(!OSCPatternMatch.matches(
            pattern: "/[0-9]{def,abc}", address: "/abc"
        ))
    }

    // MARK: - Compound Patterns

    @Test("Compound: trailing star (abc*)")
    func compoundTrailingStar() {
        #expect(OSCPatternMatch.matches(pattern: "/abc*", address: "/abc"))
        #expect(OSCPatternMatch.matches(pattern: "/abc*", address: "/abcd"))
    }

    @Test("Compound: leading star (*abc)")
    func compoundLeadingStar() {
        #expect(OSCPatternMatch.matches(pattern: "/*abc", address: "/abc"))
        #expect(OSCPatternMatch.matches(pattern: "/*abc", address: "/xabc"))
        #expect(OSCPatternMatch.matches(pattern: "/*abc", address: "/xyabc"))
        #expect(!OSCPatternMatch.matches(pattern: "/*abc", address: "/abc1"))
        #expect(!OSCPatternMatch.matches(pattern: "/*abc", address: "/xyabc1"))
        #expect(!OSCPatternMatch.matches(pattern: "/*abc", address: "/xyABC"))
    }

    @Test("Compound: surrounding stars (*abc*)")
    func compoundSurroundingStars() {
        #expect(OSCPatternMatch.matches(pattern: "/*abc*", address: "/abc"))
        #expect(OSCPatternMatch.matches(pattern: "/*abc*", address: "/abcd"))
        #expect(OSCPatternMatch.matches(pattern: "/*abc*", address: "/xabc"))
        #expect(OSCPatternMatch.matches(pattern: "/*abc*", address: "/xabcd"))
        #expect(OSCPatternMatch.matches(pattern: "/*abc*", address: "/xyabcde"))
        #expect(!OSCPatternMatch.matches(pattern: "/*abc*", address: "/xyABCde"))
    }

    @Test("Compound: multiple interior stars (*a*bc*)")
    func compoundMultipleStars() {
        #expect(OSCPatternMatch.matches(pattern: "/*a*bc*", address: "/abc"))
        #expect(OSCPatternMatch.matches(pattern: "/*a*bc*", address: "/a1bc"))
        #expect(OSCPatternMatch.matches(pattern: "/*a*bc*", address: "/1abc"))
        #expect(OSCPatternMatch.matches(pattern: "/*a*bc*", address: "/abc1"))
        #expect(OSCPatternMatch.matches(pattern: "/*a*bc*", address: "/1a1bc"))
        #expect(OSCPatternMatch.matches(pattern: "/*a*bc*", address: "/a1bc1"))
        #expect(OSCPatternMatch.matches(pattern: "/*a*bc*", address: "/1a1bc1"))
        #expect(!OSCPatternMatch.matches(pattern: "/*a*bc*", address: "/a"))
        #expect(!OSCPatternMatch.matches(pattern: "/*a*bc*", address: "/bc"))
        #expect(!OSCPatternMatch.matches(pattern: "/*a*bc*", address: "/bca"))
        #expect(!OSCPatternMatch.matches(pattern: "/*a*bc*", address: "/ABC"))
    }

    @Test("Compound: star with braces and bracket (abc*{def,xyz}[0-9])")
    func compoundStarBracesBracket() {
        #expect(OSCPatternMatch.matches(
            pattern: "/abc*{def,xyz}[0-9]", address: "/abcdef1"
        ))
        #expect(OSCPatternMatch.matches(
            pattern: "/abc*{def,xyz}[0-9]", address: "/abcXxyz2"
        ))
        #expect(OSCPatternMatch.matches(
            pattern: "/abc*{def,xyz}[0-9]", address: "/abcXXxyz2"
        ))
        #expect(!OSCPatternMatch.matches(
            pattern: "/abc*{def,xyz}[0-9]", address: "/abcxyzX"
        ))
        #expect(!OSCPatternMatch.matches(
            pattern: "/abc*{def,xyz}[0-9]", address: "/dummyName123"
        ))
    }

    @Test("Compound: leading star with braces and bracket (*abc{def,xyz}[0-9])")
    func compoundLeadingStarBracesBracket() {
        #expect(OSCPatternMatch.matches(
            pattern: "/*abc{def,xyz}[0-9]", address: "/abcdef1"
        ))
        #expect(OSCPatternMatch.matches(
            pattern: "/*abc{def,xyz}[0-9]", address: "/Xabcdef1"
        ))
        #expect(OSCPatternMatch.matches(
            pattern: "/*abc{def,xyz}[0-9]", address: "/XXabcdef1"
        ))
        #expect(!OSCPatternMatch.matches(
            pattern: "/*abc{def,xyz}[0-9]", address: "/abcdefX"
        ))
        #expect(!OSCPatternMatch.matches(
            pattern: "/*abc{def,xyz}[0-9]", address: "/abcdef1X"
        ))
    }

    @Test("Compound: star with braces and hex brackets (abc*{def,xyz}[A-F0-9][A-F0-9])")
    func compoundHexPattern() {
        #expect(OSCPatternMatch.matches(
            pattern: "/abc*{def,xyz}[A-F0-9][A-F0-9]", address: "/abcdef7F"
        ))
        #expect(OSCPatternMatch.matches(
            pattern: "/abc*{def,xyz}[A-F0-9][A-F0-9]", address: "/abcXdefF7"
        ))
        #expect(!OSCPatternMatch.matches(
            pattern: "/abc*{def,xyz}[A-F0-9][A-F0-9]", address: "/abcdefFG"
        ))
    }

    // MARK: - Wildcards Inside Special Expressions (Literal Treatment)

    @Test("Star wildcard inside brackets is literal per OSC 1.0 spec")
    func starLiteralInBrackets() {
        #expect(OSCPatternMatch.matches(pattern: "/[*abc]", address: "/*"))
        #expect(OSCPatternMatch.matches(pattern: "/[*abc]", address: "/a"))
        #expect(OSCPatternMatch.matches(pattern: "/[*abc]", address: "/b"))
        #expect(OSCPatternMatch.matches(pattern: "/[*abc]", address: "/c"))
        #expect(!OSCPatternMatch.matches(pattern: "/[*abc]", address: "/x"))
    }

    @Test("Question mark inside brackets is literal per OSC 1.0 spec")
    func questionLiteralInBrackets() {
        #expect(OSCPatternMatch.matches(pattern: "/[?abc]", address: "/?"))
        #expect(OSCPatternMatch.matches(pattern: "/[?abc]", address: "/a"))
        #expect(OSCPatternMatch.matches(pattern: "/[?abc]", address: "/b"))
        #expect(OSCPatternMatch.matches(pattern: "/[?abc]", address: "/c"))
        #expect(!OSCPatternMatch.matches(pattern: "/[?abc]", address: "/x"))
    }

    @Test("Star wildcard inside braces is literal per OSC 1.0 spec")
    func starLiteralInBraces() {
        #expect(OSCPatternMatch.matches(pattern: "/{*abc,def}", address: "/*abc"))
        #expect(OSCPatternMatch.matches(pattern: "/{*abc,def}", address: "/def"))
        #expect(!OSCPatternMatch.matches(pattern: "/{*abc,def}", address: "/abc"))
        #expect(!OSCPatternMatch.matches(pattern: "/{*abc,def}", address: "/xabc"))
        #expect(!OSCPatternMatch.matches(pattern: "/{*abc,def}", address: "/xxabc"))
    }

    @Test("Question mark inside braces is literal per OSC 1.0 spec")
    func questionLiteralInBraces() {
        #expect(OSCPatternMatch.matches(pattern: "/{?abc,def}", address: "/?abc"))
        #expect(OSCPatternMatch.matches(pattern: "/{?abc,def}", address: "/def"))
        #expect(!OSCPatternMatch.matches(pattern: "/{?abc,def}", address: "/abc"))
        #expect(!OSCPatternMatch.matches(pattern: "/{?abc,def}", address: "/xabc"))
    }

    @Test("Exclamation point inside braces is literal (not negation)")
    func exclamationInBraces() {
        #expect(OSCPatternMatch.matches(pattern: "/{!abc,def}", address: "/!abc"))
        #expect(OSCPatternMatch.matches(pattern: "/{!abc,def}", address: "/def"))
        #expect(!OSCPatternMatch.matches(pattern: "/{!abc,def}", address: "/abc"))
    }

    // MARK: - Common Symbols

    @Test("Common symbols in addresses")
    func commonSymbols() {
        #expect(OSCPatternMatch.matches(pattern: "/vol-", address: "/vol-"))
        #expect(OSCPatternMatch.matches(pattern: "/vol+", address: "/vol+"))
    }
}

// MARK: - Priority 3: Framing

@Suite("OSCKit Conformance - PLH Framing")
struct OSCKitConformance_PLHFraming {

    @Test("PLH encode prepends big-endian length header")
    func encode() {
        // Empty data
        #expect(Array(PLHFramer.frame(Data())) == [0x00, 0x00, 0x00, 0x00])

        // Single byte
        #expect(
            Array(PLHFramer.frame(Data([0x40])))
                == [0x00, 0x00, 0x00, 0x01, 0x40]
        )

        // Two bytes
        #expect(
            Array(PLHFramer.frame(Data([0x40, 0x41])))
                == [0x00, 0x00, 0x00, 0x02, 0x40, 0x41]
        )
    }

    @Test("PLH decode single packet via deframer")
    func decodeSingle() {
        var deframer = PLHFramer.Deframer()
        deframer.push(Data([0x00, 0x00, 0x00, 0x01, 0x40]))
        let packets = deframer.drainPackets()
        #expect(packets == [Data([0x40])])
    }

    @Test("PLH decode two packets via deframer")
    func decodeMultiple() {
        var deframer = PLHFramer.Deframer()
        deframer.push(Data([
            0x00, 0x00, 0x00, 0x01, 0x40,
            0x00, 0x00, 0x00, 0x02, 0x41, 0x42,
        ]))
        let packets = deframer.drainPackets()
        #expect(packets == [Data([0x40]), Data([0x41, 0x42])])
    }

    @Test("PLH practical round-trip with real OSC message")
    func practicalRoundTrip() throws {
        let msg = try OSCMessage("/address/here", arguments: [
            Int32(123),
            true,
            1.5, // Double -> float64
            "abcdefg123456",
        ])
        let raw = try OSCEncoder.encode(msg)
        #expect(raw.count == 52)

        let framed = PLHFramer.frame(raw)
        #expect(framed.count == raw.count + 4)
        // 52 = 0x34 big-endian
        #expect(Array(framed.prefix(4)) == [0x00, 0x00, 0x00, 0x34])

        var deframer = PLHFramer.Deframer()
        deframer.push(framed)
        let packets = deframer.drainPackets()
        #expect(packets == [raw])
    }
}

@Suite("OSCKit Conformance - SLIP Framing")
struct OSCKitConformance_SLIPFraming {
    private let END: UInt8 = 0xC0
    private let ESC: UInt8 = 0xDB
    private let ESC_END: UInt8 = 0xDC
    private let ESC_ESC: UInt8 = 0xDD

    // MARK: - Encode

    @Test("SLIP encode wraps payload with END bytes and escapes special bytes")
    func encode() {
        // Empty payload
        #expect(Array(SLIPFramer.frame(Data())) == [0xC0, 0xC0])

        // Simple payload (no special bytes)
        #expect(Array(SLIPFramer.frame(Data([0x01]))) == [0xC0, 0x01, 0xC0])
        #expect(
            Array(SLIPFramer.frame(Data([0x01, 0x02])))
                == [0xC0, 0x01, 0x02, 0xC0]
        )

        // Payload containing END byte (0xC0 -> ESC ESC_END)
        #expect(
            Array(SLIPFramer.frame(Data([0x01, 0xC0, 0x02])))
                == [0xC0, 0x01, 0xDB, 0xDC, 0x02, 0xC0]
        )

        // Payload containing ESC byte (0xDB -> ESC ESC_ESC)
        #expect(
            Array(SLIPFramer.frame(Data([0x01, 0xDB, 0x02])))
                == [0xC0, 0x01, 0xDB, 0xDD, 0x02, 0xC0]
        )
    }

    @Test("SLIP encode multiple special bytes in sequence")
    func encodeMultipleSpecialBytes() {
        #expect(
            Array(SLIPFramer.frame(Data([0x01, 0xC0, 0xC0, 0x02])))
                == [0xC0, 0x01, 0xDB, 0xDC, 0xDB, 0xDC, 0x02, 0xC0]
        )
        #expect(
            Array(SLIPFramer.frame(Data([0x01, 0xDB, 0xDB, 0x02])))
                == [0xC0, 0x01, 0xDB, 0xDD, 0xDB, 0xDD, 0x02, 0xC0]
        )
        #expect(
            Array(SLIPFramer.frame(Data([0x01, 0xDB, 0xC0, 0x02])))
                == [0xC0, 0x01, 0xDB, 0xDD, 0xDB, 0xDC, 0x02, 0xC0]
        )
        #expect(
            Array(SLIPFramer.frame(Data([0x01, 0xC0, 0xDB, 0x02])))
                == [0xC0, 0x01, 0xDB, 0xDC, 0xDB, 0xDD, 0x02, 0xC0]
        )
    }

    @Test("SLIP encode complex mixed payload")
    func encodeComplex() {
        #expect(
            Array(SLIPFramer.frame(Data([0x01, 0x02, 0xDB, 0x03, 0xC0, 0x04])))
                == [0xC0, 0x01, 0x02, 0xDB, 0xDD, 0x03, 0xDB, 0xDC, 0x04, 0xC0]
        )
    }

    @Test("SLIP recursive encoding (double-frame)")
    func encodeRecursive() {
        // Frame [0x01, 0x02], then frame the result again.
        // Inner: [END, 0x01, 0x02, END]
        // Outer escapes the ENDs: [END, ESC, ESC_END, 0x01, 0x02, ESC, ESC_END, END]
        let inner = SLIPFramer.frame(Data([0x01, 0x02]))
        let outer = SLIPFramer.frame(inner)
        #expect(Array(outer) == [0xC0, 0xDB, 0xDC, 0x01, 0x02, 0xDB, 0xDC, 0xC0])
    }

    // MARK: - Decode via Deframer

    @Test("SLIP decode single packets via deframer")
    func decodeSingle() {
        // Empty frame (two ENDs, no payload) -> no packets
        var d1 = SLIPFramer.Deframer()
        d1.push(Data([0xC0, 0xC0]))
        #expect(d1.drainPackets().isEmpty)

        // Single byte
        var d2 = SLIPFramer.Deframer()
        d2.push(Data([0xC0, 0x01, 0xC0]))
        #expect(d2.drainPackets() == [Data([0x01])])

        // Two bytes
        var d3 = SLIPFramer.Deframer()
        d3.push(Data([0xC0, 0x01, 0x02, 0xC0]))
        #expect(d3.drainPackets() == [Data([0x01, 0x02])])

        // Three bytes
        var d4 = SLIPFramer.Deframer()
        d4.push(Data([0xC0, 0x01, 0x02, 0x03, 0xC0]))
        #expect(d4.drainPackets() == [Data([0x01, 0x02, 0x03])])
    }

    @Test("SLIP decode escape sequences via deframer")
    func decodeEscapeSequences() {
        // ESC ESC_END -> END byte
        var d1 = SLIPFramer.Deframer()
        d1.push(Data([0xC0, 0xDB, 0xDC, 0xC0]))
        #expect(d1.drainPackets() == [Data([0xC0])])

        // ESC ESC_ESC -> ESC byte
        var d2 = SLIPFramer.Deframer()
        d2.push(Data([0xC0, 0xDB, 0xDD, 0xC0]))
        #expect(d2.drainPackets() == [Data([0xDB])])

        // Multiple escape sequences
        var d3 = SLIPFramer.Deframer()
        d3.push(Data([0xC0, 0xDB, 0xDC, 0xDB, 0xDC, 0xC0]))
        #expect(d3.drainPackets() == [Data([0xC0, 0xC0])])

        var d4 = SLIPFramer.Deframer()
        d4.push(Data([0xC0, 0xDB, 0xDD, 0xDB, 0xDD, 0xC0]))
        #expect(d4.drainPackets() == [Data([0xDB, 0xDB])])

        var d5 = SLIPFramer.Deframer()
        d5.push(Data([0xC0, 0xDB, 0xDD, 0xDB, 0xDC, 0xC0]))
        #expect(d5.drainPackets() == [Data([0xDB, 0xC0])])

        var d6 = SLIPFramer.Deframer()
        d6.push(Data([0xC0, 0xDB, 0xDC, 0xDB, 0xDD, 0xC0]))
        #expect(d6.drainPackets() == [Data([0xC0, 0xDB])])
    }

    @Test("SLIP decode complex payload with mixed escapes")
    func decodeComplex() {
        var deframer = SLIPFramer.Deframer()
        deframer.push(Data([
            0xC0, 0x01, 0xDB, 0xDD, 0x02, 0xDB, 0xDC, 0x03, 0xC0,
        ]))
        #expect(deframer.drainPackets() == [Data([0x01, 0xDB, 0x02, 0xC0, 0x03])])
    }

    @Test("SLIP decode multiple packets in one push")
    func decodeMultiplePackets() {
        var d1 = SLIPFramer.Deframer()
        d1.push(Data([0xC0, 0x01, 0xC0, 0x02, 0xC0]))
        #expect(d1.drainPackets() == [Data([0x01]), Data([0x02])])

        var d2 = SLIPFramer.Deframer()
        d2.push(Data([0xC0, 0x01, 0x02, 0xC0, 0x03, 0x04, 0xC0]))
        #expect(d2.drainPackets() == [Data([0x01, 0x02]), Data([0x03, 0x04])])

        var d3 = SLIPFramer.Deframer()
        d3.push(Data([0xC0, 0x01, 0xC0, 0x02, 0xC0, 0x03, 0xC0]))
        #expect(d3.drainPackets() == [Data([0x01]), Data([0x02]), Data([0x03])])
    }

    @Test("SLIP decode ignores extra leading/trailing END bytes")
    func decodeExtraEndBytes() {
        // Multiple leading ENDs
        var d1 = SLIPFramer.Deframer()
        d1.push(Data([0xC0, 0xC0, 0x01, 0xC0]))
        #expect(d1.drainPackets() == [Data([0x01])])

        var d2 = SLIPFramer.Deframer()
        d2.push(Data([0xC0, 0xC0, 0xC0, 0x01, 0xC0]))
        #expect(d2.drainPackets() == [Data([0x01])])

        // Multiple trailing ENDs
        var d3 = SLIPFramer.Deframer()
        d3.push(Data([0xC0, 0x01, 0xC0, 0xC0]))
        #expect(d3.drainPackets() == [Data([0x01])])

        var d4 = SLIPFramer.Deframer()
        d4.push(Data([0xC0, 0x01, 0xC0, 0xC0, 0xC0]))
        #expect(d4.drainPackets() == [Data([0x01])])
    }

    // MARK: - Round-Trip

    @Test("SLIP encode-decode round-trip for all 256 byte values")
    func allByteValuesRoundTrip() {
        for value in UInt8(0) ... UInt8(255) {
            let original = Data([value])
            let encoded = SLIPFramer.frame(original)
            var deframer = SLIPFramer.Deframer()
            deframer.push(encoded)
            let decoded = deframer.drainPackets()
            #expect(
                decoded == [original],
                "Byte \(String(format: "0x%02X", value)) failed round-trip"
            )
        }
    }

    @Test("SLIP practical round-trip with real OSC message")
    func practicalRoundTrip() throws {
        let msg = try OSCMessage("/address/here", arguments: [
            Int32(123),
            true,
            1.5, // Double -> float64
            "abcdefg123456",
        ])
        let raw = try OSCEncoder.encode(msg)

        let framed = SLIPFramer.frame(raw)
        // Framed data should be larger (at minimum +2 for END markers)
        #expect(framed.count > raw.count)

        var deframer = SLIPFramer.Deframer()
        deframer.push(framed)
        let packets = deframer.drainPackets()
        #expect(packets == [raw])
    }
}
