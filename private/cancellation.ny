// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

module NetOperationControls;
import "stdlib:stdlib.ny";
import "interface/foundation.ni";
import "interface/transport.ni";
import "interface/async_transport.ni";
import "interface/async_resolver.ni";
import "private/foundation.ny";
import "private/native_abi.ni";
import "private/native_bridge.ny";

/** @brief Copyable shared cancellation with ARC lifetime and atomic publication. */

struct NetCancelCell {
  cancelled: Atomic<int32>;
  wake_read: intptr;
  wake_write: intptr;
  wake_live: bool;
}

method(NetCancelCell) operator drop() -> void {
  if self.wake_live {
    self.wake_live = false;
    net_core_os_wake_close(self.wake_read, self.wake_write);
  }
}

/**
 * @brief Shared sticky cancellation flag; copies share an ARC-owned atomic cell.
 * @note No reset or callbacks. New is flag-only; NewWakeable owns an OS wake channel.
 */
pub struct NetCancellation {
  cell: arc<NetCancelCell>?;
}

/**
 * @brief Allocate one shared atomic cancellation cell, initially not cancelled.
 * @returns The NetCancellation value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub static method(NetCancellation) New() -> NetCancellation {
  let cell: arc<NetCancelCell> = new arc<NetCancelCell>{cancelled: Atomic<int32>{value: 0}};

  return NetCancellation{cell: cell};
}

/**
 * @brief Allocate an OS-backed token shared by copies; last drop closes its wake channel.
 * @returns Token, OS resource failure, or NotSupported on other hosts; never silently polls.
 * @note Cancel wakes all current/future readiness waits without periodic polling.
 */
pub static method(NetCancellation) NewWakeable() -> Result<NetCancellation, NetError> {
  var read_handle: intptr = 0 as intptr;
  var write_handle: intptr = 0 as intptr;
  var error: NetNativeError = NetNativeError{};
  if net_core_os_wake_open(&mut read_handle, &mut write_handle, &mut error) != 0 {
    return NetMapNativeError(error);
  }

  let cell: arc<NetCancelCell> = new arc<NetCancelCell>{
    cancelled: Atomic<int32>{value: 0},
    wake_read: read_handle,
    wake_write: write_handle,
    wake_live: true
  };

  return NetCancellation{cell: cell};
}

/**
 * @brief Whether cancellation can wake native waits; false for New/None tokens.
 * @returns Whether cancellation can wake native waits; false for New/None tokens.
 */
pub method(NetCancellation) CanWakeWaiters() -> bool {
  let optional: arc<NetCancelCell>? = self.cell;
  if optional == nil {
    return false;
  }

  let cell: arc<NetCancelCell> = optional as arc<NetCancelCell>;

  return cell.wake_live;
}

/**
 * @brief Borrow a cancellation wake descriptor without transferring its ownership.
 * @returns The read handle for a live wakeable token, or the existing absent-handle sentinel.
 *   Retain the token throughout the wait.
 */
pub func NetCancellationWakeHandle(token: ref NetCancellation) -> intptr {
  let optional: arc<NetCancelCell>? = token.cell;
  if optional == nil {
    return -1 as intptr;
  }

  let cell: arc<NetCancelCell> = optional as arc<NetCancelCell>;
  if !cell.wake_live {
    return -1 as intptr;
  }

  return cell.wake_read;
}

/**
 * @brief Allocation-free token that cannot be cancelled; also the default value.
 * @returns The NetCancellation value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub static method(NetCancellation) None() -> NetCancellation {
  return NetCancellation{};
}

/**
 * @brief Whether this token owns a cancellation cell (even before it is cancelled).
 * @returns Whether this token owns a cancellation cell (even before it is cancelled).
 */
pub method(NetCancellation) CanBeCancelled() -> bool {
  return self.cell != nil;
}

/** @brief Set a sticky flag shared by every copy; None is inert. */
pub method(NetCancellation) Cancel() -> void {
  let optional: arc<NetCancelCell>? = self.cell;
  if optional == nil {
    return;
  }

  var cell: arc<NetCancelCell> = optional as arc<NetCancelCell>;
  let previous: int32 = cell.cancelled.Exchange(1, MemoryOrder.AcqRel);
  if previous == 0 && cell.wake_live {
    net_core_os_wake_signal(cell.wake_write);
  }
}

/**
 * @brief Observe cancellation with acquire ordering; None returns false.
 * @returns Observe cancellation with acquire ordering; None returns false.
 */
pub method(NetCancellation) IsCancelled() -> bool {
  let optional: arc<NetCancelCell>? = self.cell;
  if optional == nil {
    return false;
  }

  var cell: arc<NetCancelCell> = optional as arc<NetCancelCell>;

  return cell.cancelled.Load(MemoryOrder.Acquire) != 0;
}

/**
 * @brief Check cancellation first, then deadline; returns Ok(Unit), Cancelled or TimedOut.
 * @returns Ok with Unit on success; Err with NetError on the failure paths described above.
 */
pub method(NetOperationOptions) Check(now_ns: uint64) -> Result<Unit, NetError> {
  if self.cancellation.IsCancelled() {
    return NetError{kind: NetErrorKind.Cancelled};
  }

  if self.deadline.IsExpired(now_ns) {
    return NetError{kind: NetErrorKind.TimedOut};
  }

  return UnitValue();
}

/** @brief Monotonic operation admission and shared cancellation wake access. */

/** @brief Hosted monotonic clock matching the transport deadline origin. */
pub struct NetClock {
  pad: uint8;
}

/**
 * @brief Check the original cancellation token and absolute deadline against the monotonic clock.
 * @returns Unit on admission, otherwise the original cancellation or timeout error.
 */
pub func NetCheckOperation(options: ref NetOperationOptions) -> Result<Unit, NetError> {
  return options.Check(NetClock.NowNanoseconds());
}

pub static method(NetClock) NowNanoseconds() -> uint64 {
  let instant: Instant = Instant.Now();
  let elapsed: Duration = instant.ToDurationSinceEpochish();

  return elapsed.ToNanoseconds();
}
