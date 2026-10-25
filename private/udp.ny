/** @brief UDP preserves message boundaries; truncation is an error, never silent success. */
part of NetTransport;

pub struct UdpSocket { socket_value:NetSocketState; }
/** @brief Transfer one datagram socket owner. */
pub method(UdpSocket) operator move()->UdpSocket{return UdpSocket{socket_value:self.socket_value.Take()};}
/** @brief Close the owned descriptor during language destruction. */
pub method(UdpSocket) operator drop()->void{self.socket_value.Close();}
/** @brief Bind without sharing the address; failures drop the temporary owner. */
pub static method(UdpSocket) Bind(endpoint:ref NetEndpoint)->Result<UdpSocket,NetError>{
  let ip:IpAddress=endpoint.Address();if ip.Family()==IpFamily.Unspecified{return NetError{kind:NetErrorKind.InvalidAddress};}
  var handle:intptr=0 as intptr;var error:NetNativeError=NetNativeError{};
  if net_core_os_open(net_native_family(ip.Family()),1,&mut handle,&mut error)!=0{return net_native_error(error);}
  var socket:UdpSocket=UdpSocket{socket_value:NetSocketState{handle:handle,live:true}};
  let address:NetNativeAddress=net_native_address(endpoint);
  if net_core_os_bind(handle,&address,0,&mut error)!=0{return net_native_error(error);}
  return move(socket);
}
/** @brief Send one complete message, including an empty datagram. */
pub method(UdpSocket) SendTo(endpoint:ref NetEndpoint,buffer:ref NetBytes,options:ref NetOperationOptions)->Result<intptr,NetError>{
  if !self.socket_value.live{return NetError{kind:NetErrorKind.Closed};}
  let ip:IpAddress=endpoint.Address();if ip.Family()==IpFamily.Unspecified{return NetError{kind:NetErrorKind.InvalidAddress};}
  let address:NetNativeAddress=net_native_address(endpoint);
  while true{
    let checked:Result<Unit,NetError> =net_check_operation(options);
    let failure:NetError?=checked.get_if<NetError>();if failure!=nil{return failure as NetError;}
    var count:intptr=0 as intptr;var error:NetNativeError=NetNativeError{};
    let result:int32=net_core_os_send_to(self.socket_value.handle,&address,buffer.Data(),buffer.Len(),&mut count,&mut error);
    if result==0{return count;}if result!=15{return net_native_error(error);}
    let waited:Result<Unit,NetError> =net_wait_socket(self.socket_value.handle,true,options);
    let wait_error:NetError?=waited.get_if<NetError>();if wait_error!=nil{return wait_error as NetError;}
  }
  return NetError{kind:NetErrorKind.System};
}
/** @brief Receive one message; an oversized message is consumed and reported as MessageTooLarge. */
pub method(UdpSocket) ReceiveFrom(buffer:ref NetMutableBytes,options:ref NetOperationOptions)->Result<NetDatagram,NetError>{
  if !self.socket_value.live{return NetError{kind:NetErrorKind.Closed};}
  while true{
    let checked:Result<Unit,NetError> =net_check_operation(options);
    let failure:NetError?=checked.get_if<NetError>();if failure!=nil{return failure as NetError;}
    var count:intptr=0 as intptr;var sender:NetNativeAddress=NetNativeAddress{};var error:NetNativeError=NetNativeError{};
    let result:int32=net_core_os_receive_from(self.socket_value.handle,buffer.Data(),buffer.Len(),&mut count,&mut sender,&mut error);
    if result==0{return NetDatagram{bytes_read:count,sender:net_product_endpoint(sender)};}
    if result!=15{return net_native_error(error);}
    let waited:Result<Unit,NetError> =net_wait_socket(self.socket_value.handle,false,options);
    let wait_error:NetError?=waited.get_if<NetError>();if wait_error!=nil{return wait_error as NetError;}
  }
  return NetError{kind:NetErrorKind.System};
}
/** @brief Query the bound endpoint. */
pub method(UdpSocket) LocalEndpoint()->Result<NetEndpoint,NetError>{return net_socket_endpoint(self.socket_value,false);}
/** @brief Whether the socket owns a descriptor. */
pub method(UdpSocket) IsOpen()->bool{return self.socket_value.live;}
/** @brief Close exactly once. */
pub method(UdpSocket) Close()->Result<Unit,NetError>{return self.socket_value.Close();}
