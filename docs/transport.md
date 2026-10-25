# DNS and socket substrate (N2)

## Implemented boundary

The public surface is `interface/transport.ni`. Nyra implements resource
ownership, validation, operation controls and retry policy in the NetTransport
TU. Private C code converts native layouts and invokes BSD sockets/WinSock.
There is no HTTP/TLS library dependency or compiler package-name hook.

The C ABI is private and pointer-only: handles use intptr, error fields int32,
and address records contain logical family 4/6, host-order port, numeric scope
and 16 network-order bytes. C asserts a 28-byte address and 8-byte error record.
`NetErrorKind` is mapped explicitly, not cast from errno or a native enum.

## Resolve and interface lookup

`Resolver.Resolve(host, port, family, max_results, output)` fills a caller-owned
`FastArray<NetEndpoint>` through a mutable reference. Its allocator and capacity
are reused. Validation/native failure leaves output unchanged. Successful
replacement releases old entries; results retain neither host bytes nor native
resolver memory. `max_results` is 1..4096. More unique results produce
MessageTooLarge rather than silent truncation. Native results are deduplicated,
keep resolver order, and are released with freeaddrinfo on all successful-lookup
exit paths. Temporary address storage is bounded by max_results; the OS resolver
still controls its internal allocation.

Canonical numeric addresses are parsed directly in Nyra. Noncanonical numeric
spellings accepted only by an OS resolver (integer/octal/hex/short IPv4) are
rejected, including with an AI_NUMERICHOST probe that issues no DNS request.
Other names use the synchronous OS resolver, accept ASCII only (caller supplies
IDNA ASCII if needed), and reject embedded NUL bytes. There is no service-name
lookup or automatic IPv4-mapped address synthesis. Named IPv6 scopes are resolved
explicitly with `Resolver.InterfaceIndex`, then supplied to `IpAddress.V6`.

