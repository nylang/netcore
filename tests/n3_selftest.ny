/** @brief Cross-platform N3 behavior cases; all network traffic is local or fixture-controlled. */
part of NetTransport;

@extern("C") func net_core_test_failed_connect_kind() -> int32;
@extern("C") func net_core_test_dns_reset() -> int32;
@extern("C") func net_core_test_dns_entered() -> int32;
@extern("C") func net_core_test_dns_active() -> int32;
@extern("C") func net_core_test_dns_peak() -> int32;
@extern("C") func net_core_test_dns_release() -> void;
@extern("C") func net_core_test_resource_report(expected: int32) -> void;
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
  net_test_assert_true(result.IsOk(), "n3_selftest.ny:17");
  return move((result.get_if<NetEventLoop>()) as NetEventLoop);
}
func net_test_resolver(workers: int32, limit: int32) -> AsyncResolver {
  var result: Result<AsyncResolver, NetError> = AsyncResolver.New(workers, limit);
  net_test_assert_true(result.IsOk(), "n3_selftest.ny:22");
  return move((result.get_if<AsyncResolver>()) as AsyncResolver);
}
func net_test_listener() -> TcpListener {
  let endpoint: Result<NetEndpoint, NetError> = NetEndpoint.Parse("127.0.0.1:0");
  var result: Result<TcpListener, NetError> = TcpListener.Listen((endpoint.get_if<NetEndpoint>()) as NetEndpoint, 8);
  net_test_assert_true(result.IsOk(), "n3_selftest.ny:28");
  return move((result.get_if<TcpListener>()) as TcpListener);
}
func net_test_task_future(task: ref mut TcpConnectionTask) -> AsyncFuture<Result<Unit, NetError>> {
  let result: Result<AsyncFuture<Result<Unit, NetError>>, NetError> = task.FutureHandle();
  net_test_assert_true(result.IsOk(), "n3_selftest.ny:33");
  return (result.get_if<AsyncFuture<Result<Unit, NetError>>>()) as AsyncFuture<Result<Unit, NetError>>;
}
func net_test_pump(driver: ref mut NetEventLoop, future: ref AsyncFuture<Result<Unit, NetError>>) -> void {
  var i: int32 = 0;
  while !future.is_completed && i < 1000 {
    let result: Result<int32, NetError> = driver.Poll(5);
    net_test_assert_true(result.IsOk(), "n3_selftest.ny:40");
    i = i + 1;
  }
  net_test_assert_true(future.is_completed, "n3_selftest.ny:43");
}
func net_test_transfer(driver: ref mut NetEventLoop, future: ref AsyncFuture<NetTransfer>) -> NetTransfer {
  var i: int32 = 0;
  while !future.is_completed && i < 1000 {
    net_test_assert_true(driver.Poll(5).IsOk(), "n3_selftest.ny:48");
    i = i + 1;
  }
  net_test_assert_true(future.is_completed, "n3_selftest.ny:51");
  let result: Result<NetTransfer, AsyncError> = future.GetResult();
  net_test_assert_true(result.IsOk(), "n3_selftest.ny:53");
  return (result.get_if<NetTransfer>()) as NetTransfer;
}
func net_test_pair(driver: ref mut NetEventLoop, client: ref mut TcpConnection, server: ref mut TcpConnection) -> void {
  var listener: TcpListener = net_test_listener();
  let endpoint: Result<NetEndpoint, NetError> = listener.LocalEndpoint();
  let options: NetOperationOptions = net_test_options();
  var accepted: Result<TcpConnectionTask, NetError> = listener.AcceptAsync(driver, options);
  net_test_assert_true(accepted.IsOk(), "n3_selftest.ny:61");
  var accept_task: TcpConnectionTask = move((accepted.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  var connected: Result<TcpConnectionTask, NetError> = TcpConnection.DialAsync(driver, (endpoint.get_if<NetEndpoint>()) as NetEndpoint, options);
  net_test_assert_true(connected.IsOk(), "n3_selftest.ny:64");
  var connect_task: TcpConnectionTask = move((connected.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let connect_future: AsyncFuture<Result<Unit, NetError>> = net_test_task_future(connect_task);
  let accept_future: AsyncFuture<Result<Unit, NetError>> = net_test_task_future(accept_task);
  net_test_pump(driver, connect_future);
  net_test_pump(driver, accept_future);
  net_test_assert_true(((connect_future.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>).IsOk(), "n3_selftest.ny:70");
  net_test_assert_true(((accept_future.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>).IsOk(), "n3_selftest.ny:71");
  var client_result: Result<TcpConnection, NetError> = connect_task.TakeConnection();
  var server_result: Result<TcpConnection, NetError> = accept_task.TakeConnection();
  net_test_assert_true(client_result.IsOk(), "n3_selftest.ny:74"); net_test_assert_true(server_result.IsOk(), "n3_selftest.ny:74");
  var client_value: TcpConnection = move((client_result.get_if<TcpConnection>()) as TcpConnection);
  var server_value: TcpConnection = move((server_result.get_if<TcpConnection>()) as TcpConnection);
  client.socket_value = client_value.socket_value.Take();
  server.socket_value = server_value.socket_value.Take();
  net_test_assert_true(connect_task.TakeConnection().IsErr(), "n3_selftest.ny:79");
  net_test_assert_true(!connect_task.Cancel(), "n3_selftest.ny:80");
}
func net_test_buffer(text: ref string) -> NetBuffer {
  let result: Result<NetBuffer, NetError> = NetBuffer.CopyFrom(NetBytes.FromString(text));
  net_test_assert_true(result.IsOk(), "n3_selftest.ny:84");
  return (result.get_if<NetBuffer>()) as NetBuffer;
}
func net_test_buffer_text(buffer: ref NetBuffer) -> string {
  let bytes: NetBytes = buffer.Bytes();
  return string.ViewFrom(bytes.Data() as *const int8, bytes.Len() as int32).Substring(0, bytes.Len() as int32);
}
func net_test_wait_dns(count: int32) -> void {
  var i: int32 = 0;
  while net_core_test_dns_entered() < count && i < 2000 { Thread.Sleep(1u32); i = i + 1; }
  net_test_assert_true(net_core_test_dns_entered() >= count, "n3_selftest.ny:94");
}
func net_test_release_dns_later() -> void { Thread.Sleep(200u32); net_core_test_dns_release(); }
func net_test_udp() -> UdpSocket {
  let parsed: Result<NetEndpoint, NetError> = NetEndpoint.Parse("127.0.0.1:0");
  var bound: Result<UdpSocket, NetError> = UdpSocket.Bind((parsed.get_if<NetEndpoint>()) as NetEndpoint);
  net_test_assert_true(bound.IsOk(), "n3_selftest.ny:100");
  return move((bound.get_if<UdpSocket>()) as UdpSocket);
}
func net_test_ready(queued: Result<AsyncFuture<Result<Unit, NetError>>, NetError>) -> AsyncFuture<Result<Unit, NetError>> {
  net_test_assert_true(queued.IsOk(), "n3_selftest.ny:104");
  return (queued.get_if<AsyncFuture<Result<Unit, NetError>>>()) as AsyncFuture<Result<Unit, NetError>>;
}
func net_test_io(queued: Result<AsyncFuture<NetTransfer>, NetError>) -> AsyncFuture<NetTransfer> {
  net_test_assert_true(queued.IsOk(), "n3_selftest.ny:108");
  return (queued.get_if<AsyncFuture<NetTransfer>>()) as AsyncFuture<NetTransfer>;
}
func net_test_dns(queued: Result<AsyncFuture<NetResolution>, NetError>) -> AsyncFuture<NetResolution> {
  net_test_assert_true(queued.IsOk(), "n3_selftest.ny:112");
  return (queued.get_if<AsyncFuture<NetResolution>>()) as AsyncFuture<NetResolution>;
}
func net_test_ready_error(future: ref AsyncFuture<Result<Unit, NetError>>) -> NetErrorKind {
  let completed: Result<Unit, NetError> = (future.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>;
  net_test_assert_true(completed.IsErr(), "n3_selftest.ny:117");
  return ((completed.get_if<NetError>()) as NetError).kind;
}
func net_test_retire_dns(resolver: ref mut AsyncResolver) -> void {
  var i: int32 = 0;
  while resolver.PendingCount() != 0 && i < 2000 {
    net_test_assert_true(resolver.Poll().IsOk(), "n3_selftest.ny:123"); Thread.Sleep(1u32); i = i + 1;
  }
  net_test_assert_i32(resolver.PendingCount(), 0, "n3_selftest.ny:125");
}
func net_test_fd_baseline(expected: int32) -> void {
  var i: int32 = 0;
  while net_core_test_fd_count() != expected && i < 2000 { Thread.Sleep(1u32); i = i + 1; }
  if net_core_test_fd_count() != expected { net_core_test_resource_report(expected); }
  net_test_assert_i32(net_core_test_fd_count(), expected, "resource handles return to the warmed baseline");
}
func net_test_resolution(resolver: ref mut AsyncResolver, future: ref AsyncFuture<NetResolution>) -> NetResolution {
  var i: int32 = 0;
  while !future.is_completed && i < 2000 {
    net_test_assert_true(resolver.Poll().IsOk(), "n3_selftest.ny:135");
    if !future.is_completed { Thread.Sleep(1u32); }
    i = i + 1;
  }
  net_test_assert_true(future.is_completed, "n3_selftest.ny:139");
  let result: Result<NetResolution, AsyncError> = future.GetResult();
  net_test_assert_true(result.IsOk(), "n3_selftest.ny:141");
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
  net_test_assert_true(sent.IsOk(), "n3_selftest.ny:155"); net_test_assert_true(received.IsOk(), "n3_selftest.ny:155");
  payload = NetBuffer{};
  let send_future: AsyncFuture<NetTransfer> = (sent.get_if<AsyncFuture<NetTransfer>>()) as AsyncFuture<NetTransfer>;
  let read_future: AsyncFuture<NetTransfer> = (received.get_if<AsyncFuture<NetTransfer>>()) as AsyncFuture<NetTransfer>;
  let write: NetTransfer = net_test_transfer(driver, send_future);
  let read: NetTransfer = net_test_transfer(driver, read_future);
  net_test_assert_true(write.error == nil, "n3_selftest.ny:161"); net_test_assert_true(read.error == nil, "n3_selftest.ny:161");
  net_test_assert_i64(write.bytes_transferred as int64, 5i64, "n3_selftest.ny:162");
  net_test_assert_string(net_test_buffer_text(read.buffer), "hello", "n3_selftest.ny:163");
  net_test_assert_true(client.ShutdownWrite().IsOk(), "n3_selftest.ny:164");
  let tail: Result<AsyncFuture<NetTransfer>, NetError> = server.ReadExactlyAsync(driver, 1, options);
  let eof: NetTransfer = net_test_transfer(driver, (tail.get_if<AsyncFuture<NetTransfer>>()) as AsyncFuture<NetTransfer>);
  net_test_assert_true(eof.eof, "n3_selftest.ny:167"); net_test_assert_true(eof.error != nil, "n3_selftest.ny:167");
  net_test_assert_true((eof.error as NetError).kind == NetErrorKind.UnexpectedEof, "n3_selftest.ny:168");
  net_test_assert_i32(driver.PendingCount(), 0, "n3_selftest.ny:169");
  net_test_assert_i64(driver.RetainedBytes() as int64, 0i64, "n3_selftest.ny:170");
}

@test(tag = "net_core_n3")
func test_net_core_n3_accept_cancel_and_close() {
  var driver: NetEventLoop = net_test_loop(4);
  var listener: TcpListener = net_test_listener();
  var accepted: Result<TcpConnectionTask, NetError> = listener.AcceptAsync(driver, net_test_options());
  net_test_assert_true(accepted.IsOk(), "n3_selftest.ny:178");
  var task: TcpConnectionTask = move((accepted.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let future: AsyncFuture<Result<Unit, NetError>> = net_test_task_future(task);
  net_test_assert_true(task.Cancel(), "n3_selftest.ny:181"); net_test_assert_true(!task.Cancel(), "n3_selftest.ny:181");
  net_test_pump(driver, future);
  let completed: Result<Unit, NetError> = (future.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>;
  net_test_assert_true(completed.IsErr(), "n3_selftest.ny:184"); net_test_assert_true(((completed.get_if<NetError>()) as NetError).kind == NetErrorKind.Cancelled, "n3_selftest.ny:184");
  net_test_assert_i32(driver.PendingCount(), 0, "n3_selftest.ny:185");
  net_test_assert_true(!task.Cancel(), "n3_selftest.ny:186");
  driver.Close(); driver.Close();
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_literal_and_failure() {
  var resolver: AsyncResolver = net_test_resolver(1, 4);
  let options: NetOperationOptions = net_test_options();
  let queued: Result<AsyncFuture<NetResolution>, NetError> = resolver.ResolveAsync("127.0.0.1", 443, IpFamily.V4, 4, options);
  net_test_assert_true(queued.IsOk(), "n3_selftest.ny:195");
  let future: AsyncFuture<NetResolution> = (queued.get_if<AsyncFuture<NetResolution>>()) as AsyncFuture<NetResolution>;
  let result: NetResolution = net_test_resolution(resolver, future);
  net_test_assert_true(result.error == nil, "n3_selftest.ny:198"); net_test_assert_i32(result.addresses.Len(), 1, "n3_selftest.ny:198");
  let endpoint: Result<NetEndpoint, NetError> = result.addresses.Get(0);
  net_test_assert_string(((endpoint.get_if<NetEndpoint>()) as NetEndpoint).ToString(), "127.0.0.1:443", "n3_selftest.ny:200");
  net_test_assert_true(result.addresses.Get(1).IsErr(), "n3_selftest.ny:201");
  let failed: Result<AsyncFuture<NetResolution>, NetError> = resolver.ResolveAsync("net-core-failed.invalid", 443, IpFamily.V4, 4, options);
  let failed_future: AsyncFuture<NetResolution> = (failed.get_if<AsyncFuture<NetResolution>>()) as AsyncFuture<NetResolution>;
  let failure: NetResolution = net_test_resolution(resolver, failed_future);
  net_test_assert_true(failure.error != nil, "n3_selftest.ny:205"); net_test_assert_true((failure.error as NetError).kind == NetErrorKind.NameNotFound, "n3_selftest.ny:205");
  net_test_assert_i32(failure.addresses.Len(), 0, "n3_selftest.ny:206");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dns_notification_idle_wake() {
  net_test_assert_i32(net_core_test_dns_reset(), 0, "n3_selftest.ny:211");
  var driver: NetEventLoop = net_test_loop(4);
  var resolver: AsyncResolver = net_test_resolver(1, 2);
  let options: NetOperationOptions = net_test_options();
  let queued: Result<AsyncFuture<NetResolution>, NetError> = resolver.ResolveAsync("net-core-gated.invalid", 80, IpFamily.V4, 4, options);
  net_test_assert_true(queued.IsOk(), "n3_selftest.ny:216");
  let future: AsyncFuture<NetResolution> = (queued.get_if<AsyncFuture<NetResolution>>()) as AsyncFuture<NetResolution>;
  net_test_wait_dns(1);
  let ready: Result<AsyncFuture<Result<Unit, NetError>>, NetError> = resolver.WhenReady(driver, options);
  net_test_assert_true(ready.IsOk(), "n3_selftest.ny:220"); net_test_assert_true(resolver.WhenReady(driver, options).IsErr(), "n3_selftest.ny:220");
  let notification: AsyncFuture<Result<Unit, NetError>> = (ready.get_if<AsyncFuture<Result<Unit, NetError>>>()) as AsyncFuture<Result<Unit, NetError>>;
  let release: Result<Thread, ThreadError> = Thread.Spawn(net_test_release_dns_later);
  net_test_assert_true(release.IsOk(), "n3_selftest.ny:223");
  let start: uint64 = NetClock.NowNanoseconds();
  net_test_assert_true(driver.Poll(-1).IsOk(), "n3_selftest.ny:225");
  let elapsed: uint64 = NetClock.NowNanoseconds() - start;
  net_test_assert_true(elapsed >= 100000000u64, "n3_selftest.ny:227"); net_test_assert_true(elapsed < 2500000000u64, "n3_selftest.ny:227");
  net_test_assert_true(notification.is_completed, "n3_selftest.ny:228");
  net_test_assert_true(((notification.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>).IsOk(), "n3_selftest.ny:229");
  let result: NetResolution = net_test_resolution(resolver, future);
  net_test_assert_true(result.error == nil, "n3_selftest.ny:231"); net_test_assert_i32(result.addresses.Len(), 1, "n3_selftest.ny:231");
  net_test_assert_i32(resolver.PendingCount(), 0, "n3_selftest.ny:232");
}
