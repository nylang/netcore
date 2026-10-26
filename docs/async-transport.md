# Retained asynchronous transport on macOS

## Implemented layer

`interface/async_transport.ni` adds immutable owned bytes, TCP/UDP transfer
Futures, asynchronous numeric TCP connect and asynchronous accept. The
NetTransport TU implements queue ownership, state transitions and completion
publication in Nyra. It reuses the existing private nonblocking OS primitives;
no compiler changes, protocol wrapper, background worker or new C ABI is needed.

The macOS controlled N3 suite now provides behavioral evidence for retained
transfers and connection tasks; see [tests/README.md](../tests/README.md) for the
37 accepted cases and remaining fault coverage. The compilation records below
describe the earlier increments. Asynchronous hostname resolution is implemented separately
in [async-resolver.md](async-resolver.md). HTTP, TLS/HTTPS and dependency downloads
are subsequent work.

## Shared immutable payloads

`NetBuffer.CopyFrom(NetBytes)` copies a borrowed range once into a
language-owned ARC array. The input only needs to survive that call. Copying
the resulting value or making a nonempty Slice retains its root without copying
bytes. The closed layout exposes no writable view. Bytes() returns a borrowed,
read-only NetBytes; retain a NetBuffer value for that entire borrow.

Default and empty slices retain no allocation. Bounds use subtraction to avoid
overflow. CopyFrom rejects sizes above int32 max before allocating. Len reports
visible bytes; RetainedBytes reports the full allocation held by a slice.
A small slice can retain a large root. CopyFrom(slice.Bytes()) can explicitly
compact it when that is preferable to retaining the root.

Receive buffers are allocated privately at enqueue and are not published until
the operation completes. Only initialized received bytes become visible through
the returned NetBuffer slice. No queued receive points into a caller's stack,
FastArray or mutable ByteBuffer. ARC/new/drop own all backing allocations; there
is no product Free protocol.

## Queue and memory bounds

NetEventLoop.New keeps its existing 1..256 operation capacity and now defaults
to 16 MiB of pending payload backing. NewWithLimits accepts a nonnegative byte
budget, including zero for readiness/connection-only workloads. PendingCount
includes readiness, transfers, connects and accepts. RetainedBytes reports
payload backing still charged to pending transfers.

A receive charges its requested allocation size. A send charges the entire
NetBuffer backing, including the hidden part of a slice. Shared roots are
charged per pending operation conservatively. Admission checks compare cost to
remaining budget before descriptor duplication or receive allocation. Capacity
or budget exhaustion returns WouldBlock; neither limit grows automatically.
The queue has no hidden worker/task backlog.

The budget covers pending payload backing, not ARC headers, fixed queue/native
scratch, Future metadata or buffers retained by consumers after completion.
NetBuffer.CopyFrom is caller-owned allocation outside the driver. After a
receive completes its buffer can still retain the requested capacity even if
fewer bytes arrived. These are explicit lifetimes, not process-wide heap limits.

One queued operation per socket direction is allowed within a driver. A second
queued read, write, receive, send or accept on the same owner/direction returns
WouldBlock. Reads and writes may proceed independently. Readiness observers
remain advisory and can coexist. Do not issue a synchronous/Try operation in
the same direction while a transfer is pending, including through another
driver. The duplicate shares socket state; it does not serialize external I/O.
Numeric descriptor reuse can conservatively reject a new operation until an
older matching registration is retired; it cannot redirect that old operation
to the new socket because its own duplicate remains retained.

## Transfer completion and progress

ReadAsync, ReadExactlyAsync, WriteAsync, WriteAllAsync, ReceiveFromAsync and
SendToAsync return Result<AsyncFuture<NetTransfer>, NetError>. The outer Result
reports failure before enqueue, including expired controls, validation,
backpressure and descriptor failure. Accepted operations start on a subsequent
Poll. Future.GetResult uses the ordinary local AsyncError pending/misuse
contract. Its completed NetTransfer reports:

- bytes_transferred: committed bytes, including progress before a later error.
- buffer: initialized received bytes; sends leave this empty.
- sender: present only on a successful UDP receive.
- eof: true only when an actual nonempty TCP read encounters stream EOF.
- error: nil on success, otherwise NetError without losing prior progress.

ReadAsync completes on its first positive partial read or EOF. ReadExactlyAsync
accumulates until the requested count; early EOF produces UnexpectedEof,
eof=true and the initialized prefix. UnexpectedEof is appended to the error
enum, preserving existing category ordinals. Zero-sized TCP requests complete
without I/O and without claiming EOF.

