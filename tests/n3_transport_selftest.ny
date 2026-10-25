/** @brief Local transport controls, ownership, queue budgets and reentrant completion. */
part of NetTransport;

@test(tag = "net_core_n3")
func test_net_core_n3_native_direction_and_closed_driver() {
  AssertEqI32Msg(net_core_test_native_direction(), 0, "n3_transport_selftest.ny:6");
  AssertEqI32Msg(net_core_test_empty_udp_readiness(), 1, "native empty UDP must remain readable and receivable");
  var driver: NetEventLoop = net_test_loop(2);
  AssertEqI32Msg((driver.Poll(0).get_if<int32>()) as int32, 0, "n3_transport_selftest.ny:8");
  AssertTrueMsg(driver.Poll(-2).IsErr(), "n3_transport_selftest.ny:9");
  driver.Close();
  AssertTrueMsg(driver.Poll(0).IsErr(), "n3_transport_selftest.ny:11");
}

@test(tag = "net_core_n3")
func test_net_core_n3_tcp_partial_exact_eof() {
  var driver: NetEventLoop = net_test_loop(4);
  var client: TcpConnection = TcpConnection{}; var server: TcpConnection = TcpConnection{};
  net_test_pair(driver, client, server);
  let options: NetOperationOptions = net_test_options();
  let read: AsyncFuture<NetTransfer> = net_test_io(server.ReadExactlyAsync(driver, 8, options));
  let write: AsyncFuture<NetTransfer> = net_test_io(client.WriteAllAsync(driver, net_test_buffer("abc"), options));
  AssertTrueMsg(net_test_transfer(driver, write).error == nil, "n3_transport_selftest.ny:22");
  AssertTrueMsg(client.ShutdownWrite().IsOk(), "n3_transport_selftest.ny:23");
  let result: NetTransfer = net_test_transfer(driver, read);
  AssertTrueMsg(result.eof, "n3_transport_selftest.ny:25"); AssertTrueMsg(result.error != nil, "n3_transport_selftest.ny:25");
  AssertTrueMsg((result.error as NetError).kind == NetErrorKind.UnexpectedEof, "n3_transport_selftest.ny:26");
  AssertEqI64Msg(result.bytes_transferred as int64, 3i64, "n3_transport_selftest.ny:27");
  AssertEqStringMsg(net_test_buffer_text(result.buffer), "abc", "n3_transport_selftest.ny:28");
}

func net_test_partial_read(close_driver: bool) -> void {
  var driver: NetEventLoop = net_test_loop(4);
  var client: TcpConnection = TcpConnection{}; var server: TcpConnection = TcpConnection{};
  net_test_pair(driver, client, server);
  let token: NetCancellation = NetCancellation.New();
  let options: NetOperationOptions = NetOperationOptions{deadline: net_test_options().deadline, cancellation: token};
  let read: AsyncFuture<NetTransfer> = net_test_io(server.ReadExactlyAsync(driver, 8, options));
  let write: AsyncFuture<NetTransfer> = net_test_io(client.WriteAllAsync(driver, net_test_buffer("abc"), options));
  AssertTrueMsg(net_test_transfer(driver, write).error == nil, "n3_transport_selftest.ny:39");
  var attempts: int32 = 0;
  while driver.pending.Len() == 1 && driver.pending.Get(0).progress < (3 as intptr) && attempts < 1000 {
    AssertTrueMsg(driver.Poll(5).IsOk(), "pump partial read before cancellation/Close");
    attempts = attempts + 1;
  }
  AssertTrueMsg(driver.pending.Len() == 1 && driver.pending.Get(0).progress == (3 as intptr), "partial prefix must reach the receiving operation");
  AssertTrueMsg(!read.is_completed, "n3_transport_selftest.ny:41");
  if close_driver { driver.Close(); } else { token.Cancel(); AssertTrueMsg(driver.Poll(0).IsOk(), "n3_transport_selftest.ny:42"); }
  let result: NetTransfer = net_test_transfer(driver, read);
  AssertTrueMsg(result.error != nil, "n3_transport_selftest.ny:44");
  var expected: NetErrorKind = NetErrorKind.Cancelled;
  if close_driver { expected = NetErrorKind.Closed; }
  AssertTrueMsg((result.error as NetError).kind == expected, "n3_transport_selftest.ny:47");
  AssertEqI64Msg(result.bytes_transferred as int64, 3i64, "n3_transport_selftest.ny:48");
  AssertEqStringMsg(net_test_buffer_text(result.buffer), "abc", "n3_transport_selftest.ny:49");
  AssertEqI64Msg(driver.RetainedBytes() as int64, 0i64, "n3_transport_selftest.ny:50");
}
@test(tag = "net_core_n3")
func test_net_core_n3_tcp_cancel_preserves_progress() { net_test_partial_read(false); }
@test(tag = "net_core_n3")
func test_net_core_n3_tcp_close_preserves_progress() { net_test_partial_read(true); }

