// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

/** @brief Internal pointer-only OS ABI records and foreign declarations. */
import "stdlib:stdlib.ny";

pub struct NetNativeAddress {
  family: int32;
  port: int32;
  scope_id: uint32;
  bytes: <uint8>[16];
}

pub struct NetNativeError {
  kind: int32;
  native_code: int32;
}

pub struct NetNativeWait {
  handle: intptr;
  wake_handle: intptr;
  writable: int32;
  ready: int32;
  kind: int32;
  native_code: int32;
}

pub @extern("C") func net_core_os_events_supported() -> int32;

pub @extern("C") func net_core_os_duplicate(
  handle: intptr,
  out: *mut intptr,
  error: *mut NetNativeError
) -> int32;

pub @extern("C") func net_core_os_wait_many(
  items: *mut NetNativeWait,
  count: int32,
  milliseconds: int32,
  error: *mut NetNativeError
) -> int32;

pub @extern("C") func net_core_os_open(
  family: int32,
  datagram: int32,
  out: *mut intptr,
  error: *mut NetNativeError
) -> int32;

pub @extern("C") func net_core_os_close(handle: intptr, error: *mut NetNativeError) -> int32;

pub @extern("C") func net_core_os_bind(
  handle: intptr,
  address: *const NetNativeAddress,
  listener: int32,
  error: *mut NetNativeError
) -> int32;

pub @extern("C") func net_core_os_listen(handle: intptr, backlog: int32, error: *mut NetNativeError) -> int32;

pub @extern("C") func net_core_os_connect(
  handle: intptr,
  address: *const NetNativeAddress,
  error: *mut NetNativeError
) -> int32;

pub @extern("C") func net_core_os_connect_result(handle: intptr, error: *mut NetNativeError) -> int32;

pub @extern("C") func net_core_os_accept(handle: intptr, out: *mut intptr, error: *mut NetNativeError) -> int32;

pub @extern("C") func net_core_os_wake_open(
  read_handle: *mut intptr,
  write_handle: *mut intptr,
  error: *mut NetNativeError
) -> int32;

pub @extern("C") func net_core_os_wake_close(read_handle: intptr, write_handle: intptr) -> void;

pub @extern("C") func net_core_os_wake_signal(write_handle: intptr) -> void;

pub @extern("C") func net_core_os_notify_drain(read_handle: intptr, error: *mut NetNativeError) -> int32;

pub @extern("C") func net_core_os_wait_wake(
  handle: intptr,
  writable: int32,
  milliseconds: int32,
  wake_handle: intptr,
  error: *mut NetNativeError
) -> int32;

pub @extern("C") func net_core_os_wait(
  handle: intptr,
  writable: int32,
  milliseconds: int32,
  error: *mut NetNativeError
) -> int32;

pub @extern("C") func net_core_os_endpoint(
  handle: intptr,
  peer: int32,
  out: *mut NetNativeAddress,
  error: *mut NetNativeError
) -> int32;

pub @extern("C") func net_core_os_read(
  handle: intptr,
  data: *mut uint8,
  size: intptr,
  out: *mut intptr,
  error: *mut NetNativeError
) -> int32;

pub @extern("C") func net_core_os_write(
  handle: intptr,
  data: *const uint8,
  size: intptr,
  out: *mut intptr,
  error: *mut NetNativeError
) -> int32;

pub @extern("C") func net_core_os_send_to(
  handle: intptr,
  address: *const NetNativeAddress,
  data: *const uint8,
  size: intptr,
  out: *mut intptr,
  error: *mut NetNativeError
) -> int32;

pub @extern("C") func net_core_os_receive_from(
  handle: intptr,
  data: *mut uint8,
  size: intptr,
  out: *mut intptr,
  sender: *mut NetNativeAddress,
  error: *mut NetNativeError
) -> int32;

pub @extern("C") func net_core_os_shutdown_write(handle: intptr, error: *mut NetNativeError) -> int32;

pub @extern("C") func net_core_os_no_delay(handle: intptr, enabled: int32, error: *mut NetNativeError) -> int32;

pub @extern("C") func net_core_os_resolve(
  host: *const uint8,
  length: intptr,
  port: int32,
  family: int32,
  out: *mut NetNativeAddress,
  capacity: int32,
  count: *mut int32,
  error: *mut NetNativeError
) -> int32;

pub @extern("C") func net_core_os_scope(
  name: *const uint8,
  length: intptr,
  out: *mut uint32,
  error: *mut NetNativeError
) -> int32;
