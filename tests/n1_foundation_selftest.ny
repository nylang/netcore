/** @brief Foundation boundaries exercised by the portable desktop acceptance runner. */
part of NetTransport;

func net_test_invalid_ip(text: ref string) -> void {
  let result: Result<IpAddress, NetError> = IpAddress.Parse(text);
  net_test_assert_true(result.IsErr(), text);
  if result.IsErr() {
    let error: NetError = (result.get_if<NetError>()) as NetError;
    net_test_assert_true(error.kind == NetErrorKind.InvalidAddress && error.native_code == 0, text);
  }
}
func net_test_canonical_ip(text: ref string, canonical: ref string) -> void {
  let result: Result<IpAddress, NetError> = IpAddress.Parse(text);
  net_test_assert_true(result.IsOk(), text);
  if result.IsErr() { return; }
  let address: IpAddress = (result.get_if<IpAddress>()) as IpAddress;
  net_test_assert_string(address.ToString(), canonical, text);
  let reparsed: Result<IpAddress, NetError> = IpAddress.Parse(address.ToString());
  net_test_assert_true(reparsed.IsOk(), canonical);
  if reparsed.IsOk() {
    net_test_assert_true(address.Equals((reparsed.get_if<IpAddress>()) as IpAddress), canonical);
  }
}

@test(tag = "net_core_n3")
func test_net_core_n3_foundation_ipv4_boundaries() {
  net_test_invalid_ip("");
  net_test_invalid_ip("1.2.3");
  net_test_invalid_ip("1.2.3.4.5");
  net_test_invalid_ip("1..3.4");
  net_test_invalid_ip("1.2.3.");
  net_test_invalid_ip("256.0.0.1");
  net_test_invalid_ip("01.2.3.4");
  net_test_invalid_ip("+1.2.3.4");
  net_test_invalid_ip(" 1.2.3.4");
  net_test_invalid_ip("1.2.3.4 ");
  net_test_invalid_ip("1.2.3.4/24");
  net_test_invalid_ip("1.2.3.4%1");
  net_test_invalid_ip("localhost");
  net_test_canonical_ip("0.0.0.0", "0.0.0.0");
  net_test_canonical_ip("255.255.255.255", "255.255.255.255");
  let zero: IpAddress = IpAddress.V4(0u8, 0u8, 0u8, 0u8);
  let loopback: IpAddress = IpAddress.V4(127u8, 255u8, 255u8, 255u8);
  net_test_assert_true(zero.IsUnspecified(), "IPv4 zero is a valid unspecified address");
  net_test_assert_true(loopback.IsLoopback(), "all of 127/8 is loopback");
  net_test_assert_true(loopback.ByteAt(-1).IsErr() && loopback.ByteAt(4).IsErr(), "IPv4 octet bounds");
  net_test_assert_i32((loopback.ByteAt(3).get_if<uint8>() as uint8) as int32, 255, "last IPv4 octet");
  let invalid: IpAddress = IpAddress{};
  net_test_assert_true(!invalid.IsUnspecified() && invalid.ByteAt(0).IsErr(), "default address is invalid");
  net_test_assert_string(invalid.ToString(), "", "invalid address has no text");
}

