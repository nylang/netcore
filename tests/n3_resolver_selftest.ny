// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

part of NetContractTests;

/** @brief Controlled resolver queue, notification, cancellation and shutdown cases. */

@test(tag = "net_core_n3")
// Cancelling a caller cannot free a worker slot while its native lookup is still blocked.
func test_net_core_n3_dns_running_cancel_retains_capacity() {
  AssertEqI32Msg(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:6");
  var driver: NetEventLoop = NetEventLoop.TestNew(2);
  var resolver: AsyncResolver = AsyncResolver.TestNew(1, 1);
  let token: NetCancellation = NetCancellation.New();
  let future: AsyncFuture<NetResolution> = AsyncFuture<NetResolution>.TestAdmit(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetOperationOptions{cancellation: token}
  ));
  NetTestDnsWait{count: 1}.Wait();
  token.Cancel();
  AssertTrueMsg(resolver.Poll().IsOk(), "n3_resolver_selftest.ny:11");
  AssertTrueMsg(future.is_completed, "n3_resolver_selftest.ny:12");
  let cancelled: NetResolution = (resolver).TestResolution(future);
  AssertTrueMsg(
    (cancelled.error as NetError).kind == NetErrorKind.Cancelled,
    "n3_resolver_selftest.ny:14"
  );
  AssertEqI32Msg(resolver.PendingCount(), 1, "n3_resolver_selftest.ny:15");
  let rejected: Result<AsyncFuture<NetResolution>, NetError> = resolver.ResolveAsync(
    "127.0.0.1",
    80,
    IpFamily.V4,
    2,
    NetOperationOptions.TestDefault()
  );
  AssertTrueMsg(rejected.IsErr(), "n3_resolver_selftest.ny:17");
  AssertTrueMsg(
    ((rejected.get_if<NetError>()) as NetError).kind == NetErrorKind.WouldBlock,
    "n3_resolver_selftest.ny:17"
  );
  let ready: AsyncFuture<Result<Unit, NetError>> = AsyncFuture<Result<Unit, NetError>>.TestAdmit(resolver.WhenReady(
    driver,
    NetOperationOptions.TestDefault()
  ));
  AssertTrueMsg(driver.Poll(0).IsOk(), "n3_resolver_selftest.ny:19");
  AssertTrueMsg(!ready.is_completed, "n3_resolver_selftest.ny:19");
  net_core_test_dns_release();
  (driver).TestPump(ready);
  (resolver).TestRetire();
  let retry: AsyncFuture<NetResolution> = AsyncFuture<NetResolution>.TestAdmit(resolver.ResolveAsync(
    "127.0.0.1",
    80,
    IpFamily.V4,
    2,
    NetOperationOptions.TestDefault()
  ));
  AssertTrueMsg((resolver).TestResolution(retry).error == nil, "n3_resolver_selftest.ny:22");
  AssertEqI32Msg(net_core_test_dns_peak(), 1, "n3_resolver_selftest.ny:22");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_queued_cancel_skips_lookup() {
  AssertEqI32Msg(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:27");
  var resolver: AsyncResolver = AsyncResolver.TestNew(1, 2);
  let first: AsyncFuture<NetResolution> = AsyncFuture<NetResolution>.TestAdmit(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetOperationOptions.TestDefault()
  ));
  NetTestDnsWait{count: 1}.Wait();
  let token: NetCancellation = NetCancellation.New();
  let second: AsyncFuture<NetResolution> = AsyncFuture<NetResolution>.TestAdmit(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetOperationOptions{cancellation: token}
  ));
  token.Cancel();
  AssertTrueMsg(resolver.Poll().IsOk(), "n3_resolver_selftest.ny:33");
  AssertTrueMsg(
    ((resolver).TestResolution(second).error as NetError).kind == NetErrorKind.Cancelled,
    "n3_resolver_selftest.ny:34"
  );
  AssertEqI32Msg(net_core_test_dns_entered(), 1, "n3_resolver_selftest.ny:35");
  AssertEqI32Msg(resolver.PendingCount(), 1, "n3_resolver_selftest.ny:35");
  net_core_test_dns_release();
  AssertTrueMsg((resolver).TestResolution(first).error == nil, "n3_resolver_selftest.ny:36");
  AssertEqI32Msg(net_core_test_dns_entered(), 1, "n3_resolver_selftest.ny:37");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_query_deadline_wakes_notification() {
  AssertEqI32Msg(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:42");
  var driver: NetEventLoop = NetEventLoop.TestNew(2);
  var resolver: AsyncResolver = AsyncResolver.TestNew(1, 1);
  let query_options: NetOperationOptions = NetOperationOptions{deadline: NetDeadline.After(
    Instant.Now().ToDurationSinceEpochish().ToNanoseconds(),
    50000000u64
  )};
  let query: AsyncFuture<NetResolution> = AsyncFuture<NetResolution>.TestAdmit(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    query_options
  ));
  NetTestDnsWait{count: 1}.Wait();
  let ready: AsyncFuture<Result<Unit, NetError>> = AsyncFuture<Result<Unit, NetError>>.TestAdmit(resolver.WhenReady(
    driver,
    NetOperationOptions.TestDefault()
  ));
  AssertTrueMsg(driver.Poll(-1).IsOk(), "n3_resolver_selftest.ny:48");
  AssertTrueMsg(ready.is_completed, "n3_resolver_selftest.ny:48");
  AssertTrueMsg(
    ((resolver).TestResolution(query).error as NetError).kind == NetErrorKind.TimedOut,
    "n3_resolver_selftest.ny:49"
  );
  AssertEqI32Msg(resolver.PendingCount(), 1, "n3_resolver_selftest.ny:50");
  net_core_test_dns_release();
  (resolver).TestRetire();
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_distinct_query_cancellation() {
  AssertEqI32Msg(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:56");
  var driver: NetEventLoop = NetEventLoop.TestNew(2);
  var resolver: AsyncResolver = AsyncResolver.TestNew(2, 2);
  let a_token: NetCancellation = NetCancellation.New();
  let b_token: NetCancellation = NetCancellation.New();
  let a: AsyncFuture<NetResolution> = AsyncFuture<NetResolution>.TestAdmit(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetOperationOptions{cancellation: a_token}
  ));
  let b: AsyncFuture<NetResolution> = AsyncFuture<NetResolution>.TestAdmit(resolver.ResolveAsync(
    "net-core-gated.invalid",
    81,
    IpFamily.V4,
    2,
    NetOperationOptions{cancellation: b_token}
  ));
  NetTestDnsWait{count: 2}.Wait();
  let ready: AsyncFuture<Result<Unit, NetError>> = AsyncFuture<Result<Unit, NetError>>.TestAdmit(resolver.WhenReady(
    driver,
    NetOperationOptions.TestDefault()
  ));
  let thread: Result<Thread, ThreadError> = Thread.Spawn(
    lambda[copy b_token]() -> void {
      Thread.Sleep(20u32);
      b_token.Cancel();
    }
  );
  AssertTrueMsg(thread.IsOk(), "n3_resolver_selftest.ny:64");
  let start: uint64 = Instant.Now().ToDurationSinceEpochish().ToNanoseconds();
  AssertTrueMsg(
    driver.Poll(-1).IsOk(),
    "aggregate query cancellation must interrupt an otherwise blocking Poll"
  );
  AssertTrueMsg(
    Instant.Now().ToDurationSinceEpochish().ToNanoseconds() - start < 2500000000u64,
    "query cancellation must not wait for notification timeout"
  );
  AssertTrueMsg(ready.is_completed, "aggregate query cancellation produces advisory readiness");
  let completion: Result<Unit, NetError> = (
    ready.GetResult().get_if<Result<Unit, NetError>>()
  ) as Result<Unit, NetError>;
  AssertTrueMsg(completion.IsOk(), "query cancellation is not a notification timeout");
  AssertTrueMsg(
    ((resolver).TestResolution(b).error as NetError).kind == NetErrorKind.Cancelled,
    "n3_resolver_selftest.ny:65"
  );
  AssertTrueMsg(!a.is_completed, "n3_resolver_selftest.ny:66");
  AssertEqI32Msg(resolver.PendingCount(), 2, "n3_resolver_selftest.ny:66");
  net_core_test_dns_release();
  AssertTrueMsg((resolver).TestResolution(a).error == nil, "n3_resolver_selftest.ny:67");
  (resolver).TestRetire();
  AssertEqI32Msg(net_core_test_dns_peak(), 2, "n3_resolver_selftest.ny:68");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_close_notifier_and_late_worker() {
  let baseline: int32 = net_core_test_fd_count();
  AssertEqI32Msg(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:73");
  var driver: NetEventLoop = NetEventLoop.TestNew(2);
  var resolver: AsyncResolver = AsyncResolver.TestNew(1, 1);
  let query: AsyncFuture<NetResolution> = AsyncFuture<NetResolution>.TestAdmit(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetOperationOptions.TestDefault()
  ));
  NetTestDnsWait{count: 1}.Wait();
  let ready: AsyncFuture<Result<Unit, NetError>> = AsyncFuture<Result<Unit, NetError>>.TestAdmit(resolver.WhenReady(
    driver,
    NetOperationOptions.TestDefault()
  ));
  resolver.Close();
  AssertTrueMsg(query.is_completed, "n3_resolver_selftest.ny:78");
  AssertTrueMsg(!ready.is_completed, "n3_resolver_selftest.ny:78");
  (driver).TestPump(ready);
  AssertTrueMsg((ready).TestError() == NetErrorKind.Closed, "n3_resolver_selftest.ny:79");
  let result: NetResolution = (query.GetResult().get_if<NetResolution>()) as NetResolution;
  AssertTrueMsg((result.error as NetError).kind == NetErrorKind.Closed, "n3_resolver_selftest.ny:81");
  net_core_test_dns_release();
  NetTestDescriptorBaseline{expected: baseline}.Wait();
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_driver_close_preserves_query() {
  AssertEqI32Msg(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:87");
  var driver: NetEventLoop = NetEventLoop.TestNew(2);
  var resolver: AsyncResolver = AsyncResolver.TestNew(1, 1);
  let query: AsyncFuture<NetResolution> = AsyncFuture<NetResolution>.TestAdmit(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetOperationOptions.TestDefault()
  ));
  NetTestDnsWait{count: 1}.Wait();
  let ready: AsyncFuture<Result<Unit, NetError>> = AsyncFuture<Result<Unit, NetError>>.TestAdmit(resolver.WhenReady(
    driver,
    NetOperationOptions.TestDefault()
  ));
  driver.Close();
  AssertTrueMsg((ready).TestError() == NetErrorKind.Closed, "n3_resolver_selftest.ny:92");
  AssertTrueMsg(!query.is_completed, "n3_resolver_selftest.ny:92");
  net_core_test_dns_release();
  AssertTrueMsg((resolver).TestResolution(query).error == nil, "n3_resolver_selftest.ny:93");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_notification_coalescing_and_reuse() {
  var driver: NetEventLoop = NetEventLoop.TestNew(2);
  var resolver: AsyncResolver = AsyncResolver.TestNew(2, 4);
  var round: int32 = 0;
  while round < 100 {
    let a: AsyncFuture<NetResolution> = AsyncFuture<NetResolution>.TestAdmit(resolver.ResolveAsync(
      "127.0.0.1",
      80,
      IpFamily.V4,
      2,
      NetOperationOptions.TestDefault()
    ));
    let b: AsyncFuture<NetResolution> = AsyncFuture<NetResolution>.TestAdmit(resolver.ResolveAsync(
      "::1",
      81,
      IpFamily.V6,
      2,
      NetOperationOptions.TestDefault()
    ));
    let ready: AsyncFuture<Result<Unit, NetError>> = AsyncFuture<Result<Unit, NetError>>.TestAdmit(resolver.WhenReady(
      driver,
      NetOperationOptions.TestDefault()
    ));
    if round % 2 == 0 {
      AssertTrueMsg(resolver.Poll().IsOk(), "n3_resolver_selftest.ny:104");
    }

    (driver).TestPump(ready);
    AssertTrueMsg((resolver).TestResolution(a).error == nil, "n3_resolver_selftest.ny:106");
    AssertTrueMsg((resolver).TestResolution(b).error == nil, "n3_resolver_selftest.ny:106");
    AssertEqI32Msg(resolver.PendingCount(), 0, "n3_resolver_selftest.ny:107");
    AssertEqI32Msg(driver.PendingCount(), 0, "n3_resolver_selftest.ny:107");
    round = round + 1;
  }
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_hostname_copy_and_shared_result() {
  AssertEqI32Msg(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:114");
  var resolver: AsyncResolver = AsyncResolver.TestNew(1, 2);
  let first: AsyncFuture<NetResolution> = AsyncFuture<NetResolution>.TestAdmit(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetOperationOptions.TestDefault()
  ));
  NetTestDnsWait{count: 1}.Wait();
  var host: string = "net-core-failed.invalid".Substring(0, 23);
  let second: AsyncFuture<NetResolution> = AsyncFuture<NetResolution>.TestAdmit(resolver.ResolveAsync(
    host,
    80,
    IpFamily.V4,
    2,
    NetOperationOptions.TestDefault()
  ));
  unsafe {
    * (host.data as *mut uint8) = 0u8;
  }

  net_core_test_dns_release();
  let success: NetResolution = (resolver).TestResolution(first);
  let failure: NetResolution = (resolver).TestResolution(second);
  AssertTrueMsg(success.error == nil, "n3_resolver_selftest.ny:124");
  AssertTrueMsg(
    (failure.error as NetError).kind == NetErrorKind.NameNotFound,
    "n3_resolver_selftest.ny:124"
  );
  let retained: NetResolvedAddresses = success.addresses;
  resolver.Close();
  AssertEqI32Msg(retained.Len(), 1, "n3_resolver_selftest.ny:127");
  AssertEqStringMsg(
    ((retained.Get(0).get_if<NetEndpoint>()) as NetEndpoint).ToString(),
    "127.0.0.1:80",
    "n3_resolver_selftest.ny:128"
  );
}

// nyra-lint-allow: prefer-type-owned-functions -- Return scope tests final resolver/notification release.
func net_test_pool_resource_round() -> void {
  var driver: NetEventLoop = NetEventLoop.TestNew(2);
  var resolver: AsyncResolver = AsyncResolver.TestNew(2, 2);
  let query: AsyncFuture<NetResolution> = AsyncFuture<NetResolution>.TestAdmit(resolver.ResolveAsync(
    "127.0.0.1",
    80,
    IpFamily.V4,
    2,
    NetOperationOptions.TestDefault()
  ));
  let ready: AsyncFuture<Result<Unit, NetError>> = AsyncFuture<Result<Unit, NetError>>.TestAdmit(resolver.WhenReady(
    driver,
    NetOperationOptions.TestDefault()
  ));
  (driver).TestPump(ready);
  AssertTrueMsg((resolver).TestResolution(query).error == nil, "n3_resolver_selftest.ny:135");
  resolver.Close();
  driver.Close();
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_pool_descriptor_recovery() {
  let baseline: int32 = net_core_test_fd_count();
  AssertTrueMsg(baseline >= 0, "n3_resolver_selftest.ny:140");
  var i: int32 = 0;
  while i < 64 {
    net_test_pool_resource_round();
    i = i + 1;
  }

  NetTestDescriptorBaseline{expected: baseline}.Wait();
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_move_preserves_notification() {
  AssertEqI32Msg(net_core_test_dns_reset(), 0, "reset controlled DNS");
  var driver: NetEventLoop = NetEventLoop.TestNew(2);
  var resolver: AsyncResolver = AsyncResolver.TestNew(1, 1);
  let query: AsyncFuture<NetResolution> = AsyncFuture<NetResolution>.TestAdmit(resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    2,
    NetOperationOptions.TestDefault()
  ));
  NetTestDnsWait{count: 1}.Wait();
  let ready: AsyncFuture<Result<Unit, NetError>> = AsyncFuture<Result<Unit, NetError>>.TestAdmit(resolver.WhenReady(
    driver,
    NetOperationOptions.TestDefault()
  ));
  var moved: AsyncResolver = move(resolver);
  net_core_test_dns_release();
  (driver).TestPump(ready);
  AssertTrueMsg(
    (moved).TestResolution(query).error == nil,
    "notification follows shared pool after owner move"
  );
}

// nyra-lint-allow: prefer-type-owned-functions -- Return drops Futures while operations remain retained.
func net_test_discard_dns(resolver: ref mut AsyncResolver, driver: ref mut NetEventLoop) -> void {
  AssertTrueMsg(
    resolver.ResolveAsync("net-core-gated.invalid", 80, IpFamily.V4, 2, NetOperationOptions.TestDefault()).IsOk(),
    "admit query before dropping its Future"
  );
  AssertTrueMsg(
    resolver.WhenReady(driver, NetOperationOptions.TestDefault()).IsOk(),
    "admit notification before dropping its Future"
  );
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_dropped_futures_do_not_cancel() {
  AssertEqI32Msg(net_core_test_dns_reset(), 0, "reset controlled DNS");
  var driver: NetEventLoop = NetEventLoop.TestNew(2);
  var resolver: AsyncResolver = AsyncResolver.TestNew(1, 1);
  net_test_discard_dns(resolver, driver);
  NetTestDnsWait{count: 1}.Wait();
  AssertEqI32Msg(resolver.PendingCount(), 1, "query remains owned");
  AssertEqI32Msg(driver.PendingCount(), 1, "notification remains owned");
  net_core_test_dns_release();
  var i: int32 = 0;
  while driver.PendingCount() > 0 && i < 1000 {
    AssertTrueMsg(driver.Poll(5).IsOk(), "drive dropped notification");
    i = i + 1;
  }

  AssertEqI32Msg(driver.PendingCount(), 0, "dropped notification retires");
  (resolver).TestRetire();
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_startup_fd_failure_cleanup() {
  let baseline: int32 = net_core_test_fd_count();
  AssertEqI32Msg(
    net_core_test_fd_exhaust_begin(),
    0,
    "enable the isolated startup resource-failure fixture"
  );
  var result: Result<AsyncResolver, NetError> = AsyncResolver.New(2, 2);
  let restored: int32 = net_core_test_fd_exhaust_end();
  AssertEqI32Msg(restored, 0, "restore the resource-failure fixture before further assertions");
  AssertTrueMsg(result.IsErr(), "notification startup must fail without starting a live pool");
  NetTestDescriptorBaseline{expected: baseline}.Wait();
}

@test(tag = "net_core_n3")
func test_net_core_n3_invalid_admission_preserves_capacity() {
  AssertTrueMsg(AsyncResolver.New(0, 1).IsErr(), "zero workers rejected");
  AssertTrueMsg(AsyncResolver.New(2, 1).IsErr(), "capacity must cover workers");
  AssertTrueMsg(NetEventLoop.NewWithLimits(2, -1 as intptr).IsErr(), "negative byte budget rejected");
  var resolver: AsyncResolver = AsyncResolver.TestNew(1, 1);
  AssertTrueMsg(
    resolver.ResolveAsync("", 80, IpFamily.V4, 2, NetOperationOptions.TestDefault()).IsErr(),
    "empty host rejected"
  );
  AssertTrueMsg(
    resolver.ResolveAsync("127.0.0.1", -1, IpFamily.V4, 2, NetOperationOptions.TestDefault()).IsErr(),
    "invalid port rejected"
  );
  AssertTrueMsg(
    resolver.ResolveAsync("127.0.0.1", 80, IpFamily.V4, 0, NetOperationOptions.TestDefault()).IsErr(),
    "zero result capacity rejected"
  );
  let cancelled: NetCancellation = NetCancellation.New();
  cancelled.Cancel();
  AssertTrueMsg(
    resolver.ResolveAsync(
      "127.0.0.1",
      80,
      IpFamily.V4,
      2,
      NetOperationOptions{cancellation: cancelled}
    ).IsErr(),
    "already cancelled query rejected"
  );
  AssertEqI32Msg(resolver.PendingCount(), 0, "invalid registration must not charge a slot");
}

/**
 * @brief Closed loop admission wins over an empty producer or cancelled controls.
 * @note The producer must query owner liveness through the internal operation boundary.
 */
@test(tag = "net_core_n3")
func test_net_core_n3_closed_driver_precedes_dns_admission() {
  var resolver: AsyncResolver = AsyncResolver.TestNew(1, 1);
  var driver: NetEventLoop = NetEventLoop{};
  let empty: Result<AsyncFuture<Result<Unit, NetError>>, NetError> = resolver.WhenReady(
    driver, NetOperationOptions.TestDefault()
  );
  AssertTrueMsg(empty.IsErr(), "closed driver rejects an empty DNS producer");
  AssertTrueMsg(
    ((empty.get_if<NetError>()) as NetError).kind == NetErrorKind.Closed,
    "closed ownership precedes empty-query admission"
  );

  var cancellation: NetCancellation = NetCancellation.New();
  cancellation.Cancel();
  let cancelled: Result<AsyncFuture<Result<Unit, NetError>>, NetError> = resolver.WhenReady(
    driver, NetOperationOptions{cancellation: cancellation}
  );
  AssertTrueMsg(cancelled.IsErr(), "closed driver rejects cancelled registration");
  AssertTrueMsg(
    ((cancelled.get_if<NetError>()) as NetError).kind == NetErrorKind.Closed,
    "closed ownership precedes cancellation at registration"
  );
}
