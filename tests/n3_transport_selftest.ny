/** @brief Local transport controls, ownership, queue budgets and reentrant completion. */
part of NetTransport;

@test(tag = "net_core_n3")
func test_net_core_n3_native_direction_and_closed_driver() {
  net_test_assert_i32(net_core_test_native_direction(), 0, "n3_transport_selftest.ny:6");
  net_test_assert_i32(net_core_test_empty_udp_readiness(), 1, "native empty UDP must remain readable and receivable");
  var driver: NetEventLoop = net_test_loop(2);
  net_test_assert_i32((driver.Poll(0).get_if<int32>()) as int32, 0, "n3_transport_selftest.ny:8");
  net_test_assert_true(driver.Poll(-2).IsErr(), "n3_transport_selftest.ny:9");
  driver.Close();
  net_test_assert_true(driver.Poll(0).IsErr(), "n3_transport_selftest.ny:11");
}

@test(tag = "net_core_n3")
func test_net_core_n3_tcp_partial_exact_eof() {
  var driver: NetEventLoop = net_test_loop(4);
  var client: TcpConnection = TcpConnection{}; var server: TcpConnection = TcpConnection{};
  net_test_pair(driver, client, server);
  let options: NetOperationOptions = net_test_options();
  let read: AsyncFuture<NetTransfer> = net_test_io(server.ReadExactlyAsync(driver, 8, options));
  let write: AsyncFuture<NetTransfer> = net_test_io(client.WriteAllAsync(driver, net_test_buffer("abc"), options));
  net_test_assert_true(net_test_transfer(driver, write).error == nil, "n3_transport_selftest.ny:22");
  net_test_assert_true(client.ShutdownWrite().IsOk(), "n3_transport_selftest.ny:23");
  let result: NetTransfer = net_test_transfer(driver, read);
  net_test_assert_true(result.eof, "n3_transport_selftest.ny:25"); net_test_assert_true(result.error != nil, "n3_transport_selftest.ny:25");
  net_test_assert_true((result.error as NetError).kind == NetErrorKind.UnexpectedEof, "n3_transport_selftest.ny:26");
  net_test_assert_i64(result.bytes_transferred as int64, 3i64, "n3_transport_selftest.ny:27");
  net_test_assert_string(net_test_buffer_text(result.buffer), "abc", "n3_transport_selftest.ny:28");
}

