// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

part of NetSocketDriver;

@test(tag = "net_core_n3")
func test_net_core_n3_large_transfer_is_bounded_and_exact() {
  let options: NetOperationOptions = NetOperationOptions{
    deadline: NetDeadline.After(NetClock.NowNanoseconds(), 3000000000u64)
  };
  var made: Result<NetEventLoop, NetError> = NetEventLoop.New(4);
  AssertTrue(made.IsOk());
  var driver: NetEventLoop = move((made.get_if<NetEventLoop>()) as NetEventLoop);

  let endpoint: Result<NetEndpoint, NetError> = NetEndpoint.Parse("127.0.0.1:0");
  var listening: Result<TcpListener, NetError> = TcpListener.Listen(
    (endpoint.get_if<NetEndpoint>()) as NetEndpoint, 8
  );
  AssertTrue(listening.IsOk());
  var listener: TcpListener = move((listening.get_if<TcpListener>()) as TcpListener);
  let local: Result<NetEndpoint, NetError> = listener.LocalEndpoint();
  var connected: Result<TcpConnection, NetError> = TcpConnection.Dial(
    (local.get_if<NetEndpoint>()) as NetEndpoint, options
  );
  AssertTrue(connected.IsOk());
  var client: TcpConnection = move((connected.get_if<TcpConnection>()) as TcpConnection);
  var accepted: Result<TcpConnection, NetError> = listener.Accept(options);
  AssertTrue(accepted.IsOk());
  var server: TcpConnection = move((accepted.get_if<TcpConnection>()) as TcpConnection);

  var bytes: owned <uint8>[] = new <uint8>[200000];
  var i: int32 = 0;
  while i < 200000 {
    bytes[i] = (i % 251) as uint8;
    i = i + 1;
  }

  let view: NetBytes = (NetBytes.FromRaw(&bytes[0], 200000 as intptr).get_if<NetBytes>()) as NetBytes;
  let buffer: NetBuffer = (NetBuffer.CopyFrom(view).get_if<NetBuffer>()) as NetBuffer;
  let queued_write: Result<AsyncFuture<NetTransfer>, NetError> = client.WriteAllAsync(driver, buffer, options);
  let queued_read: Result<AsyncFuture<NetTransfer>, NetError> = server.ReadExactlyAsync(driver, 200000, options);
  AssertTrue(queued_write.IsOk() && queued_read.IsOk());
  let write: AsyncFuture<NetTransfer> = (queued_write.get_if<AsyncFuture<NetTransfer>>()) as AsyncFuture<NetTransfer>;
  let read: AsyncFuture<NetTransfer> = (queued_read.get_if<AsyncFuture<NetTransfer>>()) as AsyncFuture<NetTransfer>;
  AssertTrue(driver.Poll(0).IsOk());
  AssertTrue(!write.is_completed);

  var write_progress: intptr = -1 as intptr;
  var pending_index: int32 = 0;
  while pending_index < driver.pending.Len() {
    let entry: NetPendingOperation = driver.pending.Get(pending_index);
    if entry.kind == NetOperationKind.TcpWriteAll {
      write_progress = entry.progress;
    }

    pending_index = pending_index + 1;
  }

  // One scheduling pass commits at most one 64 KiB write step.
  AssertTrue(write_progress >= (0 as intptr) && write_progress <= (65536 as intptr));

  var rounds: int32 = 0;
  while (!write.is_completed || !read.is_completed) && rounds < 1000 {
    AssertTrue(driver.Poll(5).IsOk());
    rounds = rounds + 1;
  }

  AssertTrue(write.is_completed && read.is_completed);
  let sent: NetTransfer = (write.GetResult().get_if<NetTransfer>()) as NetTransfer;
  let result: NetTransfer = (read.GetResult().get_if<NetTransfer>()) as NetTransfer;
  AssertTrue(sent.error == nil && result.error == nil);
  AssertEqI64(result.bytes_transferred as int64, 200000i64);
  let received: NetBytes = result.buffer.Bytes();
  var correct: bool = true;
  i = 0;
  unsafe {
    while i < 200000 {
      if received.Data()[i] != (i % 251) as uint8 {
        correct = false;
      }

      i = i + 1;
    }
  }

  // Partial writes must not replay an already committed prefix.
  AssertTrue(correct);
  AssertEqI64(driver.RetainedBytes() as int64, 0i64);
}
