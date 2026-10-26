# Bounded asynchronous DNS

## Scope and API

`AsyncResolver` owns an explicit fixed pool of public stdlib `Thread` workers.
The package implements queue policy and ownership in Nyra; the existing private
OS adapter still performs `getaddrinfo`. The initial worker increment reused that
adapter; the notification increment adds one private bounded notification-drain
function. There is no compiler feature, HTTP client or TLS wrapper in this layer.

`New(worker_count, max_pending)` accepts 1..8 workers and
worker_count..256 retained slots. It creates every worker during construction;
registration never creates a thread. Mutex, condition-variable or worker startup
failure returns System. Partial startup marks the pool closed and wakes already
started workers so they exit. No live resolver is returned on startup failure.
On macOS, Linux and Windows construction also creates a nonblocking notification
socket pair; native failure is returned before starting workers. WhenReady uses
the matching event backend. Linux/Windows Nyra runtime acceptance remains open;
see [platform evidence](platforms.md).

`ResolveAsync(host, port, family, max_results, options)` returns
`Result<AsyncFuture<NetResolution>, NetError>`. It validates hostname size
(1..1024 bytes), ASCII/no-NUL input, port, family, result bound (1..4096) and
already-expired controls before registration. A full pool returns WouldBlock.
Malformed numeric literals and OS name failures are completed query errors,
using the synchronous Resolver's parsing/error semantics.

Each accepted query deep-copies only the visible hostname bytes. It never
retains a borrowed caller buffer, a larger source-string root or a caller arena.
Query and worker state use the process heap. Dropping the original hostname or
the returned Future does not cancel accepted work. Cancellation tokens are
retained as independent shared copies through lookup/retirement.

## Worker and completion boundaries

The shared pool holds a fixed array of private query references. A mutex protects
slot occupancy, the round-robin claim cursor, claim flags and shutdown. Idle
workers sleep on a condition variable, rechecking their predicate after wake.
At most worker_count calls can be executing; there is no fallback executor,
thread-per-query path, unbounded waiting queue or retry queue.

Workers check controls immediately before lookup and publish only immutable
results. They clear the hostname and store the completed result before a release
store to the done atomic. The owner acquires that flag before reading results.
Workers never invoke a local Future continuation or touch a local Promise,
executor or the public resolver object's address. Local pending entries retain
those objects separately on the caller thread.

`NetResolvedAddresses` shares a closed ARC-backed endpoint array. Len reports
initialized entries; Get copies one inline endpoint and checks its index. No
mutable pointer or array is exported. Copying a completed result retains storage;
the resolver never changes it afterward. Query errors contain no addresses.

## Driving progress and control races

`Poll()` is nonblocking. Call it periodically from the same application thread
that registered queries, alongside NetEventLoop.Poll and a bounded executor pump.
It returns the number of newly published Futures. It does not pump socket events
or an executor itself, and an await cannot implicitly drive it. Use a scheduled
outer loop with a bounded wait; do not spin on Poll waiting for OS DNS.

### Readiness integration

WhenReady(driver, options) registers an advisory progress Future in the same
caller-thread NetEventLoop. A pool owns one notification pair, not a pair per
query. Each registration retains a duplicate of the read descriptor and the
private pool state; there is at most one pending registration for this pool in
that driver. No retained queries or duplicate registration returns WouldBlock.
Dropping a notification Future does not remove its driver registration.

Workers publish done with release ordering before signaling the channel. The
driver checks query atomics/control state before and after waiting. On readiness,
call resolver.Poll to publish query results, inspect those Futures and rearm
WhenReady if work remains. Notification completion does not itself publish any
query result. Notifications may be coalesced or stale, including a late byte from
a query that the owner has already retired. They are never a query identifier.

The earliest unpublished query deadline also bounds the driver's native wait.
Unpublished query cancellation uses a 50 ms cooperative cap, including wakeable
query tokens, because a single registration may aggregate many distinct tokens.
The notification's own options are independent; its own wakeable cancellation
token is registered directly and retains active wake behavior. Query control
expiry produces advisory readiness; resolver.Poll supplies the query's actual
Cancelled/TimedOut result. Already-published cancellations do not keep triggering
ready notifications while a blocked OS lookup retains its physical slot.

With no cancellable queries, application work or deadlines requiring a periodic
wake, the outer loop can wait indefinitely in driver.Poll(-1) for DNS/socket
progress. An executor with runnable work or an application with frame deadlines
still needs its normal bounded wait policy. No idle-CPU improvement is claimed
without runtime measurements.

resolver.Poll drains the resettable channel before scanning queries. A completion
racing that scan is either observed there or leaves a notification for a later
wait. Drain work is bounded to eight nonblocking reads; any remaining bytes stay
readable. Late/stale bytes may cause another advisory wake, not lost query state.
Sticky cancellation-token channels are separate and are never drained.

Poll checks cancellation before deadline expiration. A control failure observed
before local publication wins over an unpublished worker result, including a
result that completed just before that Poll. A published result never changes.
The worker also checks controls before entering lookup, but a cancellation after
that check cannot forcibly interrupt an OS resolver call.

Cancelling/timing out an unclaimed job retires it immediately under the queue
mutex. A running job's Future can complete with its control error immediately
on Poll, while its physical slot remains charged until the worker returns and a
later Poll retires it. PendingCount includes those retained running jobs. A retry
cannot bypass the physical bound by repeatedly cancelling blocked DNS calls.
An indefinitely blocked OS resolver can therefore exhaust this pool's capacity;
the pool does not pretend that cancellation stopped that call.