@test(tag = "net_core_n3")
func test_net_core_n3_foundation_ipv6_boundaries() {
  net_test_invalid_ip(":");
  net_test_invalid_ip(":::1");
  net_test_invalid_ip("1::2::3");
  net_test_invalid_ip("1:2:3:4:5:6:7");
  net_test_invalid_ip("1:2:3:4:5:6:7:8:9");
  net_test_invalid_ip("1:2:3:4:5:6:7:8::");
  net_test_invalid_ip("1:2:3:4:5:6:7:");
  net_test_invalid_ip("12345::");
  net_test_invalid_ip("gggg::");
  net_test_invalid_ip("[::1]");
  net_test_invalid_ip("::ffff:192.168.001.1");
  net_test_invalid_ip("::ffff:256.0.0.1");
  net_test_invalid_ip("fe80::1%");
  net_test_invalid_ip("fe80::1%en0");
  net_test_invalid_ip("fe80::1%4294967296");
  net_test_invalid_ip("fe80::1%1%2");
  net_test_canonical_ip("0:0:0:0:0:0:0:0", "::");
  net_test_canonical_ip("0:0:0:0:0:0:0:1", "::1");
  net_test_canonical_ip("2001:0DB8:0:0:1:0:0:1", "2001:db8::1:0:0:1");
  net_test_canonical_ip("1:0:2:3:4:5:6:7", "1:0:2:3:4:5:6:7");
  net_test_canonical_ip("1:2:3:4:5:6:0:0", "1:2:3:4:5:6::");
  net_test_canonical_ip("::FFFF:C000:0280", "::ffff:192.0.2.128");
  net_test_canonical_ip("FE80::1%4294967295", "fe80::1%4294967295");
  net_test_canonical_ip("fe80::1%0002", "fe80::1%2");
  net_test_canonical_ip("::1%0", "::1");
  let scoped: IpAddress = (IpAddress.Parse("fe80::1%4294967295").get_if<IpAddress>()) as IpAddress;
  let unscoped: IpAddress = (IpAddress.Parse("fe80::1").get_if<IpAddress>()) as IpAddress;
  net_test_assert_true(scoped.ScopeId() == 4294967295u32 && !scoped.Equals(unscoped), "scope participates in identity");
  net_test_assert_true(scoped.ByteAt(-1).IsErr() && scoped.ByteAt(16).IsErr(), "IPv6 octet bounds");
  net_test_assert_i32((scoped.ByteAt(15).get_if<uint8>() as uint8) as int32, 1, "last IPv6 octet");
}

func net_test_invalid_endpoint(text: ref string, kind: NetErrorKind) -> void {
  let result: Result<NetEndpoint, NetError> = NetEndpoint.Parse(text);
  net_test_assert_true(result.IsErr(), text);
  if result.IsErr() {
    net_test_assert_true(((result.get_if<NetError>()) as NetError).kind == kind, text);
  }
}

@test(tag = "net_core_n3")
func test_net_core_n3_foundation_endpoint_boundaries() {
  net_test_invalid_endpoint("::1:80", NetErrorKind.InvalidAddress);
  net_test_invalid_endpoint("[127.0.0.1]:80", NetErrorKind.InvalidAddress);
  net_test_invalid_endpoint("[::1:80", NetErrorKind.InvalidAddress);
  net_test_invalid_endpoint("[::1]80", NetErrorKind.InvalidAddress);
  net_test_invalid_endpoint("localhost:80", NetErrorKind.InvalidAddress);
  net_test_invalid_endpoint("127.0.0.1:", NetErrorKind.InvalidPort);
  net_test_invalid_endpoint("127.0.0.1:-1", NetErrorKind.InvalidPort);
  net_test_invalid_endpoint("127.0.0.1:65536", NetErrorKind.InvalidPort);
  net_test_invalid_endpoint("[::1]:80x", NetErrorKind.InvalidPort);
  let low: NetEndpoint = (NetEndpoint.Parse("0.0.0.0:0").get_if<NetEndpoint>()) as NetEndpoint;
  let high: NetEndpoint = (NetEndpoint.Parse("[fe80::1%2]:65535").get_if<NetEndpoint>()) as NetEndpoint;
  net_test_assert_true(low.Port() == 0u16 && high.Port() == 65535u16, "endpoint inclusive port bounds");
  net_test_assert_string(high.ToString(), "[fe80::1%2]:65535", "scoped endpoint text");
  let address: IpAddress = high.Address();
  let rebuilt: NetEndpoint = (NetEndpoint.New(address, 65535).get_if<NetEndpoint>()) as NetEndpoint;
  net_test_assert_true(high.Equals(rebuilt), "endpoint round trip");
  net_test_assert_true(NetEndpoint.New(address, -1).IsErr() && NetEndpoint.New(address, 65536).IsErr(), "constructor rejects port overflow");
  net_test_assert_true(NetEndpoint.New(IpAddress{}, 0).IsErr(), "constructor rejects invalid address");
}

