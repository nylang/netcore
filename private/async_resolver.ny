// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

module NetDnsWorkers;
import "stdlib:stdlib.ny";
import "interface/foundation.ni";
import "interface/transport.ni";
import "interface/async_transport.ni";
import "interface/async_resolver.ni";
import "private/foundation.ny";
import "private/native_abi.ni";
import "private/native_bridge.ny";
import "private/readiness.ni";
import "private/cancellation.ny";
import "private/transport.ny";
import "private/resolver.ny";

/** @brief Explicit fixed DNS workers; local Future state never crosses the worker boundary. */

/** @brief Closed immutable endpoint storage, filled before worker release publication. */
pub struct NetResolvedAddresses {
  storage: arc<owned <NetEndpoint>[]>?;
  count: int32;
}

/**
 * @brief Number of initialized endpoints, never greater than the query's max_results.
 * @returns Number of initialized endpoints, never greater than the query's max_results.
 */
pub method(NetResolvedAddresses) Len() -> int32 {
  return self.count;
}

/**
 * @brief Copy an inline endpoint, or InvalidArgument for an out-of-range index.
 * @returns Ok with NetEndpoint on success; Err with NetError on the failure paths described
 *   above.
 */
pub method(NetResolvedAddresses) Get(index: int32) -> Result<NetEndpoint, NetError> {
  if index < 0 || index >= self.count {
    return NetError{kind: NetErrorKind.InvalidArgument};
  }

  let optional: arc<owned <NetEndpoint>[]>? = self.storage;
  if optional == nil {
    return NetError{kind: NetErrorKind.InvalidArgument};
  }

  let storage: arc<owned <NetEndpoint>[]> = optional as arc<owned <NetEndpoint>[]>;

  return storage[index];
}

// claimed is protected by the pool mutex. Only the claiming worker accesses

// host/results; readers acquire done before inspecting the immutable result.

// No local Promise, Future, executor or caller allocator is stored here.
struct NetResolveCell {
  host: string;
  port: int32;
  family: IpFamily;
  max_results: int32;
  options: NetOperationOptions;
  claimed: bool;
  skip: Atomic<int32>;
  done: Atomic<int32>;
  published: Atomic<int32>;
  result: NetResolution;
}

struct NetResolverPool {
  mutex: Mutex;
  changed: ConditionVariable;
  slots: FastArray<arc<NetResolveCell>?>;
  cursor: int32;
  closed: bool;
  wake_read: intptr;
  wake_write: intptr;
  wake_live: bool;
}

method(NetResolverPool) operator drop() -> void {
  if self.wake_live {
    net_core_os_wake_close(self.wake_read, self.wake_write);
  }
}

func net_resolver_is_closed(pool: arc<NetResolverPool>) -> bool {
  pool.mutex.Lock();
  let closed: bool = pool.closed;
  pool.mutex.Unlock();

  return closed;
}

// Only immutable options and atomic publication state cross the worker boundary.

// A previously published cancellation must not cause perpetual ready notifications

// while its physical OS lookup still occupies a slot.
func net_resolver_wait_state(pool: arc<NetResolverPool>, now: uint64) -> NetReadinessState {
  var state: NetReadinessState = NetReadinessState{};
  var occupied: bool = false;
  pool.mutex.Lock();
  state.closed = pool.closed;
  var i: int32 = 0;
  while i < pool.slots.Len() && !state.closed {
    let optional: arc<NetResolveCell>? = pool.slots.Get(i);
    if optional != nil {
      occupied = true;
      var cell: arc<NetResolveCell> = optional as arc<NetResolveCell>;
      if cell.done.Load(MemoryOrder.Acquire) != 0 {
        state.ready = true;
      } else if cell.published.Load(MemoryOrder.Acquire) == 0 {
        if cell.options.cancellation.IsCancelled() || cell.options.deadline.IsExpired(now) {
          state.ready = true;
        }

        let deadline: NetDeadline = cell.options.deadline;
        if deadline.IsFinite()
          && (
            !state.deadline.IsFinite()
              || deadline.RemainingNanoseconds(now) < state.deadline.RemainingNanoseconds(now)
          ) {
          state.deadline = deadline;
        }

        if cell.options.cancellation.CanBeCancelled() {
          state.poll_controls = true;
        }
      }
    }

    i = i + 1;
  }

  pool.mutex.Unlock();
  if !occupied {
    state.ready = true;
  }

  return state;
}

