/* SPDX-License-Identifier: MIT
 * Test-only getaddrinfo interposition. Compile the OS adapter with
 * -Dgetaddrinfo=net_core_test_getaddrinfo; production builds never link this file.
 */
#include <netdb.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <dirent.h>
#include <errno.h>
#include <sys/resource.h>
#include "../../private/native/net_core_os.h"

static pthread_mutex_t gate_mutex=PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t gate_changed=PTHREAD_COND_INITIALIZER;
static int gate_open;
static _Atomic int active;
static _Atomic int entered;
static _Atomic int peak;
static struct rlimit saved_fd_limit;
int32_t net_core_test_fd_exhaust_begin(void) {
  if (getrlimit(RLIMIT_NOFILE,&saved_fd_limit)) return -1;
  struct rlimit limit=saved_fd_limit;
  limit.rlim_cur=0;
  return setrlimit(RLIMIT_NOFILE,&limit);
}
int32_t net_core_test_fd_exhaust_end(void) { return setrlimit(RLIMIT_NOFILE,&saved_fd_limit); }

int32_t net_core_test_dns_reset(void) {
  if (atomic_load(&active)) return -1;
  pthread_mutex_lock(&gate_mutex);
  gate_open=0;
  atomic_store(&entered,0);
  atomic_store(&peak,0);
  pthread_mutex_unlock(&gate_mutex);
  return 0;
}
int32_t net_core_test_dns_entered(void) { return atomic_load(&entered); }
int32_t net_core_test_dns_active(void) { return atomic_load(&active); }
int32_t net_core_test_dns_peak(void) { return atomic_load(&peak); }
void net_core_test_dns_release(void) {
  pthread_mutex_lock(&gate_mutex);
  gate_open=1;
  pthread_cond_broadcast(&gate_changed);
  pthread_mutex_unlock(&gate_mutex);
}
int net_core_test_getaddrinfo(const char *name,const char *service,
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
  struct timespec until;
  clock_gettime(CLOCK_REALTIME,&until);
  until.tv_sec+=10; /* An assertion failure must not leave an unbounded fixture wait. */
  pthread_mutex_lock(&gate_mutex);
  int status=0;
  while (!gate_open && !status) status=pthread_cond_timedwait(&gate_changed,&gate_mutex,&until);
  pthread_mutex_unlock(&gate_mutex);
  atomic_fetch_sub(&active,1);
  if (status) return EAI_AGAIN;
  return getaddrinfo("127.0.0.1",service,hints,out);
}
int32_t net_core_test_fd_count(void) {
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
