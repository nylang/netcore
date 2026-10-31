// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

module NetAddressValues;
part "endpoint.ny";
import "stdlib:stdlib.ny";
import "interface/foundation.ni";
import "interface/transport.ni";
import "interface/async_transport.ni";
import "interface/async_resolver.ni";

/** @brief Allocation-free IP parsing and canonical formatting helpers. */

/** @brief Validated IP value with inline network-order bytes and numeric scope. */
pub struct IpAddress {
  family_id: IpFamily;
  bytes: <uint8>[16];
  numeric_scope: uint32;
}

struct NetNumber {
  valid: bool;
  value: uint32;
}

static method(NetNumber) Parse(text: ref string, start: int32, end: int32, limit: uint32, strict: bool) -> NetNumber {
  if start < 0 || start >= end || end > text.length {
    return NetNumber{};
  }

  if strict && end - start > 1 && text[start] == '0' {
    return NetNumber{};
  }

  var value: uint32 = 0;
  var i: int32 = start;
  while i < end {
    let ch: int32 = text[i] as int32;
    if ch < 48 || ch > 57 {
      return NetNumber{};
    }

    let digit: uint32 = (ch - 48) as uint32;
    if value > limit / (10u32) || (value == limit / (10u32) && digit > limit % (10u32)) {
      return NetNumber{};
    }

    value = value * (10u32) + digit;
    i = i + 1;
  }

  return NetNumber{valid: true, value: value};
}

method(IpAddress) ReadV4Part(text: ref string, start: int32, end: int32) -> bool {
  var position: int32 = start;
  var octet: int32 = 0;
  while octet < 4 {
    let begin: int32 = position;
    while position < end && text[position] != '.' {
      position = position + 1;
    }

    let number: NetNumber = NetNumber.Parse(text, begin, position, 255u32, true);
    if !number.valid {
      return false;
    }

    unsafe {
      self.bytes[octet] = number.value as uint8;
    }

    octet = octet + 1;
    if octet < 4 {
      if position >= end {
        return false;
      }

      position = position + 1;
    } else if position != end {
      return false;
    }
  }

  unsafe {
    self.family_id = IpFamily.V4;
  }

  return true;
}

// nyra-lint-allow: prefer-type-owned-functions -- Small pure byte classification; no address or parser state.
func net_hex_digit(ch: int32) -> int32 {
  if ch >= 48 && ch <= 57 {
    return ch - 48;
  }

  if ch >= 65 && ch <= 70 {
    return ch - 65 + 10;
  }

  if ch >= 97 && ch <= 102 {
    return ch - 97 + 10;
  }

  return -1;
}

/**
 * @brief Construct an IPv4 address from four octets; allocates nothing.
 * @returns The IpAddress value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub static method(IpAddress) V4(a: uint8, b: uint8, c: uint8, d: uint8) -> IpAddress {
  var out: IpAddress = IpAddress{family_id: IpFamily.V4};
  out.bytes[0] = a;
  out.bytes[1] = b;
  out.bytes[2] = c;
  out.bytes[3] = d;

  return out;
}

/**
 * @brief Copy 16 IPv6 octets and an OS numeric interface scope; allocates nothing.
 * @returns The IpAddress value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub static method(IpAddress) V6(bytes: ref <uint8>[16], scope_id: uint32) -> IpAddress {
  return IpAddress{family_id: IpFamily.V6, bytes: bytes, numeric_scope: scope_id};
}

/**
 * @brief Parse strict decimal IPv4 or IPv6, including a final dotted IPv4 tail.
 * @param text Borrowed literal, without brackets, whitespace, hostname or CIDR.
 * @returns An inline address or InvalidAddress; allocates and retains nothing.
 * @note IPv6 accepts numeric %scope only; interface-name lookup belongs to the OS adapter.
 */
