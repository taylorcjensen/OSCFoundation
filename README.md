# OSCFoundation

[![CI](https://github.com/taylorcjensen/OSCFoundation/actions/workflows/ci.yml/badge.svg)](https://github.com/taylorcjensen/OSCFoundation/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/taylorcjensen/OSCFoundation/graph/badge.svg)](https://codecov.io/gh/taylorcjensen/OSCFoundation)
![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A complete, MIT-licensed [OSC 1.0](https://opensoundcontrol.stanford.edu/spec-1_0.html) implementation in pure Swift. Zero external dependencies -- built entirely on Foundation and Network framework.

## Features

- **Full OSC 1.0 spec** -- messages, bundles, all standard type tags plus extended types (int64, float64, char, color, MIDI, symbol, arrays)
- **TCP and UDP transports** -- client, server, peer, and multicast actors ready to use
- **PLH and SLIP framing** -- Packet Length Header (ETC Eos default) and SLIP for TCP streams
- **Pattern matching** -- full OSC address pattern matching with wildcards (`*`, `?`, `[chars]`, `{alt,alt}`)
- **Address space** -- register handlers and dispatch incoming messages with O(1) exact-match lookup
- **Swift 6 strict concurrency** -- all types are `Sendable`, transports are `actor`-isolated
- **Async/await** -- `AsyncStream`-based packet and connection state delivery
- **Zero dependencies** -- Foundation + Network only, no third-party packages

## Installation

Add OSCFoundation to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/taylorcjensen/OSCFoundation.git", from: "1.0.0")
]
```

Then add it to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["OSCFoundation"]
)
```

## Quick Start

### Creating and encoding a message

```swift
import OSCFoundation

// Create a message with arguments
let msg = try OSCMessage("/eos/cmd", arguments: ["Chan 1 Full Enter"])

// Encode to wire format
let data = try OSCEncoder.encode(msg)

// Decode from wire format
let packet = try OSCDecoder.decode(data)
```

### TCP client (Eos-style PLH framing)

```swift
let client = OSCTCPClient(host: "192.168.1.100", port: 3032)
client.connect()

// Wait for connection
for await state in client.stateUpdates {
    if state == .connected { break }
}

// Send a command
let msg = try OSCMessage("/eos/newcmd", arguments: ["Chan 1 Full Enter"])
try client.send(msg)

// Receive packets
for await packet in client.packets {
    if case .message(let message) = packet {
        print(message.addressPattern, message.arguments)
    }
}
```

### UDP send

```swift
let client = OSCUDPClient(host: "192.168.1.100", port: 8000)
let msg = try OSCMessage("/eos/ping")
try await client.send(msg)
client.close()
```

### UDP server (receive and reply)

```swift
let server = OSCUDPServer(port: 8000)
try await server.start()

for await incoming in server.packets {
    if case .message(let msg) = incoming.packet {
        print("Received:", msg.addressPattern)
        // Reply to sender
        let reply = try OSCMessage("/reply", arguments: ["ok"])
        try await server.send(.message(reply), to: incoming.sender)
    }
}
```

### Pattern matching and address space

```swift
// Direct pattern matching
OSCPatternMatch.matches(pattern: "/eos/out/*/level", address: "/eos/out/chan/1/level")

// Address space with registered handlers
let space = OSCAddressSpace()
space.register("/eos/out/active/chan") { message in
    print("Active channel:", message.arguments)
}

let msg = try OSCMessage("/eos/out/active/chan", arguments: [Int32(1)])
space.dispatch(msg)
```

## Architecture

```
Sources/OSCFoundation/
  Types/       OSCMessage, OSCArgument, OSCBundle, OSCPacket, OSCTimeTag, OSCColor, OSCMIDIMessage
  Coding/      OSCEncoder, OSCDecoder, PLHFramer, SLIPFramer
  Transport/   OSCTCPClient, OSCTCPServer, OSCUDPClient, OSCUDPServer, OSCUDPPeer, OSCUDPMulticast
  Matching/    OSCPatternMatch, OSCAddressSpace
```

| Layer | Purpose |
|-------|---------|
| **Types** | OSC data model -- messages, arguments, bundles, time tags |
| **Coding** | Binary encoding/decoding to OSC wire format |
| **Transport** | Network I/O over TCP (with PLH or SLIP framing) and UDP |
| **Matching** | OSC address pattern matching and handler dispatch |

## License

[MIT](LICENSE) -- Copyright (c) 2026 Taylor C Jensen
