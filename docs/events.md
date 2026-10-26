# Readiness and cancellation (N3)

## Scope

The macOS implementation adds kqueue readiness, an OS-backed cancellation
factory, local readiness Futures and nonblocking Try operations. It does not
start hidden workers, change the compiler, invoke a second executable, or
queue borrowed I/O buffers. The next increment implements retained-buffer
transfers, numeric async connect and accept in [async-transport.md](async-transport.md).
Bounded asynchronous DNS is implemented in [async-resolver.md](async-resolver.md),
with its own explicit worker pool and caller-thread Poll. HTTP and TLS remain later
stages. Linux poll and Windows select adapters now share these contracts; see
[platform implementation and evidence](platforms.md).

The private C adapter is the OS boundary. Queue policy, resource ownership,
deadlines, cancellation priority and Future publication stay in Nyra's
NetTransport TU. Address/error/byte-view/deadline values remain in NetFoundation;
shared cancellation now belongs to NetTransport because its cell can own native
resources. All exports remain behind the package's public interfaces.

## Cancellation factories

- `None()` and the default token have no cell or native resource.
- `New()` allocates a shared atomic flag. It retains its existing portable,
  cooperative behavior, with cancellable native waits capped at 50 ms.
- `NewWakeable()` returns `Result<NetCancellation, NetError>`. On macOS/Linux it owns
  one nonblocking, non-inheritable AF_UNIX socket pair in the shared ARC cell.
  Windows uses a private loopback TCP pair. Native resource failure is returned;
  other unsupported platforms return NotSupported.
  It does not silently degrade to flag polling.
- `CanWakeWaiters()` distinguishes the two cancellation capabilities.

Cancel uses an acquire/release exchange. Only the first transition signals the
channel, after publishing the flag. The signal byte is never drained. Every
waiter registers the read endpoint, so the same token can wake multiple queues
or synchronous calls on separate socket owners. Cancelling before registration
leaves the endpoint readable for future registrations. The flag is checked
before and after native waiting; cancellation precedes timeout at each control
observation, including when data and cancellation arrive in one event batch.

The operation options or queued registration retain the token for the entire
wait. Cancel takes another local ARC reference while signaling. Both endpoints
close only when the last reference is released, so another thread cannot close
them while a retained token is signaling or waiting. Cancel is thread-safe on
separately retained copies; mutating the same token variable concurrently is
not supported. No global signal handler is installed. SO_NOSIGPIPE applies to
the internal socket pair as it does to macOS transport sockets.

Wakeable waits use the deadline budget without periodic cancellation polling.
They provide an OS wake mechanism, not a hard real-time latency guarantee.
Cancellation does not undo successful I/O and does not cancel blocking DNS.

## Readiness driver

`NetEventLoop.New(max_pending)` accepts 1..256 and returns a move-only driver.
The driver preallocates FastArray queue/scratch storage. Registrations that
would exceed its limit return WouldBlock without duplicating a descriptor.
This is explicit backpressure; capacity does not grow to accommodate callers.
Native event buffers are fixed at 512 events/changes on the call stack.
A detached completion batch is allocated only when publishing a completion and
is also bounded by max_pending. Each readiness Future has one ARC promise cell;
readiness-only entries allocate no payload. Transfer entries share the queue
capacity and have a separate byte budget described in
[async-transport.md](async-transport.md).

The public registrations are:

- `TcpConnection.WhenReadable` / `WhenWritable`.
- `TcpListener.WhenAcceptable`.
- `UdpSocket.WhenReadable` / `WhenWritable`.
- `AsyncResolver.WhenReady`, described in [async-resolver.md](async-resolver.md).

Each returns `Result<AsyncFuture<Result<Unit, NetError>>, NetError>`. The outer
Result reports validation, capacity or descriptor duplication failure. A
successfully returned Future completes with Ok(Unit) for readiness or a
NetError for cancellation, deadline, registration failure or driver closure.
It uses stdlib's local AsyncPromise/AsyncFuture and its continuation rules.

Each registration holds a close-on-exec duplicate of the socket plus its
operation options and promise. The duplicate shares the underlying socket;
it does not copy data. Closing/dropping the original socket owner does not
cancel this registration or immediately destroy the underlying socket. Cancel
its token or close/drop the driver to release a pending registration early.
Dropping a Future alone does not remove the registration. With no deadline or
cancellation, a non-ready registration remains owned until the driver closes.

`Poll(maximum_wait_ms)` drives one batch. Zero polls, -1 permits an unlimited
wait, values below -1 are InvalidArgument. An empty queue returns zero. The
actual wait is bounded by the earliest absolute deadline and flag-only token
polling budget. The queue scan selects the earliest absolute deadline; its
remaining milliseconds are computed immediately before the native wait, so
preparing the retained snapshot does not extend that deadline. EINTR returns
control to the caller; later Poll recomputes
budgets. Controls are checked again after waiting and before completing each
Future. A native queue failure leaves pending registrations owned for a later
Poll or Close and is reported by Poll.

For this first adapter, each Poll owns a temporary kqueue, registers its bounded
snapshot, collects events and closes the queue before returning. Socket and
wake descriptors are distinguished by identity. Repeated wake descriptors are
registered once and fan out to every matching request. Socket events match both
descriptor identity and the requested read/write filter; wake events match the
read filter only. EV_ERROR is mapped per
registration; EOF/hangup count as readiness and the following I/O reports the
actual result. This follows the native
[Apple kqueue contract](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/kqueue.2.html).
There is no retained kernel udata pointer, stale callback or registration
surviving queue close. Persistent registration optimization requires profiling
and does not change this lifetime contract.

