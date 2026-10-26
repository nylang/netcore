/**
 * @brief Synchronous DNS and deadline-aware TCP/UDP over private nonblocking sockets.
 * @note Link libnet_core_native.a; Windows additionally needs ws2_32 and iphlpapi.
 * @note Socket values are move-only, close on drop, and are not safe for concurrent method calls.
 */
import "stdlib:stdlib.ny";
import "interface/foundation.ni";

/** @brief Hosted monotonic clock matching the transport deadline origin. */
pub struct NetClock;
/** @brief Nanoseconds since the hosted monotonic origin, not Unix time or raw clock ticks. */
pub static method(NetClock) NowNanoseconds() -> uint64;
/** @brief OS resolver; synchronous lookup has no timeout/cancellation guarantee. */
pub struct Resolver;
/**
 * @brief Resolve an ASCII hostname/literal, replacing output only after successful lookup.
 * @param family Unspecified, V4 or V6; mapped-family synthesis is not requested.
 * @param max_results Bound in 1..4096; excess unique results return MessageTooLarge.
 * @param output Caller-owned array; allocator/capacity are reused, no host bytes retained.
 * @returns Ok(Unit), or a validation/resolver failure with output unchanged.
 * @note Uses blocking OS getaddrinfo. Native temporary results are released on every exit.
 */
pub static method(Resolver) Resolve(host: ref string, port: int32, family: IpFamily, max_results: int32, output: ref mut FastArray<NetEndpoint>) -> Result<Unit, NetError>;
/** @brief Resolve an ASCII interface name into an IPv6 numeric scope; unknown names fail. */
pub static method(Resolver) InterfaceIndex(name: ref string) -> Result<uint32, NetError>;

/** @brief Sole owner of a connected TCP socket; default/moved-from values are closed. */
pub struct TcpConnection;
/** @brief Copying a socket owner is forbidden. */
pub method(TcpConnection) operator copy() -> TcpConnection = delete;
/** @brief Transfer ownership and leave the source closed. */
pub method(TcpConnection) operator move() -> TcpConnection;
/** @brief Close the owned socket during language destruction. */
pub method(TcpConnection) operator drop() -> void;
/** @brief Connect a numeric endpoint, honoring an absolute deadline and shared cancellation. */
pub static method(TcpConnection) Dial(endpoint: ref NetEndpoint, options: ref NetOperationOptions) -> Result<TcpConnection, NetError>;
/**
 * @brief Read at most the borrowed buffer length; positive progress may be partial.
 * @returns Zero for EOF (or a zero-sized buffer), count on progress, otherwise error.
 * @note The caller keeps the buffer alive/exclusively writable for this synchronous call.
 */
pub method(TcpConnection) Read(buffer: ref NetMutableBytes, options: ref NetOperationOptions) -> Result<intptr, NetError>;
/** @brief Write at most the borrowed byte length; returns partial progress, not WriteAll. */
pub method(TcpConnection) Write(buffer: ref NetBytes, options: ref NetOperationOptions) -> Result<intptr, NetError>;
/** @brief Enable or disable TCP_NODELAY. */
pub method(TcpConnection) SetNoDelay(enabled: bool) -> Result<Unit, NetError>;
/**
 * @brief Shut down sending; reading remains available and OS-accepted bytes precede FIN.
 * @note Complete pending WriteAsync/WriteAllAsync operations before calling this method.
 *       This call does not flush payload still waiting in a NetEventLoop queue.
 */
pub method(TcpConnection) ShutdownWrite() -> Result<Unit, NetError>;
/** @brief Local endpoint, including an OS-selected ephemeral port. */
pub method(TcpConnection) LocalEndpoint() -> Result<NetEndpoint, NetError>;
/** @brief Connected peer endpoint. */
pub method(TcpConnection) RemoteEndpoint() -> Result<NetEndpoint, NetError>;
/** @brief Whether the value currently owns a socket; not a connection-liveness probe. */
pub method(TcpConnection) IsOpen() -> bool;
/** @brief Retire ownership and close once; repeated calls succeed. Errors never restore ownership. */
pub method(TcpConnection) Close() -> Result<Unit, NetError>;