func net_test_partial_read(close_driver: bool) -> void {
  var driver: NetEventLoop = net_test_loop(4);
  var client: TcpConnection = TcpConnection{}; var server: TcpConnection = TcpConnection{};
  net_test_pair(driver, client, server);
  let token: NetCancellation = NetCancellation.New();
  let options: NetOperationOptions = NetOperationOptions{deadline: net_test_options().deadline, cancellation: token};
  let read: AsyncFuture<NetTransfer> = net_test_io(server.ReadExactlyAsync(driver, 8, options));
  let write: AsyncFuture<NetTransfer> = net_test_io(client.WriteAllAsync(driver, net_test_buffer("abc"), options));
  net_test_assert_true(net_test_transfer(driver, write).error == nil, "n3_transport_selftest.ny:39");
  var attempts: int32 = 0;
  while driver.pending.Len() == 1 && driver.pending.Get(0).progress < (3 as intptr) && attempts < 1000 {
    net_test_assert_true(driver.Poll(5).IsOk(), "pump partial read before cancellation/Close");
    attempts = attempts + 1;
  }
  net_test_assert_true(driver.pending.Len() == 1 && driver.pending.Get(0).progress == (3 as intptr), "partial prefix must reach the receiving operation");
  net_test_assert_true(!read.is_completed, "n3_transport_selftest.ny:41");
  if close_driver { driver.Close(); } else { token.Cancel(); net_test_assert_true(driver.Poll(0).IsOk(), "n3_transport_selftest.ny:42"); }
  let result: NetTransfer = net_test_transfer(driver, read);
  net_test_assert_true(result.error != nil, "n3_transport_selftest.ny:44");
  var expected: NetErrorKind = NetErrorKind.Cancelled;
  if close_driver { expected = NetErrorKind.Closed; }
  net_test_assert_true((result.error as NetError).kind == expected, "n3_transport_selftest.ny:47");
  net_test_assert_i64(result.bytes_transferred as int64, 3i64, "n3_transport_selftest.ny:48");
  net_test_assert_string(net_test_buffer_text(result.buffer), "abc", "n3_transport_selftest.ny:49");
  net_test_assert_i64(driver.RetainedBytes() as int64, 0i64, "n3_transport_selftest.ny:50");
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
  net_test_assert_true(!result.eof, "n3_transport_selftest.ny:65"); net_test_assert_true(result.error == nil, "n3_transport_selftest.ny:65");
  net_test_assert_i64(result.bytes_transferred as int64, 0i64, "n3_transport_selftest.ny:66");
  let empty: AsyncFuture<NetTransfer> = net_test_io(client.WriteAllAsync(driver, NetBuffer{}, options));
  net_test_assert_true(net_test_transfer(driver, empty).error == nil, "n3_transport_selftest.ny:68");
  let pending: AsyncFuture<NetTransfer> = net_test_io(server.ReadAsync(driver, 1, options));
  let overlap: Result<AsyncFuture<NetTransfer>, NetError> = server.ReadAsync(driver, 1, options);
  net_test_assert_true(overlap.IsErr(), "n3_transport_selftest.ny:71");
  net_test_assert_true(((overlap.get_if<NetError>()) as NetError).kind == NetErrorKind.WouldBlock, "n3_transport_selftest.ny:72");
  driver.Close();
  net_test_assert_true((net_test_transfer(driver, pending).error as NetError).kind == NetErrorKind.Closed, "n3_transport_selftest.ny:74");
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
  net_test_assert_i64(slice.RetainedBytes() as int64, 8i64, "n3_transport_selftest.ny:86");
  let rejected: Result<AsyncFuture<NetTransfer>, NetError> = client.WriteAllAsync(driver, slice, net_test_options());
  net_test_assert_true(rejected.IsErr(), "n3_transport_selftest.ny:88"); net_test_assert_i32(driver.PendingCount(), 0, "n3_transport_selftest.ny:88");
  let copied: Result<NetBuffer, NetError> = NetBuffer.CopyFrom(slice.Bytes());
  let compact: NetBuffer = (copied.get_if<NetBuffer>()) as NetBuffer;
  net_test_assert_i64(compact.RetainedBytes() as int64, 2i64, "n3_transport_selftest.ny:91");
  let sent: AsyncFuture<NetTransfer> = net_test_io(client.WriteAllAsync(driver, compact, net_test_options()));
  net_test_assert_i64(driver.RetainedBytes() as int64, 2i64, "n3_transport_selftest.ny:93");
  net_test_assert_true(net_test_transfer(driver, sent).error == nil, "n3_transport_selftest.ny:94");
  net_test_assert_i64(driver.RetainedBytes() as int64, 0i64, "n3_transport_selftest.ny:95");
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
  net_test_assert_true(net_test_transfer(driver, empty_send).error == nil, "n3_transport_selftest.ny:107");
  let empty: NetTransfer = net_test_transfer(driver, empty_read);
  net_test_assert_true(empty.error == nil, "n3_transport_selftest.ny:109"); net_test_assert_true(empty.sender != nil, "n3_transport_selftest.ny:109"); net_test_assert_true(!empty.eof, "n3_transport_selftest.ny:109");
  net_test_assert_i64(empty.bytes_transferred as int64, 0i64, "n3_transport_selftest.ny:110");
  let short_read: AsyncFuture<NetTransfer> = net_test_io(receiver.ReceiveFromAsync(driver, 2, options));
  let long_send: AsyncFuture<NetTransfer> = net_test_io(sender.SendToAsync(driver, endpoint, net_test_buffer("abcdef"), options));
  net_test_assert_true(net_test_transfer(driver, long_send).error == nil, "n3_transport_selftest.ny:113");
  let truncated: NetTransfer = net_test_transfer(driver, short_read);
  net_test_assert_true(truncated.error != nil, "n3_transport_selftest.ny:115"); net_test_assert_true((truncated.error as NetError).kind == NetErrorKind.MessageTooLarge, "n3_transport_selftest.ny:115");
  net_test_assert_i64(truncated.buffer.Len() as int64, 0i64, "n3_transport_selftest.ny:116"); net_test_assert_true(truncated.sender == nil, "n3_transport_selftest.ny:116");
  let token: NetCancellation = NetCancellation.New();
  let pending: AsyncFuture<NetTransfer> = net_test_io(receiver.ReceiveFromAsync(driver, 2, NetOperationOptions{cancellation: token}));
  net_test_assert_true(driver.Poll(0).IsOk(), "n3_transport_selftest.ny:119"); net_test_assert_true(!pending.is_completed, "n3_transport_selftest.ny:119");
  token.Cancel();
  net_test_assert_true((net_test_transfer(driver, pending).error as NetError).kind == NetErrorKind.Cancelled, "n3_transport_selftest.ny:121");
}

