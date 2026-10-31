// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

part of NetSocketDriver;

/** @brief Private descriptor state; only public socket owners perform destruction. */

struct NetSocketState {
  handle: intptr;
  live: bool;
}

method(NetSocketState) Take() -> NetSocketState {
  let out: NetSocketState = NetSocketState{handle: self.handle, live: self.live};
  self.handle = 0ip;
  self.live = false;

  return out;
}

method(NetSocketState) Close() -> Result<Unit, NetError> {
  if !self.live {
    return UnitValue();
  }

  let handle: intptr = self.handle;
  self.live = false;
  self.handle = 0ip;
  var error: NetNativeError = NetNativeError{};
  if net_core_os_close(handle, &mut error) != 0 {
    return (error).AsProduct();
  }

  return UnitValue();
}

/**
 * @brief Nanoseconds since the hosted monotonic origin, not Unix time or raw clock ticks.
 * @returns Nanoseconds since the hosted monotonic origin, not Unix time or raw clock ticks.
 */

// Retain the same cancellation token and absolute deadline across wakeups; readiness alone is not completion.
// A synchronous readiness lease borrows its descriptor and retains cancellation
// controls through every wakeup. The socket owner remains responsible for Close.
struct NetSocketWait {
  handle: intptr;
  writable: bool;
  options: NetOperationOptions;
}

method(NetSocketWait) Run() -> Result<Unit, NetError> {
  while true {
    let now: uint64 = Instant.Now().ToDurationSinceEpochish().ToNanoseconds();
    let checked: Result<Unit, NetError> = self.options.Check(now);
    let failure: NetError? = checked.get_if<NetError>();
    if failure != nil {
      return failure as NetError;
    }

    var timeout: int32 = self.options.deadline.PollMilliseconds(now);
    // Flag-only tokens retain cooperative polling; OS-backed tokens use only the deadline budget.
    if self.options.cancellation.CanBeCancelled()
      && !self.options.cancellation.CanWakeWaiters()
      && (timeout<0 || timeout>50) {
      timeout = 50;
    }

    var flag: int32 = 0;
    if self.writable {
      flag = 1;
    }

    var error: NetNativeError = NetNativeError{};
    let wake_handle: intptr = (self.options.cancellation).WakeHandle();
    let result: int32 = net_core_os_wait_wake(self.handle, flag, timeout, wake_handle, &mut error);
    // Recheck both controls even if readiness and cancellation arrive together.
    let active: Result<Unit, NetError> = (self.options).CheckNow();
    let active_error: NetError? = active.get_if<NetError>();
    if active_error != nil {
      return active_error as NetError;
    }

    if result == 0 {
      return UnitValue();
    }

    if result != 15 {
      return (error).AsProduct();
    }
  }

  return NetError{kind: NetErrorKind.System};
}

method(NetSocketState) Endpoint(peer: bool) -> Result<NetEndpoint, NetError> {
  if !self.live {
    return NetError{kind: NetErrorKind.Closed};
  }

  var address: NetNativeAddress = NetNativeAddress{};
  var error: NetNativeError = NetNativeError{};
  var flag: int32 = 0;
  if peer {
    flag = 1;
  }

  if net_core_os_endpoint(self.handle, flag, &mut address, &mut error) != 0 {
    return (error).AsProduct();
  }

  return (address).AsProduct();
}
