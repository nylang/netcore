/** @brief Synchronous OS name lookup; owned results stay in the caller's allocation domain. */
part of NetTransport;

pub struct Resolver { pad:uint8; }
/** @brief Resolve within an explicit result bound; preserve output on failure. */
pub static method(Resolver) Resolve(host:ref string,port:int32,family:IpFamily,max_results:int32,output:ref mut FastArray<NetEndpoint>)->Result<Unit,NetError>{
  if port<0||port>65535{return NetError{kind:NetErrorKind.InvalidPort};}
  if max_results<1||max_results>4096||host.length<1||host.length>1024{return NetError{kind:NetErrorKind.InvalidArgument};}
  if family!=IpFamily.Unspecified&&family!=IpFamily.V4&&family!=IpFamily.V6{return NetError{kind:NetErrorKind.UnsupportedFamily};}
  let parsed:Result<IpAddress,NetError> =IpAddress.Parse(host);
  let literal:IpAddress?=parsed.get_if<IpAddress>();
  if literal!=nil{
    let ip:IpAddress=literal as IpAddress;
    if family!=IpFamily.Unspecified&&family!=ip.Family(){return NetError{kind:NetErrorKind.UnsupportedFamily};}
    let endpoint:Result<NetEndpoint,NetError> =NetEndpoint.New(ip,port);
    output.Reset();output.Push((endpoint.get_if<NetEndpoint>()) as NetEndpoint);
    return UnitValue();
  }
  var numeric:bool=true;var i:int32=0;
  while i<host.length{
    let ch:int32=host[i] as int32;
    if ch==58||ch==37||ch==91||ch==93{return NetError{kind:NetErrorKind.InvalidAddress};}
    if ch!=46&&(ch<48||ch>57){numeric=false;}
    i=i+1;
  }
  if numeric{return NetError{kind:NetErrorKind.InvalidAddress};}
  var records:owned <NetNativeAddress>[]=new <NetNativeAddress>[max_results];
  var count:int32=0;var error:NetNativeError=NetNativeError{};
  if net_core_os_resolve(host.data as *const uint8,host.length as intptr,port,net_native_family(family),&mut records[0],max_results,&mut count,&mut error)!=0{return net_native_error(error);}
  output.Reset();output.Reserve(count);i=0;
  while i<count{let record:NetNativeAddress=records[i];output.Push(net_product_endpoint(record));i=i+1;}
  return UnitValue();
}
/** @brief Query the OS interface table; no hostname or service lookup occurs. */
pub static method(Resolver) InterfaceIndex(name:ref string)->Result<uint32,NetError>{
  var value:uint32=0;var error:NetNativeError=NetNativeError{};
  if net_core_os_scope(name.data as *const uint8,name.length as intptr,&mut value,&mut error)!=0{return net_native_error(error);}
  return value;
}
