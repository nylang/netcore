// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

/** @brief Reusable socket-pair, Future and assertion fixtures using operation contracts. */
module NetTestSupport;
import "stdlib:stdlib.ny";
import "ntest:ntest.ny";
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
/**
 * @brief Compare fixture int32 values through the shared failure counter.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
/**
 * @brief Compare fixture int64 values through the shared failure counter.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
/**
 * @brief Compare fixture string payloads through the shared failure counter.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */


/**
 * @brief Create a bounded operation budget for a controlled loopback fixture.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub static method(NetOperationOptions) TestDefault() -> NetOperationOptions {
  let now: uint64 = Instant.Now().ToDurationSinceEpochish().ToNanoseconds();
  return NetOperationOptions{deadline: NetDeadline.After(now, 3000000000u64)};
}

/**
 * @brief Construct an event loop with the requested fixture capacity.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub static method(NetEventLoop) TestNew(limit: int32) -> NetEventLoop {
  var result: Result<NetEventLoop, NetError> = NetEventLoop.New(limit);
  AssertTrueMsg(result.IsOk(), "n3_selftest.ny:17");

  return move((result.get_if<NetEventLoop>()) as NetEventLoop);
}

/**
 * @brief Construct a bounded DNS worker pool for a controlled fixture.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub static method(AsyncResolver) TestNew(workers: int32, limit: int32) -> AsyncResolver {
  var result: Result<AsyncResolver, NetError> = AsyncResolver.New(workers, limit);
  AssertTrueMsg(result.IsOk(), "n3_selftest.ny:22");

  return move((result.get_if<AsyncResolver>()) as AsyncResolver);
}

/**
 * @brief Bind a loopback listener to an OS-selected local port.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub static method(TcpListener) TestListen() -> TcpListener {
  let endpoint: Result<NetEndpoint, NetError> = NetEndpoint.Parse("127.0.0.1:0");
  var result: Result<TcpListener, NetError> = TcpListener.Listen(
    (endpoint.get_if<NetEndpoint>()) as NetEndpoint,
    8
  );
  AssertTrueMsg(result.IsOk(), "n3_selftest.ny:28");

  return move((result.get_if<TcpListener>()) as TcpListener);
}

/**
 * @brief Obtain the completion Future of an admitted connection task.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub method(TcpConnectionTask) TestFuture() -> AsyncFuture<Result<Unit, NetError>> {
  let result: Result<AsyncFuture<Result<Unit, NetError>>, NetError> = self.FutureHandle();
  AssertTrueMsg(result.IsOk(), "n3_selftest.ny:33");

  return (result.get_if<AsyncFuture<Result<Unit, NetError>>>()) as AsyncFuture<Result<Unit, NetError>>;
}

/**
 * @brief Drive a readiness Future with a bounded fixture polling loop.
 */
pub method(NetEventLoop) TestPump(future: ref AsyncFuture<Result<Unit, NetError>>) -> void {
  var i: int32 = 0;
  while !future.is_completed && i < 1000 {
    let result: Result<int32, NetError> = self.Poll(5);
    AssertTrueMsg(result.IsOk(), "n3_selftest.ny:40");
    i = i + 1;
  }

  AssertTrueMsg(future.is_completed, "n3_selftest.ny:43");
}

