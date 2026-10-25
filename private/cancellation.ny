/** @brief Copyable shared cancellation with ARC lifetime and atomic publication. */
part of NetFoundation;

struct NetCancelCell { cancelled: Atomic<int32>; }
pub struct NetCancellation { cell: arc<NetCancelCell>?; }

/** @brief Allocate one zero-initialized cancellation cell. */
pub static method(NetCancellation) New() -> NetCancellation {
  let cell: arc<NetCancelCell> = new arc<NetCancelCell>{cancelled:Atomic<int32>{value:0}};
  return NetCancellation{cell:cell};
}
/** @brief No allocation and no cancellation ability. */
pub static method(NetCancellation) None() -> NetCancellation { return NetCancellation{}; }
/** @brief Set a sticky flag shared by every copy; None is inert. */
pub method(NetCancellation) Cancel() -> void {
  let optional: arc<NetCancelCell>? = self.cell;
  if optional == nil { return; }
  var cell: arc<NetCancelCell> = optional as arc<NetCancelCell>;
  cell.cancelled.Store(1,MemoryOrder.Release);
}
/** @brief Observe the sticky flag with acquire ordering. */
pub method(NetCancellation) IsCancelled() -> bool {
  let optional: arc<NetCancelCell>? = self.cell;
  if optional == nil { return false; }
  var cell: arc<NetCancelCell> = optional as arc<NetCancelCell>;
  return cell.cancelled.Load(MemoryOrder.Acquire) != 0;
}
/** @brief Cancellation has deterministic priority when both conditions are met. */
pub method(NetOperationOptions) Check(now_ns: uint64) -> Result<Unit, NetError> {
  if self.cancellation.IsCancelled() { return NetError{kind:NetErrorKind.Cancelled}; }
  if self.deadline.IsExpired(now_ns) { return NetError{kind:NetErrorKind.TimedOut}; }
  return UnitValue();
}
