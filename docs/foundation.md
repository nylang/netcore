# Networking foundation

## Scope and placement

The first implementation supplies address/endpoint values, error categories,
borrowed byte ranges, deadlines and shared cancellation. It depends only on the
public `stdlib:stdlib.ny` barrel. There are no socket system calls, HTTP parsers,
TLS bindings or compiler dependencies in this stage.

`net_core.ny` exports `interface/foundation.ni`; closed bodies belong to the
`NetFoundation` module in `private/foundation.ny` with explicitly listed parts.
One module remains one TU. Future OS adapters stay private in this repository.
The compiler frontend and CodeGen do not gain networking package special cases.

## Address rules

- `IpAddress` owns 16 inline octets, a family and a numeric interface scope.
  Parsing, copying, comparing and reading octets do not allocate memory.
- Default addresses have `IpFamily.Unspecified` and are invalid. This differs
  from the valid wildcard addresses `0.0.0.0` and `::`.
- IPv4 accepts exactly four decimal octets in 0..255. Multi-digit leading-zero
  octets, integer/octal/hex shorthand and whitespace are rejected.
- IPv6 accepts 8 hexadecimal groups, one optional `::`, and a dotted IPv4 tail
  consuming the final two groups. Compression must replace at least one group.
  Embedded IPv4 tails follow the same strict decimal rule as IPv4 literals.
- A trailing `%<uint32>` stores a numeric IPv6 interface scope. Interface names
  require OS interface lookup and are not silently interpreted as numeric scopes.
  Scope zero is omitted when formatting; nonzero scopes participate in equality.
- IPv6 output is lowercase, without leading group zeros. The longest run of two
  or more zero groups is compressed; ties select the first run. Mapped IPv6 uses
  `::ffff:` followed by dotted decimal. Other IPv6 uses hexadecimal groups.
  Address syntax follows [RFC 4291 section 2.2](https://www.rfc-editor.org/rfc/rfc4291.html#section-2.2);
  formatting follows [RFC 5952 sections 4 and 5](https://www.rfc-editor.org/rfc/rfc5952.html#section-4).
- Mapped IPv6 remains IPv6; equality does not automatically unmap it to IPv4.
- `NetEndpoint` uses a host-order port. Its parser accepts `IPv4:port` and
  `[IPv6%scope]:port`. Port zero supports ephemeral binding. Ports outside
  0..65535, missing ports and unbracketed IPv6 endpoints are rejected. Parsing
  never invokes DNS. Literal endpoint input is not an HTTP URI parser.
- Formatting returns an ordinary owned string. A temporary `FastString` builder
  owns its work buffer; no view of that temporary escapes.

## Bytes and allocation ownership

`NetBytes` and `NetMutableBytes` are explicit borrowed views, not owning buffers
or replacements for the standard library's weak `Span<T>`. Copies retain no
storage. `FromRaw` validates metadata, not memory accessibility. The caller
proves accessibility, lifetime and (for writable ranges) exclusive mutation.
`FromString` likewise does not retain the string. `Slice` validates start/length
using subtraction, avoiding signed overflow in an unchecked start+length sum.

Owners can be fixed stack arrays, `FastArray<uint8>`, `ByteBuffer`, or memory
from an injected arena/stack allocator. The storage owner must survive the
entire operation. Future asynchronous operations must retain an owner or finish
before the borrowed storage is released; merely queuing a raw view is invalid.
No public malloc/free contract is introduced.

## Time and cancellation

`NetDeadline` is a small value using monotonic nanoseconds supplied by its caller.
Every observation uses the same monotonic clock origin. The deadline code does
not read a wall clock, sleep or assume that `Instant` ticks are nanoseconds.
A hosted adapter can obtain nanoseconds via
`Instant.Now().ToDurationSinceEpochish().ToNanoseconds()`; raw `ToTicks()` is not
an interchangeable value. A freestanding adapter can supply its own clock.

Default/Never is unlimited. At(0) and a zero-duration After are finite and
already expired at the corresponding now. After saturates on uint64 overflow.
Remaining budget never underflows. Native wait milliseconds round positive
fractions up, clamp to int32 max, and use -1 only for unlimited waits. OS wait
loops must recompute remaining time after interruption or spurious readiness;
reusing the original duration would extend the overall operation deadline.

`NetCancellation.New()` allocates one ARC-owned atomic cell. Value copies share
it. Cancellation is sticky: Cancel stores with release ordering and IsCancelled
loads with acquire ordering. None/default allocates nothing and is inert.
There is no reset, callback registration or OS-wait wakeup in this stage. An
operation can only observe cancellation when it polls the flag. Native event
integration must add an actual wake mechanism before claiming prompt cancellation
of blocked socket operations.

`NetOperationOptions.Check(now_ns)` gives cancellation precedence over timeout
when both conditions are visible at that observation. Success carries Unit.

## Failures and resource lifetimes

Public APIs return `Result<T, NetError>` with a stable category and preserved
native error/resolver code. Messages are immutable strings, not OS-dependent
formatted heap allocations. The OS adapters will map codes once at the private
boundary and capture the native code before cleanup can overwrite it.

Future socket values will own descriptors, forbid copying, transfer ownership
on move, and close on drop. Explicit Close must be idempotent. A borrowed handle
must not close the descriptor. Failed construction and failed async registration
must close any resource not successfully transferred to an owning value.

## Implementation evidence and pending acceptance

The source passes native semantic checking (90 modules, zero failures) and
Core/O2 precompilation with four backend workers (7.138 seconds) on macOS arm64,
using the compiler built after the package extraction. Generated objects,
archive, metadata and logs live under ignored `cache/net-core-foundation/`.
These are compilation checks, not behavioral or cross-platform acceptance.

Pending behavioral coverage includes IPv4 rejection boundaries, IPv6 zero-run
and dotted-tail combinations, scope/port limits, text round trips, empty/null
byte views and slice overflow, deadline saturation/rounding, and cancellation
sharing across threads. DNS/TCP/UDP, native pollers, HTTP, TLS/HTTPS and remote
dependency fetching remain subsequent roadmap stages.