pub static method(IpAddress) Parse(text: ref string) -> Result<IpAddress, NetError> {
  let failure: NetError = NetError{kind: NetErrorKind.InvalidAddress};
  if text.length == 0 || text.length > 64 {
    return failure;
  }

  var end: int32 = text.length;
  var numeric_scope: uint32 = 0;
  var has_colon: bool = false;
  var i: int32 = 0;
  while i < end {
    if text[i] == ':' {
      has_colon = true;
    }

    if text[i] == '%' {
      let parsed: NetNumber = NetNumber.Parse(text, i + 1, end, kUint32Max, false);
      if !parsed.valid || !has_colon {
        return failure;
      }

      numeric_scope = parsed.value;
      end = i;
      break;
    }

    i = i + 1;
  }

  var out: IpAddress = IpAddress{};
  if !has_colon {
    if !(out).ReadV4Part(text, 0, end) {
      return failure;
    }

    return out;
  }

  var words: <uint16>[8] = <uint16>[8] {
  };
  var count: int32 = 0;
  var gap: int32 = -1;
  i = 0;
  if text[0] == ':' {
    if end < 2 || text[1] != ':' {
      return failure;
    }

    gap = 0;
    i = 2;
  }

  while i < end {
    let begin: int32 = i;
    var dotted: bool = false;
    while i < end && text[i] != ':' {
      if text[i] == '.' {
        dotted = true;
      }

      i = i + 1;
    }

    if dotted {
      if count > 6 {
        return failure;
      }

      var tail: IpAddress = IpAddress{};
      if !(tail).ReadV4Part(text, begin, end) {
        return failure;
      }

      words[count] = ((tail.bytes[0] as int32) * 256 + (tail.bytes[1] as int32)) as uint16;
      words[count + 1] = ((tail.bytes[2] as int32) * 256 + (tail.bytes[3] as int32)) as uint16;
      count = count + 2;
      i = end;
      break;
    }

    if count >= 8 || i == begin || i - begin > 4 {
      return failure;
    }

    var value: int32 = 0;
    var cursor: int32 = begin;
    while cursor < i {
      let digit: int32 = net_hex_digit(text[cursor] as int32);
      if digit < 0 {
        return failure;
      }

      value = value * 16 + digit;
      cursor = cursor + 1;
    }

    words[count] = value as uint16;
    count = count + 1;
    if i < end {
      i = i + 1;
      if i == end {
        return failure;
      }

      if text[i] == ':' {
        if gap >= 0 {
          return failure;
        }

        gap = count;
        i = i + 1;
      }
    }
  }

  if gap < 0 && count != 8 {
    return failure;
  }

  if gap >= 0 && count >= 8 {
    return failure;
  }

  let zeros: int32 = 8 - count;
  i = 0;
  while i < 8 {
    var word: uint16 = 0;
    if gap < 0 || i < gap {
      word = words[i];
    } else if i >= gap + zeros {
      word = words[i - zeros];
    }

    out.bytes[i * 2] = ((word as int32) / 256) as uint8;
    out.bytes[i * 2 + 1] = ((word as int32) % 256) as uint8;
    i = i + 1;
  }

  out.family_id = IpFamily.V6;
  out.numeric_scope = numeric_scope;

  return out;
}

/**
 * @brief Address family, or Unspecified for a never-initialized value.
 * @returns The IpFamily value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub method(IpAddress) Family() -> IpFamily {
  return self.family_id;
}

/**
 * @brief Numeric IPv6 interface scope; zero for IPv4 and unscoped IPv6.
 * @returns Numeric IPv6 interface scope; zero for IPv4 and unscoped IPv6.
 */
pub method(IpAddress) ScopeId() -> uint32 {
  return self.numeric_scope;
}

/**
 * @brief Octet in network order; returns InvalidArgument outside 4/16 bytes.
 * @returns Ok with uint8 on success; Err with NetError on the failure paths described above.
 */
pub method(IpAddress) ByteAt(index: int32) -> Result<uint8, NetError> {
  var count: int32 = 0;
  if self.family_id == IpFamily.V4 {
    count = 4;
  }

  if self.family_id == IpFamily.V6 {
    count = 16;
  }

  if index < 0 || index >= count {
    return NetError{kind: NetErrorKind.InvalidArgument};
  }

  return self.bytes[index];
}

/**
 * @brief Whether this is a valid all-zero IPv4/IPv6 address.
 * @returns Whether this is a valid all-zero IPv4/IPv6 address.
 */
pub method(IpAddress) IsUnspecified() -> bool {
  var count: int32 = 4;
  if self.family_id == IpFamily.V6 {
    count = 16;
  } else if self.family_id != IpFamily.V4 {
    return false;
  }

  var i: int32 = 0;
  while i < count {
    if self.bytes[i] != 0 {
      return false;
    }

    i = i + 1;
  }

  return true;
}

/**
 * @brief Whether this is IPv4 127/8 or IPv6 ::1; no implicit family conversion.
 * @returns Whether this is IPv4 127/8 or IPv6 ::1; no implicit family conversion.
 */