@test(tag = "net_core_n3")
func test_net_core_n3_zero_tcp_and_read_overlap() {
  var driver: NetEventLoop = net_test_loop(4);
  var client: TcpConnection = TcpConnection{}; var server: TcpConnection = TcpConnection{};
  net_test_pair(driver, client, server);
  let options: NetOperationOptions = net_test_options();
  let zero: AsyncFuture<NetTransfer> = net_test_io(server.ReadAsync(driver, 0, options));
  let result: NetTransfer = net_test_transfer(driver, zero);
  AssertTrueMsg(!result.eof, "n3_transport_selftest.ny:65"); AssertTrueMsg(result.error == nil, "n3_transport_selftest.ny:65");
  AssertEqI64Msg(result.bytes_transferred as int64, 0i64, "n3_transport_selftest.ny:66");
  let empty: AsyncFuture<NetTransfer> = net_test_io(client.WriteAllAsync(driver, NetBuffer{}, options));
  AssertTrueMsg(net_test_transfer(driver, empty).error == nil, "n3_transport_selftest.ny:68");
  let pending: AsyncFuture<NetTransfer> = net_test_io(server.ReadAsync(driver, 1, options));
  let overlap: Result<AsyncFuture<NetTransfer>, NetError> = server.ReadAsync(driver, 1, options);
  AssertTrueMsg(overlap.IsErr(), "n3_transport_selftest.ny:71");
  AssertTrueMsg(((overlap.get_if<NetError>()) as NetError).kind == NetErrorKind.WouldBlock, "n3_transport_selftest.ny:72");
  driver.Close();
  AssertTrueMsg((net_test_transfer(driver, pending).error as NetError).kind == NetErrorKind.Closed, "n3_transport_selftest.ny:74");
}

@test(tag = "net_core_n3")
func test_net_core_n3_sliced_root_budget_and_compaction() {
  var made: Result<NetEventLoop, NetError> = NetEventLoop.NewWithLimits(4, 4 as intptr);
  var driver: NetEventLoop = move((made.get_if<NetEventLoop>()) as NetEventLoop);
  var client: TcpConnection = TcpConnection{}; var server: TcpConnection = TcpConnection{};
  net_test_pair(driver, client, server);
  let root: NetBuffer = net_test_buffer("abcdefgh");
  let slice_result: Result<NetBuffer, NetError> = root.Slice(2 as intptr, 2 as intptr);
  let slice: NetBuffer = (slice_result.get_if<NetBuffer>()) as NetBuffer;
  AssertEqI64Msg(slice.RetainedBytes() as int64, 8i64, "n3_transport_selftest.ny:86");
  let rejected: Result<AsyncFuture<NetTransfer>, NetError> = client.WriteAllAsync(driver, slice, net_test_options());
  AssertTrueMsg(rejected.IsErr(), "n3_transport_selftest.ny:88"); AssertEqI32Msg(driver.PendingCount(), 0, "n3_transport_selftest.ny:88");
  let copied: Result<NetBuffer, NetError> = NetBuffer.CopyFrom(slice.Bytes());
  let compact: NetBuffer = (copied.get_if<NetBuffer>()) as NetBuffer;
  AssertEqI64Msg(compact.RetainedBytes() as int64, 2i64, "n3_transport_selftest.ny:91");
  let sent: AsyncFuture<NetTransfer> = net_test_io(client.WriteAllAsync(driver, compact, net_test_options()));
  AssertEqI64Msg(driver.RetainedBytes() as int64, 2i64, "n3_transport_selftest.ny:93");
  AssertTrueMsg(net_test_transfer(driver, sent).error == nil, "n3_transport_selftest.ny:94");
  AssertEqI64Msg(driver.RetainedBytes() as int64, 0i64, "n3_transport_selftest.ny:95");
}