@test(tag = "net_core_n3")
func test_net_core_n3_foundation_read_view_ranges() {
  net_test_assert_true(NetBytes.FromRaw(0 as *const uint8, -1 as intptr).IsErr(), "negative byte count");
  net_test_assert_true(NetBytes.FromRaw(0 as *const uint8, 1 as intptr).IsErr(), "null nonempty range");
  let empty: NetBytes = (NetBytes.FromRaw(0 as *const uint8, 0 as intptr).get_if<NetBytes>()) as NetBytes;
  net_test_assert_true(empty.Slice(0 as intptr, 0 as intptr).IsOk(), "empty null slice");
  let text: string = "abcd";
  let bytes: NetBytes = NetBytes.FromString(text);
  let tail: NetBytes = (bytes.Slice(4 as intptr, 0 as intptr).get_if<NetBytes>()) as NetBytes;
  net_test_assert_true(tail.Len() == 0 && tail.Data() as uintptr == (bytes.Data() as uintptr) + 4up, "one-past empty slice");
  net_test_assert_true(bytes.Slice(-1 as intptr, 0 as intptr).IsErr(), "negative start");
  net_test_assert_true(bytes.Slice(0 as intptr, -1 as intptr).IsErr(), "negative length");
  net_test_assert_true(bytes.Slice(5 as intptr, 0 as intptr).IsErr(), "start past end");
  net_test_assert_true(bytes.Slice(3 as intptr, 2 as intptr).IsErr(), "length past end");
  let limit: intptr = 9223372036854775807i64 as intptr;
  net_test_assert_true(bytes.Slice(1 as intptr, limit).IsErr() && bytes.Slice(limit, limit).IsErr(), "overflowing subrange is rejected before pointer arithmetic");
  let middle: NetBytes = (bytes.Slice(1 as intptr, 2 as intptr).get_if<NetBytes>()) as NetBytes;
  net_test_assert_string(string.ViewFrom(middle.Data() as *const int8, middle.Len() as int32), "bc", "slice points into original storage");
}

@test(tag = "net_core_n3")
func test_net_core_n3_foundation_mutable_ranges() {
  net_test_assert_true(NetMutableBytes.FromRaw(0 as *mut uint8, -1 as intptr).IsErr(), "negative writable count");
  net_test_assert_true(NetMutableBytes.FromRaw(0 as *mut uint8, 1 as intptr).IsErr(), "null writable nonempty range");
  let empty: NetMutableBytes = (NetMutableBytes.FromRaw(0 as *mut uint8, 0 as intptr).get_if<NetMutableBytes>()) as NetMutableBytes;
  net_test_assert_true(empty.Slice(0 as intptr, 0 as intptr).IsOk(), "empty writable null slice");
  var storage: <uint8>[4] = <uint8>[4]{};
  let bytes: NetMutableBytes = (NetMutableBytes.FromRaw(&mut storage[0], 4 as intptr).get_if<NetMutableBytes>()) as NetMutableBytes;
  net_test_assert_true(bytes.Slice(-1 as intptr, 0 as intptr).IsErr() && bytes.Slice(0 as intptr, -1 as intptr).IsErr(), "negative writable slice bounds");
  net_test_assert_true(bytes.Slice(5 as intptr, 0 as intptr).IsErr() && bytes.Slice(3 as intptr, 2 as intptr).IsErr(), "writable slice past end");
  let limit: intptr = 9223372036854775807i64 as intptr;
  net_test_assert_true(bytes.Slice(1 as intptr, limit).IsErr() && bytes.Slice(limit, limit).IsErr(), "writable range overflow");
  let tail: NetMutableBytes = (bytes.Slice(4 as intptr, 0 as intptr).get_if<NetMutableBytes>()) as NetMutableBytes;
  net_test_assert_true(tail.Len() == 0 && tail.Data() as uintptr == (bytes.Data() as uintptr) + 4up, "writable one-past empty slice");
  let middle: NetMutableBytes = (bytes.Slice(1 as intptr, 2 as intptr).get_if<NetMutableBytes>()) as NetMutableBytes;
  unsafe { (*middle.Data()) = 42u8; }
  let read_view: NetBytes = middle.AsReadOnly();
  net_test_assert_true(storage[1] == 42u8 && read_view.Len() == 2, "mutable slice aliases original memory");
  unsafe { net_test_assert_true(read_view.Data()[0] == 42u8, "read-only projection retains address"); }
}

