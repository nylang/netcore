// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

part of NetSocketDriver;

/** @brief UDP preserves message boundaries; truncation is an error, never silent success. */

/** @brief Sole owner of a bound UDP socket; closes on drop. */
pub struct UdpSocket {
  socket_value: NetSocketState;
}

/**
 * @brief Transfer ownership and leave the source closed.
 * @returns The UdpSocket value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub method(UdpSocket) operator move() -> UdpSocket {
  return UdpSocket{socket_value: self.socket_value.Take()};
}

/** @brief Close the owned descriptor during language destruction. */
pub method(UdpSocket) operator drop() -> void {
  self.socket_value.Close();
}

/**
 * @brief Bind a numeric endpoint, including port zero; IPv6 is V6-only.
 * @returns Ok with UdpSocket on success; Err with NetError on the failure paths described above.
 */
pub static method(UdpSocket) Bind(endpoint: ref NetEndpoint) -> Result<UdpSocket, NetError> {
  let ip: IpAddress = endpoint.Address();
  if ip.Family() == IpFamily.Unspecified {
    return NetError{kind: NetErrorKind.InvalidAddress};
  }

  var handle: intptr = 0;
  var error: NetNativeError = NetNativeError{};
  if net_core_os_open((ip.Family()).NativeDiscriminator(), 1, &mut handle, &mut error) != 0 {
    return (error).AsProduct();
  }

  var socket: UdpSocket = UdpSocket{socket_value: NetSocketState{handle: handle, live: true}};
  let address: NetNativeAddress = (endpoint).AsNative();
  if net_core_os_bind(handle, &address, 0, &mut error) != 0 {
    return (error).AsProduct();
  }

  return move(socket);
}

/**
 * @brief Send exactly one datagram; zero-sized buffers send an actual empty datagram.
 * @returns Ok with intptr on success; Err with NetError on the failure paths described above.
 */
pub method(UdpSocket) SendTo(
  endpoint: ref NetEndpoint,
  buffer: ref NetBytes,
  options: ref NetOperationOptions
) -> Result<intptr, NetError> {
  if !self.socket_value.live {
    return NetError{kind: NetErrorKind.Closed};
  }

  let ip: IpAddress = endpoint.Address();
  if ip.Family() == IpFamily.Unspecified {
    return NetError{kind: NetErrorKind.InvalidAddress};
  }

  let address: NetNativeAddress = (endpoint).AsNative();
  while true {
    let checked: Result<Unit, NetError> = (options).CheckNow();
    let failure: NetError? = checked.get_if<NetError>();
    if failure != nil {
      return failure as NetError;
    }

    var count: intptr = 0;
    var error: NetNativeError = NetNativeError{};
    let result: int32 = net_core_os_send_to(
      self.socket_value.handle,
      &address,
      buffer.Data(),
      buffer.Len(),
      &mut count,
      &mut error
    );
    if result == 0 {
      return count;
    }

    if result != 15 {
      return (error).AsProduct();
    }

    let waited: Result<Unit, NetError> = NetSocketWait{handle: self.socket_value.handle, writable: true,
      options: options}.Run();
    let wait_error: NetError? = waited.get_if<NetError>();
    if wait_error != nil {
      return wait_error as NetError;
    }
  }

  return NetError{kind: NetErrorKind.System};
}

/**
 * @brief Receive one datagram into caller-owned writable bytes.
 * @returns Size and sender, or MessageTooLarge if truncated (that datagram is consumed).
 * @note Buffer contents may change on error. A zero-length buffer still consumes one datagram.
 */
pub method(UdpSocket) ReceiveFrom(
  buffer: ref NetMutableBytes,
  options: ref NetOperationOptions
) -> Result<NetDatagram, NetError> {
  if !self.socket_value.live {
    return NetError{kind: NetErrorKind.Closed};
  }

  while true {
    let checked: Result<Unit, NetError> = (options).CheckNow();
    let failure: NetError? = checked.get_if<NetError>();
    if failure != nil {
      return failure as NetError;
    }

    var count: intptr = 0;
    var sender: NetNativeAddress = NetNativeAddress{};
    var error: NetNativeError = NetNativeError{};
    let result: int32 = net_core_os_receive_from(
      self.socket_value.handle,
      buffer.Data(),
      buffer.Len(),
      &mut count,
      &mut sender,
      &mut error
    );
    if result == 0 {
      return NetDatagram{bytes_read: count, sender: (sender).AsProduct()};
    }

    if result != 15 {
      return (error).AsProduct();
    }

    let waited: Result<Unit, NetError> = NetSocketWait{handle: self.socket_value.handle, writable: false,
      options: options}.Run();
    let wait_error: NetError? = waited.get_if<NetError>();
    if wait_error != nil {
      return wait_error as NetError;
    }
  }

  return NetError{kind: NetErrorKind.System};
}

/**
 * @brief Actual bound address/port.
 * @returns Ok with NetEndpoint on success; Err with NetError on the failure paths described
 *   above.
 */
pub method(UdpSocket) LocalEndpoint() -> Result<NetEndpoint, NetError> {
  return (self.socket_value).Endpoint(false);
}

/**
 * @brief Whether the value owns a datagram socket.
 * @returns Whether the value owns a datagram socket.
 */
pub method(UdpSocket) IsOpen() -> bool {
  return self.socket_value.live;
}

/**
 * @brief Retire and close once; repeated calls succeed.
 * @returns Ok with Unit on success; Err with NetError on the failure paths described above.
 */
pub method(UdpSocket) Close() -> Result<Unit, NetError> {
  return self.socket_value.Close();
}

/**
 * @brief Send one datagram without waiting; preserve SendTo empty-message and size semantics.
 * @returns Ok with intptr on success; Err with NetError on the failure paths described above.
 */
pub method(UdpSocket) TrySendTo(endpoint: ref NetEndpoint, buffer: ref NetBytes) -> Result<intptr, NetError> {
  if !self.socket_value.live {
    return NetError{kind: NetErrorKind.Closed};
  }

  let ip: IpAddress = endpoint.Address();
  if ip.Family() == IpFamily.Unspecified {
    return NetError{kind: NetErrorKind.InvalidAddress};
  }

  let address: NetNativeAddress = (endpoint).AsNative();
  var count: intptr = 0;
  var error: NetNativeError = NetNativeError{};
  if net_core_os_send_to(
    self.socket_value.handle,
    &address,
    buffer.Data(),
    buffer.Len(),
    &mut count,
    &mut error
  ) != 0 {
    return (error).AsProduct();
  }

  return count;
}

/**
 * @brief Receive once without waiting; WouldBlock means no progress; truncation still consumes
 *   the message.
 * @returns Ok with NetDatagram on success; Err with NetError on the failure paths described
 *   above.
 */
pub method(UdpSocket) TryReceiveFrom(buffer: ref NetMutableBytes) -> Result<NetDatagram, NetError> {
  if !self.socket_value.live {
    return NetError{kind: NetErrorKind.Closed};
  }

  var count: intptr = 0;
  var sender: NetNativeAddress = NetNativeAddress{};
  var error: NetNativeError = NetNativeError{};
  if net_core_os_receive_from(
    self.socket_value.handle,
    buffer.Data(),
    buffer.Len(),
    &mut count,
    &mut sender,
    &mut error
  ) != 0 {
    return (error).AsProduct();
  }

  return NetDatagram{bytes_read: count, sender: (sender).AsProduct()};
}
