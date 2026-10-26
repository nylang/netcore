/** @brief Copyable shared cancellation with ARC lifetime and atomic publication. */
part of NetTransport;

struct NetCancelCell {
  cancelled: Atomic<int32>;
  wake_read: intptr;
  wake_write: intptr;
  wake_live: bool;
}
method(NetCancelCell) operator drop() -> void {
  if self.wake_live {
    self.wake_live=false;
    net_core_os_wake_close(self.wake_read,self.wake_write);
  }
}
pub struct NetCancellation { cell: arc<NetCancelCell>?; }

/** @brief Allocate one zero-initialized cancellation cell. */
pub static method(NetCancellation) New() -> NetCancellation {
  let cell: arc<NetCancelCell> = new arc<NetCancelCell>{cancelled:Atomic<int32>{value:0}};
  return NetCancellation{cell:cell};
}
/** @brief Create a shared cross-platform cancellation cell with an owned OS wake channel. */
pub static method(NetCancellation) NewWakeable() -> Result<NetCancellation,NetError> {
  var read_handle:intptr=0 as intptr;
  var write_handle:intptr=0 as intptr;
  var error:NetNativeError=NetNativeError{};
  if net_core_os_wake_open(&mut read_handle,&mut write_handle,&mut error)!=0 {
    return net_native_error(error);
  }
  let cell:arc<NetCancelCell> = new arc<NetCancelCell>{
    cancelled:Atomic<int32>{value:0},wake_read:read_handle,wake_write:write_handle,wake_live:true
  };
  return NetCancellation{cell:cell};
}
/** @brief Whether this token can interrupt native readiness waits immediately. */
pub method(NetCancellation) CanWakeWaiters() -> bool {
  let optional:arc<NetCancelCell>?=self.cell;
  if optional==nil{return false;}
  let cell:arc<NetCancelCell> = optional as arc<NetCancelCell>;
  return cell.wake_live;
}
func net_cancellation_wake_handle(token:ref NetCancellation)->intptr {
  let optional:arc<NetCancelCell>?=token.cell;
  if optional==nil{return -1 as intptr;}
  let cell:arc<NetCancelCell> = optional as arc<NetCancelCell>;
  if !cell.wake_live{return -1 as intptr;}
  return cell.wake_read;
}
/** @brief No allocation and no cancellation ability. */
pub static method(NetCancellation) None() -> NetCancellation { return NetCancellation{}; }
/** @brief Whether the token has a shared cancellation cell. */
pub method(NetCancellation) CanBeCancelled() -> bool { return self.cell != nil; }
/** @brief Set a sticky flag shared by every copy; None is inert. */
pub method(NetCancellation) Cancel() -> void {
  let optional: arc<NetCancelCell>? = self.cell;
  if optional == nil { return; }
  var cell: arc<NetCancelCell> = optional as arc<NetCancelCell>;
  let previous:int32=cell.cancelled.Exchange(1,MemoryOrder.AcqRel);
  if previous==0&&cell.wake_live { net_core_os_wake_signal(cell.wake_write); }
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