@test(tag = "net_core_n3")
func test_net_core_n3_udp_zero_capacity_does_not_write_caller() {
  var sender: UdpSocket = net_test_udp(); var receiver: UdpSocket = net_test_udp();
  var sentinel: uint8 = 77u8;
  let view_result: Result<NetMutableBytes, NetError> = NetMutableBytes.FromRaw(&mut sentinel, 0 as intptr);
  var view: NetMutableBytes = (view_result.get_if<NetMutableBytes>()) as NetMutableBytes;
  let none: Result<NetDatagram, NetError> = receiver.TryReceiveFrom(view);
  net_test_assert_true(none.IsErr(), "zero-capacity receive must wait for a datagram");
  net_test_assert_true(((none.get_if<NetError>()) as NetError).kind == NetErrorKind.WouldBlock, "empty socket is WouldBlock");
  let endpoint: NetEndpoint = (receiver.LocalEndpoint().get_if<NetEndpoint>()) as NetEndpoint;
  net_test_assert_true(sender.SendTo(endpoint, NetBytes.FromString("z"), net_test_options()).IsOk(), "send one byte");
  let received: Result<NetDatagram, NetError> = receiver.ReceiveFrom(view, net_test_options());
  net_test_assert_true(received.IsErr(), "nonempty datagram must not fit zero capacity");
  net_test_assert_true(((received.get_if<NetError>()) as NetError).kind == NetErrorKind.MessageTooLarge, "nonempty datagram is discarded");
  net_test_assert_i32(sentinel as int32, 77, "zero capacity must never write the caller pointer");
  let consumed: Result<NetDatagram, NetError> = receiver.TryReceiveFrom(view);
  net_test_assert_true(consumed.IsErr(), "the oversized datagram was consumed");
  net_test_assert_true(((consumed.get_if<NetError>()) as NetError).kind == NetErrorKind.WouldBlock, "no discarded prefix remains");
}

