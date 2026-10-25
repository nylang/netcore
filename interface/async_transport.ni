/**
 * @brief Retained-buffer asynchronous socket operations on the caller's NetEventLoop.
 * @note Register/Poll/Future/task access stay on the same driver thread. No hidden workers.
 */
import "stdlib:stdlib.ny";
import "interface/foundation.ni";
import "interface/transport.ni";

/**
 * @brief Immutable shared byte storage; copies and nonempty slices retain its ARC backing.
 * @note Language drop releases storage. Bytes() borrows; no writable view is exposed.
 */
pub struct NetBuffer;
/** @brief Copy borrowed bytes once; reject lengths above int32 max before allocation. */
pub static method(NetBuffer) CopyFrom(bytes: ref NetBytes) -> Result<NetBuffer, NetError>;
/** @brief Number of visible bytes; default is empty. */
pub method(NetBuffer) Len() -> intptr;
/** @brief Full backing allocation size retained by this slice, excluding fixed ARC overhead. */
pub method(NetBuffer) RetainedBytes() -> intptr;
/** @brief Borrow immutable bytes; keep a buffer copy alive for the entire borrow. */
pub method(NetBuffer) Bytes() -> NetBytes;
/** @brief Checked shared slice; an empty slice retains no backing allocation. */
pub method(NetBuffer) Slice(start: intptr, length: intptr) -> Result<NetBuffer, NetError>;

/**
 * @brief Completed transfer, including committed progress when an operation fails.
 * @note buffer contains only initialized received bytes; sends leave it empty.
 *       sender is present only for successful UDP receives. eof describes TCP reads only.
 *       error is nil on success; an incomplete exact read has UnexpectedEof and eof=true.
 */
pub struct NetTransfer {
  bytes_transferred: intptr;
  buffer: NetBuffer;
  sender: NetEndpoint?;
  eof: bool;
  error: NetError?;
}

/**
 * @brief Create a driver with explicit pending-payload budget; capacity remains 1..256.
 * @param max_retained_bytes Nonnegative sum of backing bytes retained by pending transfers.
 * @note New(max_pending) uses 16 MiB. Read requests reserve their allocation size; writes
 *       charge the entire buffer backing, including when a small slice retains a large root.
 *       Shared buffers are charged per operation conservatively. Completed consumer-owned
 *       buffers and fixed queue/Future/native overhead are outside this pending-byte budget.
 * @returns Driver, InvalidArgument, or NotSupported outside macOS.
 */
pub static method(NetEventLoop) NewWithLimits(max_pending: int32, max_retained_bytes: intptr) -> Result<NetEventLoop, NetError>;
/** @brief Pending transfer backing bytes currently charged to this driver. */
pub method(NetEventLoop) RetainedBytes() -> intptr;

/**
 * @brief Queue a TCP receive of up to max_bytes, allocating and retaining its own buffer.
 * @returns Local transfer Future or registration/capacity failure; errors after enqueue are
 *          in NetTransfer.error. Zero size succeeds without receiving and does not mean EOF.
 * @note No borrowed payload is queued. One OS attempt per operation per Poll; a successful
 *       nonempty read may be partial. Payload transfers retain a duplicated socket even if
 *       the original owner closes/drops. Do not issue another read on the socket until done;
 *       the driver rejects overlapping queued reads on this owner within the same driver.
 *       Cancelling or closing the driver releases pending operations; dropping only the Future
 *       does not cancel them. Controls already expired at registration fail the outer Result.
 */
pub method(TcpConnection) ReadAsync(driver: ref mut NetEventLoop, max_bytes: int32, options: ref NetOperationOptions) -> Result<AsyncFuture<NetTransfer>, NetError>;
/** @brief Queue an exact TCP read; preserve partial bytes/count on EOF, cancellation or error. */
pub method(TcpConnection) ReadExactlyAsync(driver: ref mut NetEventLoop, size: int32, options: ref NetOperationOptions) -> Result<AsyncFuture<NetTransfer>, NetError>;
/**
 * @brief Queue a TCP send retaining an immutable buffer copy; complete on first partial progress.
 * @note The original buffer value may drop immediately. Do not mix synchronous/Try/queued
 *       writes on this socket until done. The driver rejects overlapping queued writes.
 */
