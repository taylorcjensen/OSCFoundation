import Foundation

/// Frames and deframes OSC packets for TCP transport using SLIP (Serial Line Internet Protocol).
///
/// SLIP uses special byte sequences to delimit packets:
/// - `END` (0xC0) marks packet boundaries
/// - `ESC` (0xDB) followed by `ESC_END` (0xDC) represents a literal 0xC0 in the data
/// - `ESC` (0xDB) followed by `ESC_ESC` (0xDD) represents a literal 0xDB in the data
///
/// Each frame starts and ends with an END byte. Leading END bytes flush any
/// accumulated noise from the line.
public struct SLIPFramer: Sendable {

    private static let END: UInt8 = 0xC0
    private static let ESC: UInt8 = 0xDB
    private static let ESC_END: UInt8 = 0xDC
    private static let ESC_ESC: UInt8 = 0xDD

    /// Frames an encoded OSC packet using SLIP encoding.
    ///
    /// The output is: leading END + escaped data + trailing END.
    ///
    /// - Parameter packetData: The encoded OSC packet bytes.
    /// - Returns: The SLIP-framed data.
    public static func frame(_ packetData: Data) -> Data {
        var framed = Data()
        framed.append(END) // leading END flushes noise

        for byte in packetData {
            switch byte {
            case END:
                framed.append(ESC)
                framed.append(ESC_END)
            case ESC:
                framed.append(ESC)
                framed.append(ESC_ESC)
            default:
                framed.append(byte)
            }
        }

        framed.append(END) // trailing END
        return framed
    }

    /// Accumulates incoming TCP data and yields complete SLIP-decoded OSC packets.
    ///
    /// Call ``push(_:)`` each time data arrives from the TCP connection.
    /// Call ``nextPacket()`` repeatedly to consume complete packets from the buffer.
    ///
    /// Not thread-safe -- expected to be used from a single actor or serial context.
    public struct Deframer: Sendable {
        private var currentPacket = Data()
        private var completedPackets: [Data] = []
        private var inEscape = false

        /// Creates an empty deframer.
        public init() {}

        /// Processes incoming TCP bytes, extracting completed SLIP packets.
        ///
        /// - Parameter data: Raw bytes received from the TCP connection.
        public mutating func push(_ data: Data) {
            for byte in data {
                if inEscape {
                    inEscape = false
                    switch byte {
                    case SLIPFramer.ESC_END:
                        currentPacket.append(SLIPFramer.END)
                    case SLIPFramer.ESC_ESC:
                        currentPacket.append(SLIPFramer.ESC)
                    default:
                        // Protocol error: unknown escape sequence. Append raw byte.
                        currentPacket.append(byte)
                    }
                } else {
                    switch byte {
                    case SLIPFramer.END:
                        if !currentPacket.isEmpty {
                            completedPackets.append(currentPacket)
                            currentPacket = Data()
                        }
                        // Empty packets between ENDs are silently ignored
                    case SLIPFramer.ESC:
                        inEscape = true
                    default:
                        currentPacket.append(byte)
                    }
                }
            }
        }

        /// Attempts to extract the next complete packet from the buffer.
        ///
        /// Returns `nil` if no complete packets are available.
        ///
        /// - Returns: The raw OSC packet data (SLIP-decoded), or `nil`.
        public mutating func nextPacket() -> Data? {
            guard !completedPackets.isEmpty else { return nil }
            return completedPackets.removeFirst()
        }

        /// Extracts all complete packets currently available.
        ///
        /// - Returns: An array of raw OSC packet data.
        public mutating func drainPackets() -> [Data] {
            let packets = completedPackets
            completedPackets.removeAll()
            return packets
        }

        /// The number of bytes currently buffered in the incomplete packet.
        public var bufferedByteCount: Int {
            currentPacket.count
        }
    }
}
