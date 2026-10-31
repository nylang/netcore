// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

part of NetContractTests;

/** @brief Foundation boundaries exercised by the portable desktop acceptance runner. */

// Immutable input/expectation values; no socket, driver or process state.
struct NetIpCase {
  text: string;
  canonical: string;
}

struct NetEndpointCase {
  text: string;
  kind: NetErrorKind;
}

method(NetIpCase) Reject() -> void {
  let result: Result<IpAddress, NetError> = IpAddress.Parse(self.text);
  AssertTrueMsg(result.IsErr(), self.text);
  if result.IsErr() {
    let error: NetError = (result.get_if<NetError>()) as NetError;
    AssertTrueMsg(error.kind == NetErrorKind.InvalidAddress && error.native_code == 0, self.text);
  }
}

method(NetIpCase) CheckCanonical() -> void {
  let result: Result<IpAddress, NetError> = IpAddress.Parse(self.text);
  AssertTrueMsg(result.IsOk(), self.text);
  if result.IsErr() {
    return;
  }

  let address: IpAddress = (result.get_if<IpAddress>()) as IpAddress;
  AssertEqStringMsg(address.ToString(), self.canonical, self.text);
  let reparsed: Result<IpAddress, NetError> = IpAddress.Parse(address.ToString());
  AssertTrueMsg(reparsed.IsOk(), self.canonical);
  if reparsed.IsOk() {
    AssertTrueMsg(address.Equals((reparsed.get_if<IpAddress>()) as IpAddress), self.canonical);
  }
}

@test(tag = "net_core_n3")
func test_net_core_n3_foundation_ipv4_boundaries() {
  NetIpCase{text: ""}.Reject();
  NetIpCase{text: "1.2.3"}.Reject();
  NetIpCase{text: "1.2.3.4.5"}.Reject();
  NetIpCase{text: "1..3.4"}.Reject();
  NetIpCase{text: "1.2.3."}.Reject();
  NetIpCase{text: "256.0.0.1"}.Reject();
  NetIpCase{text: "01.2.3.4"}.Reject();
  NetIpCase{text: "+1.2.3.4"}.Reject();
  NetIpCase{text: " 1.2.3.4"}.Reject();
  NetIpCase{text: "1.2.3.4 "}.Reject();
  NetIpCase{text: "1.2.3.4/24"}.Reject();
  NetIpCase{text: "1.2.3.4%1"}.Reject();
  NetIpCase{text: "localhost"}.Reject();
  NetIpCase{text: "0.0.0.0", canonical: "0.0.0.0"}.CheckCanonical();
  NetIpCase{text: "255.255.255.255", canonical: "255.255.255.255"}.CheckCanonical();
  let zero: IpAddress = IpAddress.V4(0u8, 0u8, 0u8, 0u8);
  let loopback: IpAddress = IpAddress.V4(127u8, 255u8, 255u8, 255u8);
  AssertTrueMsg(zero.IsUnspecified(), "IPv4 zero is a valid unspecified address");
  AssertTrueMsg(loopback.IsLoopback(), "all of 127/8 is loopback");
  AssertTrueMsg(loopback.ByteAt(-1).IsErr() && loopback.ByteAt(4).IsErr(), "IPv4 octet bounds");
  AssertEqI32Msg((loopback.ByteAt(3).get_if<uint8>() as uint8) as int32, 255, "last IPv4 octet");
  let invalid: IpAddress = IpAddress{};
  AssertTrueMsg(!invalid.IsUnspecified() && invalid.ByteAt(0).IsErr(), "default address is invalid");
  AssertEqStringMsg(invalid.ToString(), "", "invalid address has no text");
}