pub method(TcpConnection) WriteAsync(driver: ref mut NetEventLoop, buffer: ref NetBuffer, options: ref NetOperationOptions) -> Result<AsyncFuture<NetTransfer>, NetError>;
/** @brief Queue all bytes once; retries resume at the accepted offset and failures retain progress. */
pub method(TcpConnection) WriteAllAsync(driver: ref mut NetEventLoop, buffer: ref NetBuffer, options: ref NetOperationOptions) -> Result<AsyncFuture<NetTransfer>, NetError>;
/** @brief Queue one datagram receive with owned storage; truncation consumes/discards the message. */
pub method(UdpSocket) ReceiveFromAsync(driver: ref mut NetEventLoop, max_bytes: int32, options: ref NetOperationOptions) -> Result<AsyncFuture<NetTransfer>, NetError>;
/** @brief Queue one datagram retaining its buffer, including a real send for an empty buffer. */
pub method(UdpSocket) SendToAsync(driver: ref mut NetEventLoop, endpoint: ref NetEndpoint, buffer: ref NetBuffer, options: ref NetOperationOptions) -> Result<AsyncFuture<NetTransfer>, NetError>;

/**
 * @brief Move-only asynchronous connect/accept task with one takeable connection result.
 * @note Future carries readiness/error, never copies a socket owner. The task owns a successful
 *       connection until TakeConnection moves it out. Dropping a pending task abandons it;
 *       the next Poll/driver Close releases its registration. Dropping a completed task closes
 *       any untaken connection. Task and Future remain on the driver thread.
 */
pub struct TcpConnectionTask;
/** @brief Copying a takeable connection task is forbidden. */
pub method(TcpConnectionTask) operator copy() -> TcpConnectionTask = delete;
/** @brief Transfer the task, leaving the source inert. */
pub method(TcpConnectionTask) operator move() -> TcpConnectionTask;
/** @brief Abandon a pending operation or release an untaken result on last internal reference. */
pub method(TcpConnectionTask) operator drop() -> void;
/** @brief Local completion Future; default/moved-from tasks return Closed. */
pub method(TcpConnectionTask) FutureHandle() -> Result<AsyncFuture<Result<Unit, NetError>>, NetError>;
/**
 * @brief Request cancellation of a still-pending connect/accept on the driver thread.
 * @returns true for the first request; false for default, moved-from, completed or
 *          already-cancelled tasks. A completed untaken connection is preserved.
 * @note The next driver Poll retires the descriptor before publishing Cancelled.
 *       This is cooperative, not immediate completion. Cancellation precedes timeout
 *       when both are observed in that Poll. Driver Close publishes Closed instead.
 *       Moving or dropping a cancelled pending task preserves the cancellation request.
 */
pub method(TcpConnectionTask) Cancel() -> bool;
/** @brief Move the completed connection out once; pending returns WouldBlock, repeated take returns Closed. */
pub method(TcpConnectionTask) TakeConnection() -> Result<TcpConnection, NetError>;
/** @brief Queue a numeric nonblocking connect with one absolute deadline and task-owned result. */
pub static method(TcpConnection) DialAsync(driver: ref mut NetEventLoop, endpoint: ref NetEndpoint, options: ref NetOperationOptions) -> Result<TcpConnectionTask, NetError>;
/** @brief Queue one accept; preserve the listener via a duplicate until completion/cancellation. */
pub method(TcpListener) AcceptAsync(driver: ref mut NetEventLoop, options: ref NetOperationOptions) -> Result<TcpConnectionTask, NetError>;
