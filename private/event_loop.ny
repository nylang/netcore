/** @brief Bounded caller-thread readiness and retained-transfer driver for macOS. */
part of NetTransport;

enum NetOperationKind {
  Readiness, TcpRead, TcpReadExactly, TcpWrite, TcpWriteAll,
  UdpReceive, UdpSend, TcpDial, TcpAccept, ResolverReady,
}
// Descriptor fields are POD. The driver alone retires registrations; bookkeeping
// copies never create another descriptor owner. Dial can explicitly hand off one.
struct NetPendingOperation {
  handle: intptr;
  socket_key: intptr;
  writable: bool;
  options: NetOperationOptions;
  kind: NetOperationKind;
  attempted: bool;
  promise: AsyncPromise<Result<Unit, NetError>>;
  transfer_promise: AsyncPromise<NetTransfer>;
  buffer: NetBuffer;
  endpoint: NetEndpoint;
  progress: intptr;
  cost: intptr;
  connection: arc<NetConnectionCell>?;
  resolver: arc<NetResolverPool>?;
}
struct NetOperationStep {
  complete: bool;
  error: NetError?;
  eof: bool;
  keep_handle: bool;
}
struct NetOperationCompletion {
  transfer: bool;
  promise: AsyncPromise<Result<Unit, NetError>>;
  transfer_promise: AsyncPromise<NetTransfer>;
  value: Result<Unit, NetError>;
  transfer_value: NetTransfer;
}
/** @brief Sole owner of bounded pending registrations, payload budget and native scratch. */
pub struct NetEventLoop {
  pending: FastArray<NetPendingOperation>;
  scratch: FastArray<NetNativeWait>;
  limit: int32;
  max_retained_bytes: intptr;
  retained_bytes: intptr;
  live: bool;
}

/** @brief Create a driver with the default 16 MiB pending-payload budget. */
pub static method(NetEventLoop) New(max_pending: int32) -> Result<NetEventLoop, NetError> {
  return NetEventLoop.NewWithLimits(max_pending, 16777216 as intptr);
}
/** @brief Allocate bounded queue storage and an explicit pending-payload budget. */
pub static method(NetEventLoop) NewWithLimits(max_pending: int32, max_retained_bytes: intptr) -> Result<NetEventLoop, NetError> {
  if max_pending < 1 || max_pending > 256 || max_retained_bytes < (0 as intptr) {
    return NetError{kind: NetErrorKind.InvalidArgument};
  }
  if net_core_os_events_supported() == 0 { return NetError{kind: NetErrorKind.NotSupported}; }
  var driver: NetEventLoop = NetEventLoop{
    pending: FastArray<NetPendingOperation>.NewWithCapacity(max_pending),
    scratch: FastArray<NetNativeWait>.NewWithCapacity(max_pending),
    limit: max_pending, max_retained_bytes: max_retained_bytes, live: true
  };
  return move(driver);
}
/** @brief Transfer the queue and budgets, leaving the original driver inert. */
pub method(NetEventLoop) operator move() -> NetEventLoop {
  let live: bool = self.live;
  let limit: int32 = self.limit;
  let maximum: intptr = self.max_retained_bytes;
  let retained: intptr = self.retained_bytes;
  self.live = false;
  self.limit = 0;
  self.max_retained_bytes = 0 as intptr;
  self.retained_bytes = 0 as intptr;
  return NetEventLoop{
    pending: move(self.pending), scratch: move(self.scratch), limit: limit,
    max_retained_bytes: maximum, retained_bytes: retained, live: live
  };
}
/** @brief Close pending registrations before language destruction releases queue storage. */
pub method(NetEventLoop) operator drop() -> void { self.Close(); }
/** @brief Number of operations still owned by this driver. */
pub method(NetEventLoop) PendingCount() -> int32 { return self.pending.Len(); }
/** @brief Payload bytes charged to still-pending operations. */
pub method(NetEventLoop) RetainedBytes() -> intptr { return self.retained_bytes; }