@test(tag = "net_core_n3")
func test_net_core_n3_foundation_ipv6_boundaries() {
  NetIpCase{text: ":"}.Reject();
  NetIpCase{text: ":::1"}.Reject();
  NetIpCase{text: "1::2::3"}.Reject();
  NetIpCase{text: "1:2:3:4:5:6:7"}.Reject();
  NetIpCase{text: "1:2:3:4:5:6:7:8:9"}.Reject();
  NetIpCase{text: "1:2:3:4:5:6:7:8::"}.Reject();
  NetIpCase{text: "1:2:3:4:5:6:7:"}.Reject();
  NetIpCase{text: "12345::"}.Reject();
  NetIpCase{text: "gggg::"}.Reject();
  NetIpCase{text: "[::1]"}.Reject();
  NetIpCase{text: "::ffff:192.168.001.1"}.Reject();
  NetIpCase{text: "::ffff:256.0.0.1"}.Reject();
  NetIpCase{text: "fe80::1%"}.Reject();
  NetIpCase{text: "fe80::1%en0"}.Reject();
  NetIpCase{text: "fe80::1%4294967296"}.Reject();
  NetIpCase{text: "fe80::1%1%2"}.Reject();
  NetIpCase{text: "0:0:0:0:0:0:0:0", canonical: "::"}.CheckCanonical();
  NetIpCase{text: "0:0:0:0:0:0:0:1", canonical: "::1"}.CheckCanonical();
  NetIpCase{text: "2001:0DB8:0:0:1:0:0:1", canonical: "2001:db8::1:0:0:1"}.CheckCanonical();
  NetIpCase{text: "1:0:2:3:4:5:6:7", canonical: "1:0:2:3:4:5:6:7"}.CheckCanonical();
  NetIpCase{text: "1:2:3:4:5:6:0:0", canonical: "1:2:3:4:5:6::"}.CheckCanonical();
  NetIpCase{text: "::FFFF:C000:0280", canonical: "::ffff:192.0.2.128"}.CheckCanonical();
  NetIpCase{text: "FE80::1%4294967295", canonical: "fe80::1%4294967295"}.CheckCanonical();
  NetIpCase{text: "fe80::1%0002", canonical: "fe80::1%2"}.CheckCanonical();
  NetIpCase{text: "::1%0", canonical: "::1"}.CheckCanonical();
  let scoped: IpAddress = (IpAddress.Parse("fe80::1%4294967295").get_if<IpAddress>()) as IpAddress;
  let unscoped: IpAddress = (IpAddress.Parse("fe80::1").get_if<IpAddress>()) as IpAddress;
  AssertTrueMsg(
    scoped.ScopeId() == 4294967295u32 && !scoped.Equals(unscoped),
    "scope participates in identity"
  );
  AssertTrueMsg(scoped.ByteAt(-1).IsErr() && scoped.ByteAt(16).IsErr(), "IPv6 octet bounds");
  AssertEqI32Msg((scoped.ByteAt(15).get_if<uint8>() as uint8) as int32, 1, "last IPv6 octet");
}

method(NetEndpointCase) Reject() -> void {
  let result: Result<NetEndpoint, NetError> = NetEndpoint.Parse(self.text);
  AssertTrueMsg(result.IsErr(), self.text);
  if result.IsErr() {
    AssertTrueMsg(((result.get_if<NetError>()) as NetError).kind == self.kind, self.text);
  }
}

@test(tag = "net_core_n3")
func test_net_core_n3_foundation_endpoint_boundaries() {
  NetEndpointCase{text: "::1:80", kind: NetErrorKind.InvalidAddress}.Reject();
  NetEndpointCase{text: "[127.0.0.1]:80", kind: NetErrorKind.InvalidAddress}.Reject();
  NetEndpointCase{text: "[::1:80", kind: NetErrorKind.InvalidAddress}.Reject();
  NetEndpointCase{text: "[::1]80", kind: NetErrorKind.InvalidAddress}.Reject();
  NetEndpointCase{text: "localhost:80", kind: NetErrorKind.InvalidAddress}.Reject();
  NetEndpointCase{text: "127.0.0.1:", kind: NetErrorKind.InvalidPort}.Reject();
  NetEndpointCase{text: "127.0.0.1:-1", kind: NetErrorKind.InvalidPort}.Reject();
  NetEndpointCase{text: "127.0.0.1:65536", kind: NetErrorKind.InvalidPort}.Reject();
  NetEndpointCase{text: "[::1]:80x", kind: NetErrorKind.InvalidPort}.Reject();
  let low: NetEndpoint = (NetEndpoint.Parse("0.0.0.0:0").get_if<NetEndpoint>()) as NetEndpoint;
  let high: NetEndpoint = (NetEndpoint.Parse("[fe80::1%2]:65535").get_if<NetEndpoint>()) as NetEndpoint;
  AssertTrueMsg(low.Port() == 0u16 && high.Port() == 65535u16, "endpoint inclusive port bounds");
  AssertEqStringMsg(high.ToString(), "[fe80::1%2]:65535", "scoped endpoint text");
  let address: IpAddress = high.Address();
  let rebuilt: NetEndpoint = (NetEndpoint.New(address, 65535).get_if<NetEndpoint>()) as NetEndpoint;
  AssertTrueMsg(high.Equals(rebuilt), "endpoint round trip");
  AssertTrueMsg(
    NetEndpoint.New(address, -1).IsErr() && NetEndpoint.New(address, 65536).IsErr(),
    "constructor rejects port overflow"
  );
  AssertTrueMsg(NetEndpoint.New(IpAddress{}, 0).IsErr(), "constructor rejects invalid address");
}

