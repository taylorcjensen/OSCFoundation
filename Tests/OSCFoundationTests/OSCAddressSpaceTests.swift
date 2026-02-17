import Testing
@testable import OSCFoundation
import Foundation
import os

/// Thread-safe counter for use in @Sendable test closures.
private final class Counter: Sendable {
    private let _value = OSAllocatedUnfairLock(initialState: 0)

    var value: Int { _value.withLock { $0 } }

    func increment() {
        _value.withLock { $0 += 1 }
    }
}

/// Thread-safe collector for use in @Sendable test closures.
private final class Collector<T: Sendable>: Sendable {
    private let _values = OSAllocatedUnfairLock(initialState: [T]())

    var values: [T] { _values.withLock { $0 } }

    func append(_ value: T) {
        _values.withLock { $0.append(value) }
    }
}

@Suite("OSCAddressSpace")
struct OSCAddressSpaceTests {

    @Test("Register and dispatch exact match")
    func exactDispatch() throws {
        let space = OSCAddressSpace()
        let received = Counter()

        space.register("/test") { _ in received.increment() }
        let count = space.dispatch(try OSCMessage("/test"))

        #expect(count == 1)
        #expect(received.value == 1)
    }

    @Test("No match returns zero")
    func noMatch() throws {
        let space = OSCAddressSpace()
        space.register("/test") { _ in }

        let count = space.dispatch(try OSCMessage("/other"))
        #expect(count == 0)
    }

    @Test("Pattern match dispatch")
    func patternDispatch() throws {
        let space = OSCAddressSpace()
        let received = Counter()

        space.register("/eos/*/ping") { _ in received.increment() }
        let count = space.dispatch(try OSCMessage("/eos/out/ping"))

        #expect(count == 1)
        #expect(received.value == 1)
    }

    @Test("Multiple handlers for same address")
    func multipleHandlers() throws {
        let space = OSCAddressSpace()
        let count1 = Counter()
        let count2 = Counter()

        space.register("/test") { _ in count1.increment() }
        space.register("/test") { _ in count2.increment() }

        let dispatched = space.dispatch(try OSCMessage("/test"))
        #expect(dispatched == 2)
        #expect(count1.value == 1)
        #expect(count2.value == 1)
    }

    @Test("Unregister removes handler")
    func unregister() throws {
        let space = OSCAddressSpace()
        let callCount = Counter()

        let reg = space.register("/test") { _ in callCount.increment() }

        space.dispatch(try OSCMessage("/test"))
        #expect(callCount.value == 1)

        space.unregister(reg)

        space.dispatch(try OSCMessage("/test"))
        #expect(callCount.value == 1) // not called again
    }

    @Test("Mixed exact and pattern handlers")
    func mixedHandlers() throws {
        let space = OSCAddressSpace()
        let exactCount = Counter()
        let patternCount = Counter()

        space.register("/eos/ping") { _ in exactCount.increment() }
        space.register("/eos/*") { _ in patternCount.increment() }

        let count = space.dispatch(try OSCMessage("/eos/ping"))

        #expect(count == 2)
        #expect(exactCount.value == 1)
        #expect(patternCount.value == 1)
    }

    @Test("Dispatch returns correct count")
    func dispatchCount() throws {
        let space = OSCAddressSpace()

        space.register("/a") { _ in }
        space.register("/a") { _ in }
        space.register("/b") { _ in }
        space.register("/c/*") { _ in }

        #expect(space.dispatch(try OSCMessage("/a")) == 2)
        #expect(space.dispatch(try OSCMessage("/b")) == 1)
        #expect(space.dispatch(try OSCMessage("/c/x")) == 1)
        #expect(space.dispatch(try OSCMessage("/d")) == 0)
    }

    @Test("Bundle dispatch recurses into elements")
    func bundleDispatch() throws {
        let space = OSCAddressSpace()
        let messages = Collector<String>()

        space.register("/a") { msg in messages.append(msg.addressPattern) }
        space.register("/b") { msg in messages.append(msg.addressPattern) }

        let bundle = OSCBundle(timeTag: .immediately, elements: [
            .message(try OSCMessage("/a")),
            .message(try OSCMessage("/b")),
        ])

        let count = space.dispatch(.bundle(bundle))
        #expect(count == 2)
        #expect(messages.values == ["/a", "/b"])
    }

    @Test("Nested bundle dispatch")
    func nestedBundleDispatch() throws {
        let space = OSCAddressSpace()
        let messages = Collector<String>()

        space.register("/inner") { msg in messages.append(msg.addressPattern) }
        space.register("/outer") { msg in messages.append(msg.addressPattern) }

        let inner = OSCBundle(timeTag: .immediately, elements: [
            .message(try OSCMessage("/inner")),
        ])
        let outer = OSCBundle(timeTag: .immediately, elements: [
            .bundle(inner),
            .message(try OSCMessage("/outer")),
        ])

        let count = space.dispatch(.bundle(outer))
        #expect(count == 2)
        #expect(messages.values == ["/inner", "/outer"])
    }

    @Test("removeAll clears all handlers")
    func removeAll() throws {
        let space = OSCAddressSpace()

        space.register("/a") { _ in }
        space.register("/b") { _ in }
        space.register("/c/*") { _ in }

        space.removeAll()

        #expect(space.dispatch(try OSCMessage("/a")) == 0)
        #expect(space.dispatch(try OSCMessage("/b")) == 0)
        #expect(space.dispatch(try OSCMessage("/c/x")) == 0)
    }

    @Test("Handler receives correct message")
    func handlerReceivesMessage() throws {
        let space = OSCAddressSpace()
        let receivedArgs = Collector<OSCArgument>()

        space.register("/test") { msg in
            for arg in msg.arguments {
                receivedArgs.append(arg)
            }
        }

        space.dispatch(try OSCMessage("/test", arguments: [Int32(42), "hello"]))
        #expect(receivedArgs.values == [.int32(42), .string("hello")])
    }

    @Test("Unregister wildcard handler")
    func unregisterWildcard() throws {
        let space = OSCAddressSpace()
        let called = Counter()

        let reg = space.register("/eos/*") { _ in called.increment() }
        space.unregister(reg)

        space.dispatch(try OSCMessage("/eos/ping"))
        #expect(called.value == 0)
    }

    @Test("Double unregister is a no-op")
    func doubleUnregister() throws {
        let space = OSCAddressSpace()
        let called = Counter()

        let reg = space.register("/test") { _ in called.increment() }
        space.unregister(reg)
        space.unregister(reg) // second call should be a no-op

        space.dispatch(try OSCMessage("/test"))
        #expect(called.value == 0)
    }
}