@test(tag = "net_core_n3")
func test_net_core_n3_wakeable_cancel_fanout() {
  var driver: NetEventLoop = net_test_loop(4);
  var first: UdpSocket = net_test_udp(); var second: UdpSocket = net_test_udp();
  let made: Result<NetCancellation, NetError> = NetCancellation.NewWakeable();
  let token: NetCancellation = (made.get_if<NetCancellation>()) as NetCancellation;
  net_test_assert_true(token.CanWakeWaiters(), "macOS token must use an active wake channel");
  let options: NetOperationOptions = NetOperationOptions{deadline: net_test_options().deadline, cancellation: token};
  let a: AsyncFuture<Result<Unit, NetError>> = net_test_ready(first.WhenReadable(driver, options));
  let b: AsyncFuture<Result<Unit, NetError>> = net_test_ready(second.WhenReadable(driver, options));
  let thread: Result<Thread, ThreadError> = Thread.Spawn(lambda [copy token] () -> void { Thread.Sleep(30u32); token.Cancel(); });
  net_test_assert_true(thread.IsOk(), "n3_transport_selftest.ny:134");
  let start: uint64 = NetClock.NowNanoseconds();
  net_test_assert_true(driver.Poll(-1).IsOk(), "n3_transport_selftest.ny:135");
  net_test_assert_true(NetClock.NowNanoseconds() - start < 2500000000u64, "wake must arrive before the fallback deadline");
  net_test_assert_true(a.is_completed, "n3_transport_selftest.ny:136"); net_test_assert_true(b.is_completed, "n3_transport_selftest.ny:136");
  net_test_assert_true(net_test_ready_error(a) == NetErrorKind.Cancelled, "n3_transport_selftest.ny:137");
  net_test_assert_true(net_test_ready_error(b) == NetErrorKind.Cancelled, "n3_transport_selftest.ny:138");
  let late: AsyncFuture<Result<Unit, NetError>> = net_test_ready(first.WhenReadable(driver, options));
  net_test_assert_true(late.is_completed, "n3_transport_selftest.ny:140"); net_test_assert_true(net_test_ready_error(late) == NetErrorKind.Cancelled, "n3_transport_selftest.ny:140");
  net_test_assert_i32(driver.PendingCount(), 0, "n3_transport_selftest.ny:141");
}

@test(tag = "net_core_n3")
func test_net_core_n3_readiness_deadline() {
  var driver: NetEventLoop = net_test_loop(2);
  var socket: UdpSocket = net_test_udp();
  let options: NetOperationOptions = NetOperationOptions{deadline: NetDeadline.After(NetClock.NowNanoseconds(), 20000000u64)};
  let ready: AsyncFuture<Result<Unit, NetError>> = net_test_ready(socket.WhenReadable(driver, options));
  net_test_pump(driver, ready);
  net_test_assert_true(net_test_ready_error(ready) == NetErrorKind.TimedOut, "n3_transport_selftest.ny:151");
}

func net_test_abandoned_accept(driver: ref mut NetEventLoop, listener: ref mut TcpListener, cancel: bool) -> AsyncFuture<Result<Unit, NetError>> {
  var queued: Result<TcpConnectionTask, NetError> = listener.AcceptAsync(driver, net_test_options());
  var task: TcpConnectionTask = move((queued.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let future: AsyncFuture<Result<Unit, NetError>> = net_test_task_future(task);
  if cancel { net_test_assert_true(task.Cancel(), "n3_transport_selftest.ny:158"); }
  return future;
}
@test(tag = "net_core_n3")
func test_net_core_n3_abandon_and_cancelled_drop() {
  var driver: NetEventLoop = net_test_loop(2);
  var listener: TcpListener = net_test_listener();
  let dropped: AsyncFuture<Result<Unit, NetError>> = net_test_abandoned_accept(driver, listener, false);
  net_test_pump(driver, dropped); net_test_assert_true(net_test_ready_error(dropped) == NetErrorKind.Closed, "n3_transport_selftest.ny:166");
  let cancelled: AsyncFuture<Result<Unit, NetError>> = net_test_abandoned_accept(driver, listener, true);
  net_test_pump(driver, cancelled); net_test_assert_true(net_test_ready_error(cancelled) == NetErrorKind.Cancelled, "n3_transport_selftest.ny:168");
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
  net_test_assert_true(moved.Cancel(), "n3_transport_selftest.ny:180");
  Thread.Sleep(60u32);
  net_test_pump(driver, future);
  net_test_assert_true(net_test_ready_error(future) == NetErrorKind.Cancelled, "n3_transport_selftest.ny:183");
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
      net_test_assert_true(!(*pointer).Cancel(), "n3_transport_selftest.ny:201");
      let take: Result<TcpConnection, NetError> = (*pointer).TakeConnection();
      net_test_assert_true(take.IsErr(), "n3_transport_selftest.ny:203"); net_test_assert_true(((take.get_if<NetError>()) as NetError).kind == NetErrorKind.Closed, "n3_transport_selftest.ny:203");
    }
    var state: arc<NetTestCounter> = counter; state.hits = state.hits + 1;
  });
  driver.Close();
  net_test_assert_true(af.is_completed, "n3_transport_selftest.ny:208"); net_test_assert_true(bf.is_completed, "n3_transport_selftest.ny:208"); net_test_assert_i32(counter.hits, 1, "n3_transport_selftest.ny:208");
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
      net_test_assert_true((*driver_pointer).Poll(0).IsOk(), "n3_transport_selftest.ny:222");
      net_test_assert_true((*socket_pointer).WhenReadable(*driver_pointer, net_test_options()).IsOk(), "n3_transport_selftest.ny:223");
      (*driver_pointer).Close();
    }
    var state: arc<NetTestCounter> = counter; state.hits = state.hits + 1;
  });
  token.Cancel(); net_test_assert_true(driver.Poll(0).IsOk(), "n3_transport_selftest.ny:228"); net_test_assert_i32(counter.hits, 1, "n3_transport_selftest.ny:228");
  net_test_assert_i32(driver.PendingCount(), 0, "n3_transport_selftest.ny:229");
}

