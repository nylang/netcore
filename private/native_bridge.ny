/** @brief Private fixed-width pointer-only C ABI; no native struct crosses by value. */
part of NetTransport;

struct NetNativeAddress { family: int32; port: int32; scope_id: uint32; bytes: <uint8>[16]; }
struct NetNativeError { kind: int32; native_code: int32; }
struct NetNativeWait {
  handle:intptr;wake_handle:intptr;writable:int32;ready:int32;kind:int32;native_code:int32;
}
@extern("C") func net_core_os_events_supported()->int32;
@extern("C") func net_core_os_duplicate(handle:intptr,out:*mut intptr,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_wait_many(items:*mut NetNativeWait,count:int32,milliseconds:int32,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_open(family:int32,datagram:int32,out:*mut intptr,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_close(handle:intptr,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_bind(handle:intptr,address:*const NetNativeAddress,listener:int32,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_listen(handle:intptr,backlog:int32,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_connect(handle:intptr,address:*const NetNativeAddress,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_connect_result(handle:intptr,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_accept(handle:intptr,out:*mut intptr,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_wake_open(read_handle:*mut intptr,write_handle:*mut intptr,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_wake_close(read_handle:intptr,write_handle:intptr)->void;
@extern("C") func net_core_os_wake_signal(write_handle:intptr)->void;
@extern("C") func net_core_os_notify_drain(read_handle:intptr,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_wait_wake(handle:intptr,writable:int32,milliseconds:int32,wake_handle:intptr,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_wait(handle:intptr,writable:int32,milliseconds:int32,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_endpoint(handle:intptr,peer:int32,out:*mut NetNativeAddress,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_read(handle:intptr,data:*mut uint8,size:intptr,out:*mut intptr,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_write(handle:intptr,data:*const uint8,size:intptr,out:*mut intptr,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_send_to(handle:intptr,address:*const NetNativeAddress,data:*const uint8,size:intptr,out:*mut intptr,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_receive_from(handle:intptr,data:*mut uint8,size:intptr,out:*mut intptr,sender:*mut NetNativeAddress,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_shutdown_write(handle:intptr,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_no_delay(handle:intptr,enabled:int32,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_resolve(host:*const uint8,length:intptr,port:int32,family:int32,out:*mut NetNativeAddress,capacity:int32,count:*mut int32,error:*mut NetNativeError)->int32;
@extern("C") func net_core_os_scope(name:*const uint8,length:intptr,out:*mut uint32,error:*mut NetNativeError)->int32;

func net_native_error(error:ref NetNativeError)->NetError {
  var kind:NetErrorKind=NetErrorKind.System;
  if error.kind==1{kind=NetErrorKind.InvalidArgument;}
  else if error.kind==2{kind=NetErrorKind.InvalidAddress;}
  else if error.kind==3{kind=NetErrorKind.InvalidPort;}
  else if error.kind==4{kind=NetErrorKind.UnsupportedFamily;}
  else if error.kind==5{kind=NetErrorKind.NameNotFound;}
  else if error.kind==6{kind=NetErrorKind.PermissionDenied;}
  else if error.kind==7{kind=NetErrorKind.AddressInUse;}
  else if error.kind==8{kind=NetErrorKind.AddressUnavailable;}
  else if error.kind==9{kind=NetErrorKind.ConnectionRefused;}
  else if error.kind==10{kind=NetErrorKind.ConnectionReset;}
  else if error.kind==11{kind=NetErrorKind.ConnectionAborted;}
  else if error.kind==12{kind=NetErrorKind.NotConnected;}
  else if error.kind==13{kind=NetErrorKind.NetworkUnreachable;}
  else if error.kind==14{kind=NetErrorKind.HostUnreachable;}
  else if error.kind==15{kind=NetErrorKind.WouldBlock;}
  else if error.kind==16{kind=NetErrorKind.TimedOut;}
  else if error.kind==17{kind=NetErrorKind.Cancelled;}
  else if error.kind==18{kind=NetErrorKind.Closed;}
  else if error.kind==19{kind=NetErrorKind.MessageTooLarge;}
  else if error.kind==20{kind=NetErrorKind.NotSupported;}
  return NetError{kind:kind,native_code:error.native_code};
}
func net_native_family(family:IpFamily)->int32 {
  if family==IpFamily.V4{return 4;}
  if family==IpFamily.V6{return 6;}
  return 0;
}
func net_native_address(endpoint:ref NetEndpoint)->NetNativeAddress {
  let address:IpAddress=endpoint.Address();
  var out:NetNativeAddress=NetNativeAddress{family:net_native_family(address.Family()),port:endpoint.Port() as int32,scope_id:address.ScopeId()};
  var count:int32=0;if out.family==4{count=4;}else if out.family==6{count=16;}
  var i:int32=0;while i<count{let item:Result<uint8,NetError> =address.ByteAt(i);out.bytes[i]=(item.get_if<uint8>()) as uint8;i=i+1;}
  return out;
}
func net_product_endpoint(address:ref NetNativeAddress)->NetEndpoint {
  var ip:IpAddress=IpAddress{};
  if address.family==4{ip=IpAddress.V4(address.bytes[0],address.bytes[1],address.bytes[2],address.bytes[3]);}
  else{ip=IpAddress.V6(address.bytes,address.scope_id);}
  let parsed:Result<NetEndpoint,NetError> =NetEndpoint.New(ip,address.port);
  return (parsed.get_if<NetEndpoint>()) as NetEndpoint;
}