This DNS interface does not accept operation options and has **no bounded
lookup/cancellation guarantee**. It is not an asynchronous resolver. A later
resolver service must define bounded worker ownership and completion policy
before sharing the socket deadline contract. See the OS
[getaddrinfo contract](https://man7.org/linux/man-pages/man3/getaddrinfo.3.html).
On Windows interface lookup uses ConvertInterfaceNameToLuidA and
ConvertInterfaceLuidToIndex so errors are available: the native
[if_nametoindex API does not supply a failure code](https://learn.microsoft.com/en-us/windows/win32/api/netioapi/nf-netioapi-if_nametoindex).

## Socket ownership

TcpConnection, TcpListener and UdpSocket forbid copy in their exported faces,
allow explicit move and close on drop. Each facade solely owns a private POD
state (descriptor plus live flag). The state has no independent destructor:
there are not two owners stacked around one native resource. Move takes that
state and resets the source before returning the new owner. Default and
moved-from facade values are closed.

Factories attach a newly created descriptor to a facade immediately. Failed
bind/listen/connect returns drop that facade. Accepted descriptors are configured
before publication, and failures close them. Close retires the descriptor first
and calls the OS once; repeated Close succeeds without another OS call. Close
is not retried after EINTR because its numeric descriptor may already have been
reused. Explicit Close reports errors; drop ignores them. IsOpen reports local
ownership only, not remote peer liveness.

Successful factory/Accept Results contain move-only values. Keep the Result
alive while borrowing its success arm (`get_ref_if`), or explicitly transfer the
successful value. Do not use a copying extraction for a socket owner. Separate
socket owners must not be fabricated from native numbers. Methods on one owner
must not execute concurrently, including Close versus an I/O operation.

## Nonblocking primitives and synchronous policy

All owned sockets are configured nonblocking and non-inheritable before they
are exposed. Linux socket/accept creation additionally uses atomic NONBLOCK and
CLOEXEC flags. Fallback flag configuration on other POSIX hosts is not an atomic
guarantee against an unrelated concurrent fork. Socket writes suppress SIGPIPE
per call or per socket without changing process-wide signal handlers.

N2 provides synchronous methods over these primitives: try the operation,
wait for readiness on WouldBlock/interruption, then retry. macOS uses kqueue;
other POSIX hosts use poll;
Windows uses select with exception readiness for failed connect completion.
Connect completion checks SO_ERROR. Read returns partial progress or zero on
EOF; a zero-sized TCP operation returns zero without an OS receive/send.
Write returns the bytes accepted by one OS call; it is not WriteAll. Windows
stream requests above INT_MAX are split by returning a partial OS operation.
The caller keeps borrowed buffers alive, stable and exclusively writable as
appropriate until each method returns. No raw view is queued in a background task.

TcpListener.Listen uses POSIX SO_REUSEADDR for listener rebinding and Windows
SO_EXCLUSIVEADDRUSE to avoid sharing its bind. UDP does not request address
reuse. IPv6 sockets are explicitly V6-only on every host; an IPv4-mapped literal
does not silently turn a V6-only socket into a dual-stack client. Use a V4
endpoint for IPv4 connections. Backlog must be positive; the OS may clamp it.
LocalEndpoint reports the OS-selected port after port-zero binding.

UDP SendTo sends one complete datagram, including an empty one. ReceiveFrom
consumes one message and returns its sender and byte count; zero is an empty
message, not EOF. An undersized receive buffer produces MessageTooLarge and
consumes/discards that datagram. Its buffer may already contain a prefix even
though the call failed. POSIX checks recvmsg's MSG_TRUNC; Windows preserves
WSAEMSGSIZE. The contracts are documented by
[POSIX/Linux recv](https://man7.org/linux/man-pages/man2/recv.2.html) and
[WinSock recvfrom](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-recvfrom).

A zero-capacity receive uses a one-byte private scratch range at the OS boundary.
An empty datagram succeeds; any positive payload is consumed and reported as
MessageTooLarge. The adapter never writes through a caller pointer whose declared
capacity is zero. This avoids Darwin's zero-iovec recvmsg behavior, which the
controlled N3 acceptance reproduced as a false truncation/empty-socket result.

## Deadlines and cancellation

Socket options use the same monotonic origin as NetClock.NowNanoseconds
(public stdlib tick-to-nanosecond conversion, never wall/Unix time). Compute
NetDeadline.After(now, timeout) once for the operation and reuse it across retries.
A default NetOperationOptions has no deadline and an inert cancellation token.
Closed resources fail before attempting I/O. Control checks give cancellation
precedence over an expired deadline at the same observation.

Every retry recomputes the remaining absolute deadline. New() tokens cap native
waits at 50 ms for cooperative flag checks; None avoids periodic wakes.
NewWakeable() tokens on macOS use a sticky OS wake channel without that polling
cap. Controls are checked after native waiting too. See [events.md](events.md)
for cancellation races, resource ownership and the bounded readiness Future driver.
Thread scheduling, clock/readiness granularity and synchronous DNS remain
outside a hard deadline bound.
A timeout/cancellation cannot undo bytes already transferred; methods return
successful progress if the OS operation wins that observation race.

## Build and link

From the NyraLang root, using an accepted native compiler in NYRAC:

```sh
python3 third_party/net_core/scripts/build_native.py \
  --out-dir cache/net-core/native
"$NYRAC" precompile third_party/net_core/net_core.ny -O2 -j 4 \
  --out-dir cache/net-core/objects -o cache/net-core/package
```

Consumers add their normal net_core dependency/import and link the matching
native archive using an ordinary compiler argument:

```sh
"$NYRAC" build /path/to/application/main.ny --link \
  --link-arg=/absolute/path/to/libnet_core_native.a -o cache/net-core/application
```

On Windows additionally pass `--link-arg=-lws2_32 --link-arg=-liphlpapi` and use
an appropriate output name. The ordinary stdlib platform library is still
required. Native libraries and the Nyra package must target the same platform,
architecture and ABI. build_native.py accepts a Clang --target, --sysroot,
explicit --cc/--ar and repeated --cflag; it does not download foreign system
SDKs or claim a target was accepted just because arguments were supplied.
The native output includes its MIT LICENSE, source hashes, command receipt and
archive digest. Distribution must include both package/native artifacts and
their license notices. There is no installed SDK promotion in this stage.

## Evidence and remaining acceptance

On macOS arm64 the source passes native semantic checking (92 modules, zero
failures), Core/O2 precompilation with four backend workers, and native C
compilation with Wall/Wextra/Werror. Archive symbol inspection finds all 17
native symbols referenced by the Nyra package in the matching C archive.
The final Core/O2 precompile took 4.879 seconds and the native build took
0.267 seconds. Artifacts/logs are under ignored `cache/net-core-transport/final/`.

These are compile/static-link-input checks. Actual DNS/TCP/UDP behavior,
move/drop/failed-construction descriptor lifetime, interruption, EOF/partial
I/O, port-zero binding, truncation, deadlines and cancellation have not been
run. Linux/Windows native compilation and runtime acceptance are pending too.
The N3 macOS increment adds kqueue/readiness Futures, active cancellation and
nonblocking Try methods; see [events.md](events.md). Retained-buffer async
transfers, async connect/resolution and their behavioral acceptance remain open.
HTTP/TLS/dependency fetching remain later stages.

## Current macOS N3 behavioral evidence

The subsequent N3 acceptance passes 37 cases, then replays each case independently.
It covers loopback TCP/UDP, controlled asynchronous DNS, notification/control
races, retained owners, callback reentry and descriptor recovery. It discovered
and fixed the zero-capacity UDP adapter issue above. Three 64-round FD recovery
cases cover TCP connections, wakeable tokens and resolver pools; a late-worker
Close case also waits for descriptor baseline recovery. These checks do not
establish the absence of heap leaks or acceptance of other platforms.

See [tests/README.md](../tests/README.md) for the repeatable runner, exact scope
and remaining fault matrix. Current receipts are under ignored
`cache/net-core-macos-n3-final-06/acceptance.json` in the workspace. The ordinary
production package builds and has no net_core_test_* fixture imports.
