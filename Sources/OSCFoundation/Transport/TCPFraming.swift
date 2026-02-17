import Foundation

/// The framing protocol used for OSC-over-TCP connections.
///
/// TCP is a stream protocol with no inherent message boundaries.
/// A framing layer is needed to delimit individual OSC packets.
public enum TCPFraming: Sendable {
    /// Packet Length Header: each packet is preceded by a 4-byte big-endian length.
    ///
    /// This is the most common framing for OSC over TCP and is used by
    /// ETC Eos consoles on port 3032.
    case plh
    /// SLIP (Serial Line Internet Protocol) framing using 0xC0 delimiters.
    case slip
}

/// Internal wrapper that provides a unified deframing interface for both PLH and SLIP.
enum TCPDeframer: Sendable {
    case plh(PLHFramer.Deframer)
    case slip(SLIPFramer.Deframer)

    /// Creates a deframer for the specified framing type.
    init(framing: TCPFraming) {
        switch framing {
        case .plh: self = .plh(PLHFramer.Deframer())
        case .slip: self = .slip(SLIPFramer.Deframer())
        }
    }

    /// Appends incoming TCP data to the internal buffer.
    mutating func push(_ data: Data) {
        switch self {
        case .plh(var deframer):
            deframer.push(data)
            self = .plh(deframer)
        case .slip(var deframer):
            deframer.push(data)
            self = .slip(deframer)
        }
    }

    /// Extracts all complete packets currently available.
    mutating func drainPackets() -> [Data] {
        switch self {
        case .plh(var deframer):
            let packets = deframer.drainPackets()
            self = .plh(deframer)
            return packets
        case .slip(var deframer):
            let packets = deframer.drainPackets()
            self = .slip(deframer)
            return packets
        }
    }

    /// Frames a packet using the appropriate protocol.
    static func frame(_ data: Data, using framing: TCPFraming) -> Data {
        switch framing {
        case .plh: PLHFramer.frame(data)
        case .slip: SLIPFramer.frame(data)
        }
    }
}
