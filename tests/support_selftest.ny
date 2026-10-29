// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

/** @brief Reusable socket-pair, Future and assertion fixtures using operation contracts. */
module NetTestSupport;
import "stdlib:stdlib.ny";
import "interface/foundation.ni";
import "interface/transport.ni";
import "interface/async_transport.ni";
import "interface/async_resolver.ni";
import "private/native_abi.ni";
import "private/native_bridge.ny";
import "private/cancellation.ny";

/**
 * @brief Record a fixture assertion failure without aborting its resource cleanup.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestAssertTrue(condition: bool, message: ref string) -> int32 {
  if condition {
    return 0;
  }

  Console.Eprintln(message);
  AddFail(1);

  return 1;
}

/**
 * @brief Compare fixture int32 values through the shared failure counter.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestAssertI32(actual: int32, expected: int32, message: ref string) -> int32 {
  return NetTestAssertTrue(actual == expected, message);
}

/**
 * @brief Compare fixture int64 values through the shared failure counter.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestAssertI64(actual: int64, expected: int64, message: ref string) -> int32 {
  return NetTestAssertTrue(actual == expected, message);
}

/**
 * @brief Compare fixture string payloads through the shared failure counter.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestAssertString(actual: ref string, expected: ref string, message: ref string) -> int32 {
  return NetTestAssertTrue(actual.Equal(expected), message);
}

pub @extern("C") func AddFail(count: int32) -> void;

/**
 * @brief Create a bounded operation budget for a controlled loopback fixture.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestOptions() -> NetOperationOptions {
  return NetOperationOptions{deadline: NetDeadline.After(NetClock.NowNanoseconds(), 3000000000u64)};
}

/**
 * @brief Construct an event loop with the requested fixture capacity.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestLoop(limit: int32) -> NetEventLoop {
  var result: Result<NetEventLoop, NetError> = NetEventLoop.New(limit);
  NetTestAssertTrue(result.IsOk(), "n3_selftest.ny:17");

  return move((result.get_if<NetEventLoop>()) as NetEventLoop);
}

/**
 * @brief Construct a bounded DNS worker pool for a controlled fixture.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestResolver(workers: int32, limit: int32) -> AsyncResolver {
  var result: Result<AsyncResolver, NetError> = AsyncResolver.New(workers, limit);
  NetTestAssertTrue(result.IsOk(), "n3_selftest.ny:22");

  return move((result.get_if<AsyncResolver>()) as AsyncResolver);
}

/**
 * @brief Bind a loopback listener to an OS-selected local port.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestListener() -> TcpListener {
  let endpoint: Result<NetEndpoint, NetError> = NetEndpoint.Parse("127.0.0.1:0");
  var result: Result<TcpListener, NetError> = TcpListener.Listen(
    (endpoint.get_if<NetEndpoint>()) as NetEndpoint,
    8
  );
  NetTestAssertTrue(result.IsOk(), "n3_selftest.ny:28");

  return move((result.get_if<TcpListener>()) as TcpListener);
}

/**
 * @brief Obtain the completion Future of an admitted connection task.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestTaskFuture(task: ref mut TcpConnectionTask) -> AsyncFuture<Result<Unit, NetError>> {
  let result: Result<AsyncFuture<Result<Unit, NetError>>, NetError> = task.FutureHandle();
  NetTestAssertTrue(result.IsOk(), "n3_selftest.ny:33");

  return (result.get_if<AsyncFuture<Result<Unit, NetError>>>()) as AsyncFuture<Result<Unit, NetError>>;
}

/**
 * @brief Drive a readiness Future with a bounded fixture polling loop.
 */
pub func NetTestPump(driver: ref mut NetEventLoop, future: ref AsyncFuture<Result<Unit, NetError>>) -> void {
  var i: int32 = 0;
  while !future.is_completed && i < 1000 {
    let result: Result<int32, NetError> = driver.Poll(5);
    NetTestAssertTrue(result.IsOk(), "n3_selftest.ny:40");
    i = i + 1;
  }

  NetTestAssertTrue(future.is_completed, "n3_selftest.ny:43");
}

/**
 * @brief Drive a payload Future and inspect its completed transfer result.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestTransfer(driver: ref mut NetEventLoop, future: ref AsyncFuture<NetTransfer>) -> NetTransfer {
  var i: int32 = 0;
  while !future.is_completed && i < 1000 {
    NetTestAssertTrue(driver.Poll(5).IsOk(), "n3_selftest.ny:48");
    i = i + 1;
  }

  NetTestAssertTrue(future.is_completed, "n3_selftest.ny:51");
  let result: Result<NetTransfer, AsyncError> = future.GetResult();
  NetTestAssertTrue(result.IsOk(), "n3_selftest.ny:53");

  return (result.get_if<NetTransfer>()) as NetTransfer;
}

/** @brief Two independently move-owned loopback sockets for transport tests. */
pub struct NetTestSocketPair {
  client: TcpConnection;
  server: TcpConnection;
}