Completed registrations are removed and their duplicates closed before any
promise is published. The completion batch is detached first, so a continuation
can enqueue, Poll or Close without invalidating the current scan. Close marks
the driver closed, detaches all entries, closes every descriptor, then completes
all pending Futures with Closed. Repeated Close is inert; move leaves the
source closed; language drop calls Close. Continuations may therefore run
during Close/drop and must not retain references to already-destroyed state.

## Affinity and nonblocking I/O

Register, Poll, Close, move/drop and all readiness Future access stay on one
caller-selected driver thread. Only Cancel on a retained token copy may run on
another thread. There is no ambient current driver or executor. Drive events
from the application's outer loop alongside its explicit stdlib frame executor:

```nyra
// Both values were created and remain on this same thread.
let completed: Result<int32, NetError> = driver.Poll(10);
executor.Pump(64);
```

The application's await continuation uses its explicit executor under the
existing language/stdlib contract. Poll publishes local promise completion;
it does not run an executor queue. Blocking that thread waiting for a readiness
Future without pumping the driver cannot make progress. A never-ending
RunUntilIdle drain can likewise starve socket event pumping; use frame budgets.

Readiness is advisory: another operation can consume the condition. Pair it
with `TcpConnection.TryRead/TryWrite`, `TcpListener.TryAccept`, or
`UdpSocket.TrySendTo/TryReceiveFrom`. Each Try method makes one nonblocking OS
attempt and returns WouldBlock on no progress/interruption; re-register then
retry. Stream partial progress/EOF and datagram empty/truncation semantics are
the same as their synchronous counterparts. Readiness itself transfers no data,
accepts no connection and borrows no payload buffer. The caller owns buffers
and keeps their borrows valid only for each immediate Try call. Do not use the
synchronous waiting methods in a driver continuation if doing so would block
the driver thread.

An operation's absolute deadline/token must also be checked immediately before
each Try call. A readiness completion cannot guarantee that the deadline remains
valid after the continuation was scheduled. The retained transfer layer enforces this retry contract and owns its buffers;
see [async-transport.md](async-transport.md).

## Initial readiness-increment compilation evidence and open acceptance

The native C adapter compiles with C11/O2/Wall/Wextra/Werror on macOS arm64.
The package passes native Core/O2 precompilation with four backend workers.
Generated archives, command receipts and logs are in ignored
`cache/net-core-macos-events/`. Public precompile interfaces retain the driver's
copy deletion; the Nyra archive's private native imports are supplied by the
matching C archive. The final native build took 0.124 seconds and Core/O2
precompilation took 5.045 seconds. All 23 private native imports and all
net_core-owned symbol references resolve in their matching archives. A macOS
arm64 relocatable partial link of both archives succeeds without diagnostics;
this leaves stdlib/system imports for the final application link. Source and
compiler hashes are recorded with the symbol inventory.

These receipts identify the initial readiness-only increment; the subsequent
transfer increment has its own receipts in [async-transport.md](async-transport.md).
These are compilation/interface/symbol checks. No behavioral or network cases
have been added or run for this increment. Pending acceptance includes shared
wake fanout, cancellation-before-registration, simultaneous readiness/control
expiry, token last-drop lifetime, descriptor reuse, stale readiness, capacity
backpressure, continuation reentry, pending Close/drop, partial I/O/EOF and
idle/event/deadline CPU behavior. Do not infer runtime acceptance from archives.

## N3 control and readiness review increment

The subsequent static review tightened two boundaries: read/write filter
identity in native event fanout, and conversion of the earliest deadline after
Nyra snapshot preparation. These changes add no public API or native ABI symbol.
The current driver normally owns a separate duplicate for each registration;
filter matching also makes the native batch contract correct for a shared
descriptor observed in both directions.

macOS arm64 native C compilation with Wall/Wextra/Werror completed in 0.297
seconds, and Core/O2 package precompilation with four workers completed in 6.228
seconds. All 23 private native imports and net_core-owned references resolve;
the relocatable partial link succeeds. Receipts, source/compiler hashes and
generated artifacts are under ignored `cache/net-core-macos-n3-lifecycle/`.
No behavioral tests were added or run. Direction fanout, deadline expiration
during snapshot preparation and the resource/reentry cases above still need
behavioral acceptance.

## Subsequent controlled runtime acceptance

The macOS N3 suite and its isolated case replays pass 37/37 with zero skips.
It exercises native read/write direction matching, wakeable cancellation fanout,
registration after cancellation, readiness deadlines, task cancellation/move/drop,
Close callback task-state inspection and Poll callback reentry. DNS notifications
are driven with query deadlines and distinct query controls. The idle DNS sample
waited about 216 ms while using about 2.0 ms of process CPU across its threads.
This measures one local run; it is not a bound on scheduling/wake latency.

The exact receipt, per-case CPU/RSS and remaining fault coverage are documented
in [tests/README.md](../tests/README.md). Forced native wait/duplicate failure,
active-registration descriptor reuse and expiry injected specifically during
snapshot preparation remain open.

## Cross-platform acceptance update

The current shared N3 suite passes 38/38 cases plus 38/38 isolated replays on each
of macOS arm64, Linux x86_64 and Windows x86_64. Android arm64/x86_64 and iOS
device/Simulator arm64 pass native compile/link checks and Nyra precompilation.
Earlier macOS-only counts above are historical. See [current receipts and scope](../tests/README.md),
[platform implementation](platforms.md) and [mobile integration](mobile.md).
