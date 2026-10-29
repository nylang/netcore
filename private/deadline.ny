// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

module NetDeadlines;
import "stdlib:stdlib.ny";
import "interface/foundation.ni";
import "interface/transport.ni";
import "interface/async_transport.ni";
import "interface/async_resolver.ni";

/** @brief Monotonic budgets with explicit unlimited/finite state and saturating arithmetic. */

/**
 * @brief Absolute deadline in caller-supplied monotonic nanoseconds; default is unlimited.
 * @note All calls must use the same clock origin. No wall clock or global clock is read.
 */
pub struct NetDeadline {
  finite: bool;
  expires_ns: uint64;
}

/**
 * @brief Unlimited deadline; no allocation.
 * @returns The NetDeadline value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub static method(NetDeadline) Never() -> NetDeadline {
  return NetDeadline{};
}

/**
 * @brief Finite absolute monotonic deadline; zero expires at monotonic zero.
 * @returns The NetDeadline value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub static method(NetDeadline) At(nanoseconds: uint64) -> NetDeadline {
  return NetDeadline{finite: true, expires_ns: nanoseconds};
}

/**
 * @brief Add timeout to now with saturation at uint64 max; zero expires immediately.
 * @returns The NetDeadline value described above, retaining the documented ownership and
 *   default-state semantics.
 */
pub static method(NetDeadline) After(now_ns: uint64, timeout_ns: uint64) -> NetDeadline {
  let limit: uint64 = ~(0 as uint64);
  if timeout_ns > limit - now_ns {
    return NetDeadline{finite: true, expires_ns: limit};
  }

  return NetDeadline{finite: true, expires_ns: now_ns + timeout_ns};
}

/**
 * @brief Whether a finite deadline exists (including an already expired deadline).
 * @returns Whether a finite deadline exists (including an already expired deadline).
 */
pub method(NetDeadline) IsFinite() -> bool {
  return self.finite;
}

/**
 * @brief Whether a finite deadline is at or before now_ns.
 * @returns Whether a finite deadline is at or before now_ns.
 */
pub method(NetDeadline) IsExpired(now_ns: uint64) -> bool {
  return self.finite && now_ns >= self.expires_ns;
}

/**
 * @brief Remaining nanoseconds, zero if expired, uint64 max if unlimited.
 * @returns Remaining nanoseconds, zero if expired, uint64 max if unlimited.
 */
pub method(NetDeadline) RemainingNanoseconds(now_ns: uint64) -> uint64 {
  if !self.finite {
    return ~(0 as uint64);
  }

  if now_ns >= self.expires_ns {
    return 0 as uint64;
  }

  return self.expires_ns - now_ns;
}

/**
 * @brief OS wait budget: -1 unlimited, 0 expired, otherwise ceil milliseconds clamped to int32
 *   max.
 * @returns OS wait budget: -1 unlimited, 0 expired, otherwise ceil milliseconds clamped to int32
 *   max.
 */
pub method(NetDeadline) PollMilliseconds(now_ns: uint64) -> int32 {
  if !self.finite {
    return -1;
  }

  if now_ns >= self.expires_ns {
    return 0;
  }

  let remaining: uint64 = self.expires_ns - now_ns;
  var milliseconds: uint64 = remaining / (1000000 as uint64);
  if remaining % (1000000 as uint64) != 0 {
    milliseconds = milliseconds + (1 as uint64);
  }

  if milliseconds >(2147483647 as uint64) {
    return 2147483647;
  }

  return milliseconds as int32;
}