pub method(IpAddress) IsLoopback() -> bool {
  if self.family_id == IpFamily.V4 {
    return self.bytes[0] == 127;
  }

  if self.family_id != IpFamily.V6 {
    return false;
  }

  var i: int32 = 0;
  while i < 15 {
    if self.bytes[i] != 0 {
      return false;
    }

    i = i + 1;
  }

  return self.bytes[15] == 1;
}

/**
 * @brief Whether this is an IPv4-mapped IPv6 value (::ffff:0:0/96).
 * @returns Whether this is an IPv4-mapped IPv6 value (::ffff:0:0/96).
 */
pub method(IpAddress) IsV4Mapped() -> bool {
  if self.family_id != IpFamily.V6 {
    return false;
  }

  var i: int32 = 0;
  while i < 10 {
    if self.bytes[i] != 0 {
      return false;
    }

    i = i + 1;
  }

  return self.bytes[10] == 255 && self.bytes[11] == 255;
}

/**
 * @brief Compare family, address bytes and numeric scope; invalid values compare equal.
 * @returns Compare family, address bytes and numeric scope; invalid values compare equal.
 */
pub method(IpAddress) Equals(other: ref IpAddress) -> bool {
  if self.family_id != other.family_id || self.numeric_scope != other.numeric_scope {
    return false;
  }

  var i: int32 = 0;
  while i < 16 {
    if self.bytes[i] != other.bytes[i] {
      return false;
    }

    i = i + 1;
  }

  return true;
}

// Canonical numeric address output is locale independent.
struct NetAddressWriter {
  buffer: FastString;
}

method(NetAddressWriter) AppendDecimal(value: uint32) -> void {
  self.buffer.Append(value.ToString());
}


method(IpAddress) Word(index: int32) -> int32 {
  return (self.bytes[index * 2] as int32) * 256 + (self.bytes[index * 2 + 1] as int32);
}

method(NetAddressWriter) AppendHex(value: int32) -> void {
  let alphabet: string = "0123456789abcdef";
  var divisor: int32 = 4096;
  while divisor > 1 && value / divisor == 0 {
    divisor = divisor / 16;
  }

  while divisor > 0 {
    unsafe {
      self.buffer.PushByte(alphabet[(value / divisor) % 16] as uint8);
    }

    divisor = divisor / 16;
  }
}

method(NetAddressWriter) AppendV4(address: ref IpAddress, start: int32) -> void {
  var i: int32 = 0;
  while i < 4 {
    if i > 0 {
      unsafe {
        self.buffer.PushByte(46u8);
      }
    }

    self.AppendDecimal(address.bytes[start + i] as uint32);
    i = i + 1;
  }
}

// Render address bytes directly so canonical numeric output does not depend on a resolver or locale.
method(NetAddressWriter) Render(address: ref IpAddress) -> void {
  if address.family_id == IpFamily.V4 {
    self.AppendV4(address, 0);
    return;
  }

  if address.IsV4Mapped() {
    unsafe {
      self.buffer.Append("::ffff:");
    }

    self.AppendV4(address, 12);
  } else {
    var best_start: int32 = -1;
    var best_length: int32 = 0;
    var i: int32 = 0;
    while i < 8 {
      if (address).Word(i) != 0 {
        i = i + 1;
        continue;
      }

      let start: int32 = i;
      while i < 8 && (address).Word(i) == 0 {
        i = i + 1;
      }

      if i - start >= 2 && i - start > best_length {
        best_start = start;
        best_length = i - start;
      }
    }

    i = 0;
    while i < 8 {
      if i == best_start {
        unsafe {
          self.buffer.Append("::");
        }

        i = i + best_length;
        continue;
      }

      if i > 0 && i != best_start + best_length {
        unsafe {
          self.buffer.PushByte(58u8);
        }
      }

      self.AppendHex((address).Word(i));
      i = i + 1;
    }
  }

  if address.numeric_scope != 0 {
    unsafe {
      self.buffer.PushByte(37u8);
    }

    self.AppendDecimal(address.numeric_scope);
  }
}

/**
 * @brief Owned textual address; lowercase/longest-leftmost IPv6 zero compression.
 * @returns ARC-managed string, or empty for an invalid value; mapped IPv6 uses a dotted tail.
 */
pub method(IpAddress) ToString() -> string {
  if self.family_id == IpFamily.Unspecified {
    return "";
  }

  var out: NetAddressWriter = NetAddressWriter{buffer: FastString.NewWithCapacity(64)};
  (out).Render(self);

  return out.buffer.ToString();
}