@test(tag = "net_core_n3")
func test_net_core_n3_foundation_read_view_ranges() {
  AssertTrueMsg(NetBytes.FromRaw(0 as *const uint8, -1 as intptr).IsErr(), "negative byte count");
  AssertTrueMsg(NetBytes.FromRaw(0 as *const uint8, 1 as intptr).IsErr(), "null nonempty range");
  let empty: NetBytes = (NetBytes.FromRaw(0 as *const uint8, 0 as intptr).get_if<NetBytes>()) as NetBytes;
  AssertTrueMsg(empty.Slice(0 as intptr, 0 as intptr).IsOk(), "empty null slice");
  let text: string = "abcd";
  let bytes: NetBytes = NetBytes.FromString(text);
  let tail: NetBytes = (bytes.Slice(4 as intptr, 0 as intptr).get_if<NetBytes>()) as NetBytes;
  AssertTrueMsg(
    tail.Len() == 0 && tail.Data() as uintptr == (bytes.Data() as uintptr) + 4up,
    "one-past empty slice"
  );
  AssertTrueMsg(bytes.Slice(-1 as intptr, 0 as intptr).IsErr(), "negative start");
  AssertTrueMsg(bytes.Slice(0 as intptr, -1 as intptr).IsErr(), "negative length");
  AssertTrueMsg(bytes.Slice(5 as intptr, 0 as intptr).IsErr(), "start past end");
  AssertTrueMsg(bytes.Slice(3 as intptr, 2 as intptr).IsErr(), "length past end");
  let limit: intptr = 9223372036854775807i64 as intptr;
  AssertTrueMsg(
    bytes.Slice(1 as intptr, limit).IsErr() && bytes.Slice(limit, limit).IsErr(),
    "overflowing subrange is rejected before pointer arithmetic"
  );
  let middle: NetBytes = (bytes.Slice(1 as intptr, 2 as intptr).get_if<NetBytes>()) as NetBytes;
  AssertEqStringMsg(
    string.ViewFrom(middle.Data() as *const int8, middle.Len() as int32),
    "bc",
    "slice points into original storage"
  );
}

@test(tag = "net_core_n3")
func test_net_core_n3_foundation_mutable_ranges() {
  AssertTrueMsg(
    NetMutableBytes.FromRaw(0 as *mut uint8, -1 as intptr).IsErr(),
    "negative writable count"
  );
  AssertTrueMsg(
    NetMutableBytes.FromRaw(0 as *mut uint8, 1 as intptr).IsErr(),
    "null writable nonempty range"
  );
  let empty: NetMutableBytes = (NetMutableBytes.FromRaw(
    0 as *mut uint8,
    0 as intptr
  ).get_if<NetMutableBytes>()) as NetMutableBytes;
  AssertTrueMsg(empty.Slice(0 as intptr, 0 as intptr).IsOk(), "empty writable null slice");
  var storage: <uint8>[4] = <uint8>[4] {
  };
  let bytes: NetMutableBytes = (NetMutableBytes.FromRaw(
    &mut storage[0],
    4 as intptr
  ).get_if<NetMutableBytes>()) as NetMutableBytes;
  AssertTrueMsg(
    bytes.Slice(-1 as intptr, 0 as intptr).IsErr() && bytes.Slice(0 as intptr, -1 as intptr).IsErr(),
    "negative writable slice bounds"
  );
  AssertTrueMsg(
    bytes.Slice(5 as intptr, 0 as intptr).IsErr() && bytes.Slice(3 as intptr, 2 as intptr).IsErr(),
    "writable slice past end"
  );
  let limit: intptr = 9223372036854775807i64 as intptr;
  AssertTrueMsg(
    bytes.Slice(1 as intptr, limit).IsErr() && bytes.Slice(limit, limit).IsErr(),
    "writable range overflow"
  );
  let tail: NetMutableBytes = (bytes.Slice(
    4 as intptr,
    0 as intptr
  ).get_if<NetMutableBytes>()) as NetMutableBytes;
  AssertTrueMsg(
    tail.Len() == 0 && tail.Data() as uintptr == (bytes.Data() as uintptr) + 4up,
    "writable one-past empty slice"
  );
  let middle: NetMutableBytes = (bytes.Slice(
    1 as intptr,
    2 as intptr
  ).get_if<NetMutableBytes>()) as NetMutableBytes;
  unsafe {
    (*middle.Data()) = 42u8;
  }

  let read_view: NetBytes = middle.AsReadOnly();
  AssertTrueMsg(storage[1] == 42u8 && read_view.Len() == 2, "mutable slice aliases original memory");
  unsafe {
    AssertTrueMsg(read_view.Data()[0] == 42u8, "read-only projection retains address");
  }
}

