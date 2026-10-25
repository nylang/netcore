/** @brief TCP owner factories and synchronous operations over nonblocking sockets. */
part of NetTransport;

pub struct TcpConnection { socket_value:NetSocketState; }
pub struct TcpListener { socket_value:NetSocketState; }
/** @brief Transfer the owner; its move operation invalidates the source. */
pub method(TcpConnection) operator move()->TcpConnection{
  return TcpConnection{socket_value:self.socket_value.Take()};
}
/** @brief Close the owned descriptor during language destruction. */
pub method(TcpConnection) operator drop()->void{self.socket_value.Close();}
/** @brief Transfer a listener without duplicating the descriptor. */
pub method(TcpListener) operator move()->TcpListener{return TcpListener{socket_value:self.socket_value.Take()};}
/** @brief Close a listener exactly once. */
pub method(TcpListener) operator drop()->void{self.socket_value.Close();}
/** @brief Connect using one absolute deadline throughout completion/retry waits. */
pub static method(TcpConnection) Dial(endpoint:ref NetEndpoint,options:ref NetOperationOptions)->Result<TcpConnection,NetError>{
  let checked:Result<Unit,NetError> =net_check_operation(options);
  let failure:NetError?=checked.get_if<NetError>();if failure!=nil{return move(failure as NetError);}
  let ip:IpAddress=endpoint.Address();if ip.Family()==IpFamily.Unspecified{return NetError{kind:NetErrorKind.InvalidAddress};}
  var handle:intptr=0 as intptr;var error:NetNativeError=NetNativeError{};
  if net_core_os_open(net_native_family(ip.Family()),0,&mut handle,&mut error)!=0{return net_native_error(error);}
  var connection:TcpConnection=TcpConnection{socket_value:NetSocketState{handle:handle,live:true}};
  let address:NetNativeAddress=net_native_address(endpoint);
  var result:int32=net_core_os_connect(handle,&address,&mut error);
  while result==15{
    let waited:Result<Unit,NetError> =net_wait_socket(handle,true,options);
    let wait_error:NetError?=waited.get_if<NetError>();if wait_error!=nil{return move(wait_error as NetError);}
    let active:Result<Unit,NetError> =net_check_operation(options);
    let active_error:NetError?=active.get_if<NetError>();if active_error!=nil{return move(active_error as NetError);}
    result=net_core_os_connect_result(handle,&mut error);
  }
  if result!=0{return net_native_error(error);}
  return move(connection);
}
/** @brief Read positive progress or EOF; retry only WouldBlock/interrupted operations. */
pub method(TcpConnection) Read(buffer:ref NetMutableBytes,options:ref NetOperationOptions)->Result<intptr,NetError>{
  if !self.socket_value.live{return NetError{kind:NetErrorKind.Closed};}
  while true{
    let checked:Result<Unit,NetError> =net_check_operation(options);
    let failure:NetError?=checked.get_if<NetError>();if failure!=nil{return failure as NetError;}
    var count:intptr=0 as intptr;var error:NetNativeError=NetNativeError{};
    let result:int32=net_core_os_read(self.socket_value.handle,buffer.Data(),buffer.Len(),&mut count,&mut error);
    if result==0{return count;}if result!=15{return net_native_error(error);}
    let waited:Result<Unit,NetError> =net_wait_socket(self.socket_value.handle,false,options);
    let wait_error:NetError?=waited.get_if<NetError>();if wait_error!=nil{return wait_error as NetError;}
  }
  return NetError{kind:NetErrorKind.System};
}
/** @brief Write partial progress without replaying bytes already accepted by the OS. */
pub method(TcpConnection) Write(buffer:ref NetBytes,options:ref NetOperationOptions)->Result<intptr,NetError>{
  if !self.socket_value.live{return NetError{kind:NetErrorKind.Closed};}
  while true{
    let checked:Result<Unit,NetError> =net_check_operation(options);
    let failure:NetError?=checked.get_if<NetError>();if failure!=nil{return failure as NetError;}
    var count:intptr=0 as intptr;var error:NetNativeError=NetNativeError{};
    let result:int32=net_core_os_write(self.socket_value.handle,buffer.Data(),buffer.Len(),&mut count,&mut error);
    if result==0{return count;}if result!=15{return net_native_error(error);}
    let waited:Result<Unit,NetError> =net_wait_socket(self.socket_value.handle,true,options);
    let wait_error:NetError?=waited.get_if<NetError>();if wait_error!=nil{return wait_error as NetError;}
  }
  return NetError{kind:NetErrorKind.System};
}
/** @brief Configure TCP_NODELAY. */
pub method(TcpConnection) SetNoDelay(enabled:bool)->Result<Unit,NetError>{
  if !self.socket_value.live{return NetError{kind:NetErrorKind.Closed};}
  var flag:int32=0;if enabled{flag=1;}var error:NetNativeError=NetNativeError{};
  if net_core_os_no_delay(self.socket_value.handle,flag,&mut error)!=0{return net_native_error(error);}
  return UnitValue();
}
/** @brief Shut down only the write half of an open connection. */
pub method(TcpConnection) ShutdownWrite()->Result<Unit,NetError>{
  if !self.socket_value.live{return NetError{kind:NetErrorKind.Closed};}
  var error:NetNativeError=NetNativeError{};
  if net_core_os_shutdown_write(self.socket_value.handle,&mut error)!=0{return net_native_error(error);}
  return UnitValue();
}
/** @brief Query the OS-selected local endpoint. */
pub method(TcpConnection) LocalEndpoint()->Result<NetEndpoint,NetError>{return net_socket_endpoint(self.socket_value,false);}
/** @brief Query the connected peer. */
pub method(TcpConnection) RemoteEndpoint()->Result<NetEndpoint,NetError>{return net_socket_endpoint(self.socket_value,true);}
/** @brief Ownership state only; does not test peer liveness. */
pub method(TcpConnection) IsOpen()->bool{return self.socket_value.live;}
/** @brief Close once and retire the descriptor even when close reports an error. */
pub method(TcpConnection) Close()->Result<Unit,NetError>{return self.socket_value.Close();}

