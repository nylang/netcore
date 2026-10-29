// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

part of NetContractTests;

/** @brief Controlled resolver queue, notification, cancellation and shutdown cases. */

@test(tag = "net_core_n3")
// Cancelling a caller cannot free a worker slot while its native lookup is still blocked.
func test_net_core_n3_dns_running_cancel_retains_capacity() {
  NetTestAssertI32(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:6");
  var driver: NetEventLoop = NetTestLoop(2);
  var resolver: AsyncResolver = NetTestResolver(1, 1);
  let token: NetCancellation = NetCancellation.New();
  let future: AsyncFuture<NetResolution> = NetTestDns(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetOperationOptions{cancellation: token}
  ));
  NetTestWaitDns(1);
  token.Cancel();
  NetTestAssertTrue(resolver.Poll().IsOk(), "n3_resolver_selftest.ny:11");
  NetTestAssertTrue(future.is_completed, "n3_resolver_selftest.ny:12");
  let cancelled: NetResolution = NetTestResolution(resolver, future);
  NetTestAssertTrue(
    (cancelled.error as NetError).kind == NetErrorKind.Cancelled,
    "n3_resolver_selftest.ny:14"
  );
  NetTestAssertI32(resolver.PendingCount(), 1, "n3_resolver_selftest.ny:15");
  let rejected: Result<AsyncFuture<NetResolution>, NetError> = resolver.ResolveAsync(
    "127.0.0.1",
    80,
    IpFamily.V4,
    2,
    NetTestOptions()
  );
  NetTestAssertTrue(rejected.IsErr(), "n3_resolver_selftest.ny:17");
  NetTestAssertTrue(
    ((rejected.get_if<NetError>()) as NetError).kind == NetErrorKind.WouldBlock,
    "n3_resolver_selftest.ny:17"
  );
  let ready: AsyncFuture<Result<Unit, NetError>> = NetTestReady(resolver.WhenReady(
    driver,
    NetTestOptions()
  ));
  NetTestAssertTrue(driver.Poll(0).IsOk(), "n3_resolver_selftest.ny:19");
  NetTestAssertTrue(!ready.is_completed, "n3_resolver_selftest.ny:19");
  net_core_test_dns_release();
  NetTestPump(driver, ready);
  NetTestRetireDns(resolver);
  let retry: AsyncFuture<NetResolution> = NetTestDns(resolver.ResolveAsync(
    "127.0.0.1",
    80,
    IpFamily.V4,
    2,
    NetTestOptions()
  ));
  NetTestAssertTrue(NetTestResolution(resolver, retry).error == nil, "n3_resolver_selftest.ny:22");
  NetTestAssertI32(net_core_test_dns_peak(), 1, "n3_resolver_selftest.ny:22");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_queued_cancel_skips_lookup() {
  NetTestAssertI32(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:27");
  var resolver: AsyncResolver = NetTestResolver(1, 2);
  let first: AsyncFuture<NetResolution> = NetTestDns(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetTestOptions()
  ));
  NetTestWaitDns(1);
  let token: NetCancellation = NetCancellation.New();
  let second: AsyncFuture<NetResolution> = NetTestDns(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetOperationOptions{cancellation: token}
  ));
  token.Cancel();
  NetTestAssertTrue(resolver.Poll().IsOk(), "n3_resolver_selftest.ny:33");
  NetTestAssertTrue(
    (NetTestResolution(resolver, second).error as NetError).kind == NetErrorKind.Cancelled,
    "n3_resolver_selftest.ny:34"
  );
  NetTestAssertI32(net_core_test_dns_entered(), 1, "n3_resolver_selftest.ny:35");
  NetTestAssertI32(resolver.PendingCount(), 1, "n3_resolver_selftest.ny:35");
  net_core_test_dns_release();
  NetTestAssertTrue(NetTestResolution(resolver, first).error == nil, "n3_resolver_selftest.ny:36");
  NetTestAssertI32(net_core_test_dns_entered(), 1, "n3_resolver_selftest.ny:37");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_query_deadline_wakes_notification() {
  NetTestAssertI32(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:42");
  var driver: NetEventLoop = NetTestLoop(2);
  var resolver: AsyncResolver = NetTestResolver(1, 1);
  let query_options: NetOperationOptions = NetOperationOptions{deadline: NetDeadline.After(
    NetClock.NowNanoseconds(),
    50000000u64
  )};
  let query: AsyncFuture<NetResolution> = NetTestDns(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    query_options
  ));
  NetTestWaitDns(1);
  let ready: AsyncFuture<Result<Unit, NetError>> = NetTestReady(resolver.WhenReady(
    driver,
    NetTestOptions()
  ));
  NetTestAssertTrue(driver.Poll(-1).IsOk(), "n3_resolver_selftest.ny:48");
  NetTestAssertTrue(ready.is_completed, "n3_resolver_selftest.ny:48");
  NetTestAssertTrue(
    (NetTestResolution(resolver, query).error as NetError).kind == NetErrorKind.TimedOut,
    "n3_resolver_selftest.ny:49"
  );
  NetTestAssertI32(resolver.PendingCount(), 1, "n3_resolver_selftest.ny:50");
  net_core_test_dns_release();
  NetTestRetireDns(resolver);
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_distinct_query_cancellation() {
  NetTestAssertI32(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:56");
  var driver: NetEventLoop = NetTestLoop(2);
  var resolver: AsyncResolver = NetTestResolver(2, 2);
  let a_token: NetCancellation = NetCancellation.New();
  let b_token: NetCancellation = NetCancellation.New();
  let a: AsyncFuture<NetResolution> = NetTestDns(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetOperationOptions{cancellation: a_token}
  ));
  let b: AsyncFuture<NetResolution> = NetTestDns(resolver.ResolveAsync(
    "net-core-gated.invalid",
    81,
    IpFamily.V4,
    2,
    NetOperationOptions{cancellation: b_token}
  ));
  NetTestWaitDns(2);
  let ready: AsyncFuture<Result<Unit, NetError>> = NetTestReady(resolver.WhenReady(
    driver,
    NetTestOptions()
  ));
  let thread: Result<Thread, ThreadError> = Thread.Spawn(
    lambda[copy b_token]() -> void {
      Thread.Sleep(20u32);
      b_token.Cancel();
    }
  );
  NetTestAssertTrue(thread.IsOk(), "n3_resolver_selftest.ny:64");
  let start: uint64 = NetClock.NowNanoseconds();
  NetTestAssertTrue(
    driver.Poll(-1).IsOk(),
    "aggregate query cancellation must interrupt an otherwise blocking Poll"
  );
  NetTestAssertTrue(
    NetClock.NowNanoseconds() - start < 2500000000u64,
    "query cancellation must not wait for notification timeout"
  );
  NetTestAssertTrue(ready.is_completed, "aggregate query cancellation produces advisory readiness");
  let completion: Result<Unit, NetError> = (
    ready.GetResult().get_if<Result<Unit, NetError>>()
  ) as Result<Unit, NetError>;
  NetTestAssertTrue(completion.IsOk(), "query cancellation is not a notification timeout");
  NetTestAssertTrue(
    (NetTestResolution(resolver, b).error as NetError).kind == NetErrorKind.Cancelled,
    "n3_resolver_selftest.ny:65"
  );
  NetTestAssertTrue(!a.is_completed, "n3_resolver_selftest.ny:66");
  NetTestAssertI32(resolver.PendingCount(), 2, "n3_resolver_selftest.ny:66");
  net_core_test_dns_release();
  NetTestAssertTrue(NetTestResolution(resolver, a).error == nil, "n3_resolver_selftest.ny:67");
  NetTestRetireDns(resolver);
  NetTestAssertI32(net_core_test_dns_peak(), 2, "n3_resolver_selftest.ny:68");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_close_notifier_and_late_worker() {
  let baseline: int32 = net_core_test_fd_count();
  NetTestAssertI32(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:73");
  var driver: NetEventLoop = NetTestLoop(2);
  var resolver: AsyncResolver = NetTestResolver(1, 1);
  let query: AsyncFuture<NetResolution> = NetTestDns(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetTestOptions()
  ));
  NetTestWaitDns(1);
  let ready: AsyncFuture<Result<Unit, NetError>> = NetTestReady(resolver.WhenReady(
    driver,
    NetTestOptions()
  ));
  resolver.Close();
  NetTestAssertTrue(query.is_completed, "n3_resolver_selftest.ny:78");
  NetTestAssertTrue(!ready.is_completed, "n3_resolver_selftest.ny:78");
  NetTestPump(driver, ready);
  NetTestAssertTrue(NetTestReadyError(ready) == NetErrorKind.Closed, "n3_resolver_selftest.ny:79");
  let result: NetResolution = (query.GetResult().get_if<NetResolution>()) as NetResolution;
  NetTestAssertTrue((result.error as NetError).kind == NetErrorKind.Closed, "n3_resolver_selftest.ny:81");
  net_core_test_dns_release();
  NetTestFdBaseline(baseline);
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_driver_close_preserves_query() {
  NetTestAssertI32(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:87");
  var driver: NetEventLoop = NetTestLoop(2);
  var resolver: AsyncResolver = NetTestResolver(1, 1);
  let query: AsyncFuture<NetResolution> = NetTestDns(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetTestOptions()
  ));
  NetTestWaitDns(1);
  let ready: AsyncFuture<Result<Unit, NetError>> = NetTestReady(resolver.WhenReady(
    driver,
    NetTestOptions()
  ));
  driver.Close();
  NetTestAssertTrue(NetTestReadyError(ready) == NetErrorKind.Closed, "n3_resolver_selftest.ny:92");
  NetTestAssertTrue(!query.is_completed, "n3_resolver_selftest.ny:92");
  net_core_test_dns_release();
  NetTestAssertTrue(NetTestResolution(resolver, query).error == nil, "n3_resolver_selftest.ny:93");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_notification_coalescing_and_reuse() {
  var driver: NetEventLoop = NetTestLoop(2);
  var resolver: AsyncResolver = NetTestResolver(2, 4);
  var round: int32 = 0;
  while round < 100 {
    let a: AsyncFuture<NetResolution> = NetTestDns(resolver.ResolveAsync(
      "127.0.0.1",
      80,
      IpFamily.V4,
      2,
      NetTestOptions()
    ));
    let b: AsyncFuture<NetResolution> = NetTestDns(resolver.ResolveAsync(
      "::1",
      81,
      IpFamily.V6,
      2,
      NetTestOptions()
    ));
    let ready: AsyncFuture<Result<Unit, NetError>> = NetTestReady(resolver.WhenReady(
      driver,
      NetTestOptions()
    ));
    if round % 2 == 0 {
      NetTestAssertTrue(resolver.Poll().IsOk(), "n3_resolver_selftest.ny:104");
    }

    NetTestPump(driver, ready);
    NetTestAssertTrue(NetTestResolution(resolver, a).error == nil, "n3_resolver_selftest.ny:106");
    NetTestAssertTrue(NetTestResolution(resolver, b).error == nil, "n3_resolver_selftest.ny:106");
    NetTestAssertI32(resolver.PendingCount(), 0, "n3_resolver_selftest.ny:107");
    NetTestAssertI32(driver.PendingCount(), 0, "n3_resolver_selftest.ny:107");
    round = round + 1;
  }
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_hostname_copy_and_shared_result() {
  NetTestAssertI32(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:114");
  var resolver: AsyncResolver = NetTestResolver(1, 2);
  let first: AsyncFuture<NetResolution> = NetTestDns(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetTestOptions()
  ));
  NetTestWaitDns(1);
  var host: string = "net-core-failed.invalid".Substring(0, 23);
  let second: AsyncFuture<NetResolution> = NetTestDns(resolver.ResolveAsync(
    host,
    80,
    IpFamily.V4,
    2,
    NetTestOptions()
  ));
  unsafe {
    * (host.data as *mut uint8) = 0u8;
  }

  net_core_test_dns_release();
  let success: NetResolution = NetTestResolution(resolver, first);
  let failure: NetResolution = NetTestResolution(resolver, second);
  NetTestAssertTrue(success.error == nil, "n3_resolver_selftest.ny:124");
  NetTestAssertTrue(
    (failure.error as NetError).kind == NetErrorKind.NameNotFound,
    "n3_resolver_selftest.ny:124"
  );
  let retained: NetResolvedAddresses = success.addresses;
  resolver.Close();
  NetTestAssertI32(retained.Len(), 1, "n3_resolver_selftest.ny:127");
  NetTestAssertString(
    ((retained.Get(0).get_if<NetEndpoint>()) as NetEndpoint).ToString(),
    "127.0.0.1:80",
    "n3_resolver_selftest.ny:128"
  );
}

func net_test_pool_resource_round() -> void {
  var driver: NetEventLoop = NetTestLoop(2);
  var resolver: AsyncResolver = NetTestResolver(2, 2);
  let query: AsyncFuture<NetResolution> = NetTestDns(resolver.ResolveAsync(
    "127.0.0.1",
    80,
    IpFamily.V4,
    2,
    NetTestOptions()
  ));
  let ready: AsyncFuture<Result<Unit, NetError>> = NetTestReady(resolver.WhenReady(
    driver,
    NetTestOptions()
  ));
  NetTestPump(driver, ready);
  NetTestAssertTrue(NetTestResolution(resolver, query).error == nil, "n3_resolver_selftest.ny:135");
  resolver.Close();
  driver.Close();
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_pool_descriptor_recovery() {
  let baseline: int32 = net_core_test_fd_count();
  NetTestAssertTrue(baseline >= 0, "n3_resolver_selftest.ny:140");
  var i: int32 = 0;
  while i < 64 {
    net_test_pool_resource_round();
    i = i + 1;
  }

  NetTestFdBaseline(baseline);
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_move_preserves_notification() {
  NetTestAssertI32(net_core_test_dns_reset(), 0, "reset controlled DNS");
  var driver: NetEventLoop = NetTestLoop(2);
  var resolver: AsyncResolver = NetTestResolver(1, 1);
  let query: AsyncFuture<NetResolution> = NetTestDns(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetTestOptions()
  ));
  NetTestWaitDns(1);
  let ready: AsyncFuture<Result<Unit, NetError>> = NetTestReady(resolver.WhenReady(
    driver,
    NetTestOptions()
  ));
  var moved: AsyncResolver = move(resolver);
  net_core_test_dns_release();
  NetTestPump(driver, ready);
  NetTestAssertTrue(
    NetTestResolution(moved, query).error == nil,
    "notification follows shared pool after owner move"
  );
}

func net_test_discard_dns(resolver: ref mut AsyncResolver, driver: ref mut NetEventLoop) -> void {
  NetTestAssertTrue(
    resolver.ResolveAsync("net-core-gated.invalid", 80, IpFamily.V4, 2, NetTestOptions()).IsOk(),
    "admit query before dropping its Future"
  );
  NetTestAssertTrue(
    resolver.WhenReady(driver, NetTestOptions()).IsOk(),
    "admit notification before dropping its Future"
  );
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_dropped_futures_do_not_cancel() {
  NetTestAssertI32(net_core_test_dns_reset(), 0, "reset controlled DNS");
  var driver: NetEventLoop = NetTestLoop(2);
  var resolver: AsyncResolver = NetTestResolver(1, 1);
  net_test_discard_dns(resolver, driver);
  NetTestWaitDns(1);
  NetTestAssertI32(resolver.PendingCount(), 1, "query remains owned");
  NetTestAssertI32(driver.PendingCount(), 1, "notification remains owned");
  net_core_test_dns_release();
  var i: int32 = 0;
  while driver.PendingCount() > 0 && i < 1000 {
    NetTestAssertTrue(driver.Poll(5).IsOk(), "drive dropped notification");
    i = i + 1;
  }

  NetTestAssertI32(driver.PendingCount(), 0, "dropped notification retires");
  NetTestRetireDns(resolver);
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_startup_fd_failure_cleanup() {
  let baseline: int32 = net_core_test_fd_count();
  NetTestAssertI32(
    net_core_test_fd_exhaust_begin(),
    0,
    "enable the isolated startup resource-failure fixture"
  );
  var result: Result<AsyncResolver, NetError> = AsyncResolver.New(2, 2);
  let restored: int32 = net_core_test_fd_exhaust_end();
  NetTestAssertI32(restored, 0, "restore the resource-failure fixture before further assertions");
  NetTestAssertTrue(result.IsErr(), "notification startup must fail without starting a live pool");
  NetTestFdBaseline(baseline);
}

@test(tag = "net_core_n3")
func test_net_core_n3_invalid_admission_preserves_capacity() {
  NetTestAssertTrue(AsyncResolver.New(0, 1).IsErr(), "zero workers rejected");
  NetTestAssertTrue(AsyncResolver.New(2, 1).IsErr(), "capacity must cover workers");
  NetTestAssertTrue(NetEventLoop.NewWithLimits(2, -1 as intptr).IsErr(), "negative byte budget rejected");
  var resolver: AsyncResolver = NetTestResolver(1, 1);
  NetTestAssertTrue(
    resolver.ResolveAsync("", 80, IpFamily.V4, 2, NetTestOptions()).IsErr(),
    "empty host rejected"
  );
  NetTestAssertTrue(
    resolver.ResolveAsync("127.0.0.1", -1, IpFamily.V4, 2, NetTestOptions()).IsErr(),
    "invalid port rejected"
  );
  NetTestAssertTrue(
    resolver.ResolveAsync("127.0.0.1", 80, IpFamily.V4, 0, NetTestOptions()).IsErr(),
    "zero result capacity rejected"
  );
  let cancelled: NetCancellation = NetCancellation.New();
  cancelled.Cancel();
  NetTestAssertTrue(
    resolver.ResolveAsync(
      "127.0.0.1",
      80,
      IpFamily.V4,
      2,
      NetOperationOptions{cancellation: cancelled}
    ).IsErr(),
    "already cancelled query rejected"
  );
  NetTestAssertI32(resolver.PendingCount(), 0, "invalid registration must not charge a slot");
}

/**
 * @brief Closed loop admission wins over an empty producer or cancelled controls.
 * @note The producer must query owner liveness through the internal operation boundary.
 */
@test(tag = "net_core_n3")
func test_net_core_n3_closed_driver_precedes_dns_admission() {
  var resolver: AsyncResolver = NetTestResolver(1, 1);
  var driver: NetEventLoop = NetEventLoop{};
  let empty: Result<AsyncFuture<Result<Unit, NetError>>, NetError> = resolver.WhenReady(
    driver, NetTestOptions()
  );
  NetTestAssertTrue(empty.IsErr(), "closed driver rejects an empty DNS producer");
  NetTestAssertTrue(
    ((empty.get_if<NetError>()) as NetError).kind == NetErrorKind.Closed,
    "closed ownership precedes empty-query admission"
  );

  var cancellation: NetCancellation = NetCancellation.New();
  cancellation.Cancel();
  let cancelled: Result<AsyncFuture<Result<Unit, NetError>>, NetError> = resolver.WhenReady(
    driver, NetOperationOptions{cancellation: cancellation}
  );
  NetTestAssertTrue(cancelled.IsErr(), "closed driver rejects cancelled registration");
  NetTestAssertTrue(
    ((cancelled.get_if<NetError>()) as NetError).kind == NetErrorKind.Closed,
    "closed ownership precedes cancellation at registration"
  );
}