func net_test_resource_round() -> void {
  var driver: NetEventLoop = net_test_loop(4);
  var client: TcpConnection = TcpConnection{}; var server: TcpConnection = TcpConnection{};
  net_test_pair(driver, client, server);
  let pending: AsyncFuture<NetTransfer> = net_test_io(server.ReadAsync(driver, 16, net_test_options()));
  driver.Close(); net_test_assert_true(pending.is_completed, "n3_transport_selftest.ny:237");
  net_test_assert_true(client.Close().IsOk(), "n3_transport_selftest.ny:238"); net_test_assert_true(client.Close().IsOk(), "n3_transport_selftest.ny:238");
}
@test(tag = "net_core_n3")
func test_net_core_n3_descriptor_recovery() {
  net_test_resource_round();
  let baseline: int32 = net_core_test_fd_count(); net_test_assert_true(baseline >= 0, "n3_transport_selftest.ny:243");
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
  net_test_assert_true(driver.Poll(0).IsOk(), "drive first transfer step");
  net_test_assert_true(!write.is_completed, "one Poll must not send more than 64 KiB");
  var write_progress: intptr = -1 as intptr;
  var pending_index: int32 = 0;
  while pending_index < driver.pending.Len() {
    let entry: NetPendingOperation = driver.pending.Get(pending_index);
    if entry.kind == NetOperationKind.TcpWriteAll { write_progress = entry.progress; }
    pending_index = pending_index + 1;
  }
  net_test_assert_true(write_progress >= (0 as intptr) && write_progress <= (65536 as intptr), "first Poll's committed output is bounded to 64 KiB");
  net_test_assert_true(net_test_transfer(driver, write).error == nil, "complete large write");
  let result: NetTransfer = net_test_transfer(driver, read);
  net_test_assert_true(result.error == nil, "complete large exact read");
  net_test_assert_i64(result.bytes_transferred as int64, 200000i64, "exact large read size");
  let received: NetBytes = result.buffer.Bytes();
  var correct: bool = true; i = 0;
  unsafe { while i < 200000 { if received.Data()[i] != (i % 251) as uint8 { correct = false; } i = i + 1; } }
  net_test_assert_true(correct, "every byte must match; partial writes must not replay a prefix");
  net_test_assert_i64(driver.RetainedBytes() as int64, 0i64, "large transfer releases pending charge");
}

