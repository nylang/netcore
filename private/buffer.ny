// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

module NetByteViews;
import "stdlib:stdlib.ny";
import "interface/foundation.ni";
import "interface/transport.ni";
import "interface/async_transport.ni";
import "interface/async_resolver.ni";

/** @brief Non-owning ranges used only while an operation retains the backing owner. */

/**
 * @brief Non-owning read-only byte range; copying never retains its backing store.
 * @note The owner must outlive every use. Do not queue this view without retaining an owner.
 */
pub struct NetBytes {
  address: *const uint8;
  count: intptr;
}

/**
 * @brief Non-owning mutable range; copying does not establish exclusive access.
 * @note Caller prevents concurrent/overlapping mutation and keeps the owner alive.
 */
pub struct NetMutableBytes {
  address: *mut uint8;
  count: intptr;
}

/**
 * @brief Borrow readable memory; rejects negative lengths and null nonempty ranges.
 * @param data Caller guarantees at least length accessible bytes for the view's lifetime.
 * @returns Borrowed view or InvalidArgument; an empty null range is valid.
 */
pub static method(NetBytes) FromRaw(data: *const uint8, length: intptr) -> Result<NetBytes, NetError> {
  if length < 0 || (length > 0 && data == nil) {
    return NetError{kind: NetErrorKind.InvalidArgument};
  }

  return NetBytes{address: data, count: length};
}

/**
 * @brief Borrow a string's bytes; caller keeps the string alive and unchanged.
 * @returns The NetBytes value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub static method(NetBytes) FromString(text: ref string) -> NetBytes {
  return NetBytes{address: text.data as *const uint8, count: text.length as intptr};
}

/**
 * @brief Borrowed address; never transfer or free it.
 * @returns The *const uint8 value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub method(NetBytes) Data() -> *const uint8 {
  return self.address;
}

/**
 * @brief Number of readable bytes.
 * @returns Number of readable bytes.
 */
pub method(NetBytes) Len() -> intptr {
  return self.count;
}

/**
 * @brief Borrow a checked subrange; validates with subtraction to avoid overflow.
 * @returns Ok with NetBytes on success; Err with NetError on the failure paths described above.
 */
pub method(NetBytes) Slice(start: intptr, length: intptr) -> Result<NetBytes, NetError> {
  if start < 0 || length < 0 || start > self.count || length > self.count - start {
    return NetError{kind: NetErrorKind.InvalidArgument};
  }

  return NetBytes{address:((self.address as uintptr) + (start as uintptr)) as *const uint8, count: length};
}

/**
 * @brief Borrow writable memory under the same bounds/lifetime contract as NetBytes.FromRaw.
 * @returns Ok with NetMutableBytes on success; Err with NetError on the failure paths described
 *   above.
 */
pub static method(NetMutableBytes) FromRaw(
  data: *mut uint8,
  length: intptr
) -> Result<NetMutableBytes, NetError> {
  if length < 0 || (length > 0 && data == nil) {
    return NetError{kind: NetErrorKind.InvalidArgument};
  }

  return NetMutableBytes{address: data, count: length};
}

/**
 * @brief Borrowed writable address; never transfer or free it.
 * @returns The *mut uint8 value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub method(NetMutableBytes) Data() -> *mut uint8 {
  return self.address;
}

/**
 * @brief Number of writable bytes.
 * @returns Number of writable bytes.
 */
pub method(NetMutableBytes) Len() -> intptr {
  return self.count;
}

/**
 * @brief Borrow a checked subrange; caller preserves exclusive mutation.
 * @returns Ok with NetMutableBytes on success; Err with NetError on the failure paths described
 *   above.
 */
pub method(NetMutableBytes) Slice(start: intptr, length: intptr) -> Result<NetMutableBytes, NetError> {
  if start < 0 || length < 0 || start > self.count || length > self.count - start {
    return NetError{kind: NetErrorKind.InvalidArgument};
  }

  return NetMutableBytes{
    address:((self.address as uintptr) + (start as uintptr)) as *mut uint8,
    count: length
  };
}

/**
 * @brief Read-only view of the same memory; does not extend its lifetime.
 * @returns The NetBytes value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub method(NetMutableBytes) AsReadOnly() -> NetBytes {
  return NetBytes{address: self.address as *const uint8, count: self.count};
}