Retirement and all queue mutation happen before the detached completion batch
is published. Continuations may enqueue, Poll, move or Close on the same thread
without invalidating a scan. Register/Poll/Close, move/drop and Future access
have local thread affinity. Only Cancel on a separately retained token copy is
cross-thread safe.

## Shutdown and memory bounds

Close makes the public owner inert, detaches local pending state, marks the
shared pool closed, discards queue slots and wakes idle workers. It then publishes
Closed for each unpublished Future on the caller thread. Repeated Close is inert;
move transfers ownership and leaves its source closed. No worker retains a raw
pointer into the movable public owner.

Close/drop does not join workers or block on OS DNS. Running workers retain the
private pool/query state until lookup returns, then exit on the closed flag.
Only the last worker/owner/notification ARC release destroys the shared mutex,
condition variable, notification pair and private storage. This is delayed
reclamation of bounded in-flight
work; Close is not a guarantee that all OS resolver resources have already gone.
Repeatedly creating new pools is a caller allocation policy and is not covered
by one pool's limits. No process-global cap is claimed.

Close signals the notification channel. A pending notification observes Closed
on the next driver Poll, even if the owner no longer exists; the retained private
state makes that observation safe. Closing only the event loop retires its
notification with Closed and does not stop the independent resolver or its query
Futures. The notification descriptor and pool reference are released before
callbacks run, under the ordinary event-loop retirement contract.

Limits bound package-held query counts, copied hostname bytes and returned
endpoint counts. Temporary conversion arrays are also bounded by max_results;
OS resolver internals and thread stacks are outside that accounting. Results
retained by consumers after completion are outside pending capacity. Query cells
contain no local Future state, so final worker cleanup cannot destroy a local
Promise on the wrong thread.

## Build evidence and pending acceptance

macOS arm64 Core/O2 precompilation uses four backend workers. Native C compilation,
archive symbol inventory and a relocatable partial link are recorded under
ignored `cache/net-core-macos-resolver/`. Those checks establish compilation and
link-input consistency, not behavioral acceptance. This increment changes no
bootstrap compiler or installed SDK.

The final Core/O2 precompile completed in 5.706 seconds. All 23 private native
imports resolve in the native archive; net_core-owned references also resolve,
and the relocatable partial link succeeds. The staged public interface retains
AsyncResolver's deleted copy operator. Compiler/source hashes and exact commands
are recorded in `compile-final.json` and `symbol-inventory.json` in that cache.

Required behavioral acceptance includes startup failure, fixed-worker bounds,
slot/backpressure limits, copied-host lifetime, immutable result copies, queued
and running cancellation/timeouts, done/control races, late completion, physical
slot retention, Future-only drop, pool move/drop/Close, worker exit and callback
reentry. Use controlled DNS fixtures for failure and delay scenarios. Linux and
Windows acceptance remains pending. No behavioral tests were added or run in
this increment.

### Notification increment build evidence

The notification increment adds WhenReady, shared-pool notification ownership,
aggregate query-control wait budgets and one private native drain function.
macOS arm64 native C compilation with Wall/Wextra/Werror completed in 0.126
seconds. Final Core/O2 precompilation with four backend workers completed in
5.959 seconds. All 24 private native imports and net_core-owned references
resolve, and the relocatable partial link succeeds. The staged public interface
contains WhenReady and retains the resolver's deleted copy operator.

Commands, compiler/source hashes, symbol inventory and build output are in
ignored `cache/net-core-macos-resolver-notification/`. No notification behavior
tests or CPU measurements were run. Completion/drain races, coalescing, aggregate
query controls, late worker completion, notification admission and both resolver
and driver shutdown orders still require behavioral acceptance.

### Subsequent controlled runtime acceptance

The macOS N3 suite passes 37/37 cases plus 37/37 isolated runtime replays with
zero skips. Resolver cases cover controlled success/failure, hostname copy and
result sharing, worker/slot bounds, queued and running cancellation, retained
running slots, query deadlines and distinct query cancellation tokens waking an
otherwise blocking driver. Notification coverage includes duplicate admission,
100 rounds of paired-query drain/scan scheduling, move, Close, dropped Futures
and event-loop-only Close. A late worker is released after owner Close and the
case waits for the descriptor baseline to recover. A separate child refuses
new descriptors and verifies notification-channel startup fails cleanly.

In isolated runtime samples, the idle notification case took 0.215660 wall
seconds and 0.001978 CPU seconds, with a 2,080,768-byte process peak RSS. The
distinct-query cancellation case took 0.061210 wall seconds and 0.001996 CPU
seconds. CPU includes all threads in that test child and excludes compilation;
RSS is not live heap usage. These are individual local observations.

The production package was also rebuilt and contains no test fixture imports.
Receipts and source/compiler hashes are in ignored
`cache/net-core-macos-n3-final-06/acceptance.json`. Thread creation failure after
partial worker startup and other explicit fault/platform gates remain open in
[tests/README.md](../tests/README.md).

## Cross-platform acceptance update

The current shared N3 suite passes 38/38 cases plus 38/38 isolated replays on each
of macOS arm64, Linux x86_64 and Windows x86_64. Android arm64/x86_64 and iOS
device/Simulator arm64 pass native compile/link checks and Nyra precompilation.
Earlier macOS-only counts above are historical. See [current receipts and scope](../tests/README.md),
[platform implementation](platforms.md) and [mobile integration](mobile.md).
