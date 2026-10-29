// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

part of NetSocketDriver;

/** @brief TCP owner factories and synchronous operations over nonblocking sockets. */

/** @brief Sole owner of a connected TCP socket; default/moved-from values are closed. */
pub struct TcpConnection {
  socket_value: NetSocketState;
}

/** @brief Sole owner of a listening TCP socket; closes on drop. */
pub struct TcpListener {
  socket_value: NetSocketState;
}

/**
 * @brief Transfer ownership and leave the source closed.
 * @returns The TcpConnection value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub method(TcpConnection) operator move() -> TcpConnection {
  return TcpConnection{socket_value: self.socket_value.Take()};
}

/** @brief Close the owned descriptor during language destruction. */
pub method(TcpConnection) operator drop() -> void {
  self.socket_value.Close();
}

/**
 * @brief Transfer the listener and leave its source closed.
 * @returns The TcpListener value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub method(TcpListener) operator move() -> TcpListener {
  return TcpListener{socket_value: self.socket_value.Take()};
}

/** @brief Close a listener exactly once. */
pub method(TcpListener) operator drop() -> void {
  self.socket_value.Close();
}

/**
 * @brief Connect a numeric endpoint, honoring an absolute deadline and shared cancellation.
 * @returns Ok with TcpConnection on success; Err with NetError on the failure paths described
 *   above.
 */
pub static method(TcpConnection) Dial(
  endpoint: ref NetEndpoint,
  options: ref NetOperationOptions
) -> Result<TcpConnection, NetError> {
  let checked: Result<Unit, NetError> = NetCheckOperation(options);
  let failure: NetError? = checked.get_if<NetError>();
  if failure != nil {
    return move(failure as NetError);
  }

  let ip: IpAddress = endpoint.Address();
  if ip.Family() == IpFamily.Unspecified {
    return NetError{kind: NetErrorKind.InvalidAddress};
  }

  var handle: intptr = 0 as intptr;
  var error: NetNativeError = NetNativeError{};
  if net_core_os_open(NetNativeFamily(ip.Family()), 0, &mut handle, &mut error) != 0 {
    return NetMapNativeError(error);
  }

  var connection: TcpConnection = TcpConnection{socket_value: NetSocketState{handle: handle, live: true}};
  let address: NetNativeAddress = NetEncodeNativeAddress(endpoint);
  var result: int32 = net_core_os_connect(handle, &address, &mut error);
  while result == 15 {
    let waited: Result<Unit, NetError> = net_wait_socket(handle, true, options);
    let wait_error: NetError? = waited.get_if<NetError>();
    if wait_error != nil {
      return move(wait_error as NetError);
    }

    let active: Result<Unit, NetError> = NetCheckOperation(options);
    let active_error: NetError? = active.get_if<NetError>();
    if active_error != nil {
      return move(active_error as NetError);
    }

    result = net_core_os_connect_result(handle, &mut error);
  }

  if result != 0 {
    return NetMapNativeError(error);
  }

  return move(connection);
}

/**
 * @brief Read at most the borrowed buffer length; positive progress may be partial.
 * @returns Zero for EOF (or a zero-sized buffer), count on progress, otherwise error.
 * @note The caller keeps the buffer alive/exclusively writable for this synchronous call.
 */
pub method(TcpConnection) Read(
  buffer: ref NetMutableBytes,
  options: ref NetOperationOptions
) -> Result<intptr, NetError> {
  if !self.socket_value.live {
    return NetError{kind: NetErrorKind.Closed};
  }

  while true {
    let checked: Result<Unit, NetError> = NetCheckOperation(options);
    let failure: NetError? = checked.get_if<NetError>();
    if failure != nil {
      return failure as NetError;
    }

    var count: intptr = 0 as intptr;
    var error: NetNativeError = NetNativeError{};
    let result: int32 = net_core_os_read(
      self.socket_value.handle,
      buffer.Data(),
      buffer.Len(),
      &mut count,
      &mut error
    );
    if result == 0 {
      return count;
    }

    if result != 15 {
      return NetMapNativeError(error);
    }

    let waited: Result<Unit, NetError> = net_wait_socket(self.socket_value.handle, false, options);
    let wait_error: NetError? = waited.get_if<NetError>();
    if wait_error != nil {
      return wait_error as NetError;
    }
  }

  return NetError{kind: NetErrorKind.System};
}

/**
 * @brief Write at most the borrowed byte length; returns partial progress, not WriteAll.
 * @returns Ok with intptr on success; Err with NetError on the failure paths described above.
 */
