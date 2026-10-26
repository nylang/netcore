/* SPDX-License-Identifier: MIT
 * Host-native checks for runners unable to execute the Nyra SDK binary. */
#include <stdint.h>
#include <stdio.h>
#include "../../private/native/net_core_os.h"

int32_t net_core_test_native_direction(void);
int32_t net_core_test_empty_udp_readiness(void);
int32_t net_core_test_wait_large_snapshot(void);
int32_t net_core_test_fd_count(void);

int main(void) {
  if (!net_core_os_events_supported()) return 1;
  int baseline=net_core_test_fd_count();
  if (baseline<0) return 2;
  puts("BEGIN native direction/UDP/fanout/resource smoke");
  if (net_core_test_native_direction()!=0) return 3;
  if (net_core_test_empty_udp_readiness()!=1) return 4;
  if (net_core_test_wait_large_snapshot()!=0) return 5;
  for (int i=0;i<64;i++) {
    intptr_t reader=-1,writer=-1,retained=-1;
    nc_error error;
    if (net_core_os_wake_open(&reader,&writer,&error)) return 6;
    if (net_core_os_duplicate(reader,&retained,&error)) return 7;
    net_core_os_wake_signal(writer);
    if (net_core_os_close(reader,&error)) return 8;
    if (net_core_os_wait(retained,0,1000,&error)) return 9;
    if (net_core_os_close(retained,&error)) return 10;
    /* The pair still owns the writer; its reader was explicitly closed above. */
    if (net_core_os_close(writer,&error)) return 11;
  }
  if (net_core_test_fd_count()!=baseline) return 12;
  puts("END native direction/UDP/fanout/resource smoke PASS");
  return 0;
}
