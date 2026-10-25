/** @brief Immutable shared buffers for pending and completed asynchronous transfers. */
part of NetTransport;

/** @brief Closed shared storage; only private receive operations can write before publication. */
pub struct NetBuffer {
  storage: arc<owned <uint8>[]>?;
  start: intptr;
  count: intptr;
  backing_size: intptr;
}

func net_buffer_allocate(size: int32) -> NetBuffer {
  if size == 0 { return NetBuffer{}; }
  unsafe {
    let storage: arc<owned <uint8>[]> = new arc <uint8>[size];
    return NetBuffer{storage: storage, count: size as intptr, backing_size: size as intptr};
  }
}
func net_buffer_pointer(buffer: ref NetBuffer, offset: intptr) -> *mut uint8 {
  let optional: arc<owned <uint8>[]>? = buffer.storage;
  if optional == nil { return 0 as *mut uint8; }
  var storage: arc<owned <uint8>[]> = optional as arc<owned <uint8>[]>;
  unsafe {
    return (((&mut storage[0]) as intptr) + buffer.start + offset) as *mut uint8;
  }
}
/** @brief Make one owned immutable copy; no input pointer survives this call. */
pub static method(NetBuffer) CopyFrom(bytes: ref NetBytes) -> Result<NetBuffer, NetError> {
  if bytes.Len() > (2147483647 as intptr) { return NetError{kind: NetErrorKind.MessageTooLarge}; }
  let buffer: NetBuffer = net_buffer_allocate(bytes.Len() as int32);
  if bytes.Len() > (0 as intptr) {
    unsafe { memcpy(net_buffer_pointer(buffer, 0 as intptr), bytes.Data(), bytes.Len() as uintptr); }
  }
  return buffer;
}
/** @brief Visible byte count. */
pub method(NetBuffer) Len() -> intptr { return self.count; }
/** @brief Retained root byte size, not only visible slice size. */
pub method(NetBuffer) RetainedBytes() -> intptr { return self.backing_size; }
/** @brief Borrow the immutable visible range without allocating or retaining another owner. */
pub method(NetBuffer) Bytes() -> NetBytes {
  let view: Result<NetBytes, NetError> = NetBytes.FromRaw(net_buffer_pointer(self, 0 as intptr) as *const uint8, self.count);
  return (view.get_if<NetBytes>()) as NetBytes;
}
/** @brief Share a checked subrange; zero length releases any root retention in the result. */
pub method(NetBuffer) Slice(start: intptr, length: intptr) -> Result<NetBuffer, NetError> {
  if start < (0 as intptr) || length < (0 as intptr) || start > self.count || length > self.count - start {
    return NetError{kind: NetErrorKind.InvalidArgument};
  }
  if length == (0 as intptr) { return NetBuffer{}; }
  return NetBuffer{storage: self.storage, start: self.start + start, count: length, backing_size: self.backing_size};
}