func net_operation_is_transfer(kind: NetOperationKind) -> bool {
  return kind != NetOperationKind.Readiness && kind != NetOperationKind.TcpDial && kind != NetOperationKind.TcpAccept && kind != NetOperationKind.ResolverReady;
}
func net_operation_control_error(entry: ref NetPendingOperation, now: uint64) -> NetError? {
  if entry.options.cancellation.IsCancelled() { return NetError{kind: NetErrorKind.Cancelled}; }
  let optional: arc<NetConnectionCell>? = entry.connection;
  var abandoned: bool = false;
  if optional != nil {
    let cell: arc<NetConnectionCell> = optional as arc<NetConnectionCell>;
    if cell.cancelled { return NetError{kind: NetErrorKind.Cancelled}; }
    abandoned = cell.abandoned;
  }
  if entry.options.deadline.IsExpired(now) { return NetError{kind: NetErrorKind.TimedOut}; }
  if abandoned { return NetError{kind: NetErrorKind.Closed}; }
  if entry.kind == NetOperationKind.ResolverReady {
    let resolver: arc<NetResolverPool>? = entry.resolver;
    if resolver == nil { return NetError{kind: NetErrorKind.Closed}; }
    if net_resolver_is_closed(resolver as arc<NetResolverPool>) { return NetError{kind: NetErrorKind.Closed}; }
  }
  return nil;
}
func net_operation_completion(entry: ref NetPendingOperation, error: NetError?, eof: bool) -> NetOperationCompletion {
  if net_operation_is_transfer(entry.kind) {
    var received: NetBuffer = NetBuffer{};
    var sender: NetEndpoint? = nil;
    if entry.kind == NetOperationKind.TcpRead || entry.kind == NetOperationKind.TcpReadExactly || entry.kind == NetOperationKind.UdpReceive {
      let sliced: Result<NetBuffer, NetError> = entry.buffer.Slice(0 as intptr, entry.progress);
      received = (sliced.get_if<NetBuffer>()) as NetBuffer;
      if entry.kind == NetOperationKind.UdpReceive && error == nil { sender = entry.endpoint; }
    }
    return NetOperationCompletion{
      transfer: true, transfer_promise: entry.transfer_promise,
      transfer_value: NetTransfer{bytes_transferred: entry.progress, buffer: received, sender: sender, eof: eof, error: error}
    };
  }
  let optional: arc<NetConnectionCell>? = entry.connection;
  if optional != nil {
    var cell: arc<NetConnectionCell> = optional as arc<NetConnectionCell>;
    cell.completed = true;
    cell.failure = error;
  }
  var value: Result<Unit, NetError> = UnitValue();
  if error != nil { value = error as NetError; }
  return NetOperationCompletion{promise: entry.promise, value: value};
}
func net_publish_completion(completion: ref mut NetOperationCompletion) -> void {
  if completion.transfer { completion.transfer_promise.Complete(completion.transfer_value); }
  else { completion.promise.Complete(completion.value); }
}
/** @brief Detach all state before publishing closures, allowing continuation reentry. */
pub method(NetEventLoop) Close() -> void {
  if !self.live { return; }
  self.live = false;
  self.retained_bytes = 0 as intptr;
  var detached: FastArray<NetPendingOperation> = move(self.pending);
  self.scratch.Reset();
  var i: int32 = 0;
  while i < detached.Len() {
    let entry: NetPendingOperation = detached.Get(i);
    var ignored: NetNativeError = NetNativeError{};
    net_core_os_close(entry.handle, &mut ignored);
    i = i + 1;
  }
  var completed: FastArray<NetOperationCompletion> = FastArray<NetOperationCompletion>.NewWithCapacity(detached.Len());
  i = 0;
  while i < detached.Len() {
    let entry: NetPendingOperation = detached.Get(i);
    completed.Push(net_operation_completion(entry, NetError{kind: NetErrorKind.Closed}, false));
    i = i + 1;
  }
  // Every takeable task is terminal before the first callback can inspect it.
  i = 0;
  while i < completed.Len() {
    var completion: NetOperationCompletion = completed.Get(i);
    net_publish_completion(completion);
    i = i + 1;
  }
}