/** @brief Bind/listen with cleanup on every failed construction path. */
pub static method(TcpListener) Listen(endpoint:ref NetEndpoint,backlog:int32)->Result<TcpListener,NetError>{
  if backlog<1{return NetError{kind:NetErrorKind.InvalidArgument};}
  let ip:IpAddress=endpoint.Address();if ip.Family()==IpFamily.Unspecified{return NetError{kind:NetErrorKind.InvalidAddress};}
  var handle:intptr=0 as intptr;var error:NetNativeError=NetNativeError{};
  if net_core_os_open(net_native_family(ip.Family()),0,&mut handle,&mut error)!=0{return net_native_error(error);}
  var listener:TcpListener=TcpListener{socket_value:NetSocketState{handle:handle,live:true}};
  let address:NetNativeAddress=net_native_address(endpoint);
  if net_core_os_bind(handle,&address,1,&mut error)!=0{return net_native_error(error);}
  if net_core_os_listen(handle,backlog,&mut error)!=0{return net_native_error(error);}
  return move(listener);
}
/** @brief Accept one owned connection without exposing its native descriptor. */
pub method(TcpListener) Accept(options:ref NetOperationOptions)->Result<TcpConnection,NetError>{
  if !self.socket_value.live{return NetError{kind:NetErrorKind.Closed};}
  while true{
    let checked:Result<Unit,NetError> =net_check_operation(options);
    let failure:NetError?=checked.get_if<NetError>();if failure!=nil{return move(failure as NetError);}
    var handle:intptr=0 as intptr;var error:NetNativeError=NetNativeError{};
    let result:int32=net_core_os_accept(self.socket_value.handle,&mut handle,&mut error);
    if result==0{return TcpConnection{socket_value:NetSocketState{handle:handle,live:true}};}
    if result!=15{return net_native_error(error);}
    let waited:Result<Unit,NetError> =net_wait_socket(self.socket_value.handle,false,options);
    let wait_error:NetError?=waited.get_if<NetError>();if wait_error!=nil{return move(wait_error as NetError);}
  }
  return NetError{kind:NetErrorKind.System};
}
/** @brief Query the bound address and actual ephemeral port. */
pub method(TcpListener) LocalEndpoint()->Result<NetEndpoint,NetError>{return net_socket_endpoint(self.socket_value,false);}
/** @brief Whether the listener owns a descriptor. */
pub method(TcpListener) IsOpen()->bool{return self.socket_value.live;}
/** @brief Explicitly close once; drop after this is inert. */
pub method(TcpListener) Close()->Result<Unit,NetError>{return self.socket_value.Close();}

/** @brief Perform one nonblocking read; never wait after stale readiness. */
pub method(TcpConnection) TryRead(buffer:ref NetMutableBytes)->Result<intptr,NetError> {
  if !self.socket_value.live{return NetError{kind:NetErrorKind.Closed};}
  var count:intptr=0 as intptr;
  var error:NetNativeError=NetNativeError{};
  if net_core_os_read(self.socket_value.handle,buffer.Data(),buffer.Len(),&mut count,&mut error)!=0 {
    return net_native_error(error);
  }
  return count;
}
/** @brief Perform one nonblocking write; accepted bytes are never replayed. */
pub method(TcpConnection) TryWrite(buffer:ref NetBytes)->Result<intptr,NetError> {
  if !self.socket_value.live{return NetError{kind:NetErrorKind.Closed};}
  var count:intptr=0 as intptr;
  var error:NetNativeError=NetNativeError{};
  if net_core_os_write(self.socket_value.handle,buffer.Data(),buffer.Len(),&mut count,&mut error)!=0 {
    return net_native_error(error);
  }
  return count;
}
/** @brief Accept once without waiting, preserving the sole-owner construction path. */
pub method(TcpListener) TryAccept()->Result<TcpConnection,NetError> {
  if !self.socket_value.live{return NetError{kind:NetErrorKind.Closed};}
  var handle:intptr=0 as intptr;
  var error:NetNativeError=NetNativeError{};
  if net_core_os_accept(self.socket_value.handle,&mut handle,&mut error)!=0 {
    return net_native_error(error);
  }
  return TcpConnection{socket_value:NetSocketState{handle:handle,live:true}};
}
