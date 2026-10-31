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
pub method(NetNativeError) AsProduct() -> NetError {
  var kind: NetErrorKind = NetErrorKind.System;
  if self.kind == 1 {
    kind = NetErrorKind.InvalidArgument;
  } else if self.kind == 2 {
    kind = NetErrorKind.InvalidAddress;
  } else if self.kind == 3 {
    kind = NetErrorKind.InvalidPort;
  } else if self.kind == 4 {
    kind = NetErrorKind.UnsupportedFamily;
  } else if self.kind == 5 {
    kind = NetErrorKind.NameNotFound;
  } else if self.kind == 6 {
    kind = NetErrorKind.PermissionDenied;
  } else if self.kind == 7 {
    kind = NetErrorKind.AddressInUse;
  } else if self.kind == 8 {
    kind = NetErrorKind.AddressUnavailable;
  } else if self.kind == 9 {
    kind = NetErrorKind.ConnectionRefused;
  } else if self.kind == 10 {
    kind = NetErrorKind.ConnectionReset;
  } else if self.kind == 11 {
    kind = NetErrorKind.ConnectionAborted;
  } else if self.kind == 12 {
    kind = NetErrorKind.NotConnected;
  } else if self.kind == 13 {
    kind = NetErrorKind.NetworkUnreachable;
  } else if self.kind == 14 {
    kind = NetErrorKind.HostUnreachable;
  } else if self.kind == 15 {
    kind = NetErrorKind.WouldBlock;
  } else if self.kind == 16 {
    kind = NetErrorKind.TimedOut;
  } else if self.kind == 17 {
    kind = NetErrorKind.Cancelled;
  } else if self.kind == 18 {
    kind = NetErrorKind.Closed;
  } else if self.kind == 19 {
    kind = NetErrorKind.MessageTooLarge;
  } else if self.kind == 20 {
    kind = NetErrorKind.NotSupported;
  }

  return NetError{kind: kind, native_code: self.native_code};
}

/**
 * @brief Translate a product IP family into the private native family discriminator.
 * @returns The native discriminator; zero denotes unspecified or unsupported.
 */
pub method(IpFamily) NativeDiscriminator() -> int32 {
  if self == IpFamily.V4 {
    return 4;
  }

  if self == IpFamily.V6 {
    return 6;
  }

  return 0;
}

/**
 * @brief Convert an endpoint value to the pointer-only OS ABI representation.
 * @returns An inline native address record; no descriptor or source storage is owned.
 */
pub method(NetEndpoint) AsNative() -> NetNativeAddress {
  let address: IpAddress = self.Address();
  var out: NetNativeAddress = NetNativeAddress{
    family: (address.Family()).NativeDiscriminator(),
    port: self.Port() as int32,
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
pub method(NetNativeAddress) AsProduct() -> NetEndpoint {
  var ip: IpAddress = IpAddress{};
  if self.family == 4 {
    ip = IpAddress.V4(self.bytes[0], self.bytes[1], self.bytes[2], self.bytes[3]);
  } else {
    ip = IpAddress.V6(self.bytes, self.scope_id);
  }

  let parsed: Result<NetEndpoint, NetError> = NetEndpoint.New(ip, self.port);

  return (parsed.get_if<NetEndpoint>()) as NetEndpoint;
}