func net_queue_space(driver: ref NetEventLoop, owner: ref NetSocketState) -> Result<Unit, NetError> {
  if !driver.live || !owner.live { return NetError{kind: NetErrorKind.Closed}; }
  if driver.pending.Len() >= driver.limit { return NetError{kind: NetErrorKind.WouldBlock}; }
  return UnitValue();
}
func net_queue_direction_busy(driver: ref NetEventLoop, socket_key: intptr, writable: bool) -> bool {
  var i: int32 = 0;
  while i < driver.pending.Len() {
    let entry: NetPendingOperation = driver.pending.Get(i);
    if entry.kind != NetOperationKind.Readiness && entry.kind != NetOperationKind.ResolverReady && entry.socket_key == socket_key && entry.writable == writable {
      return true;
    }
    i = i + 1;
  }
  return false;
}
func net_register_readiness(
  driver: ref mut NetEventLoop, owner: ref NetSocketState,
  writable: bool, options: ref NetOperationOptions
) -> Result<AsyncFuture<Result<Unit, NetError>>, NetError> {
  let available: Result<Unit, NetError> = net_queue_space(driver, owner);
  let space_error: NetError? = available.get_if<NetError>();
  if space_error != nil { return space_error as NetError; }
  var promise: AsyncPromise<Result<Unit, NetError>> = AsyncPromise<Result<Unit, NetError>>.New();
  let future: AsyncFuture<Result<Unit, NetError>> = promise.FutureHandle();
  let checked: Result<Unit, NetError> = net_check_operation(options);
  let failure: NetError? = checked.get_if<NetError>();
  if failure != nil { promise.Complete(checked); return future; }
  var handle: intptr = 0 as intptr;
  var error: NetNativeError = NetNativeError{};
  if net_core_os_duplicate(owner.handle, &mut handle, &mut error) != 0 { return net_native_error(error); }
  driver.pending.Push(NetPendingOperation{
    handle: handle, socket_key: owner.handle, writable: writable, options: options, promise: promise,
    kind: NetOperationKind.Readiness, attempted: true
  });
  return future;
}
func net_operation_remove(driver: ref mut NetEventLoop, index: int32, keep_handle: bool) -> void {
  let entry: NetPendingOperation = driver.pending.Get(index);
  if !keep_handle {
    var ignored: NetNativeError = NetNativeError{};
    net_core_os_close(entry.handle, &mut ignored);
  }
  driver.retained_bytes = driver.retained_bytes - entry.cost;
  let last: NetPendingOperation = driver.pending.Pop();
  if index < driver.pending.Len() { driver.pending.Set(index, last); }
}
/** @brief Drive one bounded batch; each transfer makes at most one OS attempt per batch. */
pub method(NetEventLoop) Poll(maximum_wait_ms: int32) -> Result<int32, NetError> {
  if !self.live { return NetError{kind: NetErrorKind.Closed}; }
  if maximum_wait_ms < -1 { return NetError{kind: NetErrorKind.InvalidArgument}; }
  let count: int32 = self.pending.Len();
  if count == 0 { return 0; }
  self.scratch.Reset();
  var timeout: int32 = maximum_wait_ms;
  let now: uint64 = NetClock.NowNanoseconds();
  var earliest: NetDeadline = NetDeadline.Never();
  var i: int32 = 0;
  while i < count {
    let entry: NetPendingOperation = self.pending.Get(i);
    var flag: int32 = 0;
    if entry.writable { flag = 1; }
    var row: NetNativeWait = NetNativeWait{
      handle: entry.handle, wake_handle: net_cancellation_wake_handle(entry.options.cancellation), writable: flag
    };
    let control_error: NetError? = net_operation_control_error(entry, now);
    if control_error != nil { row.ready = 1; timeout = 0; }
    else if !entry.attempted { row.ready = 1; timeout = 0; }
    let deadline: NetDeadline = entry.options.deadline;
    if deadline.IsFinite() && (!earliest.IsFinite() || deadline.RemainingNanoseconds(now) < earliest.RemainingNanoseconds(now)) {
      earliest = deadline;
    }
    if entry.kind == NetOperationKind.ResolverReady {
      let resolver: arc<NetResolverPool>? = entry.resolver;
      if resolver != nil {
        let state: NetResolverWaitState = net_resolver_wait_state(resolver as arc<NetResolverPool>, now);
        if state.ready { row.ready = 1; timeout = 0; }
        if state.deadline.IsFinite() && (!earliest.IsFinite() || state.deadline.RemainingNanoseconds(now) < earliest.RemainingNanoseconds(now)) { earliest = state.deadline; }
        if state.poll_controls && (timeout < 0 || timeout > 50) { timeout = 50; }
      }
    }
    if entry.options.cancellation.CanBeCancelled() && !entry.options.cancellation.CanWakeWaiters() && (timeout < 0 || timeout > 50) { timeout = 50; }
    self.scratch.Push(row);
    i = i + 1;
  }
  // Snapshot preparation consumes real time too. Convert the earliest absolute
  // deadline immediately before entering the native wait, rather than extending
  // it by the duration of queue traversal and retained-value copies.
  let budget: int32 = earliest.PollMilliseconds(NetClock.NowNanoseconds());
  if budget >= 0 && (timeout < 0 || budget < timeout) { timeout = budget; }
  var error: NetNativeError = NetNativeError{};
  let rows: *mut NetNativeWait = self.scratch.Data() as *mut NetNativeWait;
  if net_core_os_wait_many(rows, count, timeout, &mut error) != 0 { return net_native_error(error); }
  var completed: FastArray<NetOperationCompletion> = FastArray<NetOperationCompletion>.New();
  i = count;
  while i > 0 {
    i = i - 1;
    var entry: NetPendingOperation = self.pending.Get(i);
    var row: NetNativeWait = self.scratch.Get(i);
    var failure: NetError? = net_operation_control_error(entry, NetClock.NowNanoseconds());
    if failure == nil && entry.kind == NetOperationKind.ResolverReady {
      let resolver: arc<NetResolverPool>? = entry.resolver;
      if resolver != nil {
        let state: NetResolverWaitState = net_resolver_wait_state(resolver as arc<NetResolverPool>, NetClock.NowNanoseconds());
        if state.ready { row.ready = 1; }
      }
    }
    if failure == nil && row.ready != 0 && row.kind != 0 {
      failure = net_native_error(NetNativeError{kind: row.kind, native_code: row.native_code});
    }
    var step: NetOperationStep = NetOperationStep{};
    if failure != nil { step = NetOperationStep{complete: true, error: failure}; }
    else if row.ready != 0 {
      if entry.kind == NetOperationKind.Readiness || entry.kind == NetOperationKind.ResolverReady { step.complete = true; }
      else if entry.kind == NetOperationKind.TcpDial || entry.kind == NetOperationKind.TcpAccept { step = net_step_connection(entry); }
      else { step = net_step_transfer(entry); }
    }
    if step.complete {
      if completed.IsEmpty() { completed = FastArray<NetOperationCompletion>.NewWithCapacity(count); }
      completed.Push(net_operation_completion(entry, step.error, step.eof));
      net_operation_remove(self, i, step.keep_handle);
    } else { self.pending.Set(i, entry); }
  }
  self.scratch.Reset();
  // The batch is detached and descriptors/budgets retired before callbacks run.
  let published: int32 = completed.Len();
  i = 0;
  while i < published {
    var completion: NetOperationCompletion = completed.Get(i);
    net_publish_completion(completion);
    i = i + 1;
  }
  return published;
}

