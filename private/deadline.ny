/** @brief Monotonic budgets with explicit unlimited/finite state and saturating arithmetic. */
part of NetFoundation;

pub struct NetDeadline { finite: bool; expires_ns: uint64; }
/** @brief Unlimited budget; zero-filled values have this meaning too. */
pub static method(NetDeadline) Never() -> NetDeadline { return NetDeadline{}; }
/** @brief Absolute monotonic deadline. */
pub static method(NetDeadline) At(nanoseconds: uint64) -> NetDeadline {
  return NetDeadline{finite:true,expires_ns:nanoseconds};
}
/** @brief Saturating addition preserves the deadline rather than wrapping it into the past. */
pub static method(NetDeadline) After(now_ns: uint64,timeout_ns: uint64) -> NetDeadline {
  let limit: uint64 = ~(0 as uint64);
  if timeout_ns > limit-now_ns { return NetDeadline{finite:true,expires_ns:limit}; }
  return NetDeadline{finite:true,expires_ns:now_ns+timeout_ns};
}
/** @brief Whether the budget has a finite endpoint. */
pub method(NetDeadline) IsFinite() -> bool { return self.finite; }
/** @brief Equality to the endpoint is already expired. */
pub method(NetDeadline) IsExpired(now_ns: uint64) -> bool {
  return self.finite && now_ns >= self.expires_ns;
}
/** @brief Non-wrapping remaining budget, with uint64 max for unlimited. */
pub method(NetDeadline) RemainingNanoseconds(now_ns: uint64) -> uint64 {
  if !self.finite { return ~(0 as uint64); }
  if now_ns >= self.expires_ns { return 0 as uint64; }
  return self.expires_ns-now_ns;
}
/** @brief Round positive sub-millisecond budgets up; cap native wait arguments safely. */
pub method(NetDeadline) PollMilliseconds(now_ns: uint64) -> int32 {
  if !self.finite { return -1; }
  if now_ns >= self.expires_ns { return 0; }
  let remaining: uint64 = self.expires_ns-now_ns;
  var milliseconds: uint64 = remaining/(1000000 as uint64);
  if remaining%(1000000 as uint64) != 0 { milliseconds=milliseconds+(1 as uint64); }
  if milliseconds > (2147483647 as uint64) { return 2147483647; }
  return milliseconds as int32;
}
