// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

module NetErrors;
import "stdlib:stdlib.ny";
import "interface/foundation.ni";
import "interface/transport.ni";
import "interface/async_transport.ni";
import "interface/async_resolver.ni";

/** @brief Stable error descriptions independent of errno/WinSock numbering. */

/**
 * @brief Stable English description, returned as an immutable global string.
 * @returns Stable English description, returned as an immutable global string.
 */
pub method(NetError) Message() -> string {
  if self.kind == NetErrorKind.InvalidArgument {
    return "invalid network argument";
  }

  if self.kind == NetErrorKind.InvalidAddress {
    return "invalid IP address";
  }

  if self.kind == NetErrorKind.InvalidPort {
    return "invalid port";
  }

  if self.kind == NetErrorKind.UnsupportedFamily {
    return "unsupported address family";
  }

  if self.kind == NetErrorKind.NameNotFound {
    return "host name not found";
  }

  if self.kind == NetErrorKind.PermissionDenied {
    return "network permission denied";
  }

  if self.kind == NetErrorKind.AddressInUse {
    return "address already in use";
  }

  if self.kind == NetErrorKind.AddressUnavailable {
    return "address unavailable";
  }

  if self.kind == NetErrorKind.ConnectionRefused {
    return "connection refused";
  }

  if self.kind == NetErrorKind.ConnectionReset {
    return "connection reset";
  }

  if self.kind == NetErrorKind.ConnectionAborted {
    return "connection aborted";
  }

  if self.kind == NetErrorKind.NotConnected {
    return "socket is not connected";
  }

  if self.kind == NetErrorKind.NetworkUnreachable {
    return "network unreachable";
  }

  if self.kind == NetErrorKind.HostUnreachable {
    return "host unreachable";
  }

  if self.kind == NetErrorKind.WouldBlock {
    return "operation would block";
  }

  if self.kind == NetErrorKind.TimedOut {
    return "network deadline expired";
  }

  if self.kind == NetErrorKind.Cancelled {
    return "network operation cancelled";
  }

  if self.kind == NetErrorKind.Closed {
    return "socket is closed";
  }

  if self.kind == NetErrorKind.MessageTooLarge {
    return "network message or buffer too large";
  }

  if self.kind == NetErrorKind.NotSupported {
    return "network operation not supported";
  }

  if self.kind == NetErrorKind.UnexpectedEof {
    return "unexpected end of stream";
  }

  return "network system error";
}
