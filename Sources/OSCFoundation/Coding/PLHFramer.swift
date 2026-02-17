import Foundation

/// Frames and deframes OSC packets for TCP transport using Packet Length Header (PLH) framing.
///
/// PLH prepends a 4-byte big-endian length prefix to each packet. On the receive side,
/// the deframer accumulates bytes from the TCP stream and yields complete packets
/// as they become available.
///
/// This handles the realities of TCP streaming: partial reads, multiple packets
/// arriving in a single chunk, and packets split across chunks.
public struct PLHFramer: Sendable {
    /// Frames an encoded OSC packet by prepending a 4-byte big-endian length header.
    ///
    /// - Parameter packetData: The encoded OSC packet bytes.
    /// - Returns: The framed data (length prefix + packet data).
    public static func frame(_ packetData: Data) -> Data {
        var framed = Data(capacity: 4 + packetData.count)
        var length = UInt32(packetData.count).bigEndian
        framed.append(Data(bytes: &length, count: 4))
        framed.append(packetData)
        return framed
    }

    /// Accumulates incoming TCP data and yields complete OSC packets.
    ///
    /// Call ``push(_:)`` each time data arrives from the TCP connection.
    /// Call ``nextPacket()`` repeatedly to consume complete packets from the buffer.
    ///
    /// Not thread-safe -- expected to be used from a single actor or serial context.
    public struct Deframer: Sendable {
        private var buffer = Data()

        /// Creates an empty deframer.
        public init() {}

        /// Appends incoming TCP data to the internal buffer.
        ///
        /// - Parameter data: Raw bytes received from the TCP connection.
        public mutating func push(_ data: Data) {
            buffer.append(data)
        }

        /// Attempts to extract the next complete packet from the buffer.
        ///
        /// Returns `nil` if not enough data has arrived yet for a complete packet.
        ///
        /// - Returns: The raw OSC packet data (without the length prefix), or `nil`.
        public mutating func nextPacket() -> Data? {
            guard buffer.count >= 4 else { return nil }

            let s = buffer.startIndex
            let length = Int(buffer[s]) << 24
                | Int(buffer[s + 1]) << 16
                | Int(buffer[s + 2]) << 8
                | Int(buffer[s + 3])

            guard length > 0, buffer.count >= 4 + length else { return nil }

            let packet = Data(buffer[(s + 4) ..< (s + 4 + length)])
            buffer.removeFirst(4 + length)
            return packet
        }

        /// Extracts all complete packets currently available in the buffer.
        ///
        /// - Returns: An array of raw OSC packet data.
        public mutating func drainPackets() -> [Data] {
            var packets: [Data] = []
            while let packet = nextPacket() {
                packets.append(packet)
            }
            return packets
        }

        /// The number of bytes currently buffered but not yet consumed.
        public var bufferedByteCount: Int {
            buffer.count
        }
    }
}