@test(tag = "net_core_n3")
func test_net_core_n3_udp_empty_and_truncation() {
  var driver: NetEventLoop = net_test_loop(4);
  var sender: UdpSocket = net_test_udp(); var receiver: UdpSocket = net_test_udp();
  let endpoint_result: Result<NetEndpoint, NetError> = receiver.LocalEndpoint();
  let endpoint: NetEndpoint = (endpoint_result.get_if<NetEndpoint>()) as NetEndpoint;
  let options: NetOperationOptions = net_test_options();
  let empty_read: AsyncFuture<NetTransfer> = net_test_io(receiver.ReceiveFromAsync(driver, 0, options));
  let empty_send: AsyncFuture<NetTransfer> = net_test_io(sender.SendToAsync(driver, endpoint, NetBuffer{}, options));
  AssertTrueMsg(net_test_transfer(driver, empty_send).error == nil, "n3_transport_selftest.ny:107");
  let empty: NetTransfer = net_test_transfer(driver, empty_read);
  AssertTrueMsg(empty.error == nil, "n3_transport_selftest.ny:109"); AssertTrueMsg(empty.sender != nil, "n3_transport_selftest.ny:109"); AssertTrueMsg(!empty.eof, "n3_transport_selftest.ny:109");
  AssertEqI64Msg(empty.bytes_transferred as int64, 0i64, "n3_transport_selftest.ny:110");
  let short_read: AsyncFuture<NetTransfer> = net_test_io(receiver.ReceiveFromAsync(driver, 2, options));
  let long_send: AsyncFuture<NetTransfer> = net_test_io(sender.SendToAsync(driver, endpoint, net_test_buffer("abcdef"), options));
  AssertTrueMsg(net_test_transfer(driver, long_send).error == nil, "n3_transport_selftest.ny:113");
  let truncated: NetTransfer = net_test_transfer(driver, short_read);
  AssertTrueMsg(truncated.error != nil, "n3_transport_selftest.ny:115"); AssertTrueMsg((truncated.error as NetError).kind == NetErrorKind.MessageTooLarge, "n3_transport_selftest.ny:115");
  AssertEqI64Msg(truncated.buffer.Len() as int64, 0i64, "n3_transport_selftest.ny:116"); AssertTrueMsg(truncated.sender == nil, "n3_transport_selftest.ny:116");
  let token: NetCancellation = NetCancellation.New();
  let pending: AsyncFuture<NetTransfer> = net_test_io(receiver.ReceiveFromAsync(driver, 2, NetOperationOptions{cancellation: token}));
  AssertTrueMsg(driver.Poll(0).IsOk(), "n3_transport_selftest.ny:119"); AssertTrueMsg(!pending.is_completed, "n3_transport_selftest.ny:119");
  token.Cancel();
  AssertTrueMsg((net_test_transfer(driver, pending).error as NetError).kind == NetErrorKind.Cancelled, "n3_transport_selftest.ny:121");
}

@test(tag = "net_core_n3")
func test_net_core_n3_udp_zero_capacity_does_not_write_caller() {
  var sender: UdpSocket = net_test_udp(); var receiver: UdpSocket = net_test_udp();
  var sentinel: uint8 = 77u8;
  let view_result: Result<NetMutableBytes, NetError> = NetMutableBytes.FromRaw(&mut sentinel, 0 as intptr);
  var view: NetMutableBytes = (view_result.get_if<NetMutableBytes>()) as NetMutableBytes;
  let none: Result<NetDatagram, NetError> = receiver.TryReceiveFrom(view);
  AssertTrueMsg(none.IsErr(), "zero-capacity receive must wait for a datagram");
  AssertTrueMsg(((none.get_if<NetError>()) as NetError).kind == NetErrorKind.WouldBlock, "empty socket is WouldBlock");
  let endpoint: NetEndpoint = (receiver.LocalEndpoint().get_if<NetEndpoint>()) as NetEndpoint;
  AssertTrueMsg(sender.SendTo(endpoint, NetBytes.FromString("z"), net_test_options()).IsOk(), "send one byte");
  let received: Result<NetDatagram, NetError> = receiver.ReceiveFrom(view, net_test_options());
  AssertTrueMsg(received.IsErr(), "nonempty datagram must not fit zero capacity");
  AssertTrueMsg(((received.get_if<NetError>()) as NetError).kind == NetErrorKind.MessageTooLarge, "nonempty datagram is discarded");
  AssertEqI32Msg(sentinel as int32, 77, "zero capacity must never write the caller pointer");
  let consumed: Result<NetDatagram, NetError> = receiver.TryReceiveFrom(view);
  AssertTrueMsg(consumed.IsErr(), "the oversized datagram was consumed");
  AssertTrueMsg(((consumed.get_if<NetError>()) as NetError).kind == NetErrorKind.WouldBlock, "no discarded prefix remains");
}