// Kept solely on the owner thread, including after cancellation publication.
struct NetResolvePending {
  slot: int32;
  cell: arc<NetResolveCell>;
  options: NetOperationOptions;
  promise: AsyncPromise<NetResolution>;
  published: bool;
}

struct NetResolveCompletion {
  promise: AsyncPromise<NetResolution>;
  result: NetResolution;
}

/** @brief Local pool owner; worker captures hold only the private shared state. */
pub struct AsyncResolver {
  pool: arc<NetResolverPool>?;
  pending: FastArray<NetResolvePending>;
}

// A running resolver remains charged to its bounded pool until the native lookup actually returns.
func net_resolve_worker(pool: arc<NetResolverPool>) -> void {
  while true {
    var selected: arc<NetResolveCell>? = nil;
    pool.mutex.Lock();
    while selected == nil && !pool.closed {
      let count: int32 = pool.slots.Len();
      var scanned: int32 = 0;
      while scanned < count {
        let index: int32 = (pool.cursor + scanned) % count;
        let optional: arc<NetResolveCell>? = pool.slots.Get(index);
        if optional != nil {
          var cell: arc<NetResolveCell> = optional as arc<NetResolveCell>;
          if !cell.claimed {
            cell.claimed = true;
            selected = cell;
            pool.cursor = (index + 1) % count;
            break;
          }
        }

        scanned = scanned + 1;
      }

      if selected == nil {
        pool.changed.Wait(pool.mutex);
      }
    }

    let closed: bool = pool.closed;
    pool.mutex.Unlock();
    if closed {
      return;
    }

    var cell: arc<NetResolveCell> = selected as arc<NetResolveCell>;
    var result: NetResolution = NetResolution{};
    let checked: Result<Unit, NetError> = NetCheckOperation(cell.options);
    let control_failure: NetError? = checked.get_if<NetError>();
    if control_failure != nil {
      result.error = control_failure;
    } else if cell.skip.Load(MemoryOrder.Acquire) == 0 {
      var addresses: FastArray<NetEndpoint> = FastArray<NetEndpoint>.New();
      let resolved: Result<Unit, NetError> = Resolver.Resolve(
        cell.host,
        cell.port,
        cell.family,
        cell.max_results,
        addresses
      );
      let failure: NetError? = resolved.get_if<NetError>();
      if failure != nil {
        result.error = failure;
      } else if addresses.Len() > 0 {
        let count: int32 = addresses.Len();
        var storage: arc<owned <NetEndpoint>[]> = new arc <NetEndpoint>[count];
        var i: int32 = 0;
        while i < count {
          storage[i] = addresses.Get(i);
          i = i + 1;
        }

        result.addresses = NetResolvedAddresses{storage: storage, count: count};
      }
    } else {
      result.error = NetError{kind: NetErrorKind.Cancelled};
    }

    cell.host = "";
    cell.result = result;
    cell.done.Store(1, MemoryOrder.Release);
    // Do not mutate cell state after release publication, even when Close raced DNS.
    if pool.wake_live {
      net_core_os_wake_signal(pool.wake_write);
    }
  }
}

func net_resolver_stop(pool: arc<NetResolverPool>) -> void {
  pool.mutex.Lock();
  pool.closed = true;
  var i: int32 = 0;
  while i < pool.slots.Len() {
    let optional: arc<NetResolveCell>? = pool.slots.Get(i);
    if optional != nil {
      var cell: arc<NetResolveCell> = optional as arc<NetResolveCell>;
      cell.skip.Store(1, MemoryOrder.Release);
    }

    pool.slots.Set(i, nil);
    i = i + 1;
  }

  pool.changed.NotifyAll();
  pool.mutex.Unlock();
  if pool.wake_live {
    net_core_os_wake_signal(pool.wake_write);
  }
}

