/* SPDX-License-Identifier: MIT
 * Thin BSD sockets/WinSock adapter. Protocols and operation policy stay in Nyra.
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#ifdef _WIN32
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0600
#endif
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <netioapi.h>
typedef SOCKET nc_socket;
typedef int nc_socklen;
#define NC_INVALID INVALID_SOCKET
#define nc_last_error() WSAGetLastError()
#define nc_raw_close(s) closesocket(s)
#define NC_ERR(name) WSA##name
#else
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <net/if.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <errno.h>
typedef int nc_socket;
typedef socklen_t nc_socklen;
#define NC_INVALID (-1)
#define nc_last_error() errno
#define nc_raw_close(s) close(s)
#define NC_ERR(name) name
#endif
#include "net_core_os.h"
#include <limits.h>
#include <string.h>

static int32_t nc_fail(nc_error *out, int32_t kind, int code) {
  if (out) { out->kind=kind; out->native_code=code; }
  return kind;
}
static int32_t nc_ok(nc_error *out) { return nc_fail(out, NC_OK, 0); }
static int32_t nc_system(nc_error *out, int code) {
  int32_t kind=NC_SYSTEM;
  if (code==NC_ERR(EINTR) || code==NC_ERR(EWOULDBLOCK) || code==NC_ERR(EINPROGRESS) || code==NC_ERR(EALREADY)) kind=NC_WOULD_BLOCK;
#ifndef _WIN32
  else if (code==EAGAIN) kind=NC_WOULD_BLOCK;
  else if (code==EPIPE) kind=NC_RESET;
  else if (code==EBADF) kind=NC_CLOSED;
#endif
  else if (code==NC_ERR(EACCES)) kind=NC_PERMISSION;
  else if (code==NC_ERR(EADDRINUSE)) kind=NC_IN_USE;
  else if (code==NC_ERR(EADDRNOTAVAIL)) kind=NC_UNAVAILABLE;
  else if (code==NC_ERR(ECONNREFUSED)) kind=NC_REFUSED;
  else if (code==NC_ERR(ECONNRESET)) kind=NC_RESET;
  else if (code==NC_ERR(ECONNABORTED)) kind=NC_ABORTED;
  else if (code==NC_ERR(ENOTCONN)) kind=NC_NOT_CONNECTED;
  else if (code==NC_ERR(ENETUNREACH)) kind=NC_NETWORK;
  else if (code==NC_ERR(EHOSTUNREACH)) kind=NC_HOST;
  else if (code==NC_ERR(ETIMEDOUT)) kind=NC_TIMEOUT;
  else if (code==NC_ERR(EMSGSIZE)) kind=NC_MESSAGE_SIZE;
  else if (code==NC_ERR(EAFNOSUPPORT)) kind=NC_FAMILY;
  else if (code==NC_ERR(EOPNOTSUPP)) kind=NC_UNSUPPORTED;
  else if (code==NC_ERR(ENOTSOCK)) kind=NC_CLOSED;
  else if (code==NC_ERR(EINVAL)) kind=NC_ARGUMENT;
  return nc_fail(out,kind,code);
}
static int32_t nc_acquire(nc_error *error) {
#ifdef _WIN32
  WSADATA data;
  int code=WSAStartup(MAKEWORD(2,2),&data);
  if (code) return nc_system(error,code);
#else
  (void)error;
#endif
  return NC_OK;
}
static void nc_release(void) {
#ifdef _WIN32
  WSACleanup();
#endif
}
static int nc_family(int32_t value) { return value==4 ? AF_INET : value==6 ? AF_INET6 : AF_UNSPEC; }
static int nc_configure(nc_socket socket_value) {
#ifdef _WIN32
  u_long enabled=1;
  if (ioctlsocket(socket_value,FIONBIO,&enabled)==SOCKET_ERROR) return nc_last_error();
  if (!SetHandleInformation((HANDLE)socket_value,HANDLE_FLAG_INHERIT,0)) return (int)GetLastError();
#else
  int flags=fcntl(socket_value,F_GETFL,0);
  if (flags<0 || fcntl(socket_value,F_SETFL,flags|O_NONBLOCK)<0) return nc_last_error();
  flags=fcntl(socket_value,F_GETFD,0);
  if (flags<0 || fcntl(socket_value,F_SETFD,flags|FD_CLOEXEC)<0) return nc_last_error();
#ifdef SO_NOSIGPIPE
  int enabled=1;
  if (setsockopt(socket_value,SOL_SOCKET,SO_NOSIGPIPE,&enabled,sizeof(enabled))<0) return nc_last_error();
#endif
#endif
  return 0;
}
static int32_t nc_pack(const nc_address *address, struct sockaddr_storage *storage, nc_socklen *length, nc_error *error) {
  if (!address || address->port<0 || address->port>65535) return nc_fail(error,NC_ARGUMENT,0);
  memset(storage,0,sizeof(*storage));
  if (address->family==4) {
    struct sockaddr_in *value=(struct sockaddr_in *)storage;
    value->sin_family=AF_INET;
#ifdef __APPLE__
    value->sin_len=sizeof(*value);
#endif
    value->sin_port=htons((uint16_t)address->port);
    memcpy(&value->sin_addr,address->bytes,4);
    *length=sizeof(*value);
  } else if (address->family==6) {
    struct sockaddr_in6 *value=(struct sockaddr_in6 *)storage;
    value->sin6_family=AF_INET6;
#ifdef __APPLE__
    value->sin6_len=sizeof(*value);
#endif
    value->sin6_port=htons((uint16_t)address->port);
    value->sin6_scope_id=address->scope_id;
    memcpy(&value->sin6_addr,address->bytes,16);
    *length=sizeof(*value);
  } else return nc_fail(error,NC_FAMILY,0);
  return NC_OK;
}
static int32_t nc_unpack(const struct sockaddr *value, size_t size, nc_address *out, nc_error *error) {
  memset(out,0,sizeof(*out));
  if (value->sa_family==AF_INET && size>=sizeof(struct sockaddr_in)) {
    const struct sockaddr_in *v=(const struct sockaddr_in *)value;
    out->family=4; out->port=ntohs(v->sin_port); memcpy(out->bytes,&v->sin_addr,4);
  } else if (value->sa_family==AF_INET6 && size>=sizeof(struct sockaddr_in6)) {
    const struct sockaddr_in6 *v=(const struct sockaddr_in6 *)value;
    out->family=6; out->port=ntohs(v->sin6_port); out->scope_id=v->sin6_scope_id; memcpy(out->bytes,&v->sin6_addr,16);
  } else return nc_fail(error,NC_FAMILY,0);
  return nc_ok(error);
}
int32_t net_core_os_open(int32_t family, int32_t datagram, intptr_t *out, nc_error *error) {
  *out=-1;
  int af=nc_family(family);
  if (af==AF_UNSPEC) return nc_fail(error,NC_FAMILY,0);
  if (nc_acquire(error)!=NC_OK) return error->kind;
  int type=datagram ? SOCK_DGRAM : SOCK_STREAM;
#ifdef SOCK_CLOEXEC
  type|=SOCK_CLOEXEC;
#endif
#ifdef SOCK_NONBLOCK
  type|=SOCK_NONBLOCK;
#endif
  nc_socket value=socket(af,type,0);
  if (value==NC_INVALID) { int code=nc_last_error(); nc_release(); return nc_system(error,code); }
  int code=nc_configure(value);
  if (!code && af==AF_INET6) {
    int enabled=1;
    if (setsockopt(value,IPPROTO_IPV6,IPV6_V6ONLY,(const char *)&enabled,sizeof(enabled))<0) code=nc_last_error();
  }
  if (code) { nc_raw_close(value); nc_release(); return nc_system(error,code); }
  *out=(intptr_t)value;
  return nc_ok(error);
}
int32_t net_core_os_close(intptr_t handle, nc_error *error) {
  /* Never retry close(EINTR): the number may already have been reused. */
  int result=nc_raw_close((nc_socket)handle);
  int code=result<0 ? nc_last_error() : 0;
  nc_release();
  return code ? nc_system(error,code) : nc_ok(error);
}
int32_t net_core_os_bind(intptr_t handle,const nc_address *address,int32_t listener,nc_error *error) {
  struct sockaddr_storage storage; nc_socklen length;
  if (nc_pack(address,&storage,&length,error)!=NC_OK) return error->kind;
  int enabled=1;
#ifdef _WIN32
  (void)listener;
  if (setsockopt((nc_socket)handle,SOL_SOCKET,SO_EXCLUSIVEADDRUSE,(const char *)&enabled,sizeof(enabled))<0) return nc_system(error,nc_last_error());
#else
  if (listener && setsockopt((nc_socket)handle,SOL_SOCKET,SO_REUSEADDR,&enabled,sizeof(enabled))<0) return nc_system(error,nc_last_error());
#endif
  if (bind((nc_socket)handle,(struct sockaddr *)&storage,length)<0) return nc_system(error,nc_last_error());
  return nc_ok(error);
}
int32_t net_core_os_listen(intptr_t handle,int32_t backlog,nc_error *error) {
  if (backlog<1) return nc_fail(error,NC_ARGUMENT,0);
  if (listen((nc_socket)handle,backlog)<0) return nc_system(error,nc_last_error());
  return nc_ok(error);
}
int32_t net_core_os_connect(intptr_t handle,const nc_address *address,nc_error *error) {
  struct sockaddr_storage storage; nc_socklen length;
  if (nc_pack(address,&storage,&length,error)!=NC_OK) return error->kind;
  if (connect((nc_socket)handle,(struct sockaddr *)&storage,length)<0) {
    int code=nc_last_error();
    if (code!=NC_ERR(EISCONN)) return nc_system(error,code);
  }
  return nc_ok(error);
}
int32_t net_core_os_connect_result(intptr_t handle,nc_error *error) {
  int code=0; nc_socklen size=sizeof(code);
  if (getsockopt((nc_socket)handle,SOL_SOCKET,SO_ERROR,(char *)&code,&size)<0) return nc_system(error,nc_last_error());
  return code ? nc_system(error,code) : nc_ok(error);
}
int32_t net_core_os_accept(intptr_t handle,intptr_t *out,nc_error *error) {
  *out=-1;
  if (nc_acquire(error)!=NC_OK) return error->kind;
#ifdef __linux__
  nc_socket value=accept4((nc_socket)handle,NULL,NULL,SOCK_NONBLOCK|SOCK_CLOEXEC);
#else
  nc_socket value=accept((nc_socket)handle,NULL,NULL);
#endif
  if (value==NC_INVALID) { int code=nc_last_error(); nc_release(); return nc_system(error,code); }
  int code=nc_configure(value);
  if (code) { nc_raw_close(value); nc_release(); return nc_system(error,code); }
  *out=(intptr_t)value;
  return nc_ok(error);
}
int32_t net_core_os_wait(intptr_t handle,int32_t writable,int32_t milliseconds,nc_error *error) {
  if (milliseconds < -1) return nc_fail(error,NC_ARGUMENT,0);
#ifdef _WIN32
  fd_set target,exception; FD_ZERO(&target); FD_ZERO(&exception);
  FD_SET((nc_socket)handle,&target); FD_SET((nc_socket)handle,&exception);
  struct timeval budget; budget.tv_sec=milliseconds/1000; budget.tv_usec=(milliseconds%1000)*1000;
  int ready=select(0,writable ? NULL : &target,writable ? &target : NULL,&exception,milliseconds<0 ? NULL : &budget);
  if (ready<0) return nc_system(error,nc_last_error());
#else
  struct pollfd item; memset(&item,0,sizeof(item)); item.fd=(int)handle; item.events=writable ? POLLOUT : POLLIN;
  int ready=poll(&item,1,milliseconds);
  if (ready<0) return nc_system(error,nc_last_error());
  if (ready>0 && (item.revents&POLLNVAL)) return nc_fail(error,NC_CLOSED,EBADF);
#endif
  if (ready==0) return nc_fail(error,NC_WOULD_BLOCK,0);
  /* Error/hangup is readiness too; the following operation/SO_ERROR reports it. */
  return nc_ok(error);
}
int32_t net_core_os_endpoint(intptr_t handle,int32_t peer,nc_address *out,nc_error *error) {
  struct sockaddr_storage address; nc_socklen size=sizeof(address);
  int result=peer ? getpeername((nc_socket)handle,(struct sockaddr *)&address,&size) : getsockname((nc_socket)handle,(struct sockaddr *)&address,&size);
  if (result<0) return nc_system(error,nc_last_error());
  return nc_unpack((struct sockaddr *)&address,(size_t)size,out,error);
}
#ifndef _WIN32
static int nc_send_flags(void) {
#ifdef MSG_NOSIGNAL
  return MSG_NOSIGNAL;
#else
  return 0;
#endif
}

