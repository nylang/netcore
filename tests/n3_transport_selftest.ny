// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

part of NetContractTests;

/** @brief Local transport controls, ownership, queue budgets and reentrant completion. */

@test(tag = "net_core_n3")
func test_net_core_n3_native_direction_and_closed_driver() {
  AssertEqI32Msg(net_core_test_native_direction(), 0, "n3_transport_selftest.ny:6");
  AssertEqI32Msg(
    net_core_test_empty_udp_readiness(),
    1,
    "native empty UDP must remain readable and receivable"
  );
  var driver: NetEventLoop = NetEventLoop.TestNew(2);
  AssertEqI32Msg((driver.Poll(0).get_if<int32>()) as int32, 0, "n3_transport_selftest.ny:8");
  AssertTrueMsg(driver.Poll(-2).IsErr(), "n3_transport_selftest.ny:9");
  driver.Close();
  AssertTrueMsg(driver.Poll(0).IsErr(), "n3_transport_selftest.ny:11");
}

@test(tag = "net_core_n3")
func test_net_core_n3_tcp_partial_exact_eof() {
  var driver: NetEventLoop = NetEventLoop.TestNew(4);
  var pair: NetTestSocketPair = NetTestSocketPair.New(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  let options: NetOperationOptions = NetOperationOptions.TestDefault();
  let read: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(server.ReadExactlyAsync(driver, 8, options));
  let write: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(client.WriteAllAsync(
    driver,
    NetBuffer.TestFromString("abc"),
    options
  ));
  AssertTrueMsg((driver).TestTransfer(write).error == nil, "n3_transport_selftest.ny:22");
  AssertTrueMsg(client.ShutdownWrite().IsOk(), "n3_transport_selftest.ny:23");
  let result: NetTransfer = (driver).TestTransfer(read);
  AssertTrueMsg(result.eof, "n3_transport_selftest.ny:25");
  AssertTrueMsg(result.error != nil, "n3_transport_selftest.ny:25");
  AssertTrueMsg(
    (result.error as NetError).kind == NetErrorKind.UnexpectedEof,
    "n3_transport_selftest.ny:26"
  );
  AssertEqI64Msg(result.bytes_transferred as int64, 3i64, "n3_transport_selftest.ny:27");
  AssertEqStringMsg((result.buffer).TestText(), "abc", "n3_transport_selftest.ny:28");
}

// nyra-lint-allow: prefer-type-owned-functions -- Return drops sockets after transfer-progress checks.
func net_test_partial_read(close_driver: bool) -> void {
  var driver: NetEventLoop = NetEventLoop.TestNew(4);
  var pair: NetTestSocketPair = NetTestSocketPair.New(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  let token: NetCancellation = NetCancellation.New();
  let options: NetOperationOptions = NetOperationOptions{
    deadline: NetOperationOptions.TestDefault().deadline,
    cancellation: token
  };
  let read: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(server.ReadExactlyAsync(driver, 8, options));
  let write: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(client.WriteAllAsync(
    driver,
    NetBuffer.TestFromString("abc"),
    options
  ));
  AssertTrueMsg((driver).TestTransfer(write).error == nil, "n3_transport_selftest.ny:39");
  var attempts: int32 = 0;
  while driver.pending.Len() == 1 && driver.pending.Get(0).progress <(3 as intptr) && attempts < 1000 {
    AssertTrueMsg(driver.Poll(5).IsOk(), "pump partial read before cancellation/Close");
    attempts = attempts + 1;
  }

  AssertTrueMsg(
    driver.pending.Len() == 1 && driver.pending.Get(0).progress == (3 as intptr),
    "partial prefix must reach the receiving operation"
  );
  AssertTrueMsg(!read.is_completed, "n3_transport_selftest.ny:41");
  if close_driver {
    driver.Close();
  } else {
    token.Cancel();
    AssertTrueMsg(driver.Poll(0).IsOk(), "n3_transport_selftest.ny:42");
  }

  let result: NetTransfer = (driver).TestTransfer(read);
  AssertTrueMsg(result.error != nil, "n3_transport_selftest.ny:44");
  var expected: NetErrorKind = NetErrorKind.Cancelled;
  if close_driver {
    expected = NetErrorKind.Closed;
  }

  AssertTrueMsg((result.error as NetError).kind == expected, "n3_transport_selftest.ny:47");
  AssertEqI64Msg(result.bytes_transferred as int64, 3i64, "n3_transport_selftest.ny:48");
  AssertEqStringMsg((result.buffer).TestText(), "abc", "n3_transport_selftest.ny:49");
  AssertEqI64Msg(driver.RetainedBytes() as int64, 0i64, "n3_transport_selftest.ny:50");
}

@test(tag = "net_core_n3")
func test_net_core_n3_tcp_cancel_preserves_progress() {
  net_test_partial_read(false);
}

@test(tag = "net_core_n3")
func test_net_core_n3_tcp_close_preserves_progress() {
  net_test_partial_read(true);
}

@test(tag = "net_core_n3")
func test_net_core_n3_zero_tcp_and_read_overlap() {
  var driver: NetEventLoop = NetEventLoop.TestNew(4);
  var pair: NetTestSocketPair = NetTestSocketPair.New(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  let options: NetOperationOptions = NetOperationOptions.TestDefault();
  let zero: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(server.ReadAsync(driver, 0, options));
  let result: NetTransfer = (driver).TestTransfer(zero);
  AssertTrueMsg(!result.eof, "n3_transport_selftest.ny:65");
  AssertTrueMsg(result.error == nil, "n3_transport_selftest.ny:65");
  AssertEqI64Msg(result.bytes_transferred as int64, 0i64, "n3_transport_selftest.ny:66");
  let empty: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(client.WriteAllAsync(driver,
    NetBuffer{}, options));
  AssertTrueMsg((driver).TestTransfer(empty).error == nil, "n3_transport_selftest.ny:68");
  let pending: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(server.ReadAsync(driver, 1, options));
  let overlap: Result<AsyncFuture<NetTransfer>, NetError> = server.ReadAsync(driver, 1, options);
  AssertTrueMsg(overlap.IsErr(), "n3_transport_selftest.ny:71");
  AssertTrueMsg(
    ((overlap.get_if<NetError>()) as NetError).kind == NetErrorKind.WouldBlock,
    "n3_transport_selftest.ny:72"
  );
  driver.Close();
  AssertTrueMsg(
    ((driver).TestTransfer(pending).error as NetError).kind == NetErrorKind.Closed,
    "n3_transport_selftest.ny:74"
  );
}

@test(tag = "net_core_n3")
func test_net_core_n3_sliced_root_budget_and_compaction() {
  var made: Result<NetEventLoop, NetError> = NetEventLoop.NewWithLimits(4, 4 as intptr);
  var driver: NetEventLoop = move((made.get_if<NetEventLoop>()) as NetEventLoop);
  var pair: NetTestSocketPair = NetTestSocketPair.New(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  let root: NetBuffer = NetBuffer.TestFromString("abcdefgh");
  let slice_result: Result<NetBuffer, NetError> = root.Slice(2 as intptr, 2 as intptr);
  let slice: NetBuffer = (slice_result.get_if<NetBuffer>()) as NetBuffer;
  AssertEqI64Msg(slice.RetainedBytes() as int64, 8i64, "n3_transport_selftest.ny:86");
  let rejected: Result<AsyncFuture<NetTransfer>, NetError> = client.WriteAllAsync(
    driver,
    slice,
    NetOperationOptions.TestDefault()
  );
  AssertTrueMsg(rejected.IsErr(), "n3_transport_selftest.ny:88");
  AssertEqI32Msg(driver.PendingCount(), 0, "n3_transport_selftest.ny:88");
  let copied: Result<NetBuffer, NetError> = NetBuffer.CopyFrom(slice.Bytes());
  let compact: NetBuffer = (copied.get_if<NetBuffer>()) as NetBuffer;
  AssertEqI64Msg(compact.RetainedBytes() as int64, 2i64, "n3_transport_selftest.ny:91");
  let sent: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(client.WriteAllAsync(driver, compact,
    NetOperationOptions.TestDefault()));
  AssertEqI64Msg(driver.RetainedBytes() as int64, 2i64, "n3_transport_selftest.ny:93");
  AssertTrueMsg((driver).TestTransfer(sent).error == nil, "n3_transport_selftest.ny:94");
  AssertEqI64Msg(driver.RetainedBytes() as int64, 0i64, "n3_transport_selftest.ny:95");
}

@test(tag = "net_core_n3")
func test_net_core_n3_udp_empty_and_truncation() {
  var driver: NetEventLoop = NetEventLoop.TestNew(4);
  var sender: UdpSocket = UdpSocket.TestBind();
  var receiver: UdpSocket = UdpSocket.TestBind();
  let endpoint_result: Result<NetEndpoint, NetError> = receiver.LocalEndpoint();
  let endpoint: NetEndpoint = (endpoint_result.get_if<NetEndpoint>()) as NetEndpoint;
  let options: NetOperationOptions = NetOperationOptions.TestDefault();
  let empty_read: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(receiver.ReceiveFromAsync(driver,
    0, options));
  let empty_send: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(sender.SendToAsync(
    driver,
    endpoint,
    NetBuffer{},
    options
  ));
  AssertTrueMsg((driver).TestTransfer(empty_send).error == nil, "n3_transport_selftest.ny:107");
  let empty: NetTransfer = (driver).TestTransfer(empty_read);
  AssertTrueMsg(empty.error == nil, "n3_transport_selftest.ny:109");
  AssertTrueMsg(empty.sender != nil, "n3_transport_selftest.ny:109");
  AssertTrueMsg(!empty.eof, "n3_transport_selftest.ny:109");
  AssertEqI64Msg(empty.bytes_transferred as int64, 0i64, "n3_transport_selftest.ny:110");
  let short_read: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(receiver.ReceiveFromAsync(driver,
    2, options));
  let long_send: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(sender.SendToAsync(
    driver,
    endpoint,
    NetBuffer.TestFromString("abcdef"),
    options
  ));
  AssertTrueMsg((driver).TestTransfer(long_send).error == nil, "n3_transport_selftest.ny:113");
  let truncated: NetTransfer = (driver).TestTransfer(short_read);
  AssertTrueMsg(truncated.error != nil, "n3_transport_selftest.ny:115");
  AssertTrueMsg(
    (truncated.error as NetError).kind == NetErrorKind.MessageTooLarge,
    "n3_transport_selftest.ny:115"
  );
  AssertEqI64Msg(truncated.buffer.Len() as int64, 0i64, "n3_transport_selftest.ny:116");
  AssertTrueMsg(truncated.sender == nil, "n3_transport_selftest.ny:116");
  let token: NetCancellation = NetCancellation.New();
  let pending: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(receiver.ReceiveFromAsync(
    driver,
    2,
    NetOperationOptions{cancellation: token}
  ));
  AssertTrueMsg(driver.Poll(0).IsOk(), "n3_transport_selftest.ny:119");
  AssertTrueMsg(!pending.is_completed, "n3_transport_selftest.ny:119");
  token.Cancel();
  AssertTrueMsg(
    ((driver).TestTransfer(pending).error as NetError).kind == NetErrorKind.Cancelled,
    "n3_transport_selftest.ny:121"
  );
}

@test(tag = "net_core_n3")
func test_net_core_n3_udp_zero_capacity_does_not_write_caller() {
  var sender: UdpSocket = UdpSocket.TestBind();
  var receiver: UdpSocket = UdpSocket.TestBind();
  var sentinel: uint8 = 77u8;
  let view_result: Result<NetMutableBytes, NetError> = NetMutableBytes.FromRaw(&mut sentinel, 0 as intptr);
  var view: NetMutableBytes = (view_result.get_if<NetMutableBytes>()) as NetMutableBytes;
  let none: Result<NetDatagram, NetError> = receiver.TryReceiveFrom(view);
  AssertTrueMsg(none.IsErr(), "zero-capacity receive must wait for a datagram");
  AssertTrueMsg(
    ((none.get_if<NetError>()) as NetError).kind == NetErrorKind.WouldBlock,
    "empty socket is WouldBlock"
  );
  let endpoint: NetEndpoint = (receiver.LocalEndpoint().get_if<NetEndpoint>()) as NetEndpoint;
  AssertTrueMsg(
    sender.SendTo(endpoint, NetBytes.FromString("z"), NetOperationOptions.TestDefault()).IsOk(),
    "send one byte"
  );
  let received: Result<NetDatagram, NetError> = receiver.ReceiveFrom(view, NetOperationOptions.TestDefault());
  AssertTrueMsg(received.IsErr(), "nonempty datagram must not fit zero capacity");
  AssertTrueMsg(
    ((received.get_if<NetError>()) as NetError).kind == NetErrorKind.MessageTooLarge,
    "nonempty datagram is discarded"
  );
  AssertEqI32Msg(sentinel as int32, 77, "zero capacity must never write the caller pointer");
  let consumed: Result<NetDatagram, NetError> = receiver.TryReceiveFrom(view);
  AssertTrueMsg(consumed.IsErr(), "the oversized datagram was consumed");
  AssertTrueMsg(
    ((consumed.get_if<NetError>()) as NetError).kind == NetErrorKind.WouldBlock,
    "no discarded prefix remains"
  );
}

@test(tag = "net_core_n3")
func test_net_core_n3_wakeable_cancel_fanout() {
  var driver: NetEventLoop = NetEventLoop.TestNew(4);
  var first: UdpSocket = UdpSocket.TestBind();
  var second: UdpSocket = UdpSocket.TestBind();
  let made: Result<NetCancellation, NetError> = NetCancellation.NewWakeable();
  let token: NetCancellation = (made.get_if<NetCancellation>()) as NetCancellation;
  AssertTrueMsg(token.CanWakeWaiters(), "macOS token must use an active wake channel");
  let options: NetOperationOptions = NetOperationOptions{
    deadline: NetOperationOptions.TestDefault().deadline,
    cancellation: token
  };
  let a: AsyncFuture<Result<Unit, NetError>> = AsyncFuture<Result<Unit,
    NetError>>.TestAdmit(first.WhenReadable(driver, options));
  let b: AsyncFuture<Result<Unit, NetError>> = AsyncFuture<Result<Unit,
    NetError>>.TestAdmit(second.WhenReadable(driver, options));
  let thread: Result<Thread, ThreadError> = Thread.Spawn(
    lambda[copy token]() -> void {
      Thread.Sleep(30u32);
      token.Cancel();
    }
  );
  AssertTrueMsg(thread.IsOk(), "n3_transport_selftest.ny:134");
  let start: uint64 = Instant.Now().ToDurationSinceEpochish().ToNanoseconds();
  AssertTrueMsg(driver.Poll(-1).IsOk(), "n3_transport_selftest.ny:135");
  AssertTrueMsg(
    Instant.Now().ToDurationSinceEpochish().ToNanoseconds() - start < 2500000000u64,
    "wake must arrive before the fallback deadline"
  );
  AssertTrueMsg(a.is_completed, "n3_transport_selftest.ny:136");
  AssertTrueMsg(b.is_completed, "n3_transport_selftest.ny:136");
  AssertTrueMsg((a).TestError() == NetErrorKind.Cancelled, "n3_transport_selftest.ny:137");
  AssertTrueMsg((b).TestError() == NetErrorKind.Cancelled, "n3_transport_selftest.ny:138");
  let late: AsyncFuture<Result<Unit, NetError>> = AsyncFuture<Result<Unit,
    NetError>>.TestAdmit(first.WhenReadable(driver, options));
  AssertTrueMsg(late.is_completed, "n3_transport_selftest.ny:140");
  AssertTrueMsg((late).TestError() == NetErrorKind.Cancelled, "n3_transport_selftest.ny:140");
  AssertEqI32Msg(driver.PendingCount(), 0, "n3_transport_selftest.ny:141");
}

@test(tag = "net_core_n3")
func test_net_core_n3_readiness_deadline() {
  var driver: NetEventLoop = NetEventLoop.TestNew(2);
  var socket: UdpSocket = UdpSocket.TestBind();
  let options: NetOperationOptions = NetOperationOptions{deadline: NetDeadline.After(
    Instant.Now().ToDurationSinceEpochish().ToNanoseconds(),
    20000000u64
  )};
  let ready: AsyncFuture<Result<Unit, NetError>> = AsyncFuture<Result<Unit,
    NetError>>.TestAdmit(socket.WhenReadable(driver, options));
  (driver).TestPump(ready);
  AssertTrueMsg((ready).TestError() == NetErrorKind.TimedOut, "n3_transport_selftest.ny:151");
}

// nyra-lint-allow: prefer-type-owned-functions -- Returning the Future intentionally drops the local connection task.
func net_test_abandoned_accept(
  driver: ref mut NetEventLoop,
  listener: ref mut TcpListener,
  cancel: bool
) -> AsyncFuture<Result<Unit, NetError>> {
  var queued: Result<TcpConnectionTask, NetError> = listener.AcceptAsync(driver, NetOperationOptions.TestDefault());
  var task: TcpConnectionTask = move((queued.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let future: AsyncFuture<Result<Unit, NetError>> = (task).TestFuture();
  if cancel {
    AssertTrueMsg(task.Cancel(), "n3_transport_selftest.ny:158");
  }

  return future;
}

@test(tag = "net_core_n3")
func test_net_core_n3_abandon_and_cancelled_drop() {
  var driver: NetEventLoop = NetEventLoop.TestNew(2);
  var listener: TcpListener = TcpListener.TestListen();
  let dropped: AsyncFuture<Result<Unit, NetError>> = net_test_abandoned_accept(driver, listener, false);
  (driver).TestPump(dropped);
  AssertTrueMsg((dropped).TestError() == NetErrorKind.Closed, "n3_transport_selftest.ny:166");
  let cancelled: AsyncFuture<Result<Unit, NetError>> = net_test_abandoned_accept(driver, listener, true);
  (driver).TestPump(cancelled);
  AssertTrueMsg(
    (cancelled).TestError() == NetErrorKind.Cancelled,
    "n3_transport_selftest.ny:168"
  );
}

@test(tag = "net_core_n3")
func test_net_core_n3_task_move_cancel_timeout_order() {
  var driver: NetEventLoop = NetEventLoop.TestNew(2);
  var listener: TcpListener = TcpListener.TestListen();
  let options: NetOperationOptions = NetOperationOptions{deadline: NetDeadline.After(
    Instant.Now().ToDurationSinceEpochish().ToNanoseconds(),
    50000000u64
  )};
  var queued: Result<TcpConnectionTask, NetError> = listener.AcceptAsync(driver, options);
  var task: TcpConnectionTask = move((queued.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let future: AsyncFuture<Result<Unit, NetError>> = (task).TestFuture();
  var moved: TcpConnectionTask = move(task);
  AssertTrueMsg(moved.Cancel(), "n3_transport_selftest.ny:180");
  Thread.Sleep(60u32);
  (driver).TestPump(future);
  AssertTrueMsg(
    (future).TestError() == NetErrorKind.Cancelled,
    "n3_transport_selftest.ny:183"
  );
}

struct NetTestCounter {
  hits: int32;
}

@test(tag = "net_core_n3")
func test_net_core_n3_close_callback_observes_terminal_tasks() {
  var driver: NetEventLoop = NetEventLoop.TestNew(4);
  var first: TcpListener = TcpListener.TestListen();
  var second: TcpListener = TcpListener.TestListen();
  var qa: Result<TcpConnectionTask, NetError> = first.AcceptAsync(driver, NetOperationOptions.TestDefault());
  var qb: Result<TcpConnectionTask, NetError> = second.AcceptAsync(driver, NetOperationOptions.TestDefault());
  var a: TcpConnectionTask = move((qa.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  var b: TcpConnectionTask = move((qb.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let af: AsyncFuture<Result<Unit, NetError>> = (a).TestFuture();
  let bf: AsyncFuture<Result<Unit, NetError>> = (b).TestFuture();
  let pointer: *mut TcpConnectionTask = &mut b;
  let counter: arc<NetTestCounter> = new arc<NetTestCounter>{};
  af.RegisterContinuation(
    lambda[copy pointer, copy counter]() -> void {
      unsafe {
        AssertTrueMsg(! (*pointer).Cancel(), "n3_transport_selftest.ny:201");
        let take: Result<TcpConnection, NetError> = (*pointer).TakeConnection();
        AssertTrueMsg(take.IsErr(), "n3_transport_selftest.ny:203");
        AssertTrueMsg(
          ((take.get_if<NetError>()) as NetError).kind == NetErrorKind.Closed,
          "n3_transport_selftest.ny:203"
        );
      }

      var state: arc<NetTestCounter> = counter;
      state.hits = state.hits + 1;
    }
  );
  driver.Close();
  AssertTrueMsg(af.is_completed, "n3_transport_selftest.ny:208");
  AssertTrueMsg(bf.is_completed, "n3_transport_selftest.ny:208");
  AssertEqI32Msg(counter.hits, 1, "n3_transport_selftest.ny:208");
}

@test(tag = "net_core_n3")
func test_net_core_n3_poll_callback_reentry() {
  var driver: NetEventLoop = NetEventLoop.TestNew(4);
  var socket: UdpSocket = UdpSocket.TestBind();
  let token: NetCancellation = NetCancellation.New();
  let future: AsyncFuture<Result<Unit, NetError>> = AsyncFuture<Result<Unit, NetError>>.TestAdmit(socket.WhenReadable(
    driver,
    NetOperationOptions{cancellation: token}
  ));
  let driver_pointer: *mut NetEventLoop = &mut driver;
  let socket_pointer: *mut UdpSocket = &mut socket;
  let counter: arc<NetTestCounter> = new arc<NetTestCounter>{};
  future.RegisterContinuation(
    lambda[copy driver_pointer, copy socket_pointer, copy counter]() -> void {
      unsafe {
        AssertTrueMsg((*driver_pointer).Poll(0).IsOk(), "n3_transport_selftest.ny:222");
        AssertTrueMsg(
          (*socket_pointer).WhenReadable(*driver_pointer, NetOperationOptions.TestDefault()).IsOk(),
          "n3_transport_selftest.ny:223"
        );
        (*driver_pointer).Close();
      }

      var state: arc<NetTestCounter> = counter;
      state.hits = state.hits + 1;
    }
  );
  token.Cancel();
  AssertTrueMsg(driver.Poll(0).IsOk(), "n3_transport_selftest.ny:228");
  AssertEqI32Msg(counter.hits, 1, "n3_transport_selftest.ny:228");
  AssertEqI32Msg(driver.PendingCount(), 0, "n3_transport_selftest.ny:229");
}

// nyra-lint-allow: prefer-type-owned-functions -- Return tests final socket/driver descriptor release.
func net_test_resource_round() -> void {
  var driver: NetEventLoop = NetEventLoop.TestNew(4);
  var pair: NetTestSocketPair = NetTestSocketPair.New(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  let pending: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(server.ReadAsync(driver, 16,
    NetOperationOptions.TestDefault()));
  driver.Close();
  AssertTrueMsg(pending.is_completed, "n3_transport_selftest.ny:237");
  AssertTrueMsg(client.Close().IsOk(), "n3_transport_selftest.ny:238");
  AssertTrueMsg(client.Close().IsOk(), "n3_transport_selftest.ny:238");
}

@test(tag = "net_core_n3")
func test_net_core_n3_descriptor_recovery() {
  net_test_resource_round();
  let baseline: int32 = net_core_test_fd_count();
  AssertTrueMsg(baseline >= 0, "n3_transport_selftest.ny:243");
  var i: int32 = 0;
  while i < 64 {
    net_test_resource_round();
    i = i + 1;
  }

  NetTestDescriptorBaseline{expected: baseline}.Wait();
}

@test(tag = "net_core_n3")
func test_net_core_n3_queued_transfer_retains_closed_socket() {
  var driver: NetEventLoop = NetEventLoop.TestNew(4);
  var pair: NetTestSocketPair = NetTestSocketPair.New(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  let write: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(client.WriteAllAsync(
    driver,
    NetBuffer.TestFromString("retained"),
    NetOperationOptions.TestDefault()
  ));
  let read: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(server.ReadExactlyAsync(driver, 8,
    NetOperationOptions.TestDefault()));
  AssertTrueMsg(client.Close().IsOk(), "close original sender");
  AssertTrueMsg(server.Close().IsOk(), "close original receiver");
  AssertTrueMsg((driver).TestTransfer(write).error == nil, "retained sender remains usable");
  let result: NetTransfer = (driver).TestTransfer(read);
  AssertTrueMsg(result.error == nil, "retained receiver remains usable");
  AssertEqStringMsg(
    (result.buffer).TestText(),
    "retained",
    "retained payload remains initialized"
  );
}

// nyra-lint-allow: prefer-type-owned-functions -- Return drops the write Future without cancellation.
func net_test_discard_write(driver: ref mut NetEventLoop, client: ref mut TcpConnection) -> void {
  let queued: Result<AsyncFuture<NetTransfer>, NetError> = client.WriteAllAsync(
    driver,
    NetBuffer.TestFromString("owned"),
    NetOperationOptions.TestDefault()
  );
  AssertTrueMsg(queued.IsOk(), "queue a write whose Future will be dropped");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dropped_transfer_future_does_not_cancel() {
  var driver: NetEventLoop = NetEventLoop.TestNew(4);
  var pair: NetTestSocketPair = NetTestSocketPair.New(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  net_test_discard_write(driver, client);
  let read: AsyncFuture<NetTransfer> = AsyncFuture<NetTransfer>.TestAdmit(server.ReadExactlyAsync(driver, 5,
    NetOperationOptions.TestDefault()));
  let result: NetTransfer = (driver).TestTransfer(read);
  AssertTrueMsg(result.error == nil, "Future drop must not cancel accepted output");
  AssertEqStringMsg(
    (result.buffer).TestText(),
    "owned",
    "driver retains payload after Future drop"
  );
  AssertEqI32Msg(driver.PendingCount(), 0, "both operations retire");
}

// nyra-lint-allow: prefer-type-owned-functions -- Function-return scope exercises final token/wake descriptor release.
func net_test_token_resource_round() -> void {
  var driver: NetEventLoop = NetEventLoop.TestNew(2);
  var socket: UdpSocket = UdpSocket.TestBind();
  let token: NetCancellation = (NetCancellation.NewWakeable().get_if<NetCancellation>()) as NetCancellation;
  let future: AsyncFuture<Result<Unit, NetError>> = AsyncFuture<Result<Unit, NetError>>.TestAdmit(socket.WhenReadable(
    driver,
    NetOperationOptions{cancellation: token}
  ));
  token.Cancel();
  (driver).TestPump(future);
  AssertTrueMsg((future).TestError() == NetErrorKind.Cancelled, "retire token registration");
}

@test(tag = "net_core_n3")
func test_net_core_n3_wake_token_descriptor_recovery() {
  let baseline: int32 = net_core_test_fd_count();
  var i: int32 = 0;
  while i < 64 {
    net_test_token_resource_round();
    i = i + 1;
  }

  NetTestDescriptorBaseline{expected: baseline}.Wait();
}

@test(tag = "net_core_n3")
func test_net_core_n3_failed_connect_retires_descriptor() {
  let baseline: int32 = net_core_test_fd_count();
  var driver: NetEventLoop = NetEventLoop.TestNew(2);
  // Remote port zero cannot name an OS-assigned listener,
  // so this failure fixture never races another process acquiring a free port.
  let endpoint: NetEndpoint = (NetEndpoint.Parse("127.0.0.1:0").get_if<NetEndpoint>()) as NetEndpoint;
  var queued: Result<TcpConnectionTask, NetError> = TcpConnection.DialAsync(
    driver,
    endpoint,
    NetOperationOptions.TestDefault()
  );
  AssertTrueMsg(queued.IsOk(), "admit the OS-rejected connection attempt");
  var task: TcpConnectionTask = move((queued.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let future: AsyncFuture<Result<Unit, NetError>> = (task).TestFuture();
  (driver).TestPump(future);
  let expected: NetErrorKind = (NetNativeError{kind: net_core_test_failed_connect_kind()}).AsProduct().kind;
  AssertTrueMsg(
    (future).TestError() == expected,
    "preserve the platform's remote port-zero error"
  );
  let take: Result<TcpConnection, NetError> = task.TakeConnection();
  AssertTrueMsg(take.IsErr(), "failed task never exposes a socket owner");
  AssertTrueMsg(
    ((take.get_if<NetError>()) as NetError).kind == expected,
    "TakeConnection preserves the failure"
  );
  AssertEqI32Msg(driver.PendingCount(), 0, "failed connect registration retired");
  NetTestDescriptorBaseline{expected: baseline}.Wait();
}

@extern("C") func net_core_test_wait_large_snapshot() -> int32;

@test(tag = "net_core_n3")
func test_net_core_n3_large_native_snapshot_fanout() {
  AssertEqI32Msg(
    net_core_test_wait_large_snapshot(),
    0,
    "144 distinct read interests preserve readiness and cancellation fanout"
  );
}
