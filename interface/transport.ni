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
/** @brief Connect a numeric endpoint, honoring an absolute deadline/cooperative cancellation. */
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
/** @brief Send FIN after queued writes; reading remains available. */
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
/** @brief Accept one connection, honoring the supplied deadline/cooperative cancellation. */
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
