/** @brief Takeable asynchronous connection results without copying move-only socket values. */
part of NetTransport;

struct NetConnectionCell {
  socket_value: NetSocketState;
  completed: bool;
  abandoned: bool;
  cancelled: bool;
  failure: NetError?;
  promise: AsyncPromise<Result<Unit, NetError>>;
}
method(NetConnectionCell) operator drop() -> void { self.socket_value.Close(); }
/** @brief Local move-only task; the shared cell owns any completed untaken connection. */
pub struct TcpConnectionTask { cell: arc<NetConnectionCell>?; }
/** @brief Transfer the task reference and make the source inert. */
pub method(TcpConnectionTask) operator move() -> TcpConnectionTask {
  let cell: arc<NetConnectionCell>? = self.cell;
  self.cell = nil;
  return TcpConnectionTask{cell: cell};
}
/** @brief Pending tasks are abandoned; the driver reclaims them at its next iteration/Close. */
pub method(TcpConnectionTask) operator drop() -> void {
  let optional: arc<NetConnectionCell>? = self.cell;
  if optional == nil { return; }
  var cell: arc<NetConnectionCell> = optional as arc<NetConnectionCell>;
  cell.abandoned = true;
}
/** @brief Return a local readiness Future while preserving the takeable task owner. */
pub method(TcpConnectionTask) FutureHandle() -> Result<AsyncFuture<Result<Unit, NetError>>, NetError> {
  let optional: arc<NetConnectionCell>? = self.cell;
  if optional == nil { return NetError{kind: NetErrorKind.Closed}; }
  var cell: arc<NetConnectionCell> = optional as arc<NetConnectionCell>;
  return cell.promise.FutureHandle();
}
/** @brief Request cancellation while the driver still owns a pending connect/accept. */
pub method(TcpConnectionTask) Cancel() -> bool {
  let optional: arc<NetConnectionCell>? = self.cell;
  if optional == nil { return false; }
  var cell: arc<NetConnectionCell> = optional as arc<NetConnectionCell>;
  if cell.completed || cell.abandoned || cell.cancelled { return false; }
  cell.cancelled = true;
  return true;
}
/** @brief Transfer a completed connection exactly once without a copying Future payload. */
pub method(TcpConnectionTask) TakeConnection() -> Result<TcpConnection, NetError> {
  let optional: arc<NetConnectionCell>? = self.cell;
  if optional == nil { return NetError{kind: NetErrorKind.Closed}; }
  var cell: arc<NetConnectionCell> = optional as arc<NetConnectionCell>;
  if !cell.completed { return NetError{kind: NetErrorKind.WouldBlock}; }
  let failure: NetError? = cell.failure;
  if failure != nil { return move(failure as NetError); }
  if !cell.socket_value.live { return NetError{kind: NetErrorKind.Closed}; }
  return TcpConnection{socket_value: cell.socket_value.Take()};
}

func net_register_connection(
  driver: ref mut NetEventLoop, owner: ref NetSocketState,
  endpoint: ref NetEndpoint, options: ref NetOperationOptions, dial: bool
) -> Result<TcpConnectionTask, NetError> {
  // Dial creates its own descriptor, so only the driver state/capacity is checked here.
  if !driver.live { return NetError{kind: NetErrorKind.Closed}; }
  if driver.pending.Len() >= driver.limit { return NetError{kind: NetErrorKind.WouldBlock}; }
  if !dial && !owner.live { return NetError{kind: NetErrorKind.Closed}; }
  if !dial && net_queue_direction_busy(driver, owner.handle, false) { return NetError{kind: NetErrorKind.WouldBlock}; }
  let checked: Result<Unit, NetError> = net_check_operation(options);
  let failure: NetError? = checked.get_if<NetError>();
  if failure != nil { return move(failure as NetError); }
  var handle: intptr = 0 as intptr;
  var error: NetNativeError = NetNativeError{};
  var kind: NetOperationKind = NetOperationKind.TcpAccept;
  if dial {
    let ip: IpAddress = endpoint.Address();
    if ip.Family() == IpFamily.Unspecified { return NetError{kind: NetErrorKind.InvalidAddress}; }
    if net_core_os_open(net_native_family(ip.Family()), 0, &mut handle, &mut error) != 0 { return net_native_error(error); }
    kind = NetOperationKind.TcpDial;
  } else {
    if net_core_os_duplicate(owner.handle, &mut handle, &mut error) != 0 { return net_native_error(error); }
  }
  let promise: AsyncPromise<Result<Unit, NetError>> = AsyncPromise<Result<Unit, NetError>>.New();
  let cell: arc<NetConnectionCell> = new arc<NetConnectionCell>{promise: promise};
  var socket_key: intptr = owner.handle;
  if dial { socket_key = handle; }
  driver.pending.Push(NetPendingOperation{
    handle: handle, socket_key: socket_key, writable: dial, kind: kind,
    options: options, endpoint: endpoint, promise: promise, connection: cell
  });
  return TcpConnectionTask{cell: cell};
}
func net_step_connection(entry: ref mut NetPendingOperation) -> NetOperationStep {
  let optional: arc<NetConnectionCell>? = entry.connection;
  if optional == nil { return NetOperationStep{complete: true, error: NetError{kind: NetErrorKind.System}}; }
  var cell: arc<NetConnectionCell> = optional as arc<NetConnectionCell>;
  var error: NetNativeError = NetNativeError{};
  if entry.kind == NetOperationKind.TcpDial {
    var result: int32 = 0;
    if !entry.attempted {
      let address: NetNativeAddress = net_native_address(entry.endpoint);
      result = net_core_os_connect(entry.handle, &address, &mut error);
      entry.attempted = true;
    } else { result = net_core_os_connect_result(entry.handle, &mut error); }
    if result == 15 { return NetOperationStep{}; }
    if result != 0 { return NetOperationStep{complete: true, error: net_native_error(error)}; }
    cell.socket_value = NetSocketState{handle: entry.handle, live: true};
    return NetOperationStep{complete: true, keep_handle: true};
  }
  entry.attempted = true;
  var accepted: intptr = 0 as intptr;
  let result: int32 = net_core_os_accept(entry.handle, &mut accepted, &mut error);
  if result == 15 { return NetOperationStep{}; }
  if result != 0 { return NetOperationStep{complete: true, error: net_native_error(error)}; }
  cell.socket_value = NetSocketState{handle: accepted, live: true};
  return NetOperationStep{complete: true};
}

/** @brief Queue numeric connect with a takeable task-owned result. */
pub static method(TcpConnection) DialAsync(driver: ref mut NetEventLoop, endpoint: ref NetEndpoint, options: ref NetOperationOptions) -> Result<TcpConnectionTask, NetError> {
  return net_register_connection(driver, NetSocketState{}, endpoint, options, true);
}
/** @brief Queue one accept while retaining a duplicate of the listener. */
pub method(TcpListener) AcceptAsync(driver: ref mut NetEventLoop, options: ref NetOperationOptions) -> Result<TcpConnectionTask, NetError> {
  return net_register_connection(driver, self.socket_value, NetEndpoint{}, options, false);
}