/**
 * @brief Drive a payload Future and inspect its completed transfer result.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub method(NetEventLoop) TestTransfer(future: ref AsyncFuture<NetTransfer>) -> NetTransfer {
  var i: int32 = 0;
  while !future.is_completed && i < 1000 {
    AssertTrueMsg(self.Poll(5).IsOk(), "n3_selftest.ny:48");
    i = i + 1;
  }

  AssertTrueMsg(future.is_completed, "n3_selftest.ny:51");
  let result: Result<NetTransfer, AsyncError> = future.GetResult();
  AssertTrueMsg(result.IsOk(), "n3_selftest.ny:53");

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
pub static method(NetTestSocketPair) New(driver: ref mut NetEventLoop) -> NetTestSocketPair {
  var listener: TcpListener = TcpListener.TestListen();
  let endpoint: Result<NetEndpoint, NetError> = listener.LocalEndpoint();
  let options: NetOperationOptions = NetOperationOptions.TestDefault();
  var accepted: Result<TcpConnectionTask, NetError> = listener.AcceptAsync(driver, options);
  AssertTrueMsg(accepted.IsOk(), "n3_selftest.ny:61");
  var accept_task: TcpConnectionTask = move((accepted.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  var connected: Result<TcpConnectionTask, NetError> = TcpConnection.DialAsync(
    driver,
    (endpoint.get_if<NetEndpoint>()) as NetEndpoint,
    options
  );
  AssertTrueMsg(connected.IsOk(), "n3_selftest.ny:64");
  var connect_task: TcpConnectionTask = move((connected.get_if<TcpConnectionTask>()) as TcpConnectionTask);
  let connect_future: AsyncFuture<Result<Unit, NetError>> = (connect_task).TestFuture();
  let accept_future: AsyncFuture<Result<Unit, NetError>> = (accept_task).TestFuture();
  (driver).TestPump(connect_future);
  (driver).TestPump(accept_future);
  AssertTrueMsg(
    ((connect_future.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>).IsOk(),
    "n3_selftest.ny:70"
  );
  AssertTrueMsg(
    ((accept_future.GetResult().get_if<Result<Unit, NetError>>()) as Result<Unit, NetError>).IsOk(),
    "n3_selftest.ny:71"
  );
  var client_result: Result<TcpConnection, NetError> = connect_task.TakeConnection();
  var server_result: Result<TcpConnection, NetError> = accept_task.TakeConnection();
  AssertTrueMsg(client_result.IsOk(), "n3_selftest.ny:74");
  AssertTrueMsg(server_result.IsOk(), "n3_selftest.ny:74");
  var client_value: TcpConnection = move((client_result.get_if<TcpConnection>()) as TcpConnection);
  var server_value: TcpConnection = move((server_result.get_if<TcpConnection>()) as TcpConnection);
  AssertTrueMsg(connect_task.TakeConnection().IsErr(), "n3_selftest.ny:79");
  AssertTrueMsg(!connect_task.Cancel(), "n3_selftest.ny:80");

  return NetTestSocketPair{client: move(client_value), server: move(server_value)};
}

/**
 * @brief Copy a fixture string into a retained network buffer.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub static method(NetBuffer) TestFromString(text: ref string) -> NetBuffer {
  let result: Result<NetBuffer, NetError> = NetBuffer.CopyFrom(NetBytes.FromString(text));
  AssertTrueMsg(result.IsOk(), "n3_selftest.ny:84");

  return (result.get_if<NetBuffer>()) as NetBuffer;
}

/**
 * @brief Copy a fixture payload into a language-owned string.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub method(NetBuffer) TestText() -> string {
  let bytes: NetBytes = self.Bytes();

  return string.ViewFrom(
    bytes.Data() as *const int8,
    bytes.Len() as int32
  ).Substring(0, bytes.Len() as int32);
}

/**
 * @brief Wait with a bounded loop until controlled DNS workers enter their fixture.
 */
pub struct NetTestDnsWait {
  count: int32;
}

/** @brief Wait for the fixture expectation with a bounded timeout. */
pub method(NetTestDnsWait) Wait() -> void {
  var i: int32 = 0;
  while net_core_test_dns_entered() < self.count && i < 2000 {
    Thread.Sleep(1u32);
    i = i + 1;
  }

  AssertTrueMsg(net_core_test_dns_entered() >= self.count, "n3_selftest.ny:94");
}

/**
 * @brief Delay then release the controlled DNS barrier from a fixture thread.
 */
// nyra-lint-allow: prefer-type-owned-functions -- No-capture thread callback releases the native DNS gate.
pub func NetTestReleaseDnsLater() -> void {
  Thread.Sleep(200u32);
  net_core_test_dns_release();
}

/**
 * @brief Bind a datagram socket to an OS-selected loopback port.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub static method(UdpSocket) TestBind() -> UdpSocket {
  let parsed: Result<NetEndpoint, NetError> = NetEndpoint.Parse("127.0.0.1:0");
  var bound: Result<UdpSocket, NetError> = UdpSocket.Bind((parsed.get_if<NetEndpoint>()) as NetEndpoint);
  AssertTrueMsg(bound.IsOk(), "n3_selftest.ny:100");

  return move((bound.get_if<UdpSocket>()) as UdpSocket);
}

/**
 * @brief Require readiness registration admission before extracting its Future.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub static method(AsyncFuture<Result<Unit, NetError>>) TestAdmit(
  queued: Result<AsyncFuture<Result<Unit, NetError>>, NetError>
) -> AsyncFuture<Result<Unit, NetError>> {
  AssertTrueMsg(queued.IsOk(), "n3_selftest.ny:104");

  return (queued.get_if<AsyncFuture<Result<Unit, NetError>>>()) as AsyncFuture<Result<Unit, NetError>>;
}

/**
 * @brief Require payload-operation admission before extracting its Future.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub static method(AsyncFuture<NetTransfer>) TestAdmit(queued: Result<AsyncFuture<NetTransfer>,
  NetError>) -> AsyncFuture<NetTransfer> {
  AssertTrueMsg(queued.IsOk(), "n3_selftest.ny:108");

  return (queued.get_if<AsyncFuture<NetTransfer>>()) as AsyncFuture<NetTransfer>;
}

/**
 * @brief Require DNS admission before extracting its Future.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub static method(AsyncFuture<NetResolution>) TestAdmit(queued: Result<AsyncFuture<NetResolution>,
  NetError>) -> AsyncFuture<NetResolution> {
  AssertTrueMsg(queued.IsOk(), "n3_selftest.ny:112");

  return (queued.get_if<AsyncFuture<NetResolution>>()) as AsyncFuture<NetResolution>;
}

/**
 * @brief Inspect the original error published by a readiness Future.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub method(AsyncFuture<Result<Unit, NetError>>) TestError() -> NetErrorKind {
  let completed: Result<Unit, NetError> = (
    self.GetResult().get_if<Result<Unit, NetError>>()
  ) as Result<Unit, NetError>;
  AssertTrueMsg(completed.IsErr(), "n3_selftest.ny:117");

  return ((completed.get_if<NetError>()) as NetError).kind;
}

/**
 * @brief Drive a cancelled DNS query until its physical worker slot is retired.
 */
