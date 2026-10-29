// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

part of NetSocketDriver;

/** @brief Owned asynchronous payloads with bounded memory and one syscall per Poll step. */

func net_register_transfer(
  driver: ref mut NetEventLoop, owner: ref NetSocketState, kind: NetOperationKind,
  input: ref NetBuffer, size: int32, endpoint: ref NetEndpoint, options: ref NetOperationOptions
) -> Result<AsyncFuture<NetTransfer>, NetError> {
  if size < 0 {
    return NetError{kind: NetErrorKind.InvalidArgument};
  }

  let available: Result<Unit, NetError> = net_queue_space(driver, owner);
  let space_error: NetError? = available.get_if<NetError>();
  if space_error != nil {
    return space_error as NetError;
  }

  let writable: bool = kind == NetOperationKind.TcpWrite
    || kind == NetOperationKind.TcpWriteAll
    || kind == NetOperationKind.UdpSend;
  if net_queue_direction_busy(driver, owner.handle, writable) {
    return NetError{kind: NetErrorKind.WouldBlock};
  }

  let checked: Result<Unit, NetError> = NetCheckOperation(options);
  let failure: NetError? = checked.get_if<NetError>();
  if failure != nil {
    return failure as NetError;
  }

  var cost: intptr = input.RetainedBytes();
  if !writable {
    cost = size as intptr;
  }

  if cost > driver.max_retained_bytes - driver.retained_bytes {
    return NetError{kind: NetErrorKind.WouldBlock};
  }

  if kind == NetOperationKind.UdpSend {
    let ip: IpAddress = endpoint.Address();
    if ip.Family() == IpFamily.Unspecified {
      return NetError{kind: NetErrorKind.InvalidAddress};
    }
  }

  var handle: intptr = 0 as intptr;
  var error: NetNativeError = NetNativeError{};
  if net_core_os_duplicate(owner.handle, &mut handle, &mut error) != 0 {
    return NetMapNativeError(error);
  }

  var buffer: NetBuffer = input;
  if !writable {
    buffer = NetBufferAllocate(size);
  }

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
  let remaining: intptr = entry.buffer.Len() - entry.progress;
  if entry.kind == NetOperationKind.TcpRead || entry.kind == NetOperationKind.TcpReadExactly {
    if remaining == (0 as intptr) {
      return NetOperationStep{complete: true};
    }

    var size: intptr = remaining;
    if size >(65536 as intptr) {
      size = 65536 as intptr;
    }

    result = net_core_os_read(
      entry.handle,
      NetBufferPointer(entry.buffer, entry.progress),
      size,
      &mut count,
      &mut error
    );
    if result == 15 {
      return NetOperationStep{};
    }

    if result != 0 {
      return NetOperationStep{complete: true, error: NetMapNativeError(error)};
    }

    if count == (0 as intptr) {
      if entry.kind == NetOperationKind.TcpReadExactly {
        return NetOperationStep{complete: true, eof: true, error: NetError{kind: NetErrorKind.UnexpectedEof}};
      }

      return NetOperationStep{complete: true, eof: true};
    }

    entry.progress = entry.progress + count;

    return NetOperationStep{complete: entry.kind == NetOperationKind.TcpRead
      || entry.progress == entry.buffer.Len()};
  }

  if entry.kind == NetOperationKind.TcpWrite || entry.kind == NetOperationKind.TcpWriteAll {
    if remaining == (0 as intptr) {
      return NetOperationStep{complete: true};
    }

    var size: intptr = remaining;
    if size >(65536 as intptr) {
      size = 65536 as intptr;
    }

    result = net_core_os_write(
      entry.handle,
      NetBufferPointer(entry.buffer, entry.progress) as *const uint8,
      size,
      &mut count,
      &mut error
    );
    if result == 15 {
      return NetOperationStep{};
    }

    if result != 0 {
      return NetOperationStep{complete: true, error: NetMapNativeError(error)};
    }

    if count == (0 as intptr) {
      return NetOperationStep{complete: true, error: NetError{kind: NetErrorKind.ConnectionAborted}};
    }

    entry.progress = entry.progress + count;

    return NetOperationStep{complete: entry.kind == NetOperationKind.TcpWrite
      || entry.progress == entry.buffer.Len()};
  }

  if entry.kind == NetOperationKind.UdpReceive {
    var sender: NetNativeAddress = NetNativeAddress{};
    result = net_core_os_receive_from(
      entry.handle,
      NetBufferPointer(entry.buffer, 0 as intptr),
      entry.buffer.Len(),
      &mut count,
      &mut sender,
      &mut error
    );
    if result == 15 {
      return NetOperationStep{};
    }

    if result != 0 {
      return NetOperationStep{complete: true, error: NetMapNativeError(error)};
    }

    entry.progress = count;
    entry.endpoint = NetProductEndpoint(sender);

    return NetOperationStep{complete: true};
  }

  if entry.kind == NetOperationKind.UdpSend {
    let address: NetNativeAddress = NetEncodeNativeAddress(entry.endpoint);
    result = net_core_os_send_to(
      entry.handle,
      &address,
      NetBufferPointer(entry.buffer, 0 as intptr) as *const uint8,
      entry.buffer.Len(),
      &mut count,
      &mut error
    );
    if result == 15 {
      return NetOperationStep{};
    }

    if result != 0 {
      return NetOperationStep{complete: true, error: NetMapNativeError(error)};
    }

    entry.progress = count;

    return NetOperationStep{complete: true};
  }

  return NetOperationStep{complete: true, error: NetError{kind: NetErrorKind.System}};
}

