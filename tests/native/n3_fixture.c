/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 tangxiangjiang
 * Test-only getaddrinfo interposition. Compile the OS adapter with
 * -DNET_CORE_TEST_DNS; production builds never link this file.
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#define NC_TEST_CALL WSAAPI
#else
#include <netdb.h>
#include <pthread.h>
#include <time.h>
#include <dirent.h>
#include <sys/resource.h>
#define NC_TEST_CALL
#endif
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include "../../private/native/net_core_os.h"

#ifdef _WIN32
static SRWLOCK gate_mutex=SRWLOCK_INIT;
static CONDITION_VARIABLE gate_changed=CONDITION_VARIABLE_INIT;
#define gate_lock() AcquireSRWLockExclusive(&gate_mutex)
#define gate_unlock() ReleaseSRWLockExclusive(&gate_mutex)
#define gate_broadcast() WakeAllConditionVariable(&gate_changed)
#else
static pthread_mutex_t gate_mutex=PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t gate_changed=PTHREAD_COND_INITIALIZER;
#define gate_lock() pthread_mutex_lock(&gate_mutex)
#define gate_unlock() pthread_mutex_unlock(&gate_mutex)
#define gate_broadcast() pthread_cond_broadcast(&gate_changed)
#endif
static int gate_open;
static _Atomic int active;
static _Atomic int entered;
static _Atomic int peak;
#ifdef _WIN32
static int refuse_wake;
int32_t net_core_test_real_wake_open(intptr_t *,intptr_t *,nc_error *);
int32_t net_core_os_wake_open(intptr_t *reader,intptr_t *writer,nc_error *error) {
  if (!refuse_wake) return net_core_test_real_wake_open(reader,writer,error);
  *reader=-1; *writer=-1;
  error->kind=NC_SYSTEM; error->native_code=WSAEMFILE;
  return NC_SYSTEM;
}
int32_t net_core_test_fd_exhaust_begin(void) { refuse_wake=1; return 0; }
int32_t net_core_test_fd_exhaust_end(void) { refuse_wake=0; return 0; }
#else
static struct rlimit saved_fd_limit;
int32_t net_core_test_fd_exhaust_begin(void) {
  if (getrlimit(RLIMIT_NOFILE,&saved_fd_limit)) return -1;
  struct rlimit limit=saved_fd_limit;
  limit.rlim_cur=0;
  return setrlimit(RLIMIT_NOFILE,&limit);
}
int32_t net_core_test_fd_exhaust_end(void) { return setrlimit(RLIMIT_NOFILE,&saved_fd_limit); }
#endif
int32_t net_core_test_failed_connect_kind(void) {
#ifdef __linux__
  return NC_REFUSED;
#else
  return NC_UNAVAILABLE;
#endif
}

