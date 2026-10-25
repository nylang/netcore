/** @brief Owned asynchronous payloads with bounded memory and one syscall per Poll step. */
part of NetTransport;

func net_register_transfer(
  driver: ref mut NetEventLoop, owner: ref NetSocketState, kind: NetOperationKind,
  input: ref NetBuffer, size: int32, endpoint: ref NetEndpoint, options: ref NetOperationOptions
) -> Result<AsyncFuture<NetTransfer>, NetError> {
  if size < 0 { return NetError{kind: NetErrorKind.InvalidArgument}; }
  let available: Result<Unit, NetError> = net_queue_space(driver, owner);
  let space_error: NetError? = available.get_if<NetError>();
  if space_error != nil { return space_error as NetError; }
  let writable: bool = kind == NetOperationKind.TcpWrite || kind == NetOperationKind.TcpWriteAll || kind == NetOperationKind.UdpSend;
  if net_queue_direction_busy(driver, owner.handle, writable) { return NetError{kind: NetErrorKind.WouldBlock}; }
  let checked: Result<Unit, NetError> = net_check_operation(options);
  let failure: NetError? = checked.get_if<NetError>();
  if failure != nil { return failure as NetError; }
  var cost: intptr = input.RetainedBytes();
  if !writable { cost = size as intptr; }
  if cost > driver.max_retained_bytes - driver.retained_bytes { return NetError{kind: NetErrorKind.WouldBlock}; }
  if kind == NetOperationKind.UdpSend {
    let ip: IpAddress = endpoint.Address();
    if ip.Family() == IpFamily.Unspecified { return NetError{kind: NetErrorKind.InvalidAddress}; }
  }
  var handle: intptr = 0 as intptr;
  var error: NetNativeError = NetNativeError{};
  if net_core_os_duplicate(owner.handle, &mut handle, &mut error) != 0 { return net_native_error(error); }
  var buffer: NetBuffer = input;
  if !writable { buffer = net_buffer_allocate(size); }
  let promise: AsyncPromise<NetTransfer> = AsyncPromise<NetTransfer>.New();
  let future: AsyncFuture<NetTransfer> = promise.FutureHandle();
  driver.pending.Push(NetPendingOperation{
    handle: handle, socket_key: owner.handle, writable: writable, kind: kind, options: options,
    transfer_promise: promise, buffer: buffer, endpoint: endpoint, cost: cost
  });
  driver.retained_bytes = driver.retained_bytes + cost;
  return future;
}

func net_step_transfer(entry: ref mut NetPendingOperation) -> NetOperationStep {
  entry.attempted = true;
  var count: intptr = 0 as intptr;
  var error: NetNativeError = NetNativeError{};
  var result: int32 = 0;
  let remaining: intptr = entry.buffer.count - entry.progress;
  if entry.kind == NetOperationKind.TcpRead || entry.kind == NetOperationKind.TcpReadExactly {
    if remaining == (0 as intptr) { return NetOperationStep{complete: true}; }
    var size: intptr = remaining;
    if size > (65536 as intptr) { size = 65536 as intptr; }
    result = net_core_os_read(entry.handle, net_buffer_pointer(entry.buffer, entry.progress), size, &mut count, &mut error);
    if result == 15 { return NetOperationStep{}; }
    if result != 0 { return NetOperationStep{complete: true, error: net_native_error(error)}; }
    if count == (0 as intptr) {
      if entry.kind == NetOperationKind.TcpReadExactly {
        return NetOperationStep{complete: true, eof: true, error: NetError{kind: NetErrorKind.UnexpectedEof}};
      }
      return NetOperationStep{complete: true, eof: true};
    }
    entry.progress = entry.progress + count;
    return NetOperationStep{complete: entry.kind == NetOperationKind.TcpRead || entry.progress == entry.buffer.count};
  }
  if entry.kind == NetOperationKind.TcpWrite || entry.kind == NetOperationKind.TcpWriteAll {
    if remaining == (0 as intptr) { return NetOperationStep{complete: true}; }
    var size: intptr = remaining;
    if size > (65536 as intptr) { size = 65536 as intptr; }
    result = net_core_os_write(entry.handle, net_buffer_pointer(entry.buffer, entry.progress) as *const uint8, size, &mut count, &mut error);
    if result == 15 { return NetOperationStep{}; }
    if result != 0 { return NetOperationStep{complete: true, error: net_native_error(error)}; }
    if count == (0 as intptr) { return NetOperationStep{complete: true, error: NetError{kind: NetErrorKind.ConnectionAborted}}; }
    entry.progress = entry.progress + count;
    return NetOperationStep{complete: entry.kind == NetOperationKind.TcpWrite || entry.progress == entry.buffer.count};
  }
  if entry.kind == NetOperationKind.UdpReceive {
    var sender: NetNativeAddress = NetNativeAddress{};
    result = net_core_os_receive_from(entry.handle, net_buffer_pointer(entry.buffer, 0 as intptr), entry.buffer.count, &mut count, &mut sender, &mut error);
    if result == 15 { return NetOperationStep{}; }
    if result != 0 { return NetOperationStep{complete: true, error: net_native_error(error)}; }
    entry.progress = count;
    entry.endpoint = net_product_endpoint(sender);
    return NetOperationStep{complete: true};
  }
  if entry.kind == NetOperationKind.UdpSend {
    let address: NetNativeAddress = net_native_address(entry.endpoint);
    result = net_core_os_send_to(entry.handle, &address, net_buffer_pointer(entry.buffer, 0 as intptr) as *const uint8, entry.buffer.count, &mut count, &mut error);
    if result == 15 { return NetOperationStep{}; }
    if result != 0 { return NetOperationStep{complete: true, error: net_native_error(error)}; }
    entry.progress = count;
    return NetOperationStep{complete: true};
  }
  return NetOperationStep{complete: true, error: NetError{kind: NetErrorKind.System}};
}

