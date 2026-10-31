// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

/** @brief Internal pointer-only OS ABI records and foreign declarations. */
import "stdlib:stdlib.ny";

/** @brief Inline fixed-width address: family 4/6, host-order port, numeric scope and network-order bytes. */
pub struct NetNativeAddress {
  family: int32;
  port: int32;
  scope_id: uint32;
  bytes: <uint8>[16];
}

/** @brief Native error category and original OS code; interpreted once at the product mapping boundary. */
pub struct NetNativeError {
  kind: int32;
  native_code: int32;
}

/** @brief Caller-owned batch wait record; readiness and per-entry error outputs are overwritten by wait_many. */
pub struct NetNativeWait {
  handle: intptr;
  wake_handle: intptr;
  writable: int32;
  ready: int32;
  kind: int32;
  native_code: int32;
}

/** @brief Query native readiness backend availability.
 * @returns Nonzero when supported, zero otherwise.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_events_supported() -> int32;

/** @brief Duplicate a borrowed socket descriptor; success transfers the new descriptor through out.
 * @returns Zero on success; otherwise mapped native category and error output.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_duplicate(
  handle: intptr,
  out: *mut intptr,
  error: *mut NetNativeError
) -> int32;

/** @brief Wait on count mutable caller-owned entries; borrow all handles and buffers through the call.
 * @returns Zero after updating entries, or a batch-level native error category.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_wait_many(
  items: *mut NetNativeWait,
  count: int32,
  milliseconds: int32,
  error: *mut NetNativeError
) -> int32;

/** @brief Open a nonblocking socket for family 4/6 and stream/datagram selection; success transfers out.
 * @returns Zero on success, otherwise a mapped error with no transferred descriptor.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_open(
  family: int32,
  datagram: int32,
  out: *mut intptr,
  error: *mut NetNativeError
) -> int32;

/** @brief Close the supplied owned socket descriptor exactly once.
 * @returns Zero on success, otherwise a mapped native error category.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_close(handle: intptr, error: *mut NetNativeError) -> int32;

/** @brief Bind a borrowed socket using an inline borrowed address; listener selects exclusive/reuse policy.
 * @returns Zero on success, otherwise a mapped native error category.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_bind(
  handle: intptr,
  address: *const NetNativeAddress,
  listener: int32,
  error: *mut NetNativeError
) -> int32;

/** @brief Start listening on a borrowed stream socket with a positive backlog.
 * @returns Zero on success, otherwise a mapped native error category.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_listen(handle: intptr, backlog: int32, error: *mut NetNativeError) -> int32;

/** @brief Initiate nonblocking connection to a borrowed inline address.
 * @returns Zero when connected, WouldBlock while pending, otherwise a mapped error.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_connect(
  handle: intptr,
  address: *const NetNativeAddress,
  error: *mut NetNativeError
) -> int32;

/** @brief Read completion status of a previously initiated nonblocking connection.
 * @returns Zero on success, otherwise the mapped socket completion error.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_connect_result(handle: intptr, error: *mut NetNativeError) -> int32;

/** @brief Accept a connection; success transfers one nonblocking descriptor through out.
 * @returns Zero on success, WouldBlock if none is ready, otherwise a mapped error.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_accept(handle: intptr, out: *mut intptr, error: *mut NetNativeError) -> int32;

/** @brief Create an owned wake descriptor pair; initialize both outputs only for successful ownership transfer.
 * @returns Zero on success, otherwise a mapped native error category.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_wake_open(
  read_handle: *mut intptr,
  write_handle: *mut intptr,
  error: *mut NetNativeError
) -> int32;

/** @brief Close an owned wake pair, avoiding a double close when both values denote one handle.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_wake_close(read_handle: intptr, write_handle: intptr) -> void;

/** @brief Signal a borrowed wake writer without transferring ownership; redundant/full wake signals coalesce.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_wake_signal(write_handle: intptr) -> void;

/** @brief Drain a resettable resolver notification reader; never use on sticky cancellation channels.
 * @returns Zero when drained, otherwise a mapped native error category.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_notify_drain(read_handle: intptr, error: *mut NetNativeError) -> int32;

/** @brief Wait on borrowed socket and optional wake handles using a millisecond timeout.
 * @returns Zero for readiness, WouldBlock for timeout, otherwise a mapped error.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_wait_wake(
  handle: intptr,
  writable: int32,
  milliseconds: int32,
  wake_handle: intptr,
  error: *mut NetNativeError
) -> int32;

/** @brief Wait on one borrowed socket with a millisecond timeout and no cancellation wake handle.
 * @returns Zero for readiness, WouldBlock for timeout, otherwise a mapped error.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_wait(
  handle: intptr,
  writable: int32,
  milliseconds: int32,
  error: *mut NetNativeError
) -> int32;

/** @brief Write a borrowed socket local/peer address into caller-owned out storage.
 * @returns Zero on success, otherwise a mapped native error category.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_endpoint(
  handle: intptr,
  peer: int32,
  out: *mut NetNativeAddress,
  error: *mut NetNativeError
) -> int32;

/** @brief Read at most size bytes into caller-owned mutable data; write transferred count to out.
 * @returns Zero on success including EOF, WouldBlock when pending, otherwise a mapped error.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_read(
  handle: intptr,
  data: *mut uint8,
  size: intptr,
  out: *mut intptr,
  error: *mut NetNativeError
) -> int32;

/** @brief Write at most size borrowed bytes; store transferred count in caller-owned out.
 * @returns Zero on success, WouldBlock when pending, otherwise a mapped error.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_write(
  handle: intptr,
  data: *const uint8,
  size: intptr,
  out: *mut intptr,
  error: *mut NetNativeError
) -> int32;

/** @brief Send one datagram using a borrowed address and size bytes; report transferred count through out.
 * @returns Zero on success, WouldBlock when pending, otherwise a mapped error.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_send_to(
  handle: intptr,
  address: *const NetNativeAddress,
  data: *const uint8,
  size: intptr,
  out: *mut intptr,
  error: *mut NetNativeError
) -> int32;

/** @brief Receive one datagram into caller storage and write count/sender; truncation consumes the datagram.
 * @returns Zero on success, MessageTooLarge for truncation, otherwise a mapped error.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_receive_from(
  handle: intptr,
  data: *mut uint8,
  size: intptr,
  out: *mut intptr,
  sender: *mut NetNativeAddress,
  error: *mut NetNativeError
) -> int32;

/** @brief Shut down the write direction of a borrowed stream socket without closing its handle.
 * @returns Zero on success, otherwise a mapped native error category.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_shutdown_write(handle: intptr, error: *mut NetNativeError) -> int32;

/** @brief Set TCP_NODELAY on a borrowed stream socket.
 * @returns Zero on success, otherwise a mapped native error category.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_no_delay(handle: intptr, enabled: int32, error: *mut NetNativeError) -> int32;

/** @brief Resolve borrowed length-delimited hostname bytes into capacity caller-owned address slots.
 * @returns Zero on success with count output, otherwise a mapped native error category.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
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

/** @brief Resolve a borrowed length-delimited interface name into caller-owned numeric scope storage.
 * @returns Zero on success with scope output, otherwise a mapped native error category.
 * @note All pointer inputs/outputs borrow caller storage for this synchronous call only.
 */
pub @extern("C") func net_core_os_scope(
  name: *const uint8,
  length: intptr,
  out: *mut uint32,
  error: *mut NetNativeError
) -> int32;