/** @brief Sole owner of a listening TCP socket; closes on drop. */
pub struct TcpListener;
/** @brief Copying a listener is forbidden. */
pub method(TcpListener) operator copy() -> TcpListener = delete;
/** @brief Transfer the listener and leave its source closed. */
pub method(TcpListener) operator move() -> TcpListener;
/** @brief Close the listener during language destruction. */
pub method(TcpListener) operator drop() -> void;
/** @brief Bind and listen; backlog must be positive. IPv6 sockets are V6-only. */
pub static method(TcpListener) Listen(endpoint: ref NetEndpoint, backlog: int32) -> Result<TcpListener, NetError>;
/** @brief Accept one connection, honoring the supplied deadline and shared cancellation. */
pub method(TcpListener) Accept(options: ref NetOperationOptions) -> Result<TcpConnection, NetError>;
/** @brief Bound endpoint, including the chosen port when binding port zero. */
pub method(TcpListener) LocalEndpoint() -> Result<NetEndpoint, NetError>;
/** @brief Whether this value owns its listener. */
pub method(TcpListener) IsOpen() -> bool;
/** @brief Close once; repeated calls succeed. */
pub method(TcpListener) Close() -> Result<Unit, NetError>;

/** @brief Successful UDP receive metadata; zero bytes means an empty datagram, not EOF. */
pub struct NetDatagram { bytes_read: intptr; sender: NetEndpoint; }
/** @brief Sole owner of a bound UDP socket; closes on drop. */
pub struct UdpSocket;
/** @brief Copying a datagram socket is forbidden. */
pub method(UdpSocket) operator copy() -> UdpSocket = delete;
/** @brief Transfer ownership and leave the source closed. */
pub method(UdpSocket) operator move() -> UdpSocket;
/** @brief Close during language destruction. */
pub method(UdpSocket) operator drop() -> void;
/** @brief Bind a numeric endpoint, including port zero; IPv6 is V6-only. */
pub static method(UdpSocket) Bind(endpoint: ref NetEndpoint) -> Result<UdpSocket, NetError>;
/** @brief Send exactly one datagram; zero-sized buffers send an actual empty datagram. */
pub method(UdpSocket) SendTo(endpoint: ref NetEndpoint, buffer: ref NetBytes, options: ref NetOperationOptions) -> Result<intptr, NetError>;
/**
 * @brief Receive one datagram into caller-owned writable bytes.
 * @returns Size and sender, or MessageTooLarge if truncated (that datagram is consumed).
 * @note Buffer contents may change on error. A zero-length buffer still consumes one datagram.
 */
pub method(UdpSocket) ReceiveFrom(buffer: ref NetMutableBytes, options: ref NetOperationOptions) -> Result<NetDatagram, NetError>;
/** @brief Actual bound address/port. */
pub method(UdpSocket) LocalEndpoint() -> Result<NetEndpoint, NetError>;
/** @brief Whether the value owns a datagram socket. */
pub method(UdpSocket) IsOpen() -> bool;
/** @brief Retire and close once; repeated calls succeed. */
pub method(UdpSocket) Close() -> Result<Unit, NetError>;

/**
 * @brief Move-only cross-platform readiness driver with a bounded queue and local Future affinity.
 * @note No hidden threads. Register/Poll/Close/Future access stay on one driver thread.
 *       Only NetCancellation.Cancel may run on another thread using a retained token copy.
 */
pub struct NetEventLoop;
/** @brief Copying the driver and its registrations is forbidden. */
pub method(NetEventLoop) operator copy() -> NetEventLoop = delete;
/** @brief Transfer pending registrations; the source becomes closed. */
pub method(NetEventLoop) operator move() -> NetEventLoop;
/** @brief Close duplicated descriptors and complete pending Futures with Closed. */
pub method(NetEventLoop) operator drop() -> void;
/**
 * @brief Create a local operation queue with capacity in 1..256 and a 16 MiB pending-payload budget.
 * @returns Driver, InvalidArgument, or NotSupported on unsupported platforms.
 * @note Full queues fail with WouldBlock; no background threads or unbounded task growth.
 */
