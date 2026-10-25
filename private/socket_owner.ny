/** @brief Private descriptor state; only public socket owners perform destruction. */
part of NetTransport;

struct NetSocketState { handle: intptr; live: bool; }
method(NetSocketState) Take() -> NetSocketState {
  let out:NetSocketState=NetSocketState{handle:self.handle,live:self.live};
  self.handle=0 as intptr;self.live=false;return out;
}
method(NetSocketState) Close()->Result<Unit,NetError>{
  if !self.live{return UnitValue();}
  let handle:intptr=self.handle;self.live=false;self.handle=0 as intptr;
  var error:NetNativeError=NetNativeError{};
  if net_core_os_close(handle,&mut error)!=0{return net_native_error(error);}
  return UnitValue();
}

pub struct NetClock { pad:uint8; }
/** @brief Convert monotonic ticks through the public time API, never as raw nanoseconds. */
pub static method(NetClock) NowNanoseconds()->uint64{
  let instant:Instant=Instant.Now();
  let elapsed:Duration=instant.ToDurationSinceEpochish();
  return elapsed.ToNanoseconds();
}
func net_check_operation(options:ref NetOperationOptions)->Result<Unit,NetError>{
  return options.Check(NetClock.NowNanoseconds());
}
func net_wait_socket(handle:intptr,writable:bool,options:ref NetOperationOptions)->Result<Unit,NetError>{
  while true{
    let now:uint64=NetClock.NowNanoseconds();
    let checked:Result<Unit,NetError> =options.Check(now);
    let failure:NetError?=checked.get_if<NetError>();if failure!=nil{return failure as NetError;}
    var timeout:int32=options.deadline.PollMilliseconds(now);
    // Flag-only tokens retain cooperative polling; OS-backed tokens use only the deadline budget.
    if options.cancellation.CanBeCancelled()&&!options.cancellation.CanWakeWaiters()&&(timeout<0||timeout>50){timeout=50;}
    var flag:int32=0;if writable{flag=1;}
    var error:NetNativeError=NetNativeError{};
    let wake_handle:intptr=net_cancellation_wake_handle(options.cancellation);
    let result:int32=net_core_os_wait_wake(handle,flag,timeout,wake_handle,&mut error);
    // Recheck both controls even if readiness and cancellation arrive together.
    let active:Result<Unit,NetError> =net_check_operation(options);
    let active_error:NetError?=active.get_if<NetError>();
    if active_error!=nil{return active_error as NetError;}
    if result==0{return UnitValue();}
    if result!=15{return net_native_error(error);}
  }
  return NetError{kind:NetErrorKind.System};
}
func net_socket_endpoint(owner:ref NetSocketState,peer:bool)->Result<NetEndpoint,NetError>{
  if !owner.live{return NetError{kind:NetErrorKind.Closed};}
  var address:NetNativeAddress=NetNativeAddress{};var error:NetNativeError=NetNativeError{};
  var flag:int32=0;if peer{flag=1;}
  if net_core_os_endpoint(owner.handle,flag,&mut address,&mut error)!=0{return net_native_error(error);}
  return net_product_endpoint(address);
}
