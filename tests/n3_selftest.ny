// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

part of NetContractTests;

/** @brief Cross-platform N3 behavior cases; all network traffic is local or fixture-controlled. */

@test(tag = "net_core_n3")
func test_net_core_n3_tcp_owned_exact_and_eof() {
  var driver: NetEventLoop = NetEventLoop.TestNew(8);
  var pair: NetTestSocketPair = NetTestSocketPair.New(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  let options: NetOperationOptions = NetOperationOptions.TestDefault();
  var payload: NetBuffer = NetBuffer.TestFromString("hello");
  let sent: Result<AsyncFuture<NetTransfer>, NetError> = client.WriteAllAsync(driver, payload, options);
  let received: Result<AsyncFuture<NetTransfer>, NetError> = server.ReadExactlyAsync(driver, 5, options);
  AssertTrueMsg(sent.IsOk(), "n3_selftest.ny:155");
  AssertTrueMsg(received.IsOk(), "n3_selftest.ny:155");
  payload = NetBuffer{};
  let send_future: AsyncFuture<NetTransfer> = (
    sent.get_if<AsyncFuture<NetTransfer>>()
  ) as AsyncFuture<NetTransfer>;
  let read_future: AsyncFuture<NetTransfer> = (
    received.get_if<AsyncFuture<NetTransfer>>()
  ) as AsyncFuture<NetTransfer>;
  let write: NetTransfer = (driver).TestTransfer(send_future);
  let read: NetTransfer = (driver).TestTransfer(read_future);
  AssertTrueMsg(write.error == nil, "n3_selftest.ny:161");
  AssertTrueMsg(read.error == nil, "n3_selftest.ny:161");
  AssertEqI64Msg(write.bytes_transferred as int64, 5i64, "n3_selftest.ny:162");
  AssertEqStringMsg((read.buffer).TestText(), "hello", "n3_selftest.ny:163");
  AssertTrueMsg(client.ShutdownWrite().IsOk(), "n3_selftest.ny:164");
  let tail: Result<AsyncFuture<NetTransfer>, NetError> = server.ReadExactlyAsync(driver, 1, options);
  let eof: NetTransfer = (driver).TestTransfer((tail.get_if<AsyncFuture<NetTransfer>>()) as AsyncFuture<NetTransfer>);
  AssertTrueMsg(eof.eof, "n3_selftest.ny:167");
  AssertTrueMsg(eof.error != nil, "n3_selftest.ny:167");
  AssertTrueMsg((eof.error as NetError).kind == NetErrorKind.UnexpectedEof, "n3_selftest.ny:168");
  AssertEqI32Msg(driver.PendingCount(), 0, "n3_selftest.ny:169");
  AssertEqI64Msg(driver.RetainedBytes() as int64, 0i64, "n3_selftest.ny:170");
}

@test(tag = "net_core_n3")
func test_net_core_n3_accept_cancel_and_close() {
  var driver: NetEventLoop = NetEventLoop.TestNew(4);
  var listener: TcpListener = TcpListener.TestListen();
  var accepted: Result<TcpConnectionTask, NetError> = listener.AcceptAsync(driver, NetOperationOptions.TestDefault());
  AssertTrueMsg(accepted.IsOk(), "n3_selftest.ny:178");
  var task: TcpConnectionTask = move((accepted.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let future: AsyncFuture<Result<Unit, NetError>> = (task).TestFuture();
  AssertTrueMsg(task.Cancel(), "n3_selftest.ny:181");
  AssertTrueMsg(!task.Cancel(), "n3_selftest.ny:181");
  (driver).TestPump(future);
  let completed: Result<Unit, NetError> = (
    future.GetResult().get_if<Result<Unit, NetError>>()
  ) as Result<Unit, NetError>;
  AssertTrueMsg(completed.IsErr(), "n3_selftest.ny:184");
  AssertTrueMsg(
    ((completed.get_if<NetError>()) as NetError).kind == NetErrorKind.Cancelled,
    "n3_selftest.ny:184"
  );
  AssertEqI32Msg(driver.PendingCount(), 0, "n3_selftest.ny:185");
  AssertTrueMsg(!task.Cancel(), "n3_selftest.ny:186");
  driver.Close();
  driver.Close();
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_literal_and_failure() {
  var resolver: AsyncResolver = AsyncResolver.TestNew(1, 4);
  let options: NetOperationOptions = NetOperationOptions.TestDefault();
  let queued: Result<AsyncFuture<NetResolution>, NetError> = resolver.ResolveAsync(
    "127.0.0.1",
    443,
    IpFamily.V4,
    4,
    options
  );
  AssertTrueMsg(queued.IsOk(), "n3_selftest.ny:195");
  let future: AsyncFuture<NetResolution> = (
    queued.get_if<AsyncFuture<NetResolution>>()
  ) as AsyncFuture<NetResolution>;
  let result: NetResolution = (resolver).TestResolution(future);
  AssertTrueMsg(result.error == nil, "n3_selftest.ny:198");
  AssertEqI32Msg(result.addresses.Len(), 1, "n3_selftest.ny:198");
  let endpoint: Result<NetEndpoint, NetError> = result.addresses.Get(0);
  AssertEqStringMsg(
    ((endpoint.get_if<NetEndpoint>()) as NetEndpoint).ToString(),
    "127.0.0.1:443",
    "n3_selftest.ny:200"
  );
  AssertTrueMsg(result.addresses.Get(1).IsErr(), "n3_selftest.ny:201");
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
  let failure: NetResolution = (resolver).TestResolution(failed_future);
  AssertTrueMsg(failure.error != nil, "n3_selftest.ny:205");
  AssertTrueMsg((failure.error as NetError).kind == NetErrorKind.NameNotFound, "n3_selftest.ny:205");
  AssertEqI32Msg(failure.addresses.Len(), 0, "n3_selftest.ny:206");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_notification_idle_wake() {
  AssertEqI32Msg(net_core_test_dns_reset(), 0, "n3_selftest.ny:211");
  var driver: NetEventLoop = NetEventLoop.TestNew(4);
  var resolver: AsyncResolver = AsyncResolver.TestNew(1, 2);
  let options: NetOperationOptions = NetOperationOptions.TestDefault();
  let queued: Result<AsyncFuture<NetResolution>, NetError> = resolver.ResolveAsync(
    "net-core-gated.invalid",
    80,
    IpFamily.V4,
    4,
    options
  );
  AssertTrueMsg(queued.IsOk(), "n3_selftest.ny:216");
  let future: AsyncFuture<NetResolution> = (
    queued.get_if<AsyncFuture<NetResolution>>()
  ) as AsyncFuture<NetResolution>;
  NetTestDnsWait{count: 1}.Wait();
  let ready: Result<AsyncFuture<Result<Unit, NetError>>, NetError> = resolver.WhenReady(driver, options);
  AssertTrueMsg(ready.IsOk(), "n3_selftest.ny:220");
  AssertTrueMsg(resolver.WhenReady(driver, options).IsErr(), "n3_selftest.ny:220");
  let notification: AsyncFuture<Result<Unit, NetError>> = (
    ready.get_if<AsyncFuture<Result<Unit, NetError>>>()
  ) as AsyncFuture<Result<Unit, NetError>>;
  let release: Result<Thread, ThreadError> = Thread.Spawn(NetTestReleaseDnsLater);
  AssertTrueMsg(release.IsOk(), "n3_selftest.ny:223");
  let start: uint64 = Instant.Now().ToDurationSinceEpochish().ToNanoseconds();
  AssertTrueMsg(driver.Poll(-1).IsOk(), "n3_selftest.ny:225");
  let elapsed: uint64 = Instant.Now().ToDurationSinceEpochish().ToNanoseconds() - start;
  AssertTrueMsg(elapsed >= 100000000u64, "n3_selftest.ny:227");
  AssertTrueMsg(elapsed < 2500000000u64, "n3_selftest.ny:227");
  AssertTrueMsg(notification.is_completed, "n3_selftest.ny:228");
  AssertTrueMsg(
    ((notification.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>).IsOk(),
    "n3_selftest.ny:229"
  );
  let result: NetResolution = (resolver).TestResolution(future);
  AssertTrueMsg(result.error == nil, "n3_selftest.ny:231");
  AssertEqI32Msg(result.addresses.Len(), 1, "n3_selftest.ny:231");
  AssertEqI32Msg(resolver.PendingCount(), 0, "n3_selftest.ny:232");
}