pub static method(NetEventLoop) New(max_pending: int32) -> Result<NetEventLoop, NetError>;
/** @brief Number of pending operations, including ones now cancelled/expired. */
pub method(NetEventLoop) PendingCount() -> int32;
/**
 * @brief Drive one bounded OS event batch and publish completed readiness Futures.
 * @param maximum_wait_ms Zero polls; -1 permits waiting until readiness/control expiry.
 * @returns Completed count or native failure; an empty queue returns zero immediately.
 * @note Recomputes per-registration absolute deadlines. Flag-only tokens cap sleep at 50ms.
 *       Future continuations run on this thread, after the batch is removed and closed.
 *       No pending raw I/O buffer is borrowed. Transfers retain payload owners; each makes
 *       at most one OS attempt of up to 64 KiB (TCP) per Poll. Readiness can become stale.
 */
pub method(NetEventLoop) Poll(maximum_wait_ms: int32) -> Result<int32, NetError>;
/**
 * @brief Retire all registrations before publishing Closed; repeated calls are inert.
 * @note Completion continuations run synchronously on the caller, including during drop.
 */
pub method(NetEventLoop) Close() -> void;
/**
 * @brief Register TCP read readiness using a retained duplicate of the socket.
 * @returns Local Future of Ok(Unit)/NetError, or registration/backpressure failure.
 * @note The duplicate keeps the underlying socket alive even if this owner closes/drops.
 *       Close/cancel the registration through its token or driver to release it early.
 *       Readiness includes EOF/error; Read reports the actual result. No bytes are consumed.
 */
pub method(TcpConnection) WhenReadable(driver: ref mut NetEventLoop, options: ref NetOperationOptions) -> Result<AsyncFuture<Result<Unit, NetError>>, NetError>;
/** @brief Register TCP write readiness under the same retention/affinity contract as WhenReadable. */
pub method(TcpConnection) WhenWritable(driver: ref mut NetEventLoop, options: ref NetOperationOptions) -> Result<AsyncFuture<Result<Unit, NetError>>, NetError>;
/** @brief Register accept readiness; the Future consumes no connection and follows the same retention contract. */
pub method(TcpListener) WhenAcceptable(driver: ref mut NetEventLoop, options: ref NetOperationOptions) -> Result<AsyncFuture<Result<Unit, NetError>>, NetError>;
/** @brief Register datagram receive readiness; no datagram/buffer is retained or consumed. */
pub method(UdpSocket) WhenReadable(driver: ref mut NetEventLoop, options: ref NetOperationOptions) -> Result<AsyncFuture<Result<Unit, NetError>>, NetError>;
/** @brief Register datagram send readiness; follows the TCP registration retention/affinity contract. */
pub method(UdpSocket) WhenWritable(driver: ref mut NetEventLoop, options: ref NetOperationOptions) -> Result<AsyncFuture<Result<Unit, NetError>>, NetError>;

/**
 * @brief Perform one TCP receive without waiting; WouldBlock also covers interruption.
 * @returns Partial count, zero for EOF/empty buffer, or error under the Read buffer contract.
 * @note Pair with WhenReadable and re-register on WouldBlock; readiness is advisory.
 */
pub method(TcpConnection) TryRead(buffer: ref NetMutableBytes) -> Result<intptr, NetError>;
/** @brief Perform one TCP send without waiting; return partial progress or WouldBlock/error. */
pub method(TcpConnection) TryWrite(buffer: ref NetBytes) -> Result<intptr, NetError>;
/** @brief Accept once without waiting; return a move-only connection or WouldBlock/error. */
pub method(TcpListener) TryAccept() -> Result<TcpConnection, NetError>;
/** @brief Send one datagram without waiting; preserve SendTo empty-message and size semantics. */
pub method(UdpSocket) TrySendTo(endpoint: ref NetEndpoint, buffer: ref NetBytes) -> Result<intptr, NetError>;
/** @brief Receive once without waiting; WouldBlock means no progress; truncation still consumes the message. */
pub method(UdpSocket) TryReceiveFrom(buffer: ref NetMutableBytes) -> Result<NetDatagram, NetError>;