pub method(TcpConnection) Write(
  buffer: ref NetBytes,
  options: ref NetOperationOptions
) -> Result<intptr, NetError> {
  if !self.socket_value.live {
    return NetError{kind: NetErrorKind.Closed};
  }

  while true {
    let checked: Result<Unit, NetError> = NetCheckOperation(options);
    let failure: NetError? = checked.get_if<NetError>();
    if failure != nil {
      return failure as NetError;
    }

    var count: intptr = 0 as intptr;
    var error: NetNativeError = NetNativeError{};
    let result: int32 = net_core_os_write(
      self.socket_value.handle,
      buffer.Data(),
      buffer.Len(),
      &mut count,
      &mut error
    );
    if result == 0 {
      return count;
    }

    if result != 15 {
      return NetMapNativeError(error);
    }

    let waited: Result<Unit, NetError> = net_wait_socket(self.socket_value.handle, true, options);
    let wait_error: NetError? = waited.get_if<NetError>();
    if wait_error != nil {
      return wait_error as NetError;
    }
  }

  return NetError{kind: NetErrorKind.System};
}

/**
 * @brief Enable or disable TCP_NODELAY.
 * @returns Ok with Unit on success; Err with NetError on the failure paths described above.
 */
pub method(TcpConnection) SetNoDelay(enabled: bool) -> Result<Unit, NetError> {
  if !self.socket_value.live {
    return NetError{kind: NetErrorKind.Closed};
  }

  var flag: int32 = 0;
  if enabled {
    flag = 1;
  }

  var error: NetNativeError = NetNativeError{};
  if net_core_os_no_delay(self.socket_value.handle, flag, &mut error) != 0 {
    return NetMapNativeError(error);
  }

  return UnitValue();
}

/**
 * @brief Shut down sending; reading remains available and OS-accepted bytes precede FIN.
 * @returns Ok with Unit on success; Err with NetError on the failure paths described above.
 * @note Complete pending WriteAsync/WriteAllAsync operations before calling this method. This
 *   call does not flush payload still waiting in a NetEventLoop queue.
 */
pub method(TcpConnection) ShutdownWrite() -> Result<Unit, NetError> {
  if !self.socket_value.live {
    return NetError{kind: NetErrorKind.Closed};
  }

  var error: NetNativeError = NetNativeError{};
  if net_core_os_shutdown_write(self.socket_value.handle, &mut error) != 0 {
    return NetMapNativeError(error);
  }

  return UnitValue();
}

/**
 * @brief Local endpoint, including an OS-selected ephemeral port.
 * @returns Ok with NetEndpoint on success; Err with NetError on the failure paths described
 *   above.
 */
pub method(TcpConnection) LocalEndpoint() -> Result<NetEndpoint, NetError> {
  return net_socket_endpoint(self.socket_value, false);
}

/**
 * @brief Connected peer endpoint.
 * @returns Ok with NetEndpoint on success; Err with NetError on the failure paths described
 *   above.
 */
pub method(TcpConnection) RemoteEndpoint() -> Result<NetEndpoint, NetError> {
  return net_socket_endpoint(self.socket_value, true);
}

/**
 * @brief Whether the value currently owns a socket; not a connection-liveness probe.
 * @returns Whether the value currently owns a socket; not a connection-liveness probe.
 */
pub method(TcpConnection) IsOpen() -> bool {
  return self.socket_value.live;
}

/**
 * @brief Retire ownership and close once; repeated calls succeed. Errors never restore
 *   ownership.
 * @returns Ok with Unit on success; Err with NetError on the failure paths described above.
 */
pub method(TcpConnection) Close() -> Result<Unit, NetError> {
  return self.socket_value.Close();
}

/**
 * @brief Bind and listen; backlog must be positive. IPv6 sockets are V6-only.
 * @returns Ok with TcpListener on success; Err with NetError on the failure paths described
 *   above.
 */
pub static method(TcpListener) Listen(
  endpoint: ref NetEndpoint,
  backlog: int32
) -> Result<TcpListener, NetError> {
  if backlog<1 {
    return NetError{kind: NetErrorKind.InvalidArgument};
  }

  let ip: IpAddress = endpoint.Address();
  if ip.Family() == IpFamily.Unspecified {
    return NetError{kind: NetErrorKind.InvalidAddress};
  }

  var handle: intptr = 0 as intptr;
  var error: NetNativeError = NetNativeError{};
  if net_core_os_open(NetNativeFamily(ip.Family()), 0, &mut handle, &mut error) != 0 {
    return NetMapNativeError(error);
  }

  var listener: TcpListener = TcpListener{socket_value: NetSocketState{handle: handle, live: true}};
  let address: NetNativeAddress = NetEncodeNativeAddress(endpoint);
  if net_core_os_bind(handle, &address, 1, &mut error) != 0 {
    return NetMapNativeError(error);
  }

  if net_core_os_listen(handle, backlog, &mut error) != 0 {
    return NetMapNativeError(error);
  }

  return move(listener);
}