#endif
int32_t net_core_os_read(intptr_t handle,uint8_t *data,intptr_t size,intptr_t *out,nc_error *error) {
  *out=0;
  if (size<0 || (!data && size)) return nc_fail(error,NC_ARGUMENT,0);
  if (!size) return nc_ok(error);
#ifdef _WIN32
  int result=recv((nc_socket)handle,(char *)data,size>INT_MAX ? INT_MAX : (int)size,0);
#else
  ssize_t result=recv((nc_socket)handle,data,(size_t)size,0);
#endif
  if (result<0) return nc_system(error,nc_last_error());
  *out=(intptr_t)result;
  return nc_ok(error);
}
int32_t net_core_os_write(intptr_t handle,const uint8_t *data,intptr_t size,intptr_t *out,nc_error *error) {
  *out=0;
  if (size<0 || (!data && size)) return nc_fail(error,NC_ARGUMENT,0);
  if (!size) return nc_ok(error);
#ifdef _WIN32
  int result=send((nc_socket)handle,(const char *)data,size>INT_MAX ? INT_MAX : (int)size,0);
#else
  ssize_t result=send((nc_socket)handle,data,(size_t)size,nc_send_flags());
#endif
  if (result<0) return nc_system(error,nc_last_error());
  *out=(intptr_t)result;
  return nc_ok(error);
}
int32_t net_core_os_send_to(intptr_t handle,const nc_address *address,const uint8_t *data,intptr_t size,intptr_t *out,nc_error *error) {
  *out=0;
  if (size<0 || (!data && size)) return nc_fail(error,NC_ARGUMENT,0);
  if (size>INT_MAX) return nc_fail(error,NC_MESSAGE_SIZE,0);
  struct sockaddr_storage storage; nc_socklen length;
  if (nc_pack(address,&storage,&length,error)!=NC_OK) return error->kind;
  const uint8_t empty=0;
#ifdef _WIN32
  int result=sendto((nc_socket)handle,(const char *)(data ? data : &empty),(int)size,0,(struct sockaddr *)&storage,length);
#else
  ssize_t result=sendto((nc_socket)handle,data ? data : &empty,(size_t)size,nc_send_flags(),(struct sockaddr *)&storage,length);
#endif
  if (result<0) return nc_system(error,nc_last_error());
  if ((intptr_t)result!=size) return nc_fail(error,NC_MESSAGE_SIZE,0);
  *out=(intptr_t)result;
  return nc_ok(error);
}
int32_t net_core_os_receive_from(intptr_t handle,uint8_t *data,intptr_t size,intptr_t *out,nc_address *sender,nc_error *error) {
  *out=0;
  if (size<0 || (!data && size)) return nc_fail(error,NC_ARGUMENT,0);
  if (size>INT_MAX) return nc_fail(error,NC_MESSAGE_SIZE,0);
  struct sockaddr_storage address; memset(&address,0,sizeof(address));
  uint8_t empty=0;
#ifdef _WIN32
  nc_socklen address_size=sizeof(address);
  int result=recvfrom((nc_socket)handle,(char *)(data ? data : &empty),(int)size,0,(struct sockaddr *)&address,&address_size);
  if (result<0) return nc_system(error,nc_last_error());
#else
  struct iovec buffer; buffer.iov_base=data ? data : &empty; buffer.iov_len=(size_t)size;
  struct msghdr message; memset(&message,0,sizeof(message));
  message.msg_name=&address; message.msg_namelen=sizeof(address); message.msg_iov=&buffer; message.msg_iovlen=1;
  ssize_t result=recvmsg((nc_socket)handle,&message,0);
  if (result<0) return nc_system(error,nc_last_error());
  if (message.msg_flags&MSG_TRUNC) return nc_fail(error,NC_MESSAGE_SIZE,EMSGSIZE);
  nc_socklen address_size=message.msg_namelen;
#endif
  if (nc_unpack((struct sockaddr *)&address,(size_t)address_size,sender,error)!=NC_OK) return error->kind;
  *out=(intptr_t)result;
  return nc_ok(error);
}
int32_t net_core_os_shutdown_write(intptr_t handle,nc_error *error) {
#ifdef _WIN32
  int how=SD_SEND;
#else
  int how=SHUT_WR;
#endif
  if (shutdown((nc_socket)handle,how)<0) return nc_system(error,nc_last_error());
  return nc_ok(error);
}
int32_t net_core_os_no_delay(intptr_t handle,int32_t enabled,nc_error *error) {
  int value=enabled!=0;
  if (setsockopt((nc_socket)handle,IPPROTO_TCP,TCP_NODELAY,(const char *)&value,sizeof(value))<0) return nc_system(error,nc_last_error());
  return nc_ok(error);
}
static int nc_ascii_name(const uint8_t *text,intptr_t length,char *out,size_t capacity) {
  if (!text || length<1 || (uintptr_t)length>=capacity) return 0;
  for (intptr_t i=0;i<length;i++) { if (!text[i] || text[i]>127) return 0; out[i]=(char)text[i]; }
  out[length]=0;
  return 1;
}
int32_t net_core_os_resolve(const uint8_t *host,intptr_t length,int32_t port,int32_t family,nc_address *out,int32_t capacity,int32_t *count,nc_error *error) {
  *count=0;
  char name[1025];
  if (!nc_ascii_name(host,length,name,sizeof(name)) || !out || capacity<1 || capacity>4096) return nc_fail(error,NC_ARGUMENT,0);
  if (port<0 || port>65535) return nc_fail(error,NC_PORT,0);
  if (family!=0 && family!=4 && family!=6) return nc_fail(error,NC_FAMILY,0);
  if (nc_acquire(error)!=NC_OK) return error->kind;
  struct addrinfo hints; memset(&hints,0,sizeof(hints)); hints.ai_family=AF_UNSPEC; hints.ai_socktype=SOCK_STREAM;
  /* Nyra handles canonical numeric literals first. Block OS-only octal/hex/
     shortened numeric spellings without issuing a second DNS request. */
  hints.ai_flags=AI_NUMERICHOST;
  struct addrinfo *numeric=NULL;
  int numeric_code=getaddrinfo(name,NULL,&hints,&numeric);
  if (!numeric_code) { freeaddrinfo(numeric); nc_release(); return nc_fail(error,NC_ADDRESS,0); }
  hints.ai_flags=0; hints.ai_family=nc_family(family);
  struct addrinfo *list=NULL;
  int code=getaddrinfo(name,NULL,&hints,&list);
  if (code) {
    int32_t kind=NC_SYSTEM; int native=code;
#ifdef EAI_NONAME
    if (code==EAI_NONAME) kind=NC_NAME;
#endif
#ifdef EAI_NODATA
    if (code==EAI_NODATA) kind=NC_NAME;
#endif
#ifdef EAI_AGAIN
    if (code==EAI_AGAIN) kind=NC_WOULD_BLOCK;
#endif
#ifdef EAI_FAMILY
    if (code==EAI_FAMILY) kind=NC_FAMILY;
#endif
#ifdef EAI_SYSTEM
    if (code==EAI_SYSTEM) { native=nc_last_error(); nc_release(); return nc_system(error,native); }
#endif
    nc_release(); return nc_fail(error,kind,native);
  }
  for (struct addrinfo *item=list;item;item=item->ai_next) {
    nc_address value; nc_error ignored;
    if (nc_unpack(item->ai_addr,(size_t)item->ai_addrlen,&value,&ignored)!=NC_OK) continue;
    value.port=port;
    int duplicate=0;
    for (int32_t i=0;i<*count;i++) if (!memcmp(&out[i],&value,sizeof(value))) { duplicate=1; break; }
    if (duplicate) continue;
    if (*count==capacity) { freeaddrinfo(list); nc_release(); *count=0; return nc_fail(error,NC_MESSAGE_SIZE,0); }
    out[*count]=value; *count+=1;
  }
  freeaddrinfo(list); nc_release();
  if (!*count) return nc_fail(error,NC_NAME,0);
  return nc_ok(error);
}
int32_t net_core_os_scope(const uint8_t *name,intptr_t length,uint32_t *out,nc_error *error) {
  *out=0;
  char text[256];
  if (!nc_ascii_name(name,length,text,sizeof(text))) return nc_fail(error,NC_ARGUMENT,0);
  if (nc_acquire(error)!=NC_OK) return error->kind;
#ifdef _WIN32
  NET_LUID luid;
  NET_IFINDEX index=0;
  NETIO_STATUS code=ConvertInterfaceNameToLuidA(text,&luid);
  if (code==NO_ERROR) code=ConvertInterfaceLuidToIndex(&luid,&index);
  nc_release();
  if (code!=NO_ERROR || !index) return nc_fail(error,NC_ADDRESS,(int)code);
#else
  errno=0;
  unsigned int index=if_nametoindex(text);
  int code=index ? 0 : errno;
  nc_release();
  if (!index) return nc_fail(error,NC_ADDRESS,code);
#endif
  *out=(uint32_t)index;
  return nc_ok(error);
}