/**
 * @brief Create 1..8 fixed workers and worker_count..256 total retained job slots.
 * @returns Pool or a validation/startup/native failure; partial startup stops its workers.
 * @note Each lookup retains at most 1024 hostname bytes and 4096 endpoints. Jobs use the process
 *   heap, never a caller arena. Limits are per pool, not global process limits. On macOS, Linux,
 *   Windows, Android and iOS creation also allocates one resettable notification socket pair.
 */
pub static method(AsyncResolver) New(
  worker_count: int32,
  max_pending: int32
) -> Result<AsyncResolver, NetError> {
  if worker_count < 1 || worker_count > 8 || max_pending < worker_count || max_pending > 256 {
    return NetError{kind: NetErrorKind.InvalidArgument};
  }

  let mutex_result: Result<Mutex, ThreadError> = Mutex.New();
  let mutex_optional: Mutex? = mutex_result.get_if<Mutex>();
  if mutex_optional == nil {
    return NetError{kind: NetErrorKind.System};
  }

  let changed_result: Result<ConditionVariable, ThreadError> = ConditionVariable.New();
  let changed_optional: ConditionVariable? = changed_result.get_if<ConditionVariable>();
  if changed_optional == nil {
    return NetError{kind: NetErrorKind.System};
  }

  var pool: arc<NetResolverPool> = new arc<NetResolverPool>{
    mutex: move(mutex_optional as Mutex),
    changed: move(changed_optional as ConditionVariable),
    slots: FastArray<arc<NetResolveCell>?>.NewWithCapacity(max_pending)
  };
  var i: int32 = 0;
  while i < max_pending {
    pool.slots.Push(nil);
    i = i + 1;
  }

  if net_core_os_events_supported() != 0 {
    var read_handle: intptr = 0 as intptr;
    var write_handle: intptr = 0 as intptr;
    var error: NetNativeError = NetNativeError{};
    if net_core_os_wake_open(&mut read_handle, &mut write_handle, &mut error) != 0 {
      return NetMapNativeError(error);
    }

    pool.wake_read = read_handle;
    pool.wake_write = write_handle;
    pool.wake_live = true;
  }

  i = 0;
  while i < worker_count {
    let started: Result<Thread, ThreadError> = Thread.Spawn(
      lambda[copy pool]() -> void {
        net_resolve_worker(pool);
      }
    );
    if started.IsErr() {
      net_resolver_stop(pool);

      return NetError{kind: NetErrorKind.System};
    }

    // Thread's ordinary language drop detaches its OS record. The closure's ARC
    // retains pool state through its final lookup and condition-variable wait.
    i = i + 1;
  }

  return AsyncResolver{pool: pool, pending: FastArray<NetResolvePending>.NewWithCapacity(max_pending)};
}

/**
 * @brief Transfer the pool; leave the original closed without stopping its workers.
 * @returns The AsyncResolver value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub method(AsyncResolver) operator move() -> AsyncResolver {
  let pool: arc<NetResolverPool>? = self.pool;
  self.pool = nil;

  return AsyncResolver{pool: pool, pending: move(self.pending)};
}

/** @brief Stop admission and local publication without joining blocking resolver calls. */
pub method(AsyncResolver) operator drop() -> void {
  self.Close();
}

/**
 * @brief Number of retained jobs, including cancelled/timed-out jobs still inside OS DNS.
 * @returns Number of retained jobs, including cancelled/timed-out jobs still inside OS DNS.
 * @note Their slots cannot be reused until the worker finishes and Poll retires them.
 */
pub method(AsyncResolver) PendingCount() -> int32 {
  return self.pending.Len();
}