/**
 * @brief Accept one connection, honoring the supplied deadline and shared cancellation.
 * @returns Ok with TcpConnection on success; Err with NetError on the failure paths described
 *   above.
 */
pub method(TcpListener) Accept(options: ref NetOperationOptions) -> Result<TcpConnection, NetError> {
  if !self.socket_value.live {
    return NetError{kind: NetErrorKind.Closed};
  }

  while true {
    let checked: Result<Unit, NetError> = NetCheckOperation(options);
    let failure: NetError? = checked.get_if<NetError>();
    if failure != nil {
      return move(failure as NetError);
    }

    var handle: intptr = 0 as intptr;
    var error: NetNativeError = NetNativeError{};
    let result: int32 = net_core_os_accept(self.socket_value.handle, &mut handle, &mut error);
    if result == 0 {
      return TcpConnection{socket_value: NetSocketState{handle: handle, live: true}};
    }

    if result != 15 {
      return NetMapNativeError(error);
    }

    let waited: Result<Unit, NetError> = net_wait_socket(self.socket_value.handle, false, options);
    let wait_error: NetError? = waited.get_if<NetError>();
    if wait_error != nil {
      return move(wait_error as NetError);
    }
  }

  return NetError{kind: NetErrorKind.System};
}

/**
 * @brief Bound endpoint, including the chosen port when binding port zero.
 * @returns Ok with NetEndpoint on success; Err with NetError on the failure paths described
 *   above.
 */
pub method(TcpListener) LocalEndpoint() -> Result<NetEndpoint, NetError> {
  return net_socket_endpoint(self.socket_value, false);
}

/**
 * @brief Whether this value owns its listener.
 * @returns Whether this value owns its listener.
 */
pub method(TcpListener) IsOpen() -> bool {
  return self.socket_value.live;
}

/**
 * @brief Close once; repeated calls succeed.
 * @returns Ok with Unit on success; Err with NetError on the failure paths described above.
 */
pub method(TcpListener) Close() -> Result<Unit, NetError> {
  return self.socket_value.Close();
}

/**
 * @brief Perform one TCP receive without waiting; WouldBlock also covers interruption.
 * @returns Partial count, zero for EOF/empty buffer, or error under the Read buffer contract.
 * @note Pair with WhenReadable and re-register on WouldBlock; readiness is advisory.
 */
pub method(TcpConnection) TryRead(buffer: ref NetMutableBytes) -> Result<intptr, NetError> {
  if !self.socket_value.live {
    return NetError{kind: NetErrorKind.Closed};
  }

  var count: intptr = 0 as intptr;
  var error: NetNativeError = NetNativeError{};
  if net_core_os_read(self.socket_value.handle, buffer.Data(), buffer.Len(), &mut count, &mut error) != 0 {
    return NetMapNativeError(error);
  }

  return count;
}

/**
 * @brief Perform one TCP send without waiting; return partial progress or WouldBlock/error.
 * @returns Ok with intptr on success; Err with NetError on the failure paths described above.
 */
pub method(TcpConnection) TryWrite(buffer: ref NetBytes) -> Result<intptr, NetError> {
  if !self.socket_value.live {
    return NetError{kind: NetErrorKind.Closed};
  }

  var count: intptr = 0 as intptr;
  var error: NetNativeError = NetNativeError{};
  if net_core_os_write(self.socket_value.handle, buffer.Data(), buffer.Len(), &mut count, &mut error) != 0 {
    return NetMapNativeError(error);
  }

  return count;
}

/**
 * @brief Accept once without waiting; return a move-only connection or WouldBlock/error.
 * @returns Ok with TcpConnection on success; Err with NetError on the failure paths described
 *   above.
 */
pub method(TcpListener) TryAccept() -> Result<TcpConnection, NetError> {
  if !self.socket_value.live {
    return NetError{kind: NetErrorKind.Closed};
  }

  var handle: intptr = 0 as intptr;
  var error: NetNativeError = NetNativeError{};
  if net_core_os_accept(self.socket_value.handle, &mut handle, &mut error) != 0 {
    return NetMapNativeError(error);
  }

  return TcpConnection{socket_value: NetSocketState{handle: handle, live: true}};
}