@test(tag = "net_core_n3")
func test_net_core_n3_wakeable_cancel_fanout() {
  var driver: NetEventLoop = net_test_loop(4);
  var first: UdpSocket = net_test_udp(); var second: UdpSocket = net_test_udp();
  let made: Result<NetCancellation, NetError> = NetCancellation.NewWakeable();
  let token: NetCancellation = (made.get_if<NetCancellation>()) as NetCancellation;
  AssertTrueMsg(token.CanWakeWaiters(), "macOS token must use an active wake channel");
  let options: NetOperationOptions = NetOperationOptions{deadline: net_test_options().deadline, cancellation: token};
  let a: AsyncFuture<Result<Unit, NetError>> = net_test_ready(first.WhenReadable(driver, options));
  let b: AsyncFuture<Result<Unit, NetError>> = net_test_ready(second.WhenReadable(driver, options));
  let thread: Result<Thread, ThreadError> = Thread.Spawn(lambda [copy token] () -> void { Thread.Sleep(30u32); token.Cancel(); });
  AssertTrueMsg(thread.IsOk(), "n3_transport_selftest.ny:134");
  let start: uint64 = NetClock.NowNanoseconds();
  AssertTrueMsg(driver.Poll(-1).IsOk(), "n3_transport_selftest.ny:135");
  AssertTrueMsg(NetClock.NowNanoseconds() - start < 2500000000u64, "wake must arrive before the fallback deadline");
  AssertTrueMsg(a.is_completed, "n3_transport_selftest.ny:136"); AssertTrueMsg(b.is_completed, "n3_transport_selftest.ny:136");
  AssertTrueMsg(net_test_ready_error(a) == NetErrorKind.Cancelled, "n3_transport_selftest.ny:137");
  AssertTrueMsg(net_test_ready_error(b) == NetErrorKind.Cancelled, "n3_transport_selftest.ny:138");
  let late: AsyncFuture<Result<Unit, NetError>> = net_test_ready(first.WhenReadable(driver, options));
  AssertTrueMsg(late.is_completed, "n3_transport_selftest.ny:140"); AssertTrueMsg(net_test_ready_error(late) == NetErrorKind.Cancelled, "n3_transport_selftest.ny:140");
  AssertEqI32Msg(driver.PendingCount(), 0, "n3_transport_selftest.ny:141");
}

@test(tag = "net_core_n3")
func test_net_core_n3_readiness_deadline() {
  var driver: NetEventLoop = net_test_loop(2);
  var socket: UdpSocket = net_test_udp();
  let options: NetOperationOptions = NetOperationOptions{deadline: NetDeadline.After(NetClock.NowNanoseconds(), 20000000u64)};
  let ready: AsyncFuture<Result<Unit, NetError>> = net_test_ready(socket.WhenReadable(driver, options));
  net_test_pump(driver, ready);
  AssertTrueMsg(net_test_ready_error(ready) == NetErrorKind.TimedOut, "n3_transport_selftest.ny:151");
}

