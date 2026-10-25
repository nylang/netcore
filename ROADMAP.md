# Implementation roadmap

1. Specify errors, byte buffers, addresses, cancellation, deadlines and allocator ownership.
2. Implement private OS socket/event adapters for macOS, Linux and Windows;
   expose DNS/address resolution and TCP/UDP over public Nyra APIs.
3. Add asynchronous transport I/O with explicit lifetimes and resource cleanup.
4. Implement HTTP framing, streaming, redirects and bounded response handling.
5. Add TLS with certificate/hostname verification and trust-store integration.
   Select and document the TLS implementation before exposing HTTPS.
6. Integrate HTTPS dependency downloads in the package manager: reproducible
   versions, content hashes, caching, archive/path safety and atomic installation.

Each stage requires portable tests before it is reported usable. The network
package evolves independently of the frozen compiler language pipeline.