WriteAsync completes after the first positive accepted chunk. WriteAllAsync
retains the immutable payload and resumes at the committed offset. A failed or
cancelled write-all reports the accepted count and never resends that prefix.
Callers that need to retry the suffix must retain their input buffer themselves;
the completion does not retain sent payloads. An OS zero write for a nonempty
request terminates with ConnectionAborted instead of spinning forever.

UDP operations preserve one-message semantics. Empty sends still invoke the OS;
empty receives still consume a datagram. Truncation reports MessageTooLarge,
consumes/discards that datagram and exposes no uncertain prefix. A successful
empty UDP receive has zero bytes, a sender and eof=false.

Each pending operation makes at most one OS attempt per Poll. TCP attempts are
capped at 64 KiB, bounding per-operation work before other entries can progress.
WouldBlock/interruption preserves state and registers for the next readiness
batch. The absolute deadline survives all retries. Controls are checked after
native waiting and immediately before each attempt. Successful I/O wins that
observation race; later cancellation cannot undo committed bytes. A multi-step
operation observes it before its next attempt and returns prior progress.

Each operation retains its duplicated socket, token and payload until terminal
completion. Dropping the original socket owner or send-buffer value is safe;
closing the original owner does not cancel the duplicate. Dropping only the
transfer Future does not cancel an operation. Use its cancellation token or
close/drop the driver. Driver Close reports Closed while preserving accumulated
transfer progress and initialized receive bytes.

## Numeric connect and accept tasks

DialAsync queues a new nonblocking socket, using a numeric endpoint. The first
Poll calls connect; later write readiness checks SO_ERROR. AcceptAsync retains
a listener duplicate and attempts accept on read readiness. Neither method
performs blocking hostname lookup.

Both return a move-only TcpConnectionTask inside Result. Keep the Result alive
while borrowing its task with get_ref_if, or explicitly move the successful
value out; do not use a copying get_if extraction. Its FutureHandle returns a
local Future<Result<Unit, NetError>>, which carries completion status without copying
a socket owner. After successful completion, TakeConnection transfers the
connection out exactly once. Before completion it returns WouldBlock; after a
successful take it returns Closed. On failed completion it returns that failure.
Default and moved-from tasks are inert and report Closed.

Cancel() requests cancellation of a pending task on the driver thread. It returns
true only for the first pending request; default, moved-from, already-cancelled
and completed tasks return false. A completed untaken connection remains owned
and takeable. Cancellation does not publish synchronously: the next Poll closes
the pending registration before completing its Future with Cancelled. Moving or
dropping the task preserves an already-recorded request. Closing the driver
publishes Closed for unpublished operations, including cancelled ones.

One shared driver helper checks controls before waiting and again before each
attempt. External cancellation and task cancellation precede timeout; timeout
precedes abandonment without an explicit cancellation request. A result already
prepared in a detached completion batch is terminal: Cancel returns false even
if that task's Future callback has not yet been published. This avoids reversing
a committed connection result during another continuation's reentry.

The driver owns the connecting descriptor until success. It transfers that
ownership into the task cell before removing the registration, so it is not
closed during normal retirement. Accepted descriptors are configured before
publication and become task-owned immediately; the listener duplicate is
retired separately. A cell destructor closes an untaken connection. Taking
resets the cell's private POD state before creating the public connection owner.
There are never two independent owning destructors around one descriptor.

Dropping a pending task marks it abandoned. The next Poll detects abandonment
without waiting, or driver Close retires it. A task's Future remains copyable
but does not retain or expose a connection owner. The queue retains the cell
until retirement, so abandonment cannot leave a dangling task pointer. This
cleanup is cooperative with the local driver; an undriven driver continues to
own its pending registrations until Close/drop.

## Affinity, completion publication and use

All task, Future, registration, move/drop and driver operations stay on one
caller-selected thread. Cross-thread Cancel uses a separately retained token
copy. There is no ambient driver and no thread per operation. Drive Poll from
the outer application loop beside its explicit stdlib executor, as described
in [events.md](events.md). An await does not implicitly pump network events.

An enqueue fragment for retained bytes is:

```nyra
// connection, driver and options already exist on the driver thread.
let source: NetBytes = NetBytes.FromString("hello");
let copied: Result<NetBuffer, NetError> = NetBuffer.CopyFrom(source);
let failure: NetError? = copied.get_if<NetError>();
if failure != nil { /* handle registration failure */ }
else {
  let payload: NetBuffer = (copied.get_if<NetBuffer>()) as NetBuffer;
  let queued: Result<AsyncFuture<NetTransfer>, NetError> =
    connection.WriteAllAsync(driver, payload, options);
  // Handle queued's outer error or retain its Future, then keep pumping driver.
}
```

