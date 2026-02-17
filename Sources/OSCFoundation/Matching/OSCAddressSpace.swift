import Foundation
import os

/// A thread-safe registry of OSC address handlers with pattern-based dispatch.
///
/// Handlers can be registered for exact addresses or wildcard patterns.
/// When a message is dispatched, exact matches are tried first (fast path),
/// then wildcard patterns are checked (slow path).
///
/// ```swift
/// let space = OSCAddressSpace()
/// space.register("/eos/out/ping") { msg in
///     print("Ping received")
/// }
/// space.dispatch(message) // calls matching handlers
/// ```
public final class OSCAddressSpace: @unchecked Sendable {

    /// An opaque handle returned by ``register(_:handler:)`` for later unregistration.
    public struct Registration: Sendable, Hashable {
        let id: UInt64
    }

    private struct Entry: @unchecked Sendable {
        let id: UInt64
        let pattern: String
        let isWildcard: Bool
        let handler: @Sendable (OSCMessage) -> Void
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var nextID: UInt64 = 0
        var entries: [UInt64: Entry] = [:]
        /// Fast lookup index: exact address -> [entry IDs]
        var exactIndex: [String: [UInt64]] = [:]
    }

    /// Creates an empty address space.
    public init() {}

    /// Registers a handler for the given address pattern.
    ///
    /// Patterns containing `*`, `?`, `[`, or `{` are treated as wildcard patterns
    /// and will be matched using ``OSCPatternMatch``. All others are exact matches.
    ///
    /// - Parameters:
    ///   - pattern: The OSC address or pattern to match.
    ///   - handler: The closure to call when a matching message is dispatched.
    /// - Returns: A registration handle for later unregistration.
    @discardableResult
    public func register(_ pattern: String, handler: @escaping @Sendable (OSCMessage) -> Void) -> Registration {
        lock.withLock { state in
            let id = state.nextID
            state.nextID += 1

            let isWildcard = pattern.contains(where: { "*?[{".contains($0) })
            let entry = Entry(id: id, pattern: pattern, isWildcard: isWildcard, handler: handler)
            state.entries[id] = entry

            if !isWildcard {
                state.exactIndex[pattern, default: []].append(id)
            }

            return Registration(id: id)
        }
    }

    /// Removes a previously registered handler.
    ///
    /// - Parameter registration: The handle returned by ``register(_:handler:)``.
    public func unregister(_ registration: Registration) {
        lock.withLock { state in
            guard let entry = state.entries.removeValue(forKey: registration.id) else { return }
            if !entry.isWildcard {
                state.exactIndex[entry.pattern]?.removeAll { $0 == registration.id }
                if state.exactIndex[entry.pattern]?.isEmpty == true {
                    state.exactIndex.removeValue(forKey: entry.pattern)
                }
            }
        }
    }

    /// Dispatches a message to all matching handlers synchronously.
    ///
    /// Exact address matches are checked first (O(1) lookup), then wildcard
    /// patterns are iterated. All matching handlers are invoked on the caller's
    /// thread before this method returns. Handlers should avoid blocking.
    ///
    /// - Parameter message: The message to dispatch.
    /// - Returns: The number of handlers that were called.
    @discardableResult
    public func dispatch(_ message: OSCMessage) -> Int {
        let (exactEntries, wildcardEntries) = lock.withLock { state -> ([Entry], [Entry]) in
            let exactIDs = state.exactIndex[message.addressPattern] ?? []
            let exact = exactIDs.compactMap { state.entries[$0] }
            let wildcards = state.entries.values.filter { $0.isWildcard }
            return (exact, Array(wildcards))
        }

        var count = 0

        // Fast path: exact matches (captured by value, safe against concurrent unregister)
        for entry in exactEntries {
            entry.handler(message)
            count += 1
        }

        // Slow path: wildcard matches (also captured by value)
        for entry in wildcardEntries {
            if OSCPatternMatch.matches(pattern: entry.pattern, address: message.addressPattern) {
                entry.handler(message)
                count += 1
            }
        }

        return count
    }

    /// Dispatches a packet (message or bundle) to all matching handlers.
    ///
    /// Bundles are recursed into, dispatching each contained message.
    ///
    /// - Parameter packet: The packet to dispatch.
    /// - Returns: The total number of handler invocations.
    @discardableResult
    public func dispatch(_ packet: OSCPacket) -> Int {
        switch packet {
        case .message(let message):
            return dispatch(message)
        case .bundle(let bundle):
            var count = 0
            for element in bundle.elements {
                count += dispatch(element)
            }
            return count
        }
    }

    /// Removes all registered handlers.
    public func removeAll() {
        lock.withLock { state in
            state.entries.removeAll()
            state.exactIndex.removeAll()
        }
    }
}