@test(tag = "net_core_n3")
func test_net_core_n3_foundation_deadline_arithmetic() {
  let limit: uint64 = 18446744073709551615u64;
  let unlimited: NetDeadline = NetDeadline{};
  AssertTrueMsg(!unlimited.IsFinite() && !unlimited.IsExpired(limit), "default deadline is unlimited");
  AssertTrueMsg(unlimited.RemainingNanoseconds(limit) == limit, "unlimited remaining sentinel");
  AssertEqI32Msg(NetDeadline.Never().PollMilliseconds(limit), -1, "unlimited native wait");
  AssertTrueMsg(NetDeadline.At(0u64).IsExpired(0u64), "zero absolute deadline is finite and expired");
  AssertEqI32Msg(NetDeadline.After(10u64, 0u64).PollMilliseconds(10u64), 0, "zero timeout");
  AssertEqI32Msg(NetDeadline.At(1000001u64).PollMilliseconds(1000000u64), 1, "one nanosecond rounds up");
  AssertEqI32Msg(NetDeadline.At(1000000u64).PollMilliseconds(0u64), 1, "exact millisecond");
  AssertEqI32Msg(
    NetDeadline.At(1000001u64).PollMilliseconds(0u64),
    2,
    "fractional millisecond rounds up"
  );
  AssertEqI32Msg(
    NetDeadline.At(2147483647000001u64).PollMilliseconds(0u64),
    2147483647,
    "native wait saturation"
  );
  let saturated: NetDeadline = NetDeadline.After(limit - 5u64, 10u64);
  AssertTrueMsg(
    saturated.IsFinite() && !saturated.IsExpired(limit - 1u64),
    "saturated deadline stays finite in the future"
  );
  AssertTrueMsg(
    saturated.RemainingNanoseconds(limit - 5u64) == 5u64,
    "addition saturates without wrapping"
  );
  AssertTrueMsg(
    saturated.IsExpired(limit) && saturated.RemainingNanoseconds(limit) == 0u64,
    "deadline expires at equality"
  );
}

@test(tag = "net_core_n3")
func test_net_core_n3_foundation_cancellation_controls() {
  let none: NetCancellation = NetCancellation.None();
  none.Cancel();
  AssertTrueMsg(
    !none.CanBeCancelled() && !none.CanWakeWaiters() && !none.IsCancelled(),
    "None cancellation is inert"
  );
  let defaults: NetOperationOptions = NetOperationOptions{};
  AssertTrueMsg(defaults.Check(18446744073709551615u64).IsOk(), "default controls are unlimited");
  let token: NetCancellation = NetCancellation.New();
  let shared_token: NetCancellation = token;
  AssertTrueMsg(
    token.CanBeCancelled() && !token.CanWakeWaiters() && !shared_token.IsCancelled(),
    "flag-only token starts clear"
  );
  let options: NetOperationOptions = NetOperationOptions{
    deadline: NetDeadline.At(5u64),
    cancellation: shared_token
  };
  AssertTrueMsg(options.Check(4u64).IsOk(), "before deadline");
  let timed_out: Result<Unit, NetError> = options.Check(5u64);
  AssertTrueMsg(timed_out.IsErr(), "at deadline");
  if timed_out.IsErr() {
    AssertTrueMsg(
      ((timed_out.get_if<NetError>()) as NetError).kind == NetErrorKind.TimedOut,
      "deadline error category"
    );
  }

  token.Cancel();
  shared_token.Cancel();
  AssertTrueMsg(shared_token.IsCancelled() && token.IsCancelled(), "copies share sticky cancellation");
  let cancelled: Result<Unit, NetError> = options.Check(5u64);
  AssertTrueMsg(cancelled.IsErr(), "cancelled and expired");
  if cancelled.IsErr() {
    AssertTrueMsg(
      ((cancelled.get_if<NetError>()) as NetError).kind == NetErrorKind.Cancelled,
      "cancellation takes precedence over timeout"
    );
  }
}

// Exercise the clock-backed owner directly; accidental forwarding recursion must fail here.
@test
func test_net_core_n3_operation_check_now_uses_host_clock() {
  let admitted: NetOperationOptions = NetOperationOptions{};
  AssertTrue(admitted.CheckNow().IsOk());

  let expired: NetOperationOptions = NetOperationOptions{ deadline: NetDeadline.At(1u64) };
  AssertTrue(expired.CheckNow().IsErr());

  var token: NetCancellation = NetCancellation.New();
  token.Cancel();
  let cancelled: NetOperationOptions = NetOperationOptions{ cancellation: token };
  AssertTrue(cancelled.CheckNow().IsErr());
}
