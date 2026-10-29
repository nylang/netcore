/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 tangxiangjiang
 * Private ABI only. No sockaddr, errno constants or native handles enter the Nyra product face.
 */
#ifndef NET_CORE_OS_H
#define NET_CORE_OS_H
#include <stdint.h>
#include <stddef.h>

typedef struct {
  int32_t family;  /* 4 or 6, not AF_* */
  int32_t port;    /* host order */
  uint32_t scope_id;
  uint8_t bytes[16];
} nc_address;
typedef struct { int32_t kind; int32_t native_code; } nc_error;
_Static_assert(sizeof(nc_address) == 28, "nc_address ABI");
_Static_assert(offsetof(nc_address, bytes) == 12, "nc_address byte offset");
_Static_assert(sizeof(nc_error) == 8, "nc_error ABI");

enum {
  NC_OK=0, NC_ARGUMENT=1, NC_ADDRESS=2, NC_PORT=3, NC_FAMILY=4,
  NC_NAME=5, NC_PERMISSION=6, NC_IN_USE=7, NC_UNAVAILABLE=8,
  NC_REFUSED=9, NC_RESET=10, NC_ABORTED=11, NC_NOT_CONNECTED=12,
  NC_NETWORK=13, NC_HOST=14, NC_WOULD_BLOCK=15, NC_TIMEOUT=16,
  NC_CANCELLED=17, NC_CLOSED=18, NC_MESSAGE_SIZE=19,
  NC_UNSUPPORTED=20, NC_SYSTEM=21
};
typedef struct {
  intptr_t handle;
  intptr_t wake_handle;
  int32_t writable;
  int32_t ready;
  int32_t kind;
  int32_t native_code;
} nc_wait_item;
_Static_assert(sizeof(nc_wait_item)==2*sizeof(intptr_t)+16,"nc_wait_item ABI");
_Static_assert(offsetof(nc_wait_item,writable)==2*sizeof(intptr_t),"nc_wait_item fields");
int32_t net_core_os_events_supported(void);
int32_t net_core_os_duplicate(intptr_t handle, intptr_t *out, nc_error *error);
int32_t net_core_os_wait_many(nc_wait_item *items, int32_t count, int32_t milliseconds, nc_error *error);
int32_t net_core_os_open(int32_t family, int32_t datagram, intptr_t *out, nc_error *error);
int32_t net_core_os_close(intptr_t handle, nc_error *error);
int32_t net_core_os_bind(intptr_t handle, const nc_address *address, int32_t listener, nc_error *error);
int32_t net_core_os_listen(intptr_t handle, int32_t backlog, nc_error *error);
int32_t net_core_os_connect(intptr_t handle, const nc_address *address, nc_error *error);
int32_t net_core_os_connect_result(intptr_t handle, nc_error *error);
int32_t net_core_os_accept(intptr_t handle, intptr_t *out, nc_error *error);
int32_t net_core_os_wake_open(intptr_t *read_handle, intptr_t *write_handle, nc_error *error);
void net_core_os_wake_close(intptr_t read_handle, intptr_t write_handle);
void net_core_os_wake_signal(intptr_t write_handle);
/* Drain only resettable resolver notifications, never a sticky cancellation channel. */
int32_t net_core_os_notify_drain(intptr_t read_handle, nc_error *error);
int32_t net_core_os_wait_wake(intptr_t handle, int32_t writable, int32_t milliseconds, intptr_t wake_handle, nc_error *error);
int32_t net_core_os_wait(intptr_t handle, int32_t writable, int32_t milliseconds, nc_error *error);
int32_t net_core_os_endpoint(intptr_t handle, int32_t peer, nc_address *out, nc_error *error);
int32_t net_core_os_read(intptr_t handle, uint8_t *data, intptr_t size, intptr_t *out, nc_error *error);
int32_t net_core_os_write(intptr_t handle, const uint8_t *data, intptr_t size, intptr_t *out, nc_error *error);
int32_t net_core_os_send_to(intptr_t handle, const nc_address *address, const uint8_t *data, intptr_t size, intptr_t *out, nc_error *error);
int32_t net_core_os_receive_from(intptr_t handle, uint8_t *data, intptr_t size, intptr_t *out, nc_address *sender, nc_error *error);
int32_t net_core_os_shutdown_write(intptr_t handle, nc_error *error);
int32_t net_core_os_no_delay(intptr_t handle, int32_t enabled, nc_error *error);
int32_t net_core_os_resolve(const uint8_t *host, intptr_t length, int32_t port, int32_t family, nc_address *out, int32_t capacity, int32_t *count, nc_error *error);
int32_t net_core_os_scope(const uint8_t *name, intptr_t length, uint32_t *out, nc_error *error);
#endif
