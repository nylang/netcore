# Implementation roadmap

The compiler language pipeline remains frozen. Networking evolves as this
independent package, using public kernel/stdlib capabilities and private native
adapters.

## Package boundaries

net_core owns addresses, DNS, TCP/UDP, cancellation, deadlines, buffers and event
driving through N3. HTTP will be implemented in a separate package, as requested;
the stages below track ecosystem dependencies rather than additions to net_core.
TLS is also proposed as a separate reusable package. Its backend selection is a
design recommendation, not an implemented or accepted dependency.

The intended composition is HTTP over TCP for plain HTTP, or HTTP over TLS over
TCP for HTTPS. The HTTP parser/writer must accept a transport abstraction so that
the same protocol implementation serves both paths. net_core does not import HTTP
or TLS, and a plain TCP application must not have to link a TLS implementation.

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
- [x] Linux/Windows native compilation and controlled N3 runtime acceptance.
- [ ] Broader real-network/OS DNS and interface acceptance.
- [ ] Cross-target SDK artifact integration/acceptance with matching sysroot/CRT.

## N3 — Asynchronous transport

macOS arm64, Linux x86_64 and Windows x86_64 readiness, retained transfers, numeric
connect, accept and bounded asynchronous DNS pass 38 controlled behavior cases per
host plus all independent runtime replays. Android arm64/x86_64 and iOS device/
Simulator arm64 pass native compilation/linking and O2 Nyra package precompilation.
Advanced fault injection and mobile runtime acceptance remain open. See [tests/README.md](tests/README.md), [events.md](docs/events.md),
[async-transport.md](docs/async-transport.md) and [async-resolver.md](docs/async-resolver.md).

- [x] macOS kqueue snapshots, explicitly owned duplicated registrations and local driver affinity.
- [x] Fallible OS-backed cancellation factory, sticky wake fanout and ARC endpoint cleanup.
- [x] Bounded local readiness Futures, detached completion publication and explicit backpressure.
- [x] Nonblocking Try operations for TCP reads/writes/accept and UDP send/receive.
- [x] Direction-aware native readiness fanout and wait-entry absolute deadline budgeting.
- [x] Controlled macOS readiness/cancel/resource/reentry acceptance and isolated runtime CPU observations.
- [x] Immutable owned buffers, retained TCP/UDP transfer Futures and progress-preserving errors.
- [x] Partial/exact reads, partial/full writes, bounded work per Poll and pending-byte budgets.
- [x] Numeric async connect/accept with move-only takeable tasks and abandonment cleanup.
- [x] Explicit connection-task cancellation and terminal task states before Close callbacks.
- [x] Explicit fixed DNS workers, bounded job admission and immutable endpoint results.
- [x] Caller-thread DNS completion, nonblocking Close and cancellation retaining in-flight slots.
- [x] macOS DNS progress notifications, query-control wait budgets and retained notification ownership.
- [x] Controlled async DNS behavior, resource/cancellation/notification cases and notification-startup FD failure.
- [ ] Partial worker startup and mutex/CV/thread fault injection; forced wait/duplicate/reuse paths.
- [x] Linux poll and Windows select event adapters, wake channels and duplicated registrations.
- [x] Strict native adapter compilation on macOS arm64, Linux x86_64 and Windows x86_64.
- [x] Linux/Windows 38-case suites and 38 isolated replays per host, including resource recovery.
- [x] Shared portable DNS fixture, platform startup-failure injection and 144-interest fanout case.
- [x] Android arm64/x86_64 and iOS device/Simulator arm64 native compile/link and Nyra precompile.
- [ ] Remaining fault matrices, mobile runtime acceptance and published SDK integration.

The repeatable desktop runner is scripts/accept.py (accept_macos.py remains a
compatibility entry). scripts/build_mobile.py handles explicit Android/iOS targets.
The runners record source/compiler
hashes, complete-suite results, separate runtime CPU/RSS and production-fixture
isolation. Next closure work is the explicit fault-injection matrix in
tests/README.md; N1/N2 boundary matrices and other hosts remain separate gates.

## N4 — HTTP (separate package; deferred)

- [ ] Separate package with transport-independent protocol parsing/writing.
- [ ] Streaming request/response framing, incremental parsing and bounded headers.
- [ ] Redirect policy, body limits, connection lifecycle and error propagation.

## N5 — TLS and HTTPS (separate TLS package proposal; deferred)

- [ ] Select/document TLS implementation before exposing HTTPS.
- [ ] Prefer a maintained OpenSSL backend initially, behind a private native bridge;
      pin an upstream supported release and retain its license/security-update policy.
      Implement no cryptographic primitives or certificate parser in net_core.
- [ ] Keep public TLS session/config/error types independent of OpenSSL pointers,
      native descriptors and provider error layouts.
- [ ] Adapt bounded ciphertext BIO buffers to net_core transport; handle both read
      and write needs during handshake/read/write/shutdown. Drain pending outbound
      ciphertext before waiting for input; readiness direction is not determined
      solely by the user's Read/Write call. Preserve retry buffers and offsets.
- [ ] Certificate and hostname verification, trust-store integration and TLS errors.
- [ ] Separate trust roots from the TLS engine. Implement and accept system trust
      integration per platform, or require an explicitly configured CA source;
      do not assume OpenSSL automatically uses the macOS Keychain. Unavailable
      trust configuration must fail explicitly. SNI does not replace verification.
- [ ] TLS 1.2/1.3 policy, ALPN, certificate limits, bounded plaintext/ciphertext queues,
      handshake/shutdown deadlines, cancellation and authenticated close semantics.
- [ ] Streaming HTTPS over the implemented transport layer.
- [ ] HTTP package selects plain TCP or a TLS transport adapter; no second HTTP parser
      or TLS-specific code is introduced into the compiler's language pipeline.

## N6 — Dependency client (consumer of the separate HTTP/TLS packages)

- [ ] Reproducible versions, content hashes, caching and offline behavior.
- [ ] Archive/path safety, atomic installation and interrupted-download recovery.
- [ ] Package manager integration through net_core public APIs.

Each stage needs behavioral/platform evidence before it is reported usable.
Code added without such evidence remains implemented but unaccepted.

## Continuous integration and draft delivery

- [x] Standalone public-SDK CI driver; no private compiler/workspace source dependency.
- [x] Linux/Windows full N3 workflow commands, validated locally on both hosts.
- [x] Hosted macOS native smoke plus Android/iOS native build jobs.
- [x] Optional compatible-Mac manual Nyra workflow and local command.
- [x] Matching-tag seven-target native candidate checksums and draft-only release flow.
- [x] Workflow lint and local dry-run candidate validation.
- [x] First GitHub-hosted run: all four automatic jobs passed (run 40276141772).
- [ ] Lower-minimum macOS SDK before hosted full macOS Nyra acceptance.

See [CI boundaries and operational requirements](docs/ci.md). No runner was
registered, tag created or release published while implementing these definitions.