/**
 * @brief Queue a TCP receive of up to max_bytes, allocating and retaining its own buffer.
 * @returns Local transfer Future or registration/capacity failure; errors after enqueue are in
 *   NetTransfer.error. Zero size succeeds without receiving and does not mean EOF.
 * @note No borrowed payload is queued. One OS attempt per operation per Poll; a successful
 *   nonempty read may be partial. Payload transfers retain a duplicated socket even if the
 *   original owner closes/drops. Do not issue another read on the socket until done; the driver
 *   rejects overlapping queued reads on this owner within the same driver. Cancelling or closing
 *   the driver releases pending operations; dropping only the Future does not cancel them.
 *   Controls already expired at registration fail the outer Result.
 */
pub method(TcpConnection) ReadAsync(
  driver: ref mut NetEventLoop,
  max_bytes: int32,
  options: ref NetOperationOptions
) -> Result<AsyncFuture<NetTransfer>, NetError> {
  return net_register_transfer(
    driver,
    self.socket_value,
    NetOperationKind.TcpRead,
    NetBuffer{},
    max_bytes,
    NetEndpoint{},
    options
  );
}

/**
 * @brief Queue an exact TCP read; preserve partial bytes/count on EOF, cancellation or error.
 * @returns A Future on successful admission, or the documented immediate error; completion
 *   follows the operation contract above.
 */
pub method(TcpConnection) ReadExactlyAsync(
  driver: ref mut NetEventLoop,
  size: int32,
  options: ref NetOperationOptions
) -> Result<AsyncFuture<NetTransfer>, NetError> {
  return net_register_transfer(
    driver,
    self.socket_value,
    NetOperationKind.TcpReadExactly,
    NetBuffer{},
    size,
    NetEndpoint{},
    options
  );
}

/**
 * @brief Queue a TCP send retaining an immutable buffer copy; complete on first partial
 *   progress.
 * @returns A Future on successful admission, or the documented immediate error; completion
 *   follows the operation contract above.
 * @note The original buffer value may drop immediately. Do not mix synchronous/Try/queued writes
 *   on this socket until done. The driver rejects overlapping queued writes.
 */
pub method(TcpConnection) WriteAsync(
  driver: ref mut NetEventLoop,
  buffer: ref NetBuffer,
  options: ref NetOperationOptions
) -> Result<AsyncFuture<NetTransfer>, NetError> {
  return net_register_transfer(
    driver,
    self.socket_value,
    NetOperationKind.TcpWrite,
    buffer,
    0,
    NetEndpoint{},
    options
  );
}

/**
 * @brief Queue all bytes once; retries resume at the accepted offset and failures retain
 *   progress.
 * @returns A Future on successful admission, or the documented immediate error; completion
 *   follows the operation contract above.
 */
pub method(TcpConnection) WriteAllAsync(
  driver: ref mut NetEventLoop,
  buffer: ref NetBuffer,
  options: ref NetOperationOptions
) -> Result<AsyncFuture<NetTransfer>, NetError> {
  return net_register_transfer(
    driver,
    self.socket_value,
    NetOperationKind.TcpWriteAll,
    buffer,
    0,
    NetEndpoint{},
    options
  );
}

/**
 * @brief Queue one datagram receive with owned storage; truncation consumes/discards the
 *   message.
 * @returns A Future on successful admission, or the documented immediate error; completion
 *   follows the operation contract above.
 */
pub method(UdpSocket) ReceiveFromAsync(
  driver: ref mut NetEventLoop,
  max_bytes: int32,
  options: ref NetOperationOptions
) -> Result<AsyncFuture<NetTransfer>, NetError> {
  return net_register_transfer(
    driver,
    self.socket_value,
    NetOperationKind.UdpReceive,
    NetBuffer{},
    max_bytes,
    NetEndpoint{},
    options
  );
}

/**
 * @brief Queue one datagram retaining its buffer, including a real send for an empty buffer.
 * @returns A Future on successful admission, or the documented immediate error; completion
 *   follows the operation contract above.
 */
pub method(UdpSocket) SendToAsync(
  driver: ref mut NetEventLoop,
  endpoint: ref NetEndpoint,
  buffer: ref NetBuffer,
  options: ref NetOperationOptions
) -> Result<AsyncFuture<NetTransfer>, NetError> {
  return net_register_transfer(
    driver,
    self.socket_value,
    NetOperationKind.UdpSend,
    buffer,
    0,
    endpoint,
    options
  );
}