This illustrates ownership/API shape; it is not a standalone application or a
runtime-accepted example. An application's external loop must handle Poll
errors, pump its executor and inspect completed NetTransfer.error/progress.

On every terminal path the driver detaches completion records, retires the
registration's descriptor and releases its byte-budget charge before publishing
promise completion. All native event registrations are already gone. A
continuation may enqueue, Poll, move or Close without invalidating the current
scan. Close detaches all pending state, closes every registration and marks all
connection task cells terminal before publishing any completion. A continuation
that calls another closing task's TakeConnection sees Closed, and Cancel returns false. Future
publication itself remains sequential across the detached batch. Returned buffers become consumer-owned; pending
operations never mutate a published buffer afterward.

ShutdownWrite is synchronous: it sends FIN after bytes already accepted by the
OS. Finish pending WriteAsync/WriteAllAsync Futures first; payload still retained
by the driver has not been accepted by the OS and is not flushed by ShutdownWrite.

## Compilation evidence and remaining acceptance

Generated artifacts and receipts live in ignored `cache/net-core-macos-transfers/`.
The native adapter compiles with C11/O2/Wall/Wextra/Werror. The Nyra package
passes Core/O2 precompilation with four backend workers; public precompile
interfaces preserve TcpConnectionTask's copy deletion. Archive inspection and a
relocatable partial link check the package/native link inputs. The final native
build took 0.270 seconds and Core/O2 precompile took 5.574 seconds. All 23 native
imports and all net_core-owned symbol references resolve; the partial link
succeeds without diagnostics. Receipts include compiler/source hashes and the
exact commands. No compiler bootstrap SDK is promoted by this package work.

These checks do not establish network behavior. Required acceptance includes
partial/error/cancelled transfers, exact EOF, zero TCP/UDP operations, UDP
truncation, deadline fairness, same-direction overlap, byte-budget boundaries
and sliced-root charging. Resource cases include caller-buffer drop, Future-only
drop, driver Close after partial progress, task abandonment, untaken/taken task
drop, repeated take, failed connect/accept, descriptor reuse and reentrant
completion. No behavioral tests have been added or run in this increment.

## Connection cancellation and shutdown increment

The subsequent increment adds task-local Cancel, uses one control-check helper
before/after waiting, and prepares every closing connection task's terminal
state before publishing the first Close callback. It also documents that
ShutdownWrite does not flush asynchronous payloads still waiting in the driver.

macOS arm64 native compilation completed in 0.328 seconds and Core/O2 precompile
with four workers completed in 5.808 seconds. All 23 private native imports and
net_core-owned references resolve, and the relocatable partial link succeeds.
The staged public interface includes Cancel and preserves deleted task copying.
Receipts and compiler/source hashes are in ignored
`cache/net-core-macos-task-cancellation/`. No behavioral tests were added or run;
task cancellation, control ordering, Close callback inspection and queued-write
shutdown still need runtime acceptance.

## Subsequent controlled runtime acceptance

The macOS N3 suite passes 37/37 cases with zero skips, followed by 37/37 isolated
runtime replays. Transfer coverage includes 200,000 patterned bytes with exact
byte comparison, bounded first-Poll work, partial exact-read EOF, partial progress
on cancellation/Close, zero TCP/UDP differences, sliced-root byte charges and
compaction. Original socket Close and Future-only drop preserve accepted work.
Task cancellation/move/drop, late cancellation, control ordering, Close task-state
inspection and completion callback reentry are exercised. FD recovery is checked
after 64 TCP lifecycle rounds and 64 wakeable-token lifecycle rounds.

The runner also caught a test scheduling assumption: a completed sender does not
guarantee that a receiver already committed its prefix. Partial-progress cases
now wait for the recorded receiver progress before requesting cancellation/Close;
they still assert the returned prefix and committed byte count.

The independent large-transfer sample used 0.011746 wall seconds, 0.002062 CPU
seconds and a 2,654,208-byte process peak RSS. This is a single local case sample,
not a throughput benchmark or live-heap measurement. Receipts are under ignored
`cache/net-core-macos-n3-final-06/acceptance.json`; remaining fault/platform gates
are explicit in [tests/README.md](../tests/README.md).

## Cross-platform acceptance update

The current shared N3 suite passes 38/38 cases plus 38/38 isolated replays on each
of macOS arm64, Linux x86_64 and Windows x86_64. Android arm64/x86_64 and iOS
device/Simulator arm64 pass native compile/link checks and Nyra precompilation.
Earlier macOS-only counts above are historical. See [current receipts and scope](../tests/README.md),
[platform implementation](platforms.md) and [mobile integration](mobile.md).
