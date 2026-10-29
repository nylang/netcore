// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

part of NetContractTests;

/** @brief Local transport controls, ownership, queue budgets and reentrant completion. */

@test(tag = "net_core_n3")
func test_net_core_n3_native_direction_and_closed_driver() {
  NetTestAssertI32(net_core_test_native_direction(), 0, "n3_transport_selftest.ny:6");
  NetTestAssertI32(
    net_core_test_empty_udp_readiness(),
    1,
    "native empty UDP must remain readable and receivable"
  );
  var driver: NetEventLoop = NetTestLoop(2);
  NetTestAssertI32((driver.Poll(0).get_if<int32>()) as int32, 0, "n3_transport_selftest.ny:8");
  NetTestAssertTrue(driver.Poll(-2).IsErr(), "n3_transport_selftest.ny:9");
  driver.Close();
  NetTestAssertTrue(driver.Poll(0).IsErr(), "n3_transport_selftest.ny:11");
}

@test(tag = "net_core_n3")
func test_net_core_n3_tcp_partial_exact_eof() {
  var driver: NetEventLoop = NetTestLoop(4);
  var pair: NetTestSocketPair = NetTestPair(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  let options: NetOperationOptions = NetTestOptions();
  let read: AsyncFuture<NetTransfer> = NetTestIo(server.ReadExactlyAsync(driver, 8, options));
  let write: AsyncFuture<NetTransfer> = NetTestIo(client.WriteAllAsync(
    driver,
    NetTestBuffer("abc"),
    options
  ));
  NetTestAssertTrue(NetTestTransfer(driver, write).error == nil, "n3_transport_selftest.ny:22");
  NetTestAssertTrue(client.ShutdownWrite().IsOk(), "n3_transport_selftest.ny:23");
  let result: NetTransfer = NetTestTransfer(driver, read);
  NetTestAssertTrue(result.eof, "n3_transport_selftest.ny:25");
  NetTestAssertTrue(result.error != nil, "n3_transport_selftest.ny:25");
  NetTestAssertTrue(
    (result.error as NetError).kind == NetErrorKind.UnexpectedEof,
    "n3_transport_selftest.ny:26"
  );
  NetTestAssertI64(result.bytes_transferred as int64, 3i64, "n3_transport_selftest.ny:27");
  NetTestAssertString(NetTestBufferText(result.buffer), "abc", "n3_transport_selftest.ny:28");
}

func net_test_partial_read(close_driver: bool) -> void {
  var driver: NetEventLoop = NetTestLoop(4);
  var pair: NetTestSocketPair = NetTestPair(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  let token: NetCancellation = NetCancellation.New();
  let options: NetOperationOptions = NetOperationOptions{
    deadline: NetTestOptions().deadline,
    cancellation: token
  };
  let read: AsyncFuture<NetTransfer> = NetTestIo(server.ReadExactlyAsync(driver, 8, options));
  let write: AsyncFuture<NetTransfer> = NetTestIo(client.WriteAllAsync(
    driver,
    NetTestBuffer("abc"),
    options
  ));
  NetTestAssertTrue(NetTestTransfer(driver, write).error == nil, "n3_transport_selftest.ny:39");
  var attempts: int32 = 0;
  while driver.pending.Len() == 1 && driver.pending.Get(0).progress <(3 as intptr) && attempts < 1000 {
    NetTestAssertTrue(driver.Poll(5).IsOk(), "pump partial read before cancellation/Close");
    attempts = attempts + 1;
  }

  NetTestAssertTrue(
    driver.pending.Len() == 1 && driver.pending.Get(0).progress == (3 as intptr),
    "partial prefix must reach the receiving operation"
  );
  NetTestAssertTrue(!read.is_completed, "n3_transport_selftest.ny:41");
  if close_driver {
    driver.Close();
  } else {
    token.Cancel();
    NetTestAssertTrue(driver.Poll(0).IsOk(), "n3_transport_selftest.ny:42");
  }

  let result: NetTransfer = NetTestTransfer(driver, read);
  NetTestAssertTrue(result.error != nil, "n3_transport_selftest.ny:44");
  var expected: NetErrorKind = NetErrorKind.Cancelled;
  if close_driver {
    expected = NetErrorKind.Closed;
  }

  NetTestAssertTrue((result.error as NetError).kind == expected, "n3_transport_selftest.ny:47");
  NetTestAssertI64(result.bytes_transferred as int64, 3i64, "n3_transport_selftest.ny:48");
  NetTestAssertString(NetTestBufferText(result.buffer), "abc", "n3_transport_selftest.ny:49");
  NetTestAssertI64(driver.RetainedBytes() as int64, 0i64, "n3_transport_selftest.ny:50");
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
  var driver: NetEventLoop = NetTestLoop(4);
  var pair: NetTestSocketPair = NetTestPair(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  let options: NetOperationOptions = NetTestOptions();
  let zero: AsyncFuture<NetTransfer> = NetTestIo(server.ReadAsync(driver, 0, options));
  let result: NetTransfer = NetTestTransfer(driver, zero);
  NetTestAssertTrue(!result.eof, "n3_transport_selftest.ny:65");
  NetTestAssertTrue(result.error == nil, "n3_transport_selftest.ny:65");
  NetTestAssertI64(result.bytes_transferred as int64, 0i64, "n3_transport_selftest.ny:66");
  let empty: AsyncFuture<NetTransfer> = NetTestIo(client.WriteAllAsync(driver, NetBuffer{}, options));
  NetTestAssertTrue(NetTestTransfer(driver, empty).error == nil, "n3_transport_selftest.ny:68");
  let pending: AsyncFuture<NetTransfer> = NetTestIo(server.ReadAsync(driver, 1, options));
  let overlap: Result<AsyncFuture<NetTransfer>, NetError> = server.ReadAsync(driver, 1, options);
  NetTestAssertTrue(overlap.IsErr(), "n3_transport_selftest.ny:71");
  NetTestAssertTrue(
    ((overlap.get_if<NetError>()) as NetError).kind == NetErrorKind.WouldBlock,
    "n3_transport_selftest.ny:72"
  );
  driver.Close();
  NetTestAssertTrue(
    (NetTestTransfer(driver, pending).error as NetError).kind == NetErrorKind.Closed,
    "n3_transport_selftest.ny:74"
  );
}

@test(tag = "net_core_n3")
func test_net_core_n3_sliced_root_budget_and_compaction() {
  var made: Result<NetEventLoop, NetError> = NetEventLoop.NewWithLimits(4, 4 as intptr);
  var driver: NetEventLoop = move((made.get_if<NetEventLoop>()) as NetEventLoop);
  var pair: NetTestSocketPair = NetTestPair(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  let root: NetBuffer = NetTestBuffer("abcdefgh");
  let slice_result: Result<NetBuffer, NetError> = root.Slice(2 as intptr, 2 as intptr);
  let slice: NetBuffer = (slice_result.get_if<NetBuffer>()) as NetBuffer;
  NetTestAssertI64(slice.RetainedBytes() as int64, 8i64, "n3_transport_selftest.ny:86");
  let rejected: Result<AsyncFuture<NetTransfer>, NetError> = client.WriteAllAsync(
    driver,
    slice,
    NetTestOptions()
  );
  NetTestAssertTrue(rejected.IsErr(), "n3_transport_selftest.ny:88");
  NetTestAssertI32(driver.PendingCount(), 0, "n3_transport_selftest.ny:88");
  let copied: Result<NetBuffer, NetError> = NetBuffer.CopyFrom(slice.Bytes());
  let compact: NetBuffer = (copied.get_if<NetBuffer>()) as NetBuffer;
  NetTestAssertI64(compact.RetainedBytes() as int64, 2i64, "n3_transport_selftest.ny:91");
  let sent: AsyncFuture<NetTransfer> = NetTestIo(client.WriteAllAsync(driver, compact, NetTestOptions()));
  NetTestAssertI64(driver.RetainedBytes() as int64, 2i64, "n3_transport_selftest.ny:93");
  NetTestAssertTrue(NetTestTransfer(driver, sent).error == nil, "n3_transport_selftest.ny:94");
  NetTestAssertI64(driver.RetainedBytes() as int64, 0i64, "n3_transport_selftest.ny:95");
}

@test(tag = "net_core_n3")
func test_net_core_n3_udp_empty_and_truncation() {
  var driver: NetEventLoop = NetTestLoop(4);
  var sender: UdpSocket = NetTestUdp();
  var receiver: UdpSocket = NetTestUdp();
  let endpoint_result: Result<NetEndpoint, NetError> = receiver.LocalEndpoint();
  let endpoint: NetEndpoint = (endpoint_result.get_if<NetEndpoint>()) as NetEndpoint;
  let options: NetOperationOptions = NetTestOptions();
  let empty_read: AsyncFuture<NetTransfer> = NetTestIo(receiver.ReceiveFromAsync(driver, 0, options));
  let empty_send: AsyncFuture<NetTransfer> = NetTestIo(sender.SendToAsync(
    driver,
    endpoint,
    NetBuffer{},
    options
  ));
  NetTestAssertTrue(NetTestTransfer(driver, empty_send).error == nil, "n3_transport_selftest.ny:107");
  let empty: NetTransfer = NetTestTransfer(driver, empty_read);
  NetTestAssertTrue(empty.error == nil, "n3_transport_selftest.ny:109");
  NetTestAssertTrue(empty.sender != nil, "n3_transport_selftest.ny:109");
  NetTestAssertTrue(!empty.eof, "n3_transport_selftest.ny:109");
  NetTestAssertI64(empty.bytes_transferred as int64, 0i64, "n3_transport_selftest.ny:110");
  let short_read: AsyncFuture<NetTransfer> = NetTestIo(receiver.ReceiveFromAsync(driver, 2, options));
  let long_send: AsyncFuture<NetTransfer> = NetTestIo(sender.SendToAsync(
    driver,
    endpoint,
    NetTestBuffer("abcdef"),
    options
  ));
  NetTestAssertTrue(NetTestTransfer(driver, long_send).error == nil, "n3_transport_selftest.ny:113");
  let truncated: NetTransfer = NetTestTransfer(driver, short_read);
  NetTestAssertTrue(truncated.error != nil, "n3_transport_selftest.ny:115");
  NetTestAssertTrue(
    (truncated.error as NetError).kind == NetErrorKind.MessageTooLarge,
    "n3_transport_selftest.ny:115"
  );
  NetTestAssertI64(truncated.buffer.Len() as int64, 0i64, "n3_transport_selftest.ny:116");
  NetTestAssertTrue(truncated.sender == nil, "n3_transport_selftest.ny:116");
  let token: NetCancellation = NetCancellation.New();
  let pending: AsyncFuture<NetTransfer> = NetTestIo(receiver.ReceiveFromAsync(
    driver,
    2,
    NetOperationOptions{cancellation: token}
  ));
  NetTestAssertTrue(driver.Poll(0).IsOk(), "n3_transport_selftest.ny:119");
  NetTestAssertTrue(!pending.is_completed, "n3_transport_selftest.ny:119");
  token.Cancel();
  NetTestAssertTrue(
    (NetTestTransfer(driver, pending).error as NetError).kind == NetErrorKind.Cancelled,
    "n3_transport_selftest.ny:121"
  );
}

@test(tag = "net_core_n3")
func test_net_core_n3_udp_zero_capacity_does_not_write_caller() {
  var sender: UdpSocket = NetTestUdp();
  var receiver: UdpSocket = NetTestUdp();
  var sentinel: uint8 = 77u8;
  let view_result: Result<NetMutableBytes, NetError> = NetMutableBytes.FromRaw(&mut sentinel, 0 as intptr);
  var view: NetMutableBytes = (view_result.get_if<NetMutableBytes>()) as NetMutableBytes;
  let none: Result<NetDatagram, NetError> = receiver.TryReceiveFrom(view);
  NetTestAssertTrue(none.IsErr(), "zero-capacity receive must wait for a datagram");
  NetTestAssertTrue(
    ((none.get_if<NetError>()) as NetError).kind == NetErrorKind.WouldBlock,
    "empty socket is WouldBlock"
  );
  let endpoint: NetEndpoint = (receiver.LocalEndpoint().get_if<NetEndpoint>()) as NetEndpoint;
  NetTestAssertTrue(
    sender.SendTo(endpoint, NetBytes.FromString("z"), NetTestOptions()).IsOk(),
    "send one byte"
  );
  let received: Result<NetDatagram, NetError> = receiver.ReceiveFrom(view, NetTestOptions());
  NetTestAssertTrue(received.IsErr(), "nonempty datagram must not fit zero capacity");
  NetTestAssertTrue(
    ((received.get_if<NetError>()) as NetError).kind == NetErrorKind.MessageTooLarge,
    "nonempty datagram is discarded"
  );
  NetTestAssertI32(sentinel as int32, 77, "zero capacity must never write the caller pointer");
  let consumed: Result<NetDatagram, NetError> = receiver.TryReceiveFrom(view);
  NetTestAssertTrue(consumed.IsErr(), "the oversized datagram was consumed");
  NetTestAssertTrue(
    ((consumed.get_if<NetError>()) as NetError).kind == NetErrorKind.WouldBlock,
    "no discarded prefix remains"
  );
}

@test(tag = "net_core_n3")
func test_net_core_n3_wakeable_cancel_fanout() {
  var driver: NetEventLoop = NetTestLoop(4);
  var first: UdpSocket = NetTestUdp();
  var second: UdpSocket = NetTestUdp();
  let made: Result<NetCancellation, NetError> = NetCancellation.NewWakeable();
  let token: NetCancellation = (made.get_if<NetCancellation>()) as NetCancellation;
  NetTestAssertTrue(token.CanWakeWaiters(), "macOS token must use an active wake channel");
  let options: NetOperationOptions = NetOperationOptions{
    deadline: NetTestOptions().deadline,
    cancellation: token
  };
  let a: AsyncFuture<Result<Unit, NetError>> = NetTestReady(first.WhenReadable(driver, options));
  let b: AsyncFuture<Result<Unit, NetError>> = NetTestReady(second.WhenReadable(driver, options));
  let thread: Result<Thread, ThreadError> = Thread.Spawn(
    lambda[copy token]() -> void {
      Thread.Sleep(30u32);
      token.Cancel();
    }
  );
  NetTestAssertTrue(thread.IsOk(), "n3_transport_selftest.ny:134");
  let start: uint64 = NetClock.NowNanoseconds();
  NetTestAssertTrue(driver.Poll(-1).IsOk(), "n3_transport_selftest.ny:135");
  NetTestAssertTrue(
    NetClock.NowNanoseconds() - start < 2500000000u64,
    "wake must arrive before the fallback deadline"
  );
  NetTestAssertTrue(a.is_completed, "n3_transport_selftest.ny:136");
  NetTestAssertTrue(b.is_completed, "n3_transport_selftest.ny:136");
  NetTestAssertTrue(NetTestReadyError(a) == NetErrorKind.Cancelled, "n3_transport_selftest.ny:137");
  NetTestAssertTrue(NetTestReadyError(b) == NetErrorKind.Cancelled, "n3_transport_selftest.ny:138");
  let late: AsyncFuture<Result<Unit, NetError>> = NetTestReady(first.WhenReadable(driver, options));
  NetTestAssertTrue(late.is_completed, "n3_transport_selftest.ny:140");
  NetTestAssertTrue(NetTestReadyError(late) == NetErrorKind.Cancelled, "n3_transport_selftest.ny:140");
  NetTestAssertI32(driver.PendingCount(), 0, "n3_transport_selftest.ny:141");
}

@test(tag = "net_core_n3")
func test_net_core_n3_readiness_deadline() {
  var driver: NetEventLoop = NetTestLoop(2);
  var socket: UdpSocket = NetTestUdp();
  let options: NetOperationOptions = NetOperationOptions{deadline: NetDeadline.After(
    NetClock.NowNanoseconds(),
    20000000u64
  )};
  let ready: AsyncFuture<Result<Unit, NetError>> = NetTestReady(socket.WhenReadable(driver, options));
  NetTestPump(driver, ready);
  NetTestAssertTrue(NetTestReadyError(ready) == NetErrorKind.TimedOut, "n3_transport_selftest.ny:151");
}

func net_test_abandoned_accept(
  driver: ref mut NetEventLoop,
  listener: ref mut TcpListener,
  cancel: bool
) -> AsyncFuture<Result<Unit, NetError>> {
  var queued: Result<TcpConnectionTask, NetError> = listener.AcceptAsync(driver, NetTestOptions());
  var task: TcpConnectionTask = move((queued.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let future: AsyncFuture<Result<Unit, NetError>> = NetTestTaskFuture(task);
  if cancel {
    NetTestAssertTrue(task.Cancel(), "n3_transport_selftest.ny:158");
  }

  return future;
}

@test(tag = "net_core_n3")
func test_net_core_n3_abandon_and_cancelled_drop() {
  var driver: NetEventLoop = NetTestLoop(2);
  var listener: TcpListener = NetTestListener();
  let dropped: AsyncFuture<Result<Unit, NetError>> = net_test_abandoned_accept(driver, listener, false);
  NetTestPump(driver, dropped);
  NetTestAssertTrue(NetTestReadyError(dropped) == NetErrorKind.Closed, "n3_transport_selftest.ny:166");
  let cancelled: AsyncFuture<Result<Unit, NetError>> = net_test_abandoned_accept(driver, listener, true);
  NetTestPump(driver, cancelled);
  NetTestAssertTrue(
    NetTestReadyError(cancelled) == NetErrorKind.Cancelled,
    "n3_transport_selftest.ny:168"
  );
}

@test(tag = "net_core_n3")
func test_net_core_n3_task_move_cancel_timeout_order() {
  var driver: NetEventLoop = NetTestLoop(2);
  var listener: TcpListener = NetTestListener();
  let options: NetOperationOptions = NetOperationOptions{deadline: NetDeadline.After(
    NetClock.NowNanoseconds(),
    50000000u64
  )};
  var queued: Result<TcpConnectionTask, NetError> = listener.AcceptAsync(driver, options);
  var task: TcpConnectionTask = move((queued.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let future: AsyncFuture<Result<Unit, NetError>> = NetTestTaskFuture(task);
  var moved: TcpConnectionTask = move(task);
  NetTestAssertTrue(moved.Cancel(), "n3_transport_selftest.ny:180");
  Thread.Sleep(60u32);
  NetTestPump(driver, future);
  NetTestAssertTrue(
    NetTestReadyError(future) == NetErrorKind.Cancelled,
    "n3_transport_selftest.ny:183"
  );
}

struct NetTestCounter {
  hits: int32;
}

@test(tag = "net_core_n3")
func test_net_core_n3_close_callback_observes_terminal_tasks() {
  var driver: NetEventLoop = NetTestLoop(4);
  var first: TcpListener = NetTestListener();
  var second: TcpListener = NetTestListener();
  var qa: Result<TcpConnectionTask, NetError> = first.AcceptAsync(driver, NetTestOptions());
  var qb: Result<TcpConnectionTask, NetError> = second.AcceptAsync(driver, NetTestOptions());
  var a: TcpConnectionTask = move((qa.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  var b: TcpConnectionTask = move((qb.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let af: AsyncFuture<Result<Unit, NetError>> = NetTestTaskFuture(a);
  let bf: AsyncFuture<Result<Unit, NetError>> = NetTestTaskFuture(b);
  let pointer: *mut TcpConnectionTask = &mut b;
  let counter: arc<NetTestCounter> = new arc<NetTestCounter>{};
  af.RegisterContinuation(
    lambda[copy pointer, copy counter]() -> void {
      unsafe {
        NetTestAssertTrue(! (*pointer).Cancel(), "n3_transport_selftest.ny:201");
        let take: Result<TcpConnection, NetError> = (*pointer).TakeConnection();
        NetTestAssertTrue(take.IsErr(), "n3_transport_selftest.ny:203");
        NetTestAssertTrue(
          ((take.get_if<NetError>()) as NetError).kind == NetErrorKind.Closed,
          "n3_transport_selftest.ny:203"
        );
      }

      var state: arc<NetTestCounter> = counter;
      state.hits = state.hits + 1;
    }
  );
  driver.Close();
  NetTestAssertTrue(af.is_completed, "n3_transport_selftest.ny:208");
  NetTestAssertTrue(bf.is_completed, "n3_transport_selftest.ny:208");
  NetTestAssertI32(counter.hits, 1, "n3_transport_selftest.ny:208");
}

@test(tag = "net_core_n3")
func test_net_core_n3_poll_callback_reentry() {
  var driver: NetEventLoop = NetTestLoop(4);
  var socket: UdpSocket = NetTestUdp();
  let token: NetCancellation = NetCancellation.New();
  let future: AsyncFuture<Result<Unit, NetError>> = NetTestReady(socket.WhenReadable(
    driver,
    NetOperationOptions{cancellation: token}
  ));
  let driver_pointer: *mut NetEventLoop = &mut driver;
  let socket_pointer: *mut UdpSocket = &mut socket;
  let counter: arc<NetTestCounter> = new arc<NetTestCounter>{};
  future.RegisterContinuation(
    lambda[copy driver_pointer, copy socket_pointer, copy counter]() -> void {
      unsafe {
        NetTestAssertTrue((*driver_pointer).Poll(0).IsOk(), "n3_transport_selftest.ny:222");
        NetTestAssertTrue(
          (*socket_pointer).WhenReadable(*driver_pointer, NetTestOptions()).IsOk(),
          "n3_transport_selftest.ny:223"
        );
        (*driver_pointer).Close();
      }

      var state: arc<NetTestCounter> = counter;
      state.hits = state.hits + 1;
    }
  );
  token.Cancel();
  NetTestAssertTrue(driver.Poll(0).IsOk(), "n3_transport_selftest.ny:228");
  NetTestAssertI32(counter.hits, 1, "n3_transport_selftest.ny:228");
  NetTestAssertI32(driver.PendingCount(), 0, "n3_transport_selftest.ny:229");
}

func net_test_resource_round() -> void {
  var driver: NetEventLoop = NetTestLoop(4);
  var pair: NetTestSocketPair = NetTestPair(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  let pending: AsyncFuture<NetTransfer> = NetTestIo(server.ReadAsync(driver, 16, NetTestOptions()));
  driver.Close();
  NetTestAssertTrue(pending.is_completed, "n3_transport_selftest.ny:237");
  NetTestAssertTrue(client.Close().IsOk(), "n3_transport_selftest.ny:238");
  NetTestAssertTrue(client.Close().IsOk(), "n3_transport_selftest.ny:238");
}

@test(tag = "net_core_n3")
func test_net_core_n3_descriptor_recovery() {
  net_test_resource_round();
  let baseline: int32 = net_core_test_fd_count();
  NetTestAssertTrue(baseline >= 0, "n3_transport_selftest.ny:243");
  var i: int32 = 0;
  while i < 64 {
    net_test_resource_round();
    i = i + 1;
  }

  NetTestFdBaseline(baseline);
}

@test(tag = "net_core_n3")
func test_net_core_n3_queued_transfer_retains_closed_socket() {
  var driver: NetEventLoop = NetTestLoop(4);
  var pair: NetTestSocketPair = NetTestPair(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  let write: AsyncFuture<NetTransfer> = NetTestIo(client.WriteAllAsync(
    driver,
    NetTestBuffer("retained"),
    NetTestOptions()
  ));
  let read: AsyncFuture<NetTransfer> = NetTestIo(server.ReadExactlyAsync(driver, 8, NetTestOptions()));
  NetTestAssertTrue(client.Close().IsOk(), "close original sender");
  NetTestAssertTrue(server.Close().IsOk(), "close original receiver");
  NetTestAssertTrue(NetTestTransfer(driver, write).error == nil, "retained sender remains usable");
  let result: NetTransfer = NetTestTransfer(driver, read);
  NetTestAssertTrue(result.error == nil, "retained receiver remains usable");
  NetTestAssertString(
    NetTestBufferText(result.buffer),
    "retained",
    "retained payload remains initialized"
  );
}

func net_test_discard_write(driver: ref mut NetEventLoop, client: ref mut TcpConnection) -> void {
  let queued: Result<AsyncFuture<NetTransfer>, NetError> = client.WriteAllAsync(
    driver,
    NetTestBuffer("owned"),
    NetTestOptions()
  );
  NetTestAssertTrue(queued.IsOk(), "queue a write whose Future will be dropped");
}

@test(tag = "net_core_n3")
func test_net_core_n3_dropped_transfer_future_does_not_cancel() {
  var driver: NetEventLoop = NetTestLoop(4);
  var pair: NetTestSocketPair = NetTestPair(driver);
  var client: TcpConnection = move(pair.client);
  var server: TcpConnection = move(pair.server);
  net_test_discard_write(driver, client);
  let read: AsyncFuture<NetTransfer> = NetTestIo(server.ReadExactlyAsync(driver, 5, NetTestOptions()));
  let result: NetTransfer = NetTestTransfer(driver, read);
  NetTestAssertTrue(result.error == nil, "Future drop must not cancel accepted output");
  NetTestAssertString(
    NetTestBufferText(result.buffer),
    "owned",
    "driver retains payload after Future drop"
  );
  NetTestAssertI32(driver.PendingCount(), 0, "both operations retire");
}

func net_test_token_resource_round() -> void {
  var driver: NetEventLoop = NetTestLoop(2);
  var socket: UdpSocket = NetTestUdp();
  let token: NetCancellation = (NetCancellation.NewWakeable().get_if<NetCancellation>()) as NetCancellation;
  let future: AsyncFuture<Result<Unit, NetError>> = NetTestReady(socket.WhenReadable(
    driver,
    NetOperationOptions{cancellation: token}
  ));
  token.Cancel();
  NetTestPump(driver, future);
  NetTestAssertTrue(NetTestReadyError(future) == NetErrorKind.Cancelled, "retire token registration");
}

@test(tag = "net_core_n3")
func test_net_core_n3_wake_token_descriptor_recovery() {
  let baseline: int32 = net_core_test_fd_count();
  var i: int32 = 0;
  while i < 64 {
    net_test_token_resource_round();
    i = i + 1;
  }

  NetTestFdBaseline(baseline);
}

@test(tag = "net_core_n3")
func test_net_core_n3_failed_connect_retires_descriptor() {
  let baseline: int32 = net_core_test_fd_count();
  var driver: NetEventLoop = NetTestLoop(2);
  // Remote port zero cannot name an OS-assigned listener,
  // so this failure fixture never races another process acquiring a free port.
  let endpoint: NetEndpoint = (NetEndpoint.Parse("127.0.0.1:0").get_if<NetEndpoint>()) as NetEndpoint;
  var queued: Result<TcpConnectionTask, NetError> = TcpConnection.DialAsync(
    driver,
    endpoint,
    NetTestOptions()
  );
  NetTestAssertTrue(queued.IsOk(), "admit the OS-rejected connection attempt");
  var task: TcpConnectionTask = move((queued.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let future: AsyncFuture<Result<Unit, NetError>> = NetTestTaskFuture(task);
  NetTestPump(driver, future);
  let expected: NetErrorKind = NetMapNativeError(
    NetNativeError{kind: net_core_test_failed_connect_kind()}
  ).kind;
  NetTestAssertTrue(
    NetTestReadyError(future) == expected,
    "preserve the platform's remote port-zero error"
  );
  let take: Result<TcpConnection, NetError> = task.TakeConnection();
  NetTestAssertTrue(take.IsErr(), "failed task never exposes a socket owner");
  NetTestAssertTrue(
    ((take.get_if<NetError>()) as NetError).kind == expected,
    "TakeConnection preserves the failure"
  );
  NetTestAssertI32(driver.PendingCount(), 0, "failed connect registration retired");
  NetTestFdBaseline(baseline);
}

@extern("C") func net_core_test_wait_large_snapshot() -> int32;

@test(tag = "net_core_n3")
func test_net_core_n3_large_native_snapshot_fanout() {
  NetTestAssertI32(
    net_core_test_wait_large_snapshot(),
    0,
    "144 distinct read interests preserve readiness and cancellation fanout"
  );
}
