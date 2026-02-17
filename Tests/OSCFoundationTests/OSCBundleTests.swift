import Testing
@testable import OSCFoundation

@Suite("OSCBundle")
struct OSCBundleTests {
    @Test("Bundle with messages")
    func bundleWithMessages() throws {
        let bundle = OSCBundle(timeTag: .immediately, elements: [
            .message(try OSCMessage("/a")),
            .message(try OSCMessage("/b", arguments: [Int32(1)])),
        ])
        #expect(bundle.timeTag == .immediately)
        #expect(bundle.elements.count == 2)
    }

    @Test("Default time tag is immediately")
    func defaultTimeTag() throws {
        let bundle = OSCBundle(elements: [.message(try OSCMessage("/test"))])
        #expect(bundle.timeTag == .immediately)
    }

    @Test("Empty bundle")
    func emptyBundle() {
        let bundle = OSCBundle(elements: [])
        #expect(bundle.elements.isEmpty)
    }
}