int32_t net_core_test_dns_reset(void) {
  if (atomic_load(&active)) return -1;
  gate_lock();
  gate_open=0;
  atomic_store(&entered,0);
  atomic_store(&peak,0);
  gate_unlock();
  return 0;
}
int32_t net_core_test_dns_entered(void) { return atomic_load(&entered); }
int32_t net_core_test_dns_active(void) { return atomic_load(&active); }
int32_t net_core_test_dns_peak(void) { return atomic_load(&peak); }
void net_core_test_dns_release(void) {
  gate_lock();
  gate_open=1;
  gate_broadcast();
  gate_unlock();
}
int NC_TEST_CALL net_core_test_getaddrinfo(const char *name,const char *service,
                             const struct addrinfo *hints,struct addrinfo **out) {
  int gated=name && !strcmp(name,"net-core-gated.invalid");
  int failed=name && !strcmp(name,"net-core-failed.invalid");
  if (!gated && !failed) return getaddrinfo(name,service,hints,out);
  *out=NULL;
  if (hints && (hints->ai_flags&AI_NUMERICHOST)) return EAI_NONAME;
  if (failed) return EAI_NONAME;
  int running=atomic_fetch_add(&active,1)+1;
  int previous=atomic_load(&peak);
  while (running>previous && !atomic_compare_exchange_weak(&peak,&previous,running)) {}
  atomic_fetch_add(&entered,1);
  int status=0;
#ifdef _WIN32
  ULONGLONG until=GetTickCount64()+10000;
  gate_lock();
  while (!gate_open && !status) {
    ULONGLONG now=GetTickCount64();
    if (now>=until) { status=1; break; }
    if (!SleepConditionVariableSRW(&gate_changed,&gate_mutex,(DWORD)(until-now),0)) status=1;
  }
#else
  struct timespec until;
  clock_gettime(CLOCK_REALTIME,&until);
  until.tv_sec+=10;
  gate_lock();
  while (!gate_open && !status) status=pthread_cond_timedwait(&gate_changed,&gate_mutex,&until);
#endif
  gate_unlock();
  atomic_fetch_sub(&active,1);
  if (status) return EAI_AGAIN;
  return getaddrinfo("127.0.0.1",service,hints,out);
}
#ifdef _WIN32
static INIT_ONCE resource_once=INIT_ONCE_STATIC_INIT;
static void net_core_test_wsa_cleanup(void) { WSACleanup(); }
static BOOL CALLBACK net_core_test_prepare_resources(PINIT_ONCE once,PVOID parameter,PVOID *context) {
  (void)once; (void)parameter; (void)context;
  WSADATA data;
  if (WSAStartup(MAKEWORD(2,2),&data)) return FALSE;
  /* Keep one fixture-owned WinSock reference until process exit. Provider/DNS
   * lazy initialization is outside the per-operation resource recovery count. */
  /* First-use NLS sorting retains one Windows-owned registry key. Prime the
   * exact subsystem before measuring; never subtract an allowed leak count. */
  if (!CompareStringEx(LOCALE_NAME_INVARIANT,0,L"a",1,L"b",1,NULL,NULL,0)) {
    WSACleanup(); return FALSE;
  }
  nc_error error; intptr_t reader=-1,writer=-1,duplicate=-1;
  if (net_core_os_wake_open(&reader,&writer,&error)) { WSACleanup(); return FALSE; }
  int code=net_core_os_duplicate(reader,&duplicate,&error);
  if (!code) net_core_os_close(duplicate,&error);
  net_core_os_wake_close(reader,writer);
  struct addrinfo hints; memset(&hints,0,sizeof(hints));
  hints.ai_family=AF_INET; hints.ai_socktype=SOCK_STREAM;
  struct addrinfo *result=NULL;
  int resolved=getaddrinfo("127.0.0.1",NULL,&hints,&result);
  if (!resolved) freeaddrinfo(result);
  if (code || resolved || atexit(net_core_test_wsa_cleanup)) { WSACleanup(); return FALSE; }
  return TRUE;
}
#endif
int32_t net_core_test_fd_count(void) {
#ifdef _WIN32
  if (!InitOnceExecuteOnce(&resource_once,net_core_test_prepare_resources,NULL,NULL)) return -1;
  DWORD count=0;
  return GetProcessHandleCount(GetCurrentProcess(),&count) ? (int32_t)count : -1;
#else
  DIR *directory=opendir("/dev/fd");
  if (!directory) return -1;
  int count=0;
  struct dirent *entry;
  while ((entry=readdir(directory))) {
    if (!strcmp(entry->d_name,".") || !strcmp(entry->d_name,"..")) continue;
    count++;
  }
  closedir(directory);
  return count;
#endif
}
void net_core_test_resource_report(int32_t expected) {
  fprintf(stderr,"resource handles: expected=%d actual=%d\n",expected,net_core_test_fd_count());
}
int32_t net_core_test_native_direction(void) {
  intptr_t input=-1,output=-1;
  nc_error error;
  if (net_core_os_wake_open(&input,&output,&error)) return -1;
  nc_wait_item rows[2]={{input,-1,0,0,0,0},{input,-1,1,0,0,0}};
  int code=net_core_os_wait_many(rows,2,0,&error);
  int okay=!code && !rows[0].ready && rows[1].ready && !rows[1].kind;
  net_core_os_wake_close(input,output);
  return okay ? 0 : -2;
}

int32_t net_core_test_empty_udp_readiness(void) {
  nc_error error; intptr_t tx=-1,rx=-1,n=0;
  nc_address bind_address={0},destination;
  bind_address.family=4;bind_address.bytes[0]=127;bind_address.bytes[3]=1;
  if(net_core_os_open(4,1,&tx,&error)||net_core_os_open(4,1,&rx,&error))return -1;
  if(net_core_os_bind(rx,&bind_address,0,&error)||net_core_os_endpoint(rx,0,&destination,&error))return -2;
  if(net_core_os_send_to(tx,&destination,NULL,0,&n,&error))return -3;
  nc_wait_item row={rx,-1,0,0,0,0};
  if(net_core_os_wait_many(&row,1,10,&error))return -4;
  int ready=row.ready;
  nc_address sender;
  int received=net_core_os_receive_from(rx,NULL,0,&n,&sender,&error);
  net_core_os_close(rx,&error);net_core_os_close(tx,&error);
  return (!received&&n==0) ? ready : -5;
}

/* Exercise more read interests than WinSock's default FD_SETSIZE of 64,
 * including simultaneous transport/cancellation fanout. Stay below the usual
 * macOS descriptor limit; the production driver admits up to 256 operations. */
int32_t net_core_test_wait_large_snapshot(void) {
  intptr_t readers[72],writers[72];
  nc_wait_item rows[72];
  nc_error error;
  int opened=0,result=-1;
  memset(rows,0,sizeof(rows));
  for (int i=0;i<72;i++) {
    if (net_core_os_wake_open(&readers[i],&writers[i],&error)) goto cleanup;
    opened++;
    rows[i].handle=readers[i]; rows[i].wake_handle=writers[i];
    /* Odd rows cancel, even rows receive a transport readiness event. */
    net_core_os_wake_signal((i&1) ? readers[i] : writers[i]);
  }
  for (int attempt=0;attempt<100;attempt++) {
    if (net_core_os_wait_many(rows,72,10,&error)) goto cleanup;
    int complete=0;
    for (int i=0;i<72;i++) {
      if (!rows[i].ready) continue;
      if (rows[i].kind!=((i&1) ? NC_CANCELLED : NC_OK)) goto cleanup;
      complete++;
    }
    if (complete==72) { result=0; break; }
  }
cleanup:
  for (int i=0;i<opened;i++) net_core_os_wake_close(readers[i],writers[i]);
  return result;
}
