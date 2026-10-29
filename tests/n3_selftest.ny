// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

part of NetContractTests;

/** @brief Cross-platform N3 behavior cases; all network traffic is local or fixture-controlled. */

@test(tag = "net_core_n3")
func test_net_core_n3_tcp_owned_exact_and_eof() {
  var driver: NetEventLoop = NetTestLoop(8);
  var pair: NetTestSocketPair = NetTestPair(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  let options: NetOperationOptions = NetTestOptions();
  var payload: NetBuffer = NetTestBuffer("hello");
  let sent: Result<AsyncFuture<NetTransfer>, NetError> = client.WriteAllAsync(driver, payload, options);
  let received: Result<AsyncFuture<NetTransfer>, NetError> = server.ReadExactlyAsync(driver, 5, options);
  NetTestAssertTrue(sent.IsOk(), "n3_selftest.ny:155");
  NetTestAssertTrue(received.IsOk(), "n3_selftest.ny:155");
  payload = NetBuffer{};
  let send_future: AsyncFuture<NetTransfer> = (
    sent.get_if<AsyncFuture<NetTransfer>>()
  ) as AsyncFuture<NetTransfer>;
  let read_future: AsyncFuture<NetTransfer> = (
    received.get_if<AsyncFuture<NetTransfer>>()
  ) as AsyncFuture<NetTransfer>;
  let write: NetTransfer = NetTestTransfer(driver, send_future);
  let read: NetTransfer = NetTestTransfer(driver, read_future);
  NetTestAssertTrue(write.error == nil, "n3_selftest.ny:161");
  NetTestAssertTrue(read.error == nil, "n3_selftest.ny:161");
  NetTestAssertI64(write.bytes_transferred as int64, 5i64, "n3_selftest.ny:162");
  NetTestAssertString(NetTestBufferText(read.buffer), "hello", "n3_selftest.ny:163");
  NetTestAssertTrue(client.ShutdownWrite().IsOk(), "n3_selftest.ny:164");
  let tail: Result<AsyncFuture<NetTransfer>, NetError> = server.ReadExactlyAsync(driver, 1, options);
  let eof: NetTransfer = NetTestTransfer(
    driver,
    (tail.get_if<AsyncFuture<NetTransfer>>()) as AsyncFuture<NetTransfer>
  );
  NetTestAssertTrue(eof.eof, "n3_selftest.ny:167");
  NetTestAssertTrue(eof.error != nil, "n3_selftest.ny:167");
  NetTestAssertTrue((eof.error as NetError).kind == NetErrorKind.UnexpectedEof, "n3_selftest.ny:168");
  NetTestAssertI32(driver.PendingCount(), 0, "n3_selftest.ny:169");
  NetTestAssertI64(driver.RetainedBytes() as int64, 0i64, "n3_selftest.ny:170");
}

@test(tag = "net_core_n3")
func test_net_core_n3_accept_cancel_and_close() {
  var driver: NetEventLoop = NetTestLoop(4);
  var listener: TcpListener = NetTestListener();
  var accepted: Result<TcpConnectionTask, NetError> = listener.AcceptAsync(driver, NetTestOptions());
  NetTestAssertTrue(accepted.IsOk(), "n3_selftest.ny:178");
  var task: TcpConnectionTask = move((accepted.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let future: AsyncFuture<Result<Unit, NetError>> = NetTestTaskFuture(task);
  NetTestAssertTrue(task.Cancel(), "n3_selftest.ny:181");
  NetTestAssertTrue(!task.Cancel(), "n3_selftest.ny:181");
  NetTestPump(driver, future);
  let completed: Result<Unit, NetError> = (
    future.GetResult().get_if<Result<Unit, NetError>>()
  ) as Result<Unit, NetError>;
  NetTestAssertTrue(completed.IsErr(), "n3_selftest.ny:184");
  NetTestAssertTrue(
    ((completed.get_if<NetError>()) as NetError).kind == NetErrorKind.Cancelled,
    "n3_selftest.ny:184"
  );
  NetTestAssertI32(driver.PendingCount(), 0, "n3_selftest.ny:185");
  NetTestAssertTrue(!task.Cancel(), "n3_selftest.ny:186");
  driver.Close();
  driver.Close();
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_literal_and_failure() {
  var resolver: AsyncResolver = NetTestResolver(1, 4);
  let options: NetOperationOptions = NetTestOptions();
  let queued: Result<AsyncFuture<NetResolution>, NetError> = resolver.ResolveAsync(
    "127.0.0.1",
    443,
    IpFamily.V4,
    4,
    options
  );
  NetTestAssertTrue(queued.IsOk(), "n3_selftest.ny:195");
  let future: AsyncFuture<NetResolution> = (
    queued.get_if<AsyncFuture<NetResolution>>()
  ) as AsyncFuture<NetResolution>;
  let result: NetResolution = NetTestResolution(resolver, future);
  NetTestAssertTrue(result.error == nil, "n3_selftest.ny:198");
  NetTestAssertI32(result.addresses.Len(), 1, "n3_selftest.ny:198");
  let endpoint: Result<NetEndpoint, NetError> = result.addresses.Get(0);
  NetTestAssertString(
    ((endpoint.get_if<NetEndpoint>()) as NetEndpoint).ToString(),
    "127.0.0.1:443",
    "n3_selftest.ny:200"
  );
  NetTestAssertTrue(result.addresses.Get(1).IsErr(), "n3_selftest.ny:201");
  let failed: Result<AsyncFuture<NetResolution>, NetError> = resolver.ResolveAsync(
    "net-core-failed.invalid",
    443,
    IpFamily.V4,
    4,
    options
  );
  let failed_future: AsyncFuture<NetResolution> = (
    failed.get_if<AsyncFuture<NetResolution>>()
  ) as AsyncFuture<NetResolution>;
  let failure: NetResolution = NetTestResolution(resolver, failed_future);
  NetTestAssertTrue(failure.error != nil, "n3_selftest.ny:205");
  NetTestAssertTrue((failure.error as NetError).kind == NetErrorKind.NameNotFound, "n3_selftest.ny:205");
  NetTestAssertI32(failure.addresses.Len(), 0, "n3_selftest.ny:206");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_notification_idle_wake() {
  NetTestAssertI32(net_core_test_dns_reset(), 0, "n3_selftest.ny:211");
  var driver: NetEventLoop = NetTestLoop(4);
  var resolver: AsyncResolver = NetTestResolver(1, 2);
  let options: NetOperationOptions = NetTestOptions();
  let queued: Result<AsyncFuture<NetResolution>, NetError> = resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    4,
    options
  );
  NetTestAssertTrue(queued.IsOk(), "n3_selftest.ny:216");
  let future: AsyncFuture<NetResolution> = (
    queued.get_if<AsyncFuture<NetResolution>>()
  ) as AsyncFuture<NetResolution>;
  NetTestWaitDns(1);
  let ready: Result<AsyncFuture<Result<Unit, NetError>>, NetError> = resolver.WhenReady(driver, options);
  NetTestAssertTrue(ready.IsOk(), "n3_selftest.ny:220");
  NetTestAssertTrue(resolver.WhenReady(driver, options).IsErr(), "n3_selftest.ny:220");
  let notification: AsyncFuture<Result<Unit, NetError>> = (
    ready.get_if<AsyncFuture<Result<Unit, NetError>>>()
  ) as AsyncFuture<Result<Unit, NetError>>;
  let release: Result<Thread, ThreadError> = Thread.Spawn(NetTestReleaseDnsLater);
  NetTestAssertTrue(release.IsOk(), "n3_selftest.ny:223");
  let start: uint64 = NetClock.NowNanoseconds();
  NetTestAssertTrue(driver.Poll(-1).IsOk(), "n3_selftest.ny:225");
  let elapsed: uint64 = NetClock.NowNanoseconds() - start;
  NetTestAssertTrue(elapsed >= 100000000u64, "n3_selftest.ny:227");
  NetTestAssertTrue(elapsed < 2500000000u64, "n3_selftest.ny:227");
  NetTestAssertTrue(notification.is_completed, "n3_selftest.ny:228");
  NetTestAssertTrue(
    ((notification.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>).IsOk(),
    "n3_selftest.ny:229"
  );
  let result: NetResolution = NetTestResolution(resolver, future);
  NetTestAssertTrue(result.error == nil, "n3_selftest.ny:231");
  NetTestAssertI32(result.addresses.Len(), 1, "n3_selftest.ny:231");
  NetTestAssertI32(resolver.PendingCount(), 0, "n3_selftest.ny:232");
}