pub method(AsyncResolver) TestRetire() -> void {
  var i: int32 = 0;
  while self.PendingCount() != 0 && i < 2000 {
    AssertTrueMsg(self.Poll().IsOk(), "n3_selftest.ny:123");
    Thread.Sleep(1u32);
    i = i + 1;
  }

  AssertEqI32Msg(self.PendingCount(), 0, "n3_selftest.ny:125");
}

/**
 * @brief Wait until fixture descriptor accounting reaches a stable baseline.
 */
pub struct NetTestDescriptorBaseline {
  expected: int32;
}

/** @brief Wait for the fixture expectation with a bounded timeout. */
pub method(NetTestDescriptorBaseline) Wait() -> void {
  var i: int32 = 0;
  while net_core_test_fd_count() != self.expected && i < 2000 {
    Thread.Sleep(1u32);
    i = i + 1;
  }

  if net_core_test_fd_count() != self.expected {
    net_core_test_resource_report(self.expected);
  }

  AssertEqI32Msg(net_core_test_fd_count(), self.expected, "resource handles return to the warmed baseline");
}

/**
 * @brief Drive a DNS query and inspect its completed resolution result.
 * @returns The fixture result described above; admission/completion failures increment the
 *   shared test failure count.
 */
pub method(AsyncResolver) TestResolution(
  future: ref AsyncFuture<NetResolution>
) -> NetResolution {
  var i: int32 = 0;
  while !future.is_completed && i < 2000 {
    AssertTrueMsg(self.Poll().IsOk(), "n3_selftest.ny:135");
    if !future.is_completed {
      Thread.Sleep(1u32);
    }

    i = i + 1;
  }

  AssertTrueMsg(future.is_completed, "n3_selftest.ny:139");
  let result: Result<NetResolution, AsyncError> = future.GetResult();
  AssertTrueMsg(result.IsOk(), "n3_selftest.ny:141");

  return (result.get_if<NetResolution>()) as NetResolution;
}

/** @brief Read the platform-specific expected remote-port-zero connect failure.
 * @returns Product error-kind discriminator used only by the test fixture.
 */
pub @extern("C") func net_core_test_failed_connect_kind() -> int32;

/** @brief Reset controlled DNS gate and counters when no previous fixture lookup is active.
 * @returns Zero when reset succeeds, nonzero when an active lookup prevents reset.
 */
pub @extern("C") func net_core_test_dns_reset() -> int32;

/** @brief Read the number of controlled DNS lookups admitted to the native gate.
 * @returns Atomic entered count since reset.
 */
pub @extern("C") func net_core_test_dns_entered() -> int32;

/** @brief Read the current number of controlled DNS lookups waiting inside the gate.
 * @returns Atomic active count.
 */
pub @extern("C") func net_core_test_dns_active() -> int32;

/** @brief Read peak concurrent controlled DNS activity since reset.
 * @returns Atomic peak count.
 */
pub @extern("C") func net_core_test_dns_peak() -> int32;

/** @brief Release the process-wide controlled DNS gate and wake its waiters.
 */
pub @extern("C") func net_core_test_dns_release() -> void;

/** @brief Print a native descriptor diagnostic against the expected fixture count.
 */
pub @extern("C") func net_core_test_resource_report(expected: int32) -> void;

/** @brief Count live native resource descriptors using the platform fixture.
 * @returns Descriptor count, or a negative value when observation fails.
 */
pub @extern("C") func net_core_test_fd_count() -> int32;

/** @brief Exercise native directional batch readiness with controlled loopback sockets.
 * @returns Zero when the fixture passes, nonzero on failure.
 */
pub @extern("C") func net_core_test_native_direction() -> int32;

/** @brief Exercise readiness for an empty UDP datagram on controlled sockets.
 * @returns Zero when the fixture passes, nonzero on failure.
 */
pub @extern("C") func net_core_test_empty_udp_readiness() -> int32;

/** @brief Enter bounded descriptor exhaustion or the platform wake-allocation failure injection.
 * @returns Zero when the controlled failure fixture is armed, nonzero on failure.
 */
pub @extern("C") func net_core_test_fd_exhaust_begin() -> int32;

/** @brief Release all descriptors/injection state retained by fd_exhaust_begin.
 * @returns Zero when cleanup succeeds, nonzero on failure.
 */
pub @extern("C") func net_core_test_fd_exhaust_end() -> int32;