/** @brief Queue a partial TCP receive into retained private storage. */
pub method(TcpConnection) ReadAsync(driver: ref mut NetEventLoop, max_bytes: int32, options: ref NetOperationOptions) -> Result<AsyncFuture<NetTransfer>, NetError> {
  return net_register_transfer(driver, self.socket_value, NetOperationKind.TcpRead, NetBuffer{}, max_bytes, NetEndpoint{}, options);
}
/** @brief Queue an exact TCP receive, retaining progress across driver iterations. */
pub method(TcpConnection) ReadExactlyAsync(driver: ref mut NetEventLoop, size: int32, options: ref NetOperationOptions) -> Result<AsyncFuture<NetTransfer>, NetError> {
  return net_register_transfer(driver, self.socket_value, NetOperationKind.TcpReadExactly, NetBuffer{}, size, NetEndpoint{}, options);
}
/** @brief Retain one immutable payload and complete after the first accepted chunk. */
pub method(TcpConnection) WriteAsync(driver: ref mut NetEventLoop, buffer: ref NetBuffer, options: ref NetOperationOptions) -> Result<AsyncFuture<NetTransfer>, NetError> {
  return net_register_transfer(driver, self.socket_value, NetOperationKind.TcpWrite, buffer, 0, NetEndpoint{}, options);
}
/** @brief Retain a payload and resume each send after the last accepted byte. */
pub method(TcpConnection) WriteAllAsync(driver: ref mut NetEventLoop, buffer: ref NetBuffer, options: ref NetOperationOptions) -> Result<AsyncFuture<NetTransfer>, NetError> {
  return net_register_transfer(driver, self.socket_value, NetOperationKind.TcpWriteAll, buffer, 0, NetEndpoint{}, options);
}
/** @brief Queue one UDP receive, including empty datagrams and truncation failure. */
pub method(UdpSocket) ReceiveFromAsync(driver: ref mut NetEventLoop, max_bytes: int32, options: ref NetOperationOptions) -> Result<AsyncFuture<NetTransfer>, NetError> {
  return net_register_transfer(driver, self.socket_value, NetOperationKind.UdpReceive, NetBuffer{}, max_bytes, NetEndpoint{}, options);
}
/** @brief Retain one complete UDP payload until it is sent or the operation terminates. */
pub method(UdpSocket) SendToAsync(driver: ref mut NetEventLoop, endpoint: ref NetEndpoint, buffer: ref NetBuffer, options: ref NetOperationOptions) -> Result<AsyncFuture<NetTransfer>, NetError> {
  return net_register_transfer(driver, self.socket_value, NetOperationKind.UdpSend, buffer, 0, endpoint, options);
}