func net_test_abandoned_accept(driver: ref mut NetEventLoop, listener: ref mut TcpListener, cancel: bool) -> AsyncFuture<Result<Unit, NetError>> {
  var queued: Result<TcpConnectionTask, NetError> = listener.AcceptAsync(driver, net_test_options());
  var task: TcpConnectionTask = move((queued.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let future: AsyncFuture<Result<Unit, NetError>> = net_test_task_future(task);
  if cancel { AssertTrueMsg(task.Cancel(), "n3_transport_selftest.ny:158"); }
  return future;
}
@test(tag = "net_core_n3")
func test_net_core_n3_abandon_and_cancelled_drop() {
  var driver: NetEventLoop = net_test_loop(2);
  var listener: TcpListener = net_test_listener();
  let dropped: AsyncFuture<Result<Unit, NetError>> = net_test_abandoned_accept(driver, listener, false);
  net_test_pump(driver, dropped); AssertTrueMsg(net_test_ready_error(dropped) == NetErrorKind.Closed, "n3_transport_selftest.ny:166");
  let cancelled: AsyncFuture<Result<Unit, NetError>> = net_test_abandoned_accept(driver, listener, true);
  net_test_pump(driver, cancelled); AssertTrueMsg(net_test_ready_error(cancelled) == NetErrorKind.Cancelled, "n3_transport_selftest.ny:168");
}

@test(tag = "net_core_n3")
func test_net_core_n3_task_move_cancel_timeout_order() {
  var driver: NetEventLoop = net_test_loop(2);
  var listener: TcpListener = net_test_listener();
  let options: NetOperationOptions = NetOperationOptions{deadline: NetDeadline.After(NetClock.NowNanoseconds(), 50000000u64)};
  var queued: Result<TcpConnectionTask, NetError> = listener.AcceptAsync(driver, options);
  var task: TcpConnectionTask = move((queued.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let future: AsyncFuture<Result<Unit, NetError>> = net_test_task_future(task);
  var moved: TcpConnectionTask = move(task);
  AssertTrueMsg(moved.Cancel(), "n3_transport_selftest.ny:180");
  Thread.Sleep(60u32);
  net_test_pump(driver, future);
  AssertTrueMsg(net_test_ready_error(future) == NetErrorKind.Cancelled, "n3_transport_selftest.ny:183");
}

struct NetTestCounter { hits: int32; }
@test(tag = "net_core_n3")
func test_net_core_n3_close_callback_observes_terminal_tasks() {
  var driver: NetEventLoop = net_test_loop(4);
  var first: TcpListener = net_test_listener(); var second: TcpListener = net_test_listener();
  var qa: Result<TcpConnectionTask, NetError> = first.AcceptAsync(driver, net_test_options());
  var qb: Result<TcpConnectionTask, NetError> = second.AcceptAsync(driver, net_test_options());
  var a: TcpConnectionTask = move((qa.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  var b: TcpConnectionTask = move((qb.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let af: AsyncFuture<Result<Unit, NetError>> = net_test_task_future(a);
  let bf: AsyncFuture<Result<Unit, NetError>> = net_test_task_future(b);
  let pointer: *mut TcpConnectionTask = &mut b;
  let counter: arc<NetTestCounter> = new arc<NetTestCounter>{};
  af.RegisterContinuation(lambda [copy pointer, copy counter] () -> void {
    unsafe {
      AssertTrueMsg(!(*pointer).Cancel(), "n3_transport_selftest.ny:201");
      let take: Result<TcpConnection, NetError> = (*pointer).TakeConnection();
      AssertTrueMsg(take.IsErr(), "n3_transport_selftest.ny:203"); AssertTrueMsg(((take.get_if<NetError>()) as NetError).kind == NetErrorKind.Closed, "n3_transport_selftest.ny:203");
    }
    var state: arc<NetTestCounter> = counter; state.hits = state.hits + 1;
  });
  driver.Close();
  AssertTrueMsg(af.is_completed, "n3_transport_selftest.ny:208"); AssertTrueMsg(bf.is_completed, "n3_transport_selftest.ny:208"); AssertEqI32Msg(counter.hits, 1, "n3_transport_selftest.ny:208");
}

@test(tag = "net_core_n3")
func test_net_core_n3_poll_callback_reentry() {
  var driver: NetEventLoop = net_test_loop(4);
  var socket: UdpSocket = net_test_udp();
  let token: NetCancellation = NetCancellation.New();
  let future: AsyncFuture<Result<Unit, NetError>> = net_test_ready(socket.WhenReadable(driver, NetOperationOptions{cancellation: token}));
  let driver_pointer: *mut NetEventLoop = &mut driver;
  let socket_pointer: *mut UdpSocket = &mut socket;
  let counter: arc<NetTestCounter> = new arc<NetTestCounter>{};
  future.RegisterContinuation(lambda [copy driver_pointer, copy socket_pointer, copy counter] () -> void {
    unsafe {
      AssertTrueMsg((*driver_pointer).Poll(0).IsOk(), "n3_transport_selftest.ny:222");
      AssertTrueMsg((*socket_pointer).WhenReadable(*driver_pointer, net_test_options()).IsOk(), "n3_transport_selftest.ny:223");
      (*driver_pointer).Close();
    }
    var state: arc<NetTestCounter> = counter; state.hits = state.hits + 1;
  });
  token.Cancel(); AssertTrueMsg(driver.Poll(0).IsOk(), "n3_transport_selftest.ny:228"); AssertEqI32Msg(counter.hits, 1, "n3_transport_selftest.ny:228");
  AssertEqI32Msg(driver.PendingCount(), 0, "n3_transport_selftest.ny:229");
}

func net_test_resource_round() -> void {
  var driver: NetEventLoop = net_test_loop(4);
  var client: TcpConnection = TcpConnection{}; var server: TcpConnection = TcpConnection{};
  net_test_pair(driver, client, server);
  let pending: AsyncFuture<NetTransfer> = net_test_io(server.ReadAsync(driver, 16, net_test_options()));
  driver.Close(); AssertTrueMsg(pending.is_completed, "n3_transport_selftest.ny:237");
  AssertTrueMsg(client.Close().IsOk(), "n3_transport_selftest.ny:238"); AssertTrueMsg(client.Close().IsOk(), "n3_transport_selftest.ny:238");
}
@test(tag = "net_core_n3")
func test_net_core_n3_descriptor_recovery() {
  net_test_resource_round();
  let baseline: int32 = net_core_test_fd_count(); AssertTrueMsg(baseline >= 0, "n3_transport_selftest.ny:243");
  var i: int32 = 0;
  while i < 64 { net_test_resource_round(); i = i + 1; }
  net_test_fd_baseline(baseline);
}

@test(tag = "net_core_n3")
func test_net_core_n3_large_transfer_is_bounded_and_exact() {
  var driver: NetEventLoop = net_test_loop(4);
  var client: TcpConnection = TcpConnection{}; var server: TcpConnection = TcpConnection{};
  net_test_pair(driver, client, server);
  var bytes: owned <uint8>[] = new <uint8>[200000];
  var i: int32 = 0;
  while i < 200000 { bytes[i] = (i % 251) as uint8; i = i + 1; }
  let view: NetBytes = (NetBytes.FromRaw(&bytes[0], 200000 as intptr).get_if<NetBytes>()) as NetBytes;
  let buffer: NetBuffer = (NetBuffer.CopyFrom(view).get_if<NetBuffer>()) as NetBuffer;
  let write: AsyncFuture<NetTransfer> = net_test_io(client.WriteAllAsync(driver, buffer, net_test_options()));
  let read: AsyncFuture<NetTransfer> = net_test_io(server.ReadExactlyAsync(driver, 200000, net_test_options()));
  AssertTrueMsg(driver.Poll(0).IsOk(), "drive first transfer step");
  AssertTrueMsg(!write.is_completed, "one Poll must not send more than 64 KiB");
  var write_progress: intptr = -1 as intptr;
  var pending_index: int32 = 0;
  while pending_index < driver.pending.Len() {
    let entry: NetPendingOperation = driver.pending.Get(pending_index);
    if entry.kind == NetOperationKind.TcpWriteAll { write_progress = entry.progress; }
    pending_index = pending_index + 1;
  }
  AssertTrueMsg(write_progress >= (0 as intptr) && write_progress <= (65536 as intptr), "first Poll's committed output is bounded to 64 KiB");
  AssertTrueMsg(net_test_transfer(driver, write).error == nil, "complete large write");
  let result: NetTransfer = net_test_transfer(driver, read);
  AssertTrueMsg(result.error == nil, "complete large exact read");
  AssertEqI64Msg(result.bytes_transferred as int64, 200000i64, "exact large read size");
  let received: NetBytes = result.buffer.Bytes();
  var correct: bool = true; i = 0;
  unsafe { while i < 200000 { if received.Data()[i] != (i % 251) as uint8 { correct = false; } i = i + 1; } }
  AssertTrueMsg(correct, "every byte must match; partial writes must not replay a prefix");
  AssertEqI64Msg(driver.RetainedBytes() as int64, 0i64, "large transfer releases pending charge");
}

@test(tag = "net_core_n3")
func test_net_core_n3_queued_transfer_retains_closed_socket() {
  var driver: NetEventLoop = net_test_loop(4);
  var client: TcpConnection = TcpConnection{}; var server: TcpConnection = TcpConnection{};
  net_test_pair(driver, client, server);
  let write: AsyncFuture<NetTransfer> = net_test_io(client.WriteAllAsync(driver, net_test_buffer("retained"), net_test_options()));
  let read: AsyncFuture<NetTransfer> = net_test_io(server.ReadExactlyAsync(driver, 8, net_test_options()));
  AssertTrueMsg(client.Close().IsOk(), "close original sender");
  AssertTrueMsg(server.Close().IsOk(), "close original receiver");
  AssertTrueMsg(net_test_transfer(driver, write).error == nil, "retained sender remains usable");
  let result: NetTransfer = net_test_transfer(driver, read);
  AssertTrueMsg(result.error == nil, "retained receiver remains usable");
  AssertEqStringMsg(net_test_buffer_text(result.buffer), "retained", "retained payload remains initialized");
}

func net_test_discard_write(driver: ref mut NetEventLoop, client: ref mut TcpConnection) -> void {
  let queued: Result<AsyncFuture<NetTransfer>, NetError> = client.WriteAllAsync(driver, net_test_buffer("owned"), net_test_options());
  AssertTrueMsg(queued.IsOk(), "queue a write whose Future will be dropped");
}
@test(tag = "net_core_n3")
func test_net_core_n3_dropped_transfer_future_does_not_cancel() {
  var driver: NetEventLoop = net_test_loop(4);
  var client: TcpConnection = TcpConnection{}; var server: TcpConnection = TcpConnection{};
  net_test_pair(driver, client, server); net_test_discard_write(driver, client);
  let read: AsyncFuture<NetTransfer> = net_test_io(server.ReadExactlyAsync(driver, 5, net_test_options()));
  let result: NetTransfer = net_test_transfer(driver, read);
  AssertTrueMsg(result.error == nil, "Future drop must not cancel accepted output");
  AssertEqStringMsg(net_test_buffer_text(result.buffer), "owned", "driver retains payload after Future drop");
  AssertEqI32Msg(driver.PendingCount(), 0, "both operations retire");
}

func net_test_token_resource_round() -> void {
  var driver: NetEventLoop = net_test_loop(2); var socket: UdpSocket = net_test_udp();
  let token: NetCancellation = (NetCancellation.NewWakeable().get_if<NetCancellation>()) as NetCancellation;
  let future: AsyncFuture<Result<Unit, NetError>> = net_test_ready(socket.WhenReadable(driver, NetOperationOptions{cancellation: token}));
  token.Cancel(); net_test_pump(driver, future);
  AssertTrueMsg(net_test_ready_error(future) == NetErrorKind.Cancelled, "retire token registration");
}
@test(tag = "net_core_n3")
func test_net_core_n3_wake_token_descriptor_recovery() {
  let baseline: int32 = net_core_test_fd_count();
  var i: int32 = 0;
  while i < 64 { net_test_token_resource_round(); i = i + 1; }
  net_test_fd_baseline(baseline);
}

@test(tag = "net_core_n3")
func test_net_core_n3_failed_connect_retires_descriptor() {
  let baseline: int32 = net_core_test_fd_count();
  var driver: NetEventLoop = net_test_loop(2);
  // Darwin rejects remote port zero. It cannot name an OS-assigned listener,
  // so this failure fixture never races another process acquiring a free port.
  let endpoint: NetEndpoint = (NetEndpoint.Parse("127.0.0.1:0").get_if<NetEndpoint>()) as NetEndpoint;
  var queued: Result<TcpConnectionTask, NetError> = TcpConnection.DialAsync(driver, endpoint, net_test_options());
  AssertTrueMsg(queued.IsOk(), "admit the OS-rejected connection attempt");
  var task: TcpConnectionTask = move((queued.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let future: AsyncFuture<Result<Unit, NetError>> = net_test_task_future(task);
  net_test_pump(driver, future);
  AssertTrueMsg(net_test_ready_error(future) == NetErrorKind.AddressUnavailable, "preserve Darwin's remote port-zero error");
  let take: Result<TcpConnection, NetError> = task.TakeConnection();
  AssertTrueMsg(take.IsErr(), "failed task never exposes a socket owner");
  AssertTrueMsg(((take.get_if<NetError>()) as NetError).kind == NetErrorKind.AddressUnavailable, "TakeConnection preserves the failure");
  AssertEqI32Msg(driver.PendingCount(), 0, "failed connect registration retired");
  net_test_fd_baseline(baseline);
}