/**
 * @brief Register advisory DNS progress on a NetEventLoop without publishing query results.
 * @param driver Caller-thread event loop; one pending notification per resolver in this driver.
 * @param options Controls for this notification, independent of the individual queries.
 * @returns Local readiness Future or Closed/NotSupported/WouldBlock/registration failure.
 * @note WouldBlock also means no retained queries. Worker completion wakes the driver; queued
 *   query deadlines bound its wait. Query cancellation is observed with a cooperative wait cap of
 *   50ms; this notification's own wakeable token stays active. On readiness, call resolver.Poll(),
 *   inspect query Futures, then rearm if needed. Readiness can be stale/coalesced. Closing the
 *   resolver completes a still-pending notification with Closed when the driver is next polled.
 *   Registrations retain private pool state until retirement; dropping this Future does not cancel
 *   them.
 */
pub method(AsyncResolver) WhenReady(
  driver: ref mut NetEventLoop,
  options: ref NetOperationOptions
) -> Result<AsyncFuture<Result<Unit, NetError>>, NetError> {
  let optional: arc<NetResolverPool>? = self.pool;
  if optional == nil || !NetLoopIsOpen(driver) {
    return NetError{kind: NetErrorKind.Closed};
  }

  let pool: arc<NetResolverPool> = optional as arc<NetResolverPool>;
  if !pool.wake_live {
    return NetError{kind: NetErrorKind.NotSupported};
  }

  if self.pending.IsEmpty() {
    return NetError{kind: NetErrorKind.WouldBlock};
  }

  return NetRegisterResolverReady(
    driver,
    pool.wake_read,
    options,
    lambda[copy pool](now: uint64) -> NetReadinessState {
      return net_resolver_wait_state(pool, now);
    }
  );
}

/**
 * @brief Queue an ASCII hostname/literal with port 0..65535 and max_results in 1..4096.
 * @returns Local Future or an admission/validation/control failure before registration.
 * @note Copies host bytes; borrows end at return. Full pools return WouldBlock. Dropping the
 *   Future alone does not cancel. Drive Poll directly or after WhenReady notification.
 */
pub method(AsyncResolver) ResolveAsync(
  host: ref string,
  port: int32,
  family: IpFamily,
  max_results: int32,
  options: ref NetOperationOptions
) -> Result<AsyncFuture<NetResolution>, NetError> {
  let optional: arc<NetResolverPool>? = self.pool;
  if optional == nil {
    return NetError{kind: NetErrorKind.Closed};
  }

  if port < 0 || port > 65535 {
    return NetError{kind: NetErrorKind.InvalidPort};
  }

  if host.length < 1 || host.length > 1024 || max_results < 1 || max_results > 4096 {
    return NetError{kind: NetErrorKind.InvalidArgument};
  }

  if family != IpFamily.Unspecified && family != IpFamily.V4 && family != IpFamily.V6 {
    return NetError{kind: NetErrorKind.UnsupportedFamily};
  }

  var i: int32 = 0;
  while i < host.length {
    let byte: uint8 = host[i] as uint8;
    if byte == 0u8 || byte > 127u8 {
      return NetError{kind: NetErrorKind.InvalidArgument};
    }

    i = i + 1;
  }

  let checked: Result<Unit, NetError> = NetCheckOperation(options);
  let failure: NetError? = checked.get_if<NetError>();
  if failure != nil {
    return failure as NetError;
  }

  var pool: arc<NetResolverPool> = optional as arc<NetResolverPool>;
  // Only this driver thread admits/retires slots; workers never change occupancy.
  if self.pending.Len() >= pool.slots.Len() {
    return NetError{kind: NetErrorKind.WouldBlock};
  }

  let promise: AsyncPromise<NetResolution> = AsyncPromise<NetResolution>.New();
  let future: AsyncFuture<NetResolution> = promise.FutureHandle();
  let cell: arc<NetResolveCell> = new arc<NetResolveCell>{
    host: copy(host),
    port: port,
    family: family,
    max_results: max_results,
    options: options,
    skip: Atomic<int32>{value: 0},
    done: Atomic<int32>{value: 0},
    published: Atomic<int32>{value: 0}
  };
  pool.mutex.Lock();
  var slot: int32 = 0;
  while slot < pool.slots.Len() {
    if pool.slots.Get(slot) == nil {
      break;
    }

    slot = slot + 1;
  }

  pool.slots.Set(slot, cell);
  pool.changed.NotifyOne();
  pool.mutex.Unlock();
  self.pending.Push(NetResolvePending{slot: slot, cell: cell, options: options, promise: promise});

  return future;
}