/** @brief Establish a loopback pair through connection-task ownership transfers.
 * @returns The client and accepted server sockets, each owned by the caller.
 */
pub func NetTestPair(driver: ref mut NetEventLoop) -> NetTestSocketPair {
  var listener: TcpListener = NetTestListener();
  let endpoint: Result<NetEndpoint, NetError> = listener.LocalEndpoint();
  let options: NetOperationOptions = NetTestOptions();
  var accepted: Result<TcpConnectionTask, NetError> = listener.AcceptAsync(driver, options);
  NetTestAssertTrue(accepted.IsOk(), "n3_selftest.ny:61");
  var accept_task: TcpConnectionTask = move((accepted.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  var connected: Result<TcpConnectionTask, NetError> = TcpConnection.DialAsync(
    driver,
    (endpoint.get_if<NetEndpoint>()) as NetEndpoint,
    options
  );
  NetTestAssertTrue(connected.IsOk(), "n3_selftest.ny:64");
  var connect_task: TcpConnectionTask = move((connected.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let connect_future: AsyncFuture<Result<Unit, NetError>> = NetTestTaskFuture(connect_task);
  let accept_future: AsyncFuture<Result<Unit, NetError>> = NetTestTaskFuture(accept_task);
  NetTestPump(driver, connect_future);
  NetTestPump(driver, accept_future);
  NetTestAssertTrue(
    ((connect_future.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>).IsOk(),
    "n3_selftest.ny:70"
  );
  NetTestAssertTrue(
    ((accept_future.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>).IsOk(),
    "n3_selftest.ny:71"
  );
  var client_result: Result<TcpConnection, NetError> = connect_task.TakeConnection();
  var server_result: Result<TcpConnection, NetError> = accept_task.TakeConnection();
  NetTestAssertTrue(client_result.IsOk(), "n3_selftest.ny:74");
  NetTestAssertTrue(server_result.IsOk(), "n3_selftest.ny:74");
  var client_value: TcpConnection = move((client_result.get_if<TcpConnection>()) as TcpConnection);
  var server_value: TcpConnection = move((server_result.get_if<TcpConnection>()) as TcpConnection);
  NetTestAssertTrue(connect_task.TakeConnection().IsErr(), "n3_selftest.ny:79");
  NetTestAssertTrue(!connect_task.Cancel(), "n3_selftest.ny:80");

  return NetTestSocketPair{client: move(client_value), server: move(server_value)};
}

/**
 * @brief Copy a fixture string into a retained network buffer.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestBuffer(text: ref string) -> NetBuffer {
  let result: Result<NetBuffer, NetError> = NetBuffer.CopyFrom(NetBytes.FromString(text));
  NetTestAssertTrue(result.IsOk(), "n3_selftest.ny:84");

  return (result.get_if<NetBuffer>()) as NetBuffer;
}

/**
 * @brief Copy a fixture payload into a language-owned string.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestBufferText(buffer: ref NetBuffer) -> string {
  let bytes: NetBytes = buffer.Bytes();

  return string.ViewFrom(
    bytes.Data() as *const int8,
    bytes.Len() as int32
  ).Substring(0, bytes.Len() as int32);
}

/**
 * @brief Wait with a bounded loop until controlled DNS workers enter their fixture.
 */
pub func NetTestWaitDns(count: int32) -> void {
  var i: int32 = 0;
  while net_core_test_dns_entered() < count && i < 2000 {
    Thread.Sleep(1u32);
    i = i + 1;
  }

  NetTestAssertTrue(net_core_test_dns_entered() >= count, "n3_selftest.ny:94");
}

/**
 * @brief Delay then release the controlled DNS barrier from a fixture thread.
 */
pub func NetTestReleaseDnsLater() -> void {
  Thread.Sleep(200u32);
  net_core_test_dns_release();
}

/**
 * @brief Bind a datagram socket to an OS-selected loopback port.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestUdp() -> UdpSocket {
  let parsed: Result<NetEndpoint, NetError> = NetEndpoint.Parse("127.0.0.1:0");
  var bound: Result<UdpSocket, NetError> = UdpSocket.Bind((parsed.get_if<NetEndpoint>()) as NetEndpoint);
  NetTestAssertTrue(bound.IsOk(), "n3_selftest.ny:100");

  return move((bound.get_if<UdpSocket>()) as UdpSocket);
}

/**
 * @brief Require readiness registration admission before extracting its Future.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestReady(
  queued: Result<AsyncFuture<Result<Unit, NetError>>, NetError>
) -> AsyncFuture<Result<Unit, NetError>> {
  NetTestAssertTrue(queued.IsOk(), "n3_selftest.ny:104");

  return (queued.get_if<AsyncFuture<Result<Unit, NetError>>>()) as AsyncFuture<Result<Unit, NetError>>;
}

/**
 * @brief Require payload-operation admission before extracting its Future.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestIo(queued: Result<AsyncFuture<NetTransfer>, NetError>) -> AsyncFuture<NetTransfer> {
  NetTestAssertTrue(queued.IsOk(), "n3_selftest.ny:108");

  return (queued.get_if<AsyncFuture<NetTransfer>>()) as AsyncFuture<NetTransfer>;
}

/**
 * @brief Require DNS admission before extracting its Future.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestDns(queued: Result<AsyncFuture<NetResolution>, NetError>) -> AsyncFuture<NetResolution> {
  NetTestAssertTrue(queued.IsOk(), "n3_selftest.ny:112");

  return (queued.get_if<AsyncFuture<NetResolution>>()) as AsyncFuture<NetResolution>;
}

/**
 * @brief Inspect the original error published by a readiness Future.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestReadyError(future: ref AsyncFuture<Result<Unit, NetError>>) -> NetErrorKind {
  let completed: Result<Unit, NetError> = (
    future.GetResult().get_if<Result<Unit, NetError>>()
  ) as Result<Unit, NetError>;
  NetTestAssertTrue(completed.IsErr(), "n3_selftest.ny:117");

  return ((completed.get_if<NetError>()) as NetError).kind;
}

/**
 * @brief Drive a cancelled DNS query until its physical worker slot is retired.
 */
pub func NetTestRetireDns(resolver: ref mut AsyncResolver) -> void {
  var i: int32 = 0;
  while resolver.PendingCount() != 0 && i < 2000 {
    NetTestAssertTrue(resolver.Poll().IsOk(), "n3_selftest.ny:123");
    Thread.Sleep(1u32);
    i = i + 1;
  }

  NetTestAssertI32(resolver.PendingCount(), 0, "n3_selftest.ny:125");
}

/**
 * @brief Wait until fixture descriptor accounting reaches a stable baseline.
 */
pub func NetTestFdBaseline(expected: int32) -> void {
  var i: int32 = 0;
  while net_core_test_fd_count() != expected && i < 2000 {
    Thread.Sleep(1u32);
    i = i + 1;
  }

  if net_core_test_fd_count() != expected {
    net_core_test_resource_report(expected);
  }

  NetTestAssertI32(net_core_test_fd_count(), expected, "resource handles return to the warmed baseline");
}

/**
 * @brief Drive a DNS query and inspect its completed resolution result.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub func NetTestResolution(
  resolver: ref mut AsyncResolver,
  future: ref AsyncFuture<NetResolution>
) -> NetResolution {
  var i: int32 = 0;
  while !future.is_completed && i < 2000 {
    NetTestAssertTrue(resolver.Poll().IsOk(), "n3_selftest.ny:135");
    if !future.is_completed {
      Thread.Sleep(1u32);
    }

    i = i + 1;
  }

  NetTestAssertTrue(future.is_completed, "n3_selftest.ny:139");
  let result: Result<NetResolution, AsyncError> = future.GetResult();
  NetTestAssertTrue(result.IsOk(), "n3_selftest.ny:141");

  return (result.get_if<NetResolution>()) as NetResolution;
}

pub @extern("C") func net_core_test_failed_connect_kind() -> int32;

pub @extern("C") func net_core_test_dns_reset() -> int32;

pub @extern("C") func net_core_test_dns_entered() -> int32;

pub @extern("C") func net_core_test_dns_active() -> int32;

pub @extern("C") func net_core_test_dns_peak() -> int32;

pub @extern("C") func net_core_test_dns_release() -> void;

pub @extern("C") func net_core_test_resource_report(expected: int32) -> void;

pub @extern("C") func net_core_test_fd_count() -> int32;

pub @extern("C") func net_core_test_native_direction() -> int32;

pub @extern("C") func net_core_test_empty_udp_readiness() -> int32;

pub @extern("C") func net_core_test_fd_exhaust_begin() -> int32;

pub @extern("C") func net_core_test_fd_exhaust_end() -> int32;
