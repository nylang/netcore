// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

part of NetAddressValues;

/** @brief Literal endpoint parsing, independent of native sockaddr packing. */

/** @brief IP address and host-order port; independent of native sockaddr layout. */
pub struct NetEndpoint {
  ip: IpAddress;
  port_number: uint16;
}

/**
 * @brief Combine a valid address and port (0..65535); no allocation.
 * @returns Ok with NetEndpoint on success; Err with NetError on the failure paths described
 *   above.
 */
pub static method(NetEndpoint) New(address: ref IpAddress, port: int32) -> Result<NetEndpoint, NetError> {
  if address.Family() == IpFamily.Unspecified {
    return NetError{kind: NetErrorKind.InvalidAddress};
  }

  if port < 0 || port > 65535 {
    return NetError{kind: NetErrorKind.InvalidPort};
  }

  return NetEndpoint{ip: address, port_number: port as uint16};
}

/**
 * @brief Parse IPv4:port or [IPv6%scope]:port; hostnames require a resolver.
 * @returns Inline endpoint or validation failure; no allocation or retained text.
 * @note Port zero is valid for local ephemeral binding. Brackets are mandatory for IPv6.
 */
pub static method(NetEndpoint) Parse(text: ref string) -> Result<NetEndpoint, NetError> {
  if text.length < 3 || text.length > 72 {
    return NetError{kind: NetErrorKind.InvalidAddress};
  }

  var begin: int32 = 0;
  var end: int32 = 0;
  var port_start: int32 = 0;
  let bracketed: bool = text[0] == '[';
  if bracketed {
    begin = 1;
    end = 1;
    while end < text.length && text[end] != ']' {
      end = end + 1;
    }

    if end + 1 >= text.length || text[end + 1] != ':' {
      return NetError{kind: NetErrorKind.InvalidAddress};
    }

    port_start = end + 2;
  } else {
    while end < text.length && text[end] != ':' {
      end = end + 1;
    }

    if end == text.length {
      return NetError{kind: NetErrorKind.InvalidAddress};
    }

    port_start = end + 1;
  }

  let address_text: string = text.Slice(begin, end);
  let parsed: Result<IpAddress, NetError> = IpAddress.Parse(address_text);
  let failure: NetError? = parsed.get_if<NetError>();
  if failure != nil {
    return failure as NetError;
  }

  let address: IpAddress = (parsed.get_if<IpAddress>()) as IpAddress;
  if (bracketed && address.Family() != IpFamily.V6) || (!bracketed && address.Family() != IpFamily.V4) {
    return NetError{kind: NetErrorKind.InvalidAddress};
  }

  let port: NetNumber = net_parse_decimal(text, port_start, text.length, 65535 as uint32, false);
  if !port.valid {
    return NetError{kind: NetErrorKind.InvalidPort};
  }

  return NetEndpoint{ip: address, port_number: port.value as uint16};
}

/**
 * @brief Copy the inline IP value; no allocation.
 * @returns The IpAddress value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub method(NetEndpoint) Address() -> IpAddress {
  return self.ip;
}

/**
 * @brief Host-order port.
 * @returns The uint16 value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub method(NetEndpoint) Port() -> uint16 {
  return self.port_number;
}

/**
 * @brief Compare address, scope and port; no allocation.
 * @returns Compare address, scope and port; no allocation.
 */
pub method(NetEndpoint) Equals(other: ref NetEndpoint) -> bool {
  return self.port_number == other.port_number && self.ip.Equals(other.ip);
}

/**
 * @brief Owned endpoint text; brackets surround IPv6. Invalid values return empty.
 * @returns Owned endpoint text; brackets surround IPv6. Invalid values return empty.
 */
pub method(NetEndpoint) ToString() -> string {
  if self.ip.Family() == IpFamily.Unspecified {
    return "";
  }

  var out: FastString = FastString.NewWithCapacity(72);
  if self.ip.Family() == IpFamily.V6 {
    out.PushByte(91 as uint8);
  }

  net_append_address(&mut out, self.ip);
  if self.ip.Family() == IpFamily.V6 {
    out.PushByte(93 as uint8);
  }

  out.PushByte(58 as uint8);
  net_append_decimal(&mut out, self.port_number as uint32);

  return out.ToString();
}
