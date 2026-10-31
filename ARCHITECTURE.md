# net_core module architecture

Network values, resource owners, socket scheduling and DNS workers have explicit
boundaries. The OS C ABI remains private and no protocol layer is introduced.

- `private/error.ny`, `address.ny` (with `endpoint.ny`), `buffer.ny` and `deadline.ny`
  own errors, address values, borrowed byte views and deadline arithmetic. The
  foundation entry only assembles these independent value modules.
- `private/native_abi.ni` defines the existing pointer-only native records and
  foreign calls. `native_bridge.ny` translates immutable native/product values;
  it does not own sockets, pending operations or DNS workers.
- `private/cancellation.ny` owns cancellation wake resources, monotonic admission
  checks and the clock. Its wake-handle borrow never transfers ownership.
- `private/owned_buffer.ny` owns retained payload storage, slicing and bounded
  mutable borrows. Socket scheduling uses buffer operations instead of ARC fields.
- `private/resolver.ny` owns synchronous OS name resolution.
- `private/transport.ny` owns socket descriptors, connection tasks, pending socket
  operations and retirement-before-completion ordering. Socket, connection and
  transfer parts intentionally share this single descriptor/queue state machine.
- `private/async_resolver.ny` owns worker threads, pool slots and DNS query results.
- `private/readiness.ni` is a value-only producer/loop contract. DNS supplies a
  retained readiness closure; the loop owns a duplicate wake descriptor and queue
  admission. The loop cannot inspect worker mutexes, slots or pool layouts.

DNS depends on loop registration operations. The loop has no dependency on the
DNS implementation and retains only the closure and immutable probe result. Probe
closure lifetime covers pending registration through retirement. Cancellation,
deadline precedence, duplicate-handle ownership and result publication remain the
existing contracts. Public contract tests are independent selftest TUs; only the
bounded-write queue inspection remains a private owner-side unit test.


## 1.0.5 type ownership

The native bridge extends NetNativeError/NetNativeAddress with product conversion,
and NetEndpoint/IpFamily with private ABI conversion. NetEventLoop owns queue
admission, direction checks, registration and retirement. NetPendingOperation
owns control precedence and step/completion values; NetOperationCompletion
publishes only after queue detachment. NetResolverPool owns mutex-protected slot
selection, readiness, worker execution and stop. Worker closures retain an ARC
owner throughout each borrowed method call. No DNS layout enters the event loop.

NetSocketWait retains immutable controls but borrows the descriptor for a bounded
synchronous wait; it cannot close it. NetNumber owns bounded decimal admission,
IpAddress owns partial IPv4 parsing/word projection, and NetAddressWriter owns
canonical text output. Shared integer formatting supplies decimal text. Generic
single-byte hex classification stays a small documented pure-function exception.

Test-only constructors/polling extensions remain in the fixture TU, outside the
product face. Immutable address/DNS/descriptor expectations own their checks.
Assertions use the shared ntest protocol. Functions that intentionally exercise
return-time resource/Future drop have specific local lint reasons; there is no
package-wide suppression. The native C ABI declarations and adapter bodies are
unchanged. Matching 1.0.5 source runtimes are required for integer formatting.

Generic monotonic sampling uses stdlib Instant/Duration directly. NetClock and
its dummy storage field are removed; NetOperationOptions.CheckNow owns transport
admission policy over that existing clock capability. No replacement namespace
or new provider clock is introduced.
