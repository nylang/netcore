// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

module NetNativeMapping;
import "stdlib:stdlib.ny";
import "interface/foundation.ni";
import "interface/transport.ni";
import "interface/async_transport.ni";
import "interface/async_resolver.ni";
import "private/native_abi.ni";

/** @brief Private fixed-width pointer-only C ABI; no native struct crosses by value. */

// Translate native errors once at the boundary so socket and DNS callers share the public error taxonomy.
/**
 * @brief Translate the fixed native error record into the product error taxonomy.
 * @returns The mapped kind with its original native code retained.
 */
pub func NetMapNativeError(error: ref NetNativeError) -> NetError {
  var kind: NetErrorKind = NetErrorKind.System;
  if error.kind == 1 {
    kind = NetErrorKind.InvalidArgument;
  } else if error.kind == 2 {
    kind = NetErrorKind.InvalidAddress;
  } else if error.kind == 3 {
    kind = NetErrorKind.InvalidPort;
  } else if error.kind == 4 {
    kind = NetErrorKind.UnsupportedFamily;
  } else if error.kind == 5 {
    kind = NetErrorKind.NameNotFound;
  } else if error.kind == 6 {
    kind = NetErrorKind.PermissionDenied;
  } else if error.kind == 7 {
    kind = NetErrorKind.AddressInUse;
  } else if error.kind == 8 {
    kind = NetErrorKind.AddressUnavailable;
  } else if error.kind == 9 {
    kind = NetErrorKind.ConnectionRefused;
  } else if error.kind == 10 {
    kind = NetErrorKind.ConnectionReset;
  } else if error.kind == 11 {
    kind = NetErrorKind.ConnectionAborted;
  } else if error.kind == 12 {
    kind = NetErrorKind.NotConnected;
  } else if error.kind == 13 {
    kind = NetErrorKind.NetworkUnreachable;
  } else if error.kind == 14 {
    kind = NetErrorKind.HostUnreachable;
  } else if error.kind == 15 {
    kind = NetErrorKind.WouldBlock;
  } else if error.kind == 16 {
    kind = NetErrorKind.TimedOut;
  } else if error.kind == 17 {
    kind = NetErrorKind.Cancelled;
  } else if error.kind == 18 {
    kind = NetErrorKind.Closed;
  } else if error.kind == 19 {
    kind = NetErrorKind.MessageTooLarge;
  } else if error.kind == 20 {
    kind = NetErrorKind.NotSupported;
  }

  return NetError{kind: kind, native_code: error.native_code};
}

/**
 * @brief Translate a product IP family into the private native family discriminator.
 * @returns The native discriminator; zero denotes unspecified or unsupported.
 */
pub func NetNativeFamily(family: IpFamily) -> int32 {
  if family == IpFamily.V4 {
    return 4;
  }

  if family == IpFamily.V6 {
    return 6;
  }

  return 0;
}

/**
 * @brief Convert an endpoint value to the pointer-only OS ABI representation.
 * @returns An inline native address record; no descriptor or source storage is owned.
 */
pub func NetEncodeNativeAddress(endpoint: ref NetEndpoint) -> NetNativeAddress {
  let address: IpAddress = endpoint.Address();
  var out: NetNativeAddress = NetNativeAddress{
    family: NetNativeFamily(address.Family()),
    port: endpoint.Port() as int32,
    scope_id: address.ScopeId()
  };
  var count: int32 = 0;
  if out.family == 4 {
    count = 4;
  } else if out.family == 6 {
    count = 16;
  }

  var i: int32 = 0;
  while i<count {
    let item: Result<uint8, NetError> = address.ByteAt(i);
    out.bytes[i] = (item.get_if<uint8>()) as uint8;
    i = i + 1;
  }

  return out;
}

/**
 * @brief Convert a completed native address record into a product endpoint value.
 * @returns An inline endpoint preserving address bytes, port and scope.
 */
pub func NetProductEndpoint(address: ref NetNativeAddress) -> NetEndpoint {
  var ip: IpAddress = IpAddress{};
  if address.family == 4 {
    ip = IpAddress.V4(address.bytes[0], address.bytes[1], address.bytes[2], address.bytes[3]);
  } else {
    ip = IpAddress.V6(address.bytes, address.scope_id);
  }

  let parsed: Result<NetEndpoint, NetError> = NetEndpoint.New(ip, address.port);

  return (parsed.get_if<NetEndpoint>()) as NetEndpoint;
}