@test(tag = "net_core_n3")
func test_net_core_n3_foundation_deadline_arithmetic() {
  let limit: uint64 = 18446744073709551615u64;
  let unlimited: NetDeadline = NetDeadline{};
  net_test_assert_true(!unlimited.IsFinite() && !unlimited.IsExpired(limit), "default deadline is unlimited");
  net_test_assert_true(unlimited.RemainingNanoseconds(limit) == limit, "unlimited remaining sentinel");
  net_test_assert_i32(NetDeadline.Never().PollMilliseconds(limit), -1, "unlimited native wait");
  net_test_assert_true(NetDeadline.At(0u64).IsExpired(0u64), "zero absolute deadline is finite and expired");
  net_test_assert_i32(NetDeadline.After(10u64, 0u64).PollMilliseconds(10u64), 0, "zero timeout");
  net_test_assert_i32(NetDeadline.At(1000001u64).PollMilliseconds(1000000u64), 1, "one nanosecond rounds up");
  net_test_assert_i32(NetDeadline.At(1000000u64).PollMilliseconds(0u64), 1, "exact millisecond");
  net_test_assert_i32(NetDeadline.At(1000001u64).PollMilliseconds(0u64), 2, "fractional millisecond rounds up");
  net_test_assert_i32(NetDeadline.At(2147483647000001u64).PollMilliseconds(0u64), 2147483647, "native wait saturation");
  let saturated: NetDeadline = NetDeadline.After(limit - 5u64, 10u64);
  net_test_assert_true(saturated.IsFinite() && !saturated.IsExpired(limit - 1u64), "saturated deadline stays finite in the future");
  net_test_assert_true(saturated.RemainingNanoseconds(limit - 5u64) == 5u64, "addition saturates without wrapping");
  net_test_assert_true(saturated.IsExpired(limit) && saturated.RemainingNanoseconds(limit) == 0u64, "deadline expires at equality");
}

@test(tag = "net_core_n3")
func test_net_core_n3_foundation_cancellation_controls() {
  let none: NetCancellation = NetCancellation.None();
  none.Cancel();
  net_test_assert_true(!none.CanBeCancelled() && !none.CanWakeWaiters() && !none.IsCancelled(), "None cancellation is inert");
  let defaults: NetOperationOptions = NetOperationOptions{};
  net_test_assert_true(defaults.Check(18446744073709551615u64).IsOk(), "default controls are unlimited");
  let token: NetCancellation = NetCancellation.New();
  let shared_token: NetCancellation = token;
  net_test_assert_true(token.CanBeCancelled() && !token.CanWakeWaiters() && !shared_token.IsCancelled(), "flag-only token starts clear");
  let options: NetOperationOptions = NetOperationOptions{deadline: NetDeadline.At(5u64), cancellation: shared_token};
  net_test_assert_true(options.Check(4u64).IsOk(), "before deadline");
  let timed_out: Result<Unit, NetError> = options.Check(5u64);
  net_test_assert_true(timed_out.IsErr(), "at deadline");
  if timed_out.IsErr() { net_test_assert_true(((timed_out.get_if<NetError>()) as NetError).kind == NetErrorKind.TimedOut, "deadline error category"); }
  token.Cancel();
  shared_token.Cancel();
  net_test_assert_true(shared_token.IsCancelled() && token.IsCancelled(), "copies share sticky cancellation");
  let cancelled: Result<Unit, NetError> = options.Check(5u64);
  net_test_assert_true(cancelled.IsErr(), "cancelled and expired");
  if cancelled.IsErr() { net_test_assert_true(((cancelled.get_if<NetError>()) as NetError).kind == NetErrorKind.Cancelled, "cancellation takes precedence over timeout"); }
}