/**
 * @brief Nonblocking scan; publish completed/cancelled/timed-out Futures on this thread.
 * @returns Number of newly completed Futures, or Closed for a default/closed resolver.
 * @note Does not pump NetEventLoop or an executor. Call from an outer scheduled loop; do not
 *   busy-spin. Cancellation precedes timeout at each observation. Controls observed before
 *   publication take priority over an unpublished worker result.
 */
pub method(AsyncResolver) Poll() -> Result<int32, NetError> {
  let optional: arc<NetResolverPool>? = self.pool;
  if optional == nil {
    return NetError{kind: NetErrorKind.Closed};
  }

  var pool: arc<NetResolverPool> = optional as arc<NetResolverPool>;
  // Drain before scanning: a later publication either appears in this scan or
  // leaves its notification readable. Late bytes may cause one advisory wake.
  if pool.wake_live {
    var error: NetNativeError = NetNativeError{};
    if net_core_os_notify_drain(pool.wake_read, &mut error) != 0 {
      return NetMapNativeError(error);
    }
  }

  var completions: FastArray<NetResolveCompletion> = FastArray<NetResolveCompletion>.New();
  var i: int32 = self.pending.Len();
  while i > 0 {
    i = i - 1;
    var entry: NetResolvePending = self.pending.Get(i);
    var cell: arc<NetResolveCell> = entry.cell;
    var done: bool = cell.done.Load(MemoryOrder.Acquire) != 0;
    if !entry.published {
      let checked: Result<Unit, NetError> = NetCheckOperation(entry.options);
      let failure: NetError? = checked.get_if<NetError>();
      if failure != nil || done {
        var result: NetResolution = NetResolution{};
        if failure != nil {
          cell.skip.Store(1, MemoryOrder.Release);
          result.error = failure;
          // Unclaimed work can be retired now. Running OS calls still hold the
          // slot until their worker publishes done; cancellation never recycles it.
          pool.mutex.Lock();
          if !cell.claimed {
            cell.claimed = true;
            cell.host = "";
            cell.result = result;
            cell.done.Store(1, MemoryOrder.Release);
            done = true;
          }

          pool.mutex.Unlock();
        } else {
          result = cell.result;
        }

        if completions.IsEmpty() {
          completions = FastArray<NetResolveCompletion>.NewWithCapacity(self.pending.Len());
        }

        completions.Push(NetResolveCompletion{promise: entry.promise, result: result});
        entry.published = true;
        cell.published.Store(1, MemoryOrder.Release);
      }
    }

    if done {
      pool.mutex.Lock();
      pool.slots.Set(entry.slot, nil);
      pool.mutex.Unlock();
      let last: NetResolvePending = self.pending.Pop();
      if i < self.pending.Len() {
        self.pending.Set(i, last);
      }
    } else {
      self.pending.Set(i, entry);
    }
  }

  let count: int32 = completions.Len();
  i = 0;
  while i < count {
    var completion: NetResolveCompletion = completions.Get(i);
    completion.promise.Complete(completion.result);
    i = i + 1;
  }

  return count;
}

/** @brief Close and detach all local work before publishing failures on the caller thread. */
pub method(AsyncResolver) Close() -> void {
  let optional: arc<NetResolverPool>? = self.pool;
  if optional == nil {
    return;
  }

  self.pool = nil;
  var detached: FastArray<NetResolvePending> = move(self.pending);
  var pool: arc<NetResolverPool> = optional as arc<NetResolverPool>;
  net_resolver_stop(pool);
  var i: int32 = 0;
  while i < detached.Len() {
    var entry: NetResolvePending = detached.Get(i);
    if !entry.published {
      entry.promise.Complete(NetResolution{error: NetError{kind: NetErrorKind.Closed}});
    }

    i = i + 1;
  }
}
