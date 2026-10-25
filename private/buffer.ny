/** @brief Non-owning ranges used only while an operation retains the backing owner. */
part of NetFoundation;

pub struct NetBytes { address: *const uint8; count: intptr; }
pub struct NetMutableBytes { address: *mut uint8; count: intptr; }

/** @brief Validate range metadata; accessible storage remains the caller's obligation. */
pub static method(NetBytes) FromRaw(data: *const uint8,length: intptr) -> Result<NetBytes, NetError> {
  if length < 0 || (length > 0 && data == nil) { return NetError{kind:NetErrorKind.InvalidArgument}; }
  return NetBytes{address:data,count:length};
}
/** @brief Borrow string bytes without allocation or retention. */
pub static method(NetBytes) FromString(text: ref string) -> NetBytes {
  return NetBytes{address:text.data as *const uint8,count:text.length as intptr};
}
/** @brief Return the borrowed read-only pointer. */
pub method(NetBytes) Data() -> *const uint8 { return self.address; }
/** @brief Return the number of readable bytes. */
pub method(NetBytes) Len() -> intptr { return self.count; }
/** @brief Subtraction-based bounds checks avoid start+length integer overflow. */
pub method(NetBytes) Slice(start: intptr,length: intptr) -> Result<NetBytes, NetError> {
  if start < 0 || length < 0 || start > self.count || length > self.count-start {
    return NetError{kind:NetErrorKind.InvalidArgument};
  }
  return NetBytes{address:((self.address as uintptr)+(start as uintptr)) as *const uint8,count:length};
}
/** @brief Borrow writable storage; this call neither creates ownership nor checks aliasing. */
pub static method(NetMutableBytes) FromRaw(data: *mut uint8,length: intptr) -> Result<NetMutableBytes, NetError> {
  if length < 0 || (length > 0 && data == nil) { return NetError{kind:NetErrorKind.InvalidArgument}; }
  return NetMutableBytes{address:data,count:length};
}
/** @brief Return the borrowed writable pointer. */
pub method(NetMutableBytes) Data() -> *mut uint8 { return self.address; }
/** @brief Return the number of writable bytes. */
pub method(NetMutableBytes) Len() -> intptr { return self.count; }
/** @brief Borrow a checked writable subrange without allocation or retention. */
pub method(NetMutableBytes) Slice(start: intptr,length: intptr) -> Result<NetMutableBytes, NetError> {
  if start < 0 || length < 0 || start > self.count || length > self.count-start {
    return NetError{kind:NetErrorKind.InvalidArgument};
  }
  return NetMutableBytes{address:((self.address as uintptr)+(start as uintptr)) as *mut uint8,count:length};
}
/** @brief Borrow the same range through a read-only pointer. */
pub method(NetMutableBytes) AsReadOnly() -> NetBytes {
  return NetBytes{address:self.address as *const uint8,count:self.count};
}