/** @brief Register read readiness without borrowing an I/O buffer. */
pub method(TcpConnection) WhenReadable(driver: ref mut NetEventLoop, options: ref NetOperationOptions) -> Result<AsyncFuture<Result<Unit, NetError>>, NetError> {
  return net_register_readiness(driver, self.socket_value, false, options);
}
/** @brief Register write readiness on the caller's driver. */
pub method(TcpConnection) WhenWritable(driver: ref mut NetEventLoop, options: ref NetOperationOptions) -> Result<AsyncFuture<Result<Unit, NetError>>, NetError> {
  return net_register_readiness(driver, self.socket_value, true, options);
}
/** @brief Register pending accept readiness without accepting a connection. */
pub method(TcpListener) WhenAcceptable(driver: ref mut NetEventLoop, options: ref NetOperationOptions) -> Result<AsyncFuture<Result<Unit, NetError>>, NetError> {
  return net_register_readiness(driver, self.socket_value, false, options);
}
/** @brief Register datagram read readiness without receiving a message. */
pub method(UdpSocket) WhenReadable(driver: ref mut NetEventLoop, options: ref NetOperationOptions) -> Result<AsyncFuture<Result<Unit, NetError>>, NetError> {
  return net_register_readiness(driver, self.socket_value, false, options);
}
/** @brief Register datagram write readiness without retaining a message. */
pub method(UdpSocket) WhenWritable(driver: ref mut NetEventLoop, options: ref NetOperationOptions) -> Result<AsyncFuture<Result<Unit, NetError>>, NetError> {
  return net_register_readiness(driver, self.socket_value, true, options);
}