@test(tag = "net_core_n3")
func test_net_core_n3_queued_transfer_retains_closed_socket() {
  var driver: NetEventLoop = net_test_loop(4);
  var client: TcpConnection = TcpConnection{}; var server: TcpConnection = TcpConnection{};
  net_test_pair(driver, client, server);
  let write: AsyncFuture<NetTransfer> = net_test_io(client.WriteAllAsync(driver, net_test_buffer("retained"), net_test_options()));
  let read: AsyncFuture<NetTransfer> = net_test_io(server.ReadExactlyAsync(driver, 8, net_test_options()));
  net_test_assert_true(client.Close().IsOk(), "close original sender");
  net_test_assert_true(server.Close().IsOk(), "close original receiver");
  net_test_assert_true(net_test_transfer(driver, write).error == nil, "retained sender remains usable");
  let result: NetTransfer = net_test_transfer(driver, read);
  net_test_assert_true(result.error == nil, "retained receiver remains usable");
  net_test_assert_string(net_test_buffer_text(result.buffer), "retained", "retained payload remains initialized");
}

func net_test_discard_write(driver: ref mut NetEventLoop, client: ref mut TcpConnection) -> void {
  let queued: Result<AsyncFuture<NetTransfer>, NetError> = client.WriteAllAsync(driver, net_test_buffer("owned"), net_test_options());
  net_test_assert_true(queued.IsOk(), "queue a write whose Future will be dropped");
}
@test(tag = "net_core_n3")
func test_net_core_n3_dropped_transfer_future_does_not_cancel() {
  var driver: NetEventLoop = net_test_loop(4);
  var client: TcpConnection = TcpConnection{}; var server: TcpConnection = TcpConnection{};
  net_test_pair(driver, client, server); net_test_discard_write(driver, client);
  let read: AsyncFuture<NetTransfer> = net_test_io(server.ReadExactlyAsync(driver, 5, net_test_options()));
  let result: NetTransfer = net_test_transfer(driver, read);
  net_test_assert_true(result.error == nil, "Future drop must not cancel accepted output");
  net_test_assert_string(net_test_buffer_text(result.buffer), "owned", "driver retains payload after Future drop");
  net_test_assert_i32(driver.PendingCount(), 0, "both operations retire");
}

func net_test_token_resource_round() -> void {
  var driver: NetEventLoop = net_test_loop(2); var socket: UdpSocket = net_test_udp();
  let token: NetCancellation = (NetCancellation.NewWakeable().get_if<NetCancellation>()) as NetCancellation;
  let future: AsyncFuture<Result<Unit, NetError>> = net_test_ready(socket.WhenReadable(driver, NetOperationOptions{cancellation: token}));
  token.Cancel(); net_test_pump(driver, future);
  net_test_assert_true(net_test_ready_error(future) == NetErrorKind.Cancelled, "retire token registration");
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
  // Remote port zero cannot name an OS-assigned listener,
  // so this failure fixture never races another process acquiring a free port.
  let endpoint: NetEndpoint = (NetEndpoint.Parse("127.0.0.1:0").get_if<NetEndpoint>()) as NetEndpoint;
  var queued: Result<TcpConnectionTask, NetError> = TcpConnection.DialAsync(driver, endpoint, net_test_options());
  net_test_assert_true(queued.IsOk(), "admit the OS-rejected connection attempt");
  var task: TcpConnectionTask = move((queued.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let future: AsyncFuture<Result<Unit, NetError>> = net_test_task_future(task);
  net_test_pump(driver, future);
  let expected: NetErrorKind = net_native_error(NetNativeError{kind: net_core_test_failed_connect_kind()}).kind;
  net_test_assert_true(net_test_ready_error(future) == expected, "preserve the platform's remote port-zero error");
  let take: Result<TcpConnection, NetError> = task.TakeConnection();
  net_test_assert_true(take.IsErr(), "failed task never exposes a socket owner");
  net_test_assert_true(((take.get_if<NetError>()) as NetError).kind == expected, "TakeConnection preserves the failure");
  net_test_assert_i32(driver.PendingCount(), 0, "failed connect registration retired");
  net_test_fd_baseline(baseline);
}

@extern("C") func net_core_test_wait_large_snapshot() -> int32;
@test(tag = "net_core_n3")
func test_net_core_n3_large_native_snapshot_fanout() {
  net_test_assert_i32(net_core_test_wait_large_snapshot(), 0, "144 distinct read interests preserve readiness and cancellation fanout");
}
