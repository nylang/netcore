// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

module NetPayloadOwner;
import "stdlib:stdlib.ny";
import "interface/foundation.ni";
import "interface/transport.ni";
import "interface/async_transport.ni";
import "interface/async_resolver.ni";

/** @brief Immutable shared buffers for pending and completed asynchronous transfers. */

/** @brief Closed shared storage; only private receive operations can write before publication. */
pub struct NetBuffer {
  storage: arc<owned <uint8>[]>?;
  start: intptr;
  count: intptr;
  backing_size: intptr;
}

/**
 * @brief Allocate zero-initialized storage retained by a network payload owner.
 * @returns An empty buffer for nonpositive size, otherwise a buffer owning size bytes.
 */
pub static method(NetBuffer) Allocate(size: int32) -> NetBuffer {
  if size == 0 {
    return NetBuffer{};
  }

  unsafe {
    let storage: arc<owned <uint8>[]> = new arc <uint8>[size];

    return NetBuffer{storage: storage, count: size as intptr, backing_size: size as intptr};
  }
}

/**
 * @brief Borrow a mutable pointer into a retained payload allocation.
 * @returns A pointer at the requested offset, or null for an empty owner. Keep the buffer alive
 *   and validate the range before using it.
 */
pub method(NetBuffer) MutablePointer(offset: intptr) -> *mut uint8 {
  let optional: arc<owned <uint8>[]>? = self.storage;
  if optional == nil {
    return 0 as *mut uint8;
  }

  var storage: arc<owned <uint8>[]> = optional as arc<owned <uint8>[]>;
  unsafe {
    return (((&mut storage[0]) as intptr) + self.start + offset) as *mut uint8;
  }
}

/**
 * @brief Copy borrowed bytes once; reject lengths above int32 max before allocation.
 * @returns Ok with NetBuffer on success; Err with NetError on the failure paths described above.
 */
pub static method(NetBuffer) CopyFrom(bytes: ref NetBytes) -> Result<NetBuffer, NetError> {
  if bytes.Len() >(2147483647ip) {
    return NetError{kind: NetErrorKind.MessageTooLarge};
  }

  let buffer: NetBuffer = NetBuffer.Allocate(bytes.Len() as int32);
  if bytes.Len() >(0ip) {
    unsafe {
      memcpy((buffer).MutablePointer(0ip), bytes.Data(), bytes.Len() as uintptr);
    }
  }

  return buffer;
}

/**
 * @brief Number of visible bytes; default is empty.
 * @returns Number of visible bytes; default is empty.
 */
pub method(NetBuffer) Len() -> intptr {
  return self.count;
}

/**
 * @brief Full backing allocation size retained by this slice, excluding fixed ARC overhead.
 * @returns Full backing allocation size retained by this slice, excluding fixed ARC overhead.
 */
pub method(NetBuffer) RetainedBytes() -> intptr {
  return self.backing_size;
}

/**
 * @brief Borrow immutable bytes; keep a buffer copy alive for the entire borrow.
 * @returns The NetBytes value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub method(NetBuffer) Bytes() -> NetBytes {
  let view: Result<NetBytes, NetError> = NetBytes.FromRaw(
    self.MutablePointer(0ip) as *const uint8,
    self.count
  );

  return (view.get_if<NetBytes>()) as NetBytes;
}

/**
 * @brief Checked shared slice; an empty slice retains no backing allocation.
 * @returns Ok with NetBuffer on success; Err with NetError on the failure paths described above.
 */
pub method(NetBuffer) Slice(start: intptr, length: intptr) -> Result<NetBuffer, NetError> {
  if start <(0ip) || length <(0ip) || start > self.count || length > self.count - start {
    return NetError{kind: NetErrorKind.InvalidArgument};
  }

  if length == (0ip) {
    return NetBuffer{};
  }

  return NetBuffer{
    storage: self.storage,
    start: self.start + start,
    count: length,
    backing_size: self.backing_size
  };
}
