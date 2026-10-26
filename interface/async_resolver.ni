/** @brief Bounded explicit DNS workers with caller-thread completion publication. */
import "stdlib:stdlib.ny";
import "interface/foundation.ni";
import "interface/transport.ni";

/** @brief Immutable shared endpoint results; copies retain storage, default is empty. */
pub struct NetResolvedAddresses;
/** @brief Number of initialized endpoints, never greater than the query's max_results. */
pub method(NetResolvedAddresses) Len() -> int32;
/** @brief Copy an inline endpoint, or InvalidArgument for an out-of-range index. */
pub method(NetResolvedAddresses) Get(index: int32) -> Result<NetEndpoint, NetError>;
/** @brief DNS completion; error is nil on success, failures contain no addresses. */
pub struct NetResolution {
  addresses: NetResolvedAddresses;
  error: NetError?;
}

/**
 * @brief Move-only owner of an explicit fixed DNS worker pool and bounded job slots.
 * @note Register/Poll/Close/Future access stay on one caller-selected thread.
 *       Workers only resolve and publish private results; they never complete local Futures.
 */
pub struct AsyncResolver;
/** @brief A resolver pool cannot be copied. */
pub method(AsyncResolver) operator copy() -> AsyncResolver = delete;
/** @brief Transfer the pool; leave the original closed without stopping its workers. */
pub method(AsyncResolver) operator move() -> AsyncResolver;
/** @brief Close without waiting for a blocking OS resolver call to return. */
pub method(AsyncResolver) operator drop() -> void;
/**
 * @brief Create 1..8 fixed workers and worker_count..256 total retained job slots.
 * @returns Pool or a validation/startup/native failure; partial startup stops its workers.
 * @note Each lookup retains at most 1024 hostname bytes and 4096 endpoints. Jobs use the
 *       process heap, never a caller arena. Limits are per pool, not global process limits.
 *       On macOS, Linux, Windows, Android and iOS creation also allocates one resettable notification socket pair.
 */
pub static method(AsyncResolver) New(worker_count: int32, max_pending: int32) -> Result<AsyncResolver, NetError>;
/**
 * @brief Queue an ASCII hostname/literal with port 0..65535 and max_results in 1..4096.
 * @returns Local Future or an admission/validation/control failure before registration.
 * @note Copies host bytes; borrows end at return. Full pools return WouldBlock. Dropping
 *       the Future alone does not cancel. Drive Poll directly or after WhenReady notification.
 */
pub method(AsyncResolver) ResolveAsync(host: ref string, port: int32, family: IpFamily, max_results: int32, options: ref NetOperationOptions) -> Result<AsyncFuture<NetResolution>, NetError>;
/**
 * @brief Number of retained jobs, including cancelled/timed-out jobs still inside OS DNS.
 * @note Their slots cannot be reused until the worker finishes and Poll retires them.
 */
pub method(AsyncResolver) PendingCount() -> int32;
/**
 * @brief Register advisory DNS progress on a NetEventLoop without publishing query results.
 * @param driver Caller-thread event loop; one pending notification per resolver in this driver.
 * @param options Controls for this notification, independent of the individual queries.
 * @returns Local readiness Future or Closed/NotSupported/WouldBlock/registration failure.
 * @note WouldBlock also means no retained queries. Worker completion wakes the driver;
 *       queued query deadlines bound its wait. Query cancellation is observed with a
 *       cooperative wait cap of 50ms; this notification's own wakeable token stays active.
 *       On readiness, call resolver.Poll(), inspect query Futures, then rearm if needed.
 *       Readiness can be stale/coalesced. Closing the resolver completes a still-pending
 *       notification with Closed when the driver is next polled. Registrations retain
 *       private pool state until retirement; dropping this Future does not cancel them.
 */
pub method(AsyncResolver) WhenReady(driver: ref mut NetEventLoop, options: ref NetOperationOptions) -> Result<AsyncFuture<Result<Unit, NetError>>, NetError>;
/**
 * @brief Nonblocking scan; publish completed/cancelled/timed-out Futures on this thread.
 * @returns Number of newly completed Futures, or Closed for a default/closed resolver.
 * @note Does not pump NetEventLoop or an executor. Call from an outer scheduled loop;
 *       do not busy-spin. Cancellation precedes timeout at each observation. Controls
 *       observed before publication take priority over an unpublished worker result.
 */
pub method(AsyncResolver) Poll() -> Result<int32, NetError>;
/**
 * @brief Stop admission, discard queued work and publish Closed after detaching local state.
 * @note Does not wait for in-progress OS DNS. Workers retain private state until they exit;
 *       OS DNS is not forcibly interrupted. Repeated Close is inert. Continuations may reenter.
 */
pub method(AsyncResolver) Close() -> void;
