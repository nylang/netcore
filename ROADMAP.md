# Implementation roadmap

The compiler language pipeline remains frozen. Networking evolves as this
independent package, using public kernel/stdlib capabilities and private native
adapters.

## N1 — Values, buffers and controls

Implementation complete; native semantic checking and Core/O2 precompilation
pass on macOS arm64. Behavioral/cross-platform acceptance is pending.

- [x] Stable NetError categories and preserved native error codes.
- [x] Inline IPv4/IPv6 literals, numeric scopes, endpoints and canonical formatting.
- [x] Borrowed read-only/writable ranges and overflow-safe slicing.
- [x] Explicit monotonic deadline semantics with saturating arithmetic.
- [x] ARC-owned atomic cancellation and per-operation options.
- [x] Public API lifetime/allocation contracts; no exported native C ABI.
- [ ] Behavioral coverage for malformed/boundary literals, formatting, byte views,
      deadline overflow/rounding and shared cancellation.

See [foundation.md](docs/foundation.md) for the implemented contract and evidence.

## N2 — DNS and socket substrate

Implementation complete; macOS native semantic checking, Core/O2 precompilation,
C compilation and adapter symbol inventory pass. Runtime and other-host
acceptance are pending. See [transport.md](docs/transport.md).

- [x] Private BSD sockets/WinSock adapter sources; no HTTP/TLS library wrapper.
- [x] Capture native errors before cleanup; map once at the boundary.
- [x] sockaddr conversion, numeric/interface scopes and bounded-result synchronous DNS.
- [x] Move-only TCP connection/listener and UDP owners, close on drop/idempotent Close,
      partial I/O, EOF and explicit datagram truncation failures.
- [x] Nonblocking primitives, absolute socket deadlines and cooperative cancellation;
      SIGPIPE suppression and descriptor/length validation.
- [x] Independent native library builder, MIT notices and ordinary linker arguments.
- [ ] Behavioral resource/I/O/deadline/cancellation coverage and real network acceptance.
- [ ] Linux/Windows native compilation and runtime acceptance.
- [ ] Cross-target SDK artifact integration/acceptance with matching sysroot/CRT.

## N3 — Asynchronous transport

- [ ] OS event adapters, registration ownership and explicit executor affinity.
- [ ] Actual cancellation wakeup and cleanup of cancelled/pending registrations.
- [ ] Integrate public Future/Executor APIs with retained-buffer lifetimes.
- [ ] Deadlines survive retries; bound queues and retained memory with backpressure.

## N4 — HTTP

- [ ] Streaming request/response framing, incremental parsing and bounded headers.
- [ ] Redirect policy, body limits, connection lifecycle and error propagation.

## N5 — TLS and HTTPS

- [ ] Select/document TLS implementation before exposing HTTPS.
- [ ] Certificate and hostname verification, trust-store integration and TLS errors.
- [ ] Streaming HTTPS over the implemented transport layer.

## N6 — Dependency client

- [ ] Reproducible versions, content hashes, caching and offline behavior.
- [ ] Archive/path safety, atomic installation and interrupted-download recovery.
- [ ] Package manager integration through net_core public APIs.

Each stage needs behavioral/platform evidence before it is reported usable.
Code added without such evidence remains implemented but unaccepted.
