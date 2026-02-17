import Foundation

/// The state of an OSC TCP connection.
public enum ConnectionState: Sendable, Equatable {
    /// Not connected and not attempting to connect.
    case disconnected
    /// Actively establishing a connection.
    case connecting
    /// Connected and ready to send/receive.
    case connected
    /// The connection failed or was terminated with an error.
    case failed(String)

    public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected): true
        case (.connecting, .connecting): true
        case (.connected, .connected): true
        case (.failed(let a), .failed(let b)): a == b
        default: false
        }
    }
}
