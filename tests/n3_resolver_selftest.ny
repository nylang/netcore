/** @brief Controlled resolver queue, notification, cancellation and shutdown cases. */
part of NetTransport;

@test(tag = "net_core_n3")
func test_net_core_n3_dns_running_cancel_retains_capacity() {
  net_test_assert_i32(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:6");
  var driver: NetEventLoop = net_test_loop(2);
  var resolver: AsyncResolver = net_test_resolver(1, 1);
  let token: NetCancellation = NetCancellation.New();
  let future: AsyncFuture<NetResolution> = net_test_dns(resolver.ResolveAsync("net-core-gated.invalid", 80, IpFamily.V4, 2, NetOperationOptions{cancellation: token}));
  net_test_wait_dns(1); token.Cancel(); net_test_assert_true(resolver.Poll().IsOk(), "n3_resolver_selftest.ny:11");
  net_test_assert_true(future.is_completed, "n3_resolver_selftest.ny:12");
  let cancelled: NetResolution = net_test_resolution(resolver, future);
  net_test_assert_true((cancelled.error as NetError).kind == NetErrorKind.Cancelled, "n3_resolver_selftest.ny:14");
  net_test_assert_i32(resolver.PendingCount(), 1, "n3_resolver_selftest.ny:15");
  let rejected: Result<AsyncFuture<NetResolution>, NetError> = resolver.ResolveAsync("127.0.0.1", 80, IpFamily.V4, 2, net_test_options());
  net_test_assert_true(rejected.IsErr(), "n3_resolver_selftest.ny:17"); net_test_assert_true(((rejected.get_if<NetError>()) as NetError).kind == NetErrorKind.WouldBlock, "n3_resolver_selftest.ny:17");
  let ready: AsyncFuture<Result<Unit, NetError>> = net_test_ready(resolver.WhenReady(driver, net_test_options()));
  net_test_assert_true(driver.Poll(0).IsOk(), "n3_resolver_selftest.ny:19"); net_test_assert_true(!ready.is_completed, "n3_resolver_selftest.ny:19");
  net_core_test_dns_release(); net_test_pump(driver, ready); net_test_retire_dns(resolver);
  let retry: AsyncFuture<NetResolution> = net_test_dns(resolver.ResolveAsync("127.0.0.1", 80, IpFamily.V4, 2, net_test_options()));
  net_test_assert_true(net_test_resolution(resolver, retry).error == nil, "n3_resolver_selftest.ny:22"); net_test_assert_i32(net_core_test_dns_peak(), 1, "n3_resolver_selftest.ny:22");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_queued_cancel_skips_lookup() {
  net_test_assert_i32(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:27");
  var resolver: AsyncResolver = net_test_resolver(1, 2);
  let first: AsyncFuture<NetResolution> = net_test_dns(resolver.ResolveAsync("net-core-gated.invalid", 80, IpFamily.V4, 2, net_test_options()));
  net_test_wait_dns(1);
  let token: NetCancellation = NetCancellation.New();
  let second: AsyncFuture<NetResolution> = net_test_dns(resolver.ResolveAsync("net-core-gated.invalid", 80, IpFamily.V4, 2, NetOperationOptions{cancellation: token}));
  token.Cancel(); net_test_assert_true(resolver.Poll().IsOk(), "n3_resolver_selftest.ny:33");
  net_test_assert_true((net_test_resolution(resolver, second).error as NetError).kind == NetErrorKind.Cancelled, "n3_resolver_selftest.ny:34");
  net_test_assert_i32(net_core_test_dns_entered(), 1, "n3_resolver_selftest.ny:35"); net_test_assert_i32(resolver.PendingCount(), 1, "n3_resolver_selftest.ny:35");
  net_core_test_dns_release(); net_test_assert_true(net_test_resolution(resolver, first).error == nil, "n3_resolver_selftest.ny:36");
  net_test_assert_i32(net_core_test_dns_entered(), 1, "n3_resolver_selftest.ny:37");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_query_deadline_wakes_notification() {
  net_test_assert_i32(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:42");
  var driver: NetEventLoop = net_test_loop(2); var resolver: AsyncResolver = net_test_resolver(1, 1);
  let query_options: NetOperationOptions = NetOperationOptions{deadline: NetDeadline.After(NetClock.NowNanoseconds(), 50000000u64)};
  let query: AsyncFuture<NetResolution> = net_test_dns(resolver.ResolveAsync("net-core-gated.invalid", 80, IpFamily.V4, 2, query_options));
  net_test_wait_dns(1);
  let ready: AsyncFuture<Result<Unit, NetError>> = net_test_ready(resolver.WhenReady(driver, net_test_options()));
  net_test_assert_true(driver.Poll(-1).IsOk(), "n3_resolver_selftest.ny:48"); net_test_assert_true(ready.is_completed, "n3_resolver_selftest.ny:48");
  net_test_assert_true((net_test_resolution(resolver, query).error as NetError).kind == NetErrorKind.TimedOut, "n3_resolver_selftest.ny:49");
  net_test_assert_i32(resolver.PendingCount(), 1, "n3_resolver_selftest.ny:50");
  net_core_test_dns_release(); net_test_retire_dns(resolver);
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_distinct_query_cancellation() {
  net_test_assert_i32(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:56");
  var driver: NetEventLoop = net_test_loop(2); var resolver: AsyncResolver = net_test_resolver(2, 2);
  let a_token: NetCancellation = NetCancellation.New(); let b_token: NetCancellation = NetCancellation.New();
  let a: AsyncFuture<NetResolution> = net_test_dns(resolver.ResolveAsync("net-core-gated.invalid", 80, IpFamily.V4, 2, NetOperationOptions{cancellation: a_token}));
  let b: AsyncFuture<NetResolution> = net_test_dns(resolver.ResolveAsync("net-core-gated.invalid", 81, IpFamily.V4, 2, NetOperationOptions{cancellation: b_token}));
  net_test_wait_dns(2);
  let ready: AsyncFuture<Result<Unit, NetError>> = net_test_ready(resolver.WhenReady(driver, net_test_options()));
  let thread: Result<Thread, ThreadError> = Thread.Spawn(lambda [copy b_token] () -> void { Thread.Sleep(20u32); b_token.Cancel(); });
  net_test_assert_true(thread.IsOk(), "n3_resolver_selftest.ny:64");
  let start: uint64 = NetClock.NowNanoseconds();
  net_test_assert_true(driver.Poll(-1).IsOk(), "aggregate query cancellation must interrupt an otherwise blocking Poll");
  net_test_assert_true(NetClock.NowNanoseconds() - start < 2500000000u64, "query cancellation must not wait for notification timeout");
  net_test_assert_true(ready.is_completed, "aggregate query cancellation produces advisory readiness");
  let completion: Result<Unit, NetError> = (ready.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>;
  net_test_assert_true(completion.IsOk(), "query cancellation is not a notification timeout");
  net_test_assert_true((net_test_resolution(resolver, b).error as NetError).kind == NetErrorKind.Cancelled, "n3_resolver_selftest.ny:65");
  net_test_assert_true(!a.is_completed, "n3_resolver_selftest.ny:66"); net_test_assert_i32(resolver.PendingCount(), 2, "n3_resolver_selftest.ny:66");
  net_core_test_dns_release(); net_test_assert_true(net_test_resolution(resolver, a).error == nil, "n3_resolver_selftest.ny:67"); net_test_retire_dns(resolver);
  net_test_assert_i32(net_core_test_dns_peak(), 2, "n3_resolver_selftest.ny:68");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_close_notifier_and_late_worker() {
  let baseline: int32 = net_core_test_fd_count();
  net_test_assert_i32(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:73");
  var driver: NetEventLoop = net_test_loop(2); var resolver: AsyncResolver = net_test_resolver(1, 1);
  let query: AsyncFuture<NetResolution> = net_test_dns(resolver.ResolveAsync("net-core-gated.invalid", 80, IpFamily.V4, 2, net_test_options()));
  net_test_wait_dns(1);
  let ready: AsyncFuture<Result<Unit, NetError>> = net_test_ready(resolver.WhenReady(driver, net_test_options()));
  resolver.Close(); net_test_assert_true(query.is_completed, "n3_resolver_selftest.ny:78"); net_test_assert_true(!ready.is_completed, "n3_resolver_selftest.ny:78");
  net_test_pump(driver, ready); net_test_assert_true(net_test_ready_error(ready) == NetErrorKind.Closed, "n3_resolver_selftest.ny:79");
  let result: NetResolution = (query.GetResult().get_if<NetResolution>()) as NetResolution;
  net_test_assert_true((result.error as NetError).kind == NetErrorKind.Closed, "n3_resolver_selftest.ny:81");
  net_core_test_dns_release();
  net_test_fd_baseline(baseline);
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_driver_close_preserves_query() {
  net_test_assert_i32(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:87");
  var driver: NetEventLoop = net_test_loop(2); var resolver: AsyncResolver = net_test_resolver(1, 1);
  let query: AsyncFuture<NetResolution> = net_test_dns(resolver.ResolveAsync("net-core-gated.invalid", 80, IpFamily.V4, 2, net_test_options()));
  net_test_wait_dns(1);
  let ready: AsyncFuture<Result<Unit, NetError>> = net_test_ready(resolver.WhenReady(driver, net_test_options()));
  driver.Close(); net_test_assert_true(net_test_ready_error(ready) == NetErrorKind.Closed, "n3_resolver_selftest.ny:92"); net_test_assert_true(!query.is_completed, "n3_resolver_selftest.ny:92");
  net_core_test_dns_release(); net_test_assert_true(net_test_resolution(resolver, query).error == nil, "n3_resolver_selftest.ny:93");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_notification_coalescing_and_reuse() {
  var driver: NetEventLoop = net_test_loop(2); var resolver: AsyncResolver = net_test_resolver(2, 4);
  var round: int32 = 0;
  while round < 100 {
    let a: AsyncFuture<NetResolution> = net_test_dns(resolver.ResolveAsync("127.0.0.1", 80, IpFamily.V4, 2, net_test_options()));
    let b: AsyncFuture<NetResolution> = net_test_dns(resolver.ResolveAsync("::1", 81, IpFamily.V6, 2, net_test_options()));
    let ready: AsyncFuture<Result<Unit, NetError>> = net_test_ready(resolver.WhenReady(driver, net_test_options()));
    if round % 2 == 0 { net_test_assert_true(resolver.Poll().IsOk(), "n3_resolver_selftest.ny:104"); }
    net_test_pump(driver, ready);
    net_test_assert_true(net_test_resolution(resolver, a).error == nil, "n3_resolver_selftest.ny:106"); net_test_assert_true(net_test_resolution(resolver, b).error == nil, "n3_resolver_selftest.ny:106");
    net_test_assert_i32(resolver.PendingCount(), 0, "n3_resolver_selftest.ny:107"); net_test_assert_i32(driver.PendingCount(), 0, "n3_resolver_selftest.ny:107");
    round = round + 1;
  }
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_hostname_copy_and_shared_result() {
  net_test_assert_i32(net_core_test_dns_reset(), 0, "n3_resolver_selftest.ny:114");
  var resolver: AsyncResolver = net_test_resolver(1, 2);
  let first: AsyncFuture<NetResolution> = net_test_dns(resolver.ResolveAsync("net-core-gated.invalid", 80, IpFamily.V4, 2, net_test_options()));
  net_test_wait_dns(1);
  var host: string = "net-core-failed.invalid".Substring(0, 23);
  let second: AsyncFuture<NetResolution> = net_test_dns(resolver.ResolveAsync(host, 80, IpFamily.V4, 2, net_test_options()));
  unsafe { *(host.data as *mut uint8) = 0u8; }
  net_core_test_dns_release();
  let success: NetResolution = net_test_resolution(resolver, first);
  let failure: NetResolution = net_test_resolution(resolver, second);
  net_test_assert_true(success.error == nil, "n3_resolver_selftest.ny:124"); net_test_assert_true((failure.error as NetError).kind == NetErrorKind.NameNotFound, "n3_resolver_selftest.ny:124");
  let retained: NetResolvedAddresses = success.addresses;
  resolver.Close();
  net_test_assert_i32(retained.Len(), 1, "n3_resolver_selftest.ny:127");
  net_test_assert_string(((retained.Get(0).get_if<NetEndpoint>()) as NetEndpoint).ToString(), "127.0.0.1:80", "n3_resolver_selftest.ny:128");
}

func net_test_pool_resource_round() -> void {
  var driver: NetEventLoop = net_test_loop(2); var resolver: AsyncResolver = net_test_resolver(2, 2);
  let query: AsyncFuture<NetResolution> = net_test_dns(resolver.ResolveAsync("127.0.0.1", 80, IpFamily.V4, 2, net_test_options()));
  let ready: AsyncFuture<Result<Unit, NetError>> = net_test_ready(resolver.WhenReady(driver, net_test_options()));
  net_test_pump(driver, ready); net_test_assert_true(net_test_resolution(resolver, query).error == nil, "n3_resolver_selftest.ny:135");
  resolver.Close(); driver.Close();
}
@test(tag = "net_core_n3")
func test_net_core_n3_dns_pool_descriptor_recovery() {
  let baseline: int32 = net_core_test_fd_count(); net_test_assert_true(baseline >= 0, "n3_resolver_selftest.ny:140");
  var i: int32 = 0;
  while i < 64 { net_test_pool_resource_round(); i = i + 1; }
  net_test_fd_baseline(baseline);
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_move_preserves_notification() {
  net_test_assert_i32(net_core_test_dns_reset(), 0, "reset controlled DNS");
  var driver: NetEventLoop = net_test_loop(2); var resolver: AsyncResolver = net_test_resolver(1, 1);
  let query: AsyncFuture<NetResolution> = net_test_dns(resolver.ResolveAsync("net-core-gated.invalid", 80, IpFamily.V4, 2, net_test_options()));
  net_test_wait_dns(1);
  let ready: AsyncFuture<Result<Unit, NetError>> = net_test_ready(resolver.WhenReady(driver, net_test_options()));
  var moved: AsyncResolver = move(resolver);
  net_core_test_dns_release(); net_test_pump(driver, ready);
  net_test_assert_true(net_test_resolution(moved, query).error == nil, "notification follows shared pool after owner move");
}

func net_test_discard_dns(resolver: ref mut AsyncResolver, driver: ref mut NetEventLoop) -> void {
  net_test_assert_true(resolver.ResolveAsync("net-core-gated.invalid", 80, IpFamily.V4, 2, net_test_options()).IsOk(), "admit query before dropping its Future");
  net_test_assert_true(resolver.WhenReady(driver, net_test_options()).IsOk(), "admit notification before dropping its Future");
}
@test(tag = "net_core_n3")
func test_net_core_n3_dns_dropped_futures_do_not_cancel() {
  net_test_assert_i32(net_core_test_dns_reset(), 0, "reset controlled DNS");
  var driver: NetEventLoop = net_test_loop(2); var resolver: AsyncResolver = net_test_resolver(1, 1);
  net_test_discard_dns(resolver, driver); net_test_wait_dns(1);
  net_test_assert_i32(resolver.PendingCount(), 1, "query remains owned"); net_test_assert_i32(driver.PendingCount(), 1, "notification remains owned");
  net_core_test_dns_release();
  var i: int32 = 0;
  while driver.PendingCount() > 0 && i < 1000 { net_test_assert_true(driver.Poll(5).IsOk(), "drive dropped notification"); i = i + 1; }
  net_test_assert_i32(driver.PendingCount(), 0, "dropped notification retires"); net_test_retire_dns(resolver);
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_startup_fd_failure_cleanup() {
  let baseline: int32 = net_core_test_fd_count();
  net_test_assert_i32(net_core_test_fd_exhaust_begin(), 0, "enable the isolated startup resource-failure fixture");
  var result: Result<AsyncResolver, NetError> = AsyncResolver.New(2, 2);
  let restored: int32 = net_core_test_fd_exhaust_end();
  net_test_assert_i32(restored, 0, "restore the resource-failure fixture before further assertions");
  net_test_assert_true(result.IsErr(), "notification startup must fail without starting a live pool");
  net_test_fd_baseline(baseline);
}

@test(tag = "net_core_n3")
func test_net_core_n3_invalid_admission_preserves_capacity() {
  net_test_assert_true(AsyncResolver.New(0, 1).IsErr(), "zero workers rejected");
  net_test_assert_true(AsyncResolver.New(2, 1).IsErr(), "capacity must cover workers");
  net_test_assert_true(NetEventLoop.NewWithLimits(2, -1 as intptr).IsErr(), "negative byte budget rejected");
  var resolver: AsyncResolver = net_test_resolver(1, 1);
  net_test_assert_true(resolver.ResolveAsync("", 80, IpFamily.V4, 2, net_test_options()).IsErr(), "empty host rejected");
  net_test_assert_true(resolver.ResolveAsync("127.0.0.1", -1, IpFamily.V4, 2, net_test_options()).IsErr(), "invalid port rejected");
  net_test_assert_true(resolver.ResolveAsync("127.0.0.1", 80, IpFamily.V4, 0, net_test_options()).IsErr(), "zero result capacity rejected");
  let cancelled: NetCancellation = NetCancellation.New(); cancelled.Cancel();
  net_test_assert_true(resolver.ResolveAsync("127.0.0.1", 80, IpFamily.V4, 2, NetOperationOptions{cancellation: cancelled}).IsErr(), "already cancelled query rejected");
  net_test_assert_i32(resolver.PendingCount(), 0, "invalid registration must not charge a slot");
}
