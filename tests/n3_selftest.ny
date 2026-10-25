/** @brief macOS N3 behavior cases; all network traffic is local or fixture-controlled. */
part of NetTransport;

@extern("C") func net_core_test_dns_reset() -> int32;
@extern("C") func net_core_test_dns_entered() -> int32;
@extern("C") func net_core_test_dns_active() -> int32;
@extern("C") func net_core_test_dns_peak() -> int32;
@extern("C") func net_core_test_dns_release() -> void;
@extern("C") func net_core_test_fd_count() -> int32;
@extern("C") func net_core_test_native_direction() -> int32;
@extern("C") func net_core_test_empty_udp_readiness() -> int32;
@extern("C") func net_core_test_fd_exhaust_begin() -> int32;
@extern("C") func net_core_test_fd_exhaust_end() -> int32;

func net_test_options() -> NetOperationOptions {
  return NetOperationOptions{deadline: NetDeadline.After(NetClock.NowNanoseconds(), 3000000000u64)};
}
func net_test_loop(limit: int32) -> NetEventLoop {
  var result: Result<NetEventLoop, NetError> = NetEventLoop.New(limit);
  AssertTrueMsg(result.IsOk(), "n3_selftest.ny:17");
  return move((result.get_if<NetEventLoop>()) as NetEventLoop);
}
func net_test_resolver(workers: int32, limit: int32) -> AsyncResolver {
  var result: Result<AsyncResolver, NetError> = AsyncResolver.New(workers, limit);
  AssertTrueMsg(result.IsOk(), "n3_selftest.ny:22");
  return move((result.get_if<AsyncResolver>()) as AsyncResolver);
}
func net_test_listener() -> TcpListener {
  let endpoint: Result<NetEndpoint, NetError> = NetEndpoint.Parse("127.0.0.1:0");
  var result: Result<TcpListener, NetError> = TcpListener.Listen((endpoint.get_if<NetEndpoint>()) as NetEndpoint, 8);
  AssertTrueMsg(result.IsOk(), "n3_selftest.ny:28");
  return move((result.get_if<TcpListener>()) as TcpListener);
}
func net_test_task_future(task: ref mut TcpConnectionTask) -> AsyncFuture<Result<Unit, NetError>> {
  let result: Result<AsyncFuture<Result<Unit, NetError>>, NetError> = task.FutureHandle();
  AssertTrueMsg(result.IsOk(), "n3_selftest.ny:33");
  return (result.get_if<AsyncFuture<Result<Unit, NetError>>>()) as AsyncFuture<Result<Unit, NetError>>;
}
func net_test_pump(driver: ref mut NetEventLoop, future: ref AsyncFuture<Result<Unit, NetError>>) -> void {
  var i: int32 = 0;
  while !future.is_completed && i < 1000 {
    let result: Result<int32, NetError> = driver.Poll(5);
    AssertTrueMsg(result.IsOk(), "n3_selftest.ny:40");
    i = i + 1;
  }
  AssertTrueMsg(future.is_completed, "n3_selftest.ny:43");
}
func net_test_transfer(driver: ref mut NetEventLoop, future: ref AsyncFuture<NetTransfer>) -> NetTransfer {
  var i: int32 = 0;
  while !future.is_completed && i < 1000 {
    AssertTrueMsg(driver.Poll(5).IsOk(), "n3_selftest.ny:48");
    i = i + 1;
  }
  AssertTrueMsg(future.is_completed, "n3_selftest.ny:51");
  let result: Result<NetTransfer, AsyncError> = future.GetResult();
  AssertTrueMsg(result.IsOk(), "n3_selftest.ny:53");
  return (result.get_if<NetTransfer>()) as NetTransfer;
}
func net_test_pair(driver: ref mut NetEventLoop, client: ref mut TcpConnection, server: ref mut TcpConnection) -> void {
  var listener: TcpListener = net_test_listener();
  let endpoint: Result<NetEndpoint, NetError> = listener.LocalEndpoint();
  let options: NetOperationOptions = net_test_options();
  var accepted: Result<TcpConnectionTask, NetError> = listener.AcceptAsync(driver, options);
  AssertTrueMsg(accepted.IsOk(), "n3_selftest.ny:61");
  var accept_task: TcpConnectionTask = move((accepted.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  var connected: Result<TcpConnectionTask, NetError> = TcpConnection.DialAsync(driver, (endpoint.get_if<NetEndpoint>()) as NetEndpoint, options);
  AssertTrueMsg(connected.IsOk(), "n3_selftest.ny:64");
  var connect_task: TcpConnectionTask = move((connected.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let connect_future: AsyncFuture<Result<Unit, NetError>> = net_test_task_future(connect_task);
  let accept_future: AsyncFuture<Result<Unit, NetError>> = net_test_task_future(accept_task);
  net_test_pump(driver, connect_future);
  net_test_pump(driver, accept_future);
  AssertTrueMsg(((connect_future.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>).IsOk(), "n3_selftest.ny:70");
  AssertTrueMsg(((accept_future.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>).IsOk(), "n3_selftest.ny:71");
  var client_result: Result<TcpConnection, NetError> = connect_task.TakeConnection();
  var server_result: Result<TcpConnection, NetError> = accept_task.TakeConnection();
  AssertTrueMsg(client_result.IsOk(), "n3_selftest.ny:74"); AssertTrueMsg(server_result.IsOk(), "n3_selftest.ny:74");
  var client_value: TcpConnection = move((client_result.get_if<TcpConnection>()) as TcpConnection);
  var server_value: TcpConnection = move((server_result.get_if<TcpConnection>()) as TcpConnection);
  client.socket_value = client_value.socket_value.Take();
  server.socket_value = server_value.socket_value.Take();
  AssertTrueMsg(connect_task.TakeConnection().IsErr(), "n3_selftest.ny:79");
  AssertTrueMsg(!connect_task.Cancel(), "n3_selftest.ny:80");
}
func net_test_buffer(text: ref string) -> NetBuffer {
  let result: Result<NetBuffer, NetError> = NetBuffer.CopyFrom(NetBytes.FromString(text));
  AssertTrueMsg(result.IsOk(), "n3_selftest.ny:84");
  return (result.get_if<NetBuffer>()) as NetBuffer;
}
func net_test_buffer_text(buffer: ref NetBuffer) -> string {
  let bytes: NetBytes = buffer.Bytes();
  return string.ViewFrom(bytes.Data() as *const int8, bytes.Len() as int32).Substring(0, bytes.Len() as int32);
}
func net_test_wait_dns(count: int32) -> void {
  var i: int32 = 0;
  while net_core_test_dns_entered() < count && i < 2000 { Thread.Sleep(1u32); i = i + 1; }
  AssertTrueMsg(net_core_test_dns_entered() >= count, "n3_selftest.ny:94");
}
func net_test_release_dns_later() -> void { Thread.Sleep(200u32); net_core_test_dns_release(); }
func net_test_udp() -> UdpSocket {
  let parsed: Result<NetEndpoint, NetError> = NetEndpoint.Parse("127.0.0.1:0");
  var bound: Result<UdpSocket, NetError> = UdpSocket.Bind((parsed.get_if<NetEndpoint>()) as NetEndpoint);
  AssertTrueMsg(bound.IsOk(), "n3_selftest.ny:100");
  return move((bound.get_if<UdpSocket>()) as UdpSocket);
}
func net_test_ready(queued: Result<AsyncFuture<Result<Unit, NetError>>, NetError>) -> AsyncFuture<Result<Unit, NetError>> {
  AssertTrueMsg(queued.IsOk(), "n3_selftest.ny:104");
  return (queued.get_if<AsyncFuture<Result<Unit, NetError>>>()) as AsyncFuture<Result<Unit, NetError>>;
}
func net_test_io(queued: Result<AsyncFuture<NetTransfer>, NetError>) -> AsyncFuture<NetTransfer> {
  AssertTrueMsg(queued.IsOk(), "n3_selftest.ny:108");
  return (queued.get_if<AsyncFuture<NetTransfer>>()) as AsyncFuture<NetTransfer>;
}
func net_test_dns(queued: Result<AsyncFuture<NetResolution>, NetError>) -> AsyncFuture<NetResolution> {
  AssertTrueMsg(queued.IsOk(), "n3_selftest.ny:112");
  return (queued.get_if<AsyncFuture<NetResolution>>()) as AsyncFuture<NetResolution>;
}
func net_test_ready_error(future: ref AsyncFuture<Result<Unit, NetError>>) -> NetErrorKind {
  let completed: Result<Unit, NetError> = (future.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>;
  AssertTrueMsg(completed.IsErr(), "n3_selftest.ny:117");
  return ((completed.get_if<NetError>()) as NetError).kind;
}
func net_test_retire_dns(resolver: ref mut AsyncResolver) -> void {
  var i: int32 = 0;
  while resolver.PendingCount() != 0 && i < 2000 {
    AssertTrueMsg(resolver.Poll().IsOk(), "n3_selftest.ny:123"); Thread.Sleep(1u32); i = i + 1;
  }
  AssertEqI32Msg(resolver.PendingCount(), 0, "n3_selftest.ny:125");
}
func net_test_fd_baseline(expected: int32) -> void {
  var i: int32 = 0;
  while net_core_test_fd_count() != expected && i < 2000 { Thread.Sleep(1u32); i = i + 1; }
  AssertEqI32Msg(net_core_test_fd_count(), expected, "n3_selftest.ny:130");
}
func net_test_resolution(resolver: ref mut AsyncResolver, future: ref AsyncFuture<NetResolution>) -> NetResolution {
  var i: int32 = 0;
  while !future.is_completed && i < 2000 {
    AssertTrueMsg(resolver.Poll().IsOk(), "n3_selftest.ny:135");
    if !future.is_completed { Thread.Sleep(1u32); }
    i = i + 1;
  }
  AssertTrueMsg(future.is_completed, "n3_selftest.ny:139");
  let result: Result<NetResolution, AsyncError> = future.GetResult();
  AssertTrueMsg(result.IsOk(), "n3_selftest.ny:141");
  return (result.get_if<NetResolution>()) as NetResolution;
}

@test(tag = "net_core_n3")
func test_net_core_n3_tcp_owned_exact_and_eof() {
  var driver: NetEventLoop = net_test_loop(8);
  var client: TcpConnection = TcpConnection{};
  var server: TcpConnection = TcpConnection{};
  net_test_pair(driver, client, server);
  let options: NetOperationOptions = net_test_options();
  var payload: NetBuffer = net_test_buffer("hello");
  let sent: Result<AsyncFuture<NetTransfer>, NetError> = client.WriteAllAsync(driver, payload, options);
  let received: Result<AsyncFuture<NetTransfer>, NetError> = server.ReadExactlyAsync(driver, 5, options);
  AssertTrueMsg(sent.IsOk(), "n3_selftest.ny:155"); AssertTrueMsg(received.IsOk(), "n3_selftest.ny:155");
  payload = NetBuffer{};
  let send_future: AsyncFuture<NetTransfer> = (sent.get_if<AsyncFuture<NetTransfer>>()) as AsyncFuture<NetTransfer>;
  let read_future: AsyncFuture<NetTransfer> = (received.get_if<AsyncFuture<NetTransfer>>()) as AsyncFuture<NetTransfer>;
  let write: NetTransfer = net_test_transfer(driver, send_future);
  let read: NetTransfer = net_test_transfer(driver, read_future);
  AssertTrueMsg(write.error == nil, "n3_selftest.ny:161"); AssertTrueMsg(read.error == nil, "n3_selftest.ny:161");
  AssertEqI64Msg(write.bytes_transferred as int64, 5i64, "n3_selftest.ny:162");
  AssertEqStringMsg(net_test_buffer_text(read.buffer), "hello", "n3_selftest.ny:163");
  AssertTrueMsg(client.ShutdownWrite().IsOk(), "n3_selftest.ny:164");
  let tail: Result<AsyncFuture<NetTransfer>, NetError> = server.ReadExactlyAsync(driver, 1, options);
  let eof: NetTransfer = net_test_transfer(driver, (tail.get_if<AsyncFuture<NetTransfer>>()) as AsyncFuture<NetTransfer>);
  AssertTrueMsg(eof.eof, "n3_selftest.ny:167"); AssertTrueMsg(eof.error != nil, "n3_selftest.ny:167");
  AssertTrueMsg((eof.error as NetError).kind == NetErrorKind.UnexpectedEof, "n3_selftest.ny:168");
  AssertEqI32Msg(driver.PendingCount(), 0, "n3_selftest.ny:169");
  AssertEqI64Msg(driver.RetainedBytes() as int64, 0i64, "n3_selftest.ny:170");
}

@test(tag = "net_core_n3")
func test_net_core_n3_accept_cancel_and_close() {
  var driver: NetEventLoop = net_test_loop(4);
  var listener: TcpListener = net_test_listener();
  var accepted: Result<TcpConnectionTask, NetError> = listener.AcceptAsync(driver, net_test_options());
  AssertTrueMsg(accepted.IsOk(), "n3_selftest.ny:178");
  var task: TcpConnectionTask = move((accepted.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let future: AsyncFuture<Result<Unit, NetError>> = net_test_task_future(task);
  AssertTrueMsg(task.Cancel(), "n3_selftest.ny:181"); AssertTrueMsg(!task.Cancel(), "n3_selftest.ny:181");
  net_test_pump(driver, future);
  let completed: Result<Unit, NetError> = (future.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>;
  AssertTrueMsg(completed.IsErr(), "n3_selftest.ny:184"); AssertTrueMsg(((completed.get_if<NetError>()) as NetError).kind == NetErrorKind.Cancelled, "n3_selftest.ny:184");
  AssertEqI32Msg(driver.PendingCount(), 0, "n3_selftest.ny:185");
  AssertTrueMsg(!task.Cancel(), "n3_selftest.ny:186");
  driver.Close(); driver.Close();
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_literal_and_failure() {
  var resolver: AsyncResolver = net_test_resolver(1, 4);
  let options: NetOperationOptions = net_test_options();
  let queued: Result<AsyncFuture<NetResolution>, NetError> = resolver.ResolveAsync("127.0.0.1", 443, IpFamily.V4, 4, options);
  AssertTrueMsg(queued.IsOk(), "n3_selftest.ny:195");
  let future: AsyncFuture<NetResolution> = (queued.get_if<AsyncFuture<NetResolution>>()) as AsyncFuture<NetResolution>;
  let result: NetResolution = net_test_resolution(resolver, future);
  AssertTrueMsg(result.error == nil, "n3_selftest.ny:198"); AssertEqI32Msg(result.addresses.Len(), 1, "n3_selftest.ny:198");
  let endpoint: Result<NetEndpoint, NetError> = result.addresses.Get(0);
  AssertEqStringMsg(((endpoint.get_if<NetEndpoint>()) as NetEndpoint).ToString(), "127.0.0.1:443", "n3_selftest.ny:200");
  AssertTrueMsg(result.addresses.Get(1).IsErr(), "n3_selftest.ny:201");
  let failed: Result<AsyncFuture<NetResolution>, NetError> = resolver.ResolveAsync("net-core-failed.invalid", 443, IpFamily.V4, 4, options);
  let failed_future: AsyncFuture<NetResolution> = (failed.get_if<AsyncFuture<NetResolution>>()) as AsyncFuture<NetResolution>;
  let failure: NetResolution = net_test_resolution(resolver, failed_future);
  AssertTrueMsg(failure.error != nil, "n3_selftest.ny:205"); AssertTrueMsg((failure.error as NetError).kind == NetErrorKind.NameNotFound, "n3_selftest.ny:205");
  AssertEqI32Msg(failure.addresses.Len(), 0, "n3_selftest.ny:206");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_notification_idle_wake() {
  AssertEqI32Msg(net_core_test_dns_reset(), 0, "n3_selftest.ny:211");
  var driver: NetEventLoop = net_test_loop(4);
  var resolver: AsyncResolver = net_test_resolver(1, 2);
  let options: NetOperationOptions = net_test_options();
  let queued: Result<AsyncFuture<NetResolution>, NetError> = resolver.ResolveAsync("net-core-gated.invalid", 80, IpFamily.V4, 4, options);
  AssertTrueMsg(queued.IsOk(), "n3_selftest.ny:216");
  let future: AsyncFuture<NetResolution> = (queued.get_if<AsyncFuture<NetResolution>>()) as AsyncFuture<NetResolution>;
  net_test_wait_dns(1);
  let ready: Result<AsyncFuture<Result<Unit, NetError>>, NetError> = resolver.WhenReady(driver, options);
  AssertTrueMsg(ready.IsOk(), "n3_selftest.ny:220"); AssertTrueMsg(resolver.WhenReady(driver, options).IsErr(), "n3_selftest.ny:220");
  let notification: AsyncFuture<Result<Unit, NetError>> = (ready.get_if<AsyncFuture<Result<Unit, NetError>>>()) as AsyncFuture<Result<Unit, NetError>>;
  let release: Result<Thread, ThreadError> = Thread.Spawn(net_test_release_dns_later);
  AssertTrueMsg(release.IsOk(), "n3_selftest.ny:223");
  let start: uint64 = NetClock.NowNanoseconds();
  AssertTrueMsg(driver.Poll(-1).IsOk(), "n3_selftest.ny:225");
  let elapsed: uint64 = NetClock.NowNanoseconds() - start;
  AssertTrueMsg(elapsed >= 100000000u64, "n3_selftest.ny:227"); AssertTrueMsg(elapsed < 2500000000u64, "n3_selftest.ny:227");
  AssertTrueMsg(notification.is_completed, "n3_selftest.ny:228");
  AssertTrueMsg(((notification.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>).IsOk(), "n3_selftest.ny:229");
  let result: NetResolution = net_test_resolution(resolver, future);
  AssertTrueMsg(result.error == nil, "n3_selftest.ny:231"); AssertEqI32Msg(result.addresses.Len(), 1, "n3_selftest.ny:231");
  AssertEqI32Msg(resolver.PendingCount(), 0, "n3_selftest.ny:232");
}
