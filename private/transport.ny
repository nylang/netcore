// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

module NetSocketDriver;
part "socket_owner.ny";
part "event_loop.ny";
part "async_transfer.ny";
part "async_connection.ny";
part "tcp.ny";
part "udp.ny";
part "../tests/driver_storage_selftest.ny";
import "stdlib:stdlib.ny";
import "interface/foundation.ni";
import "interface/transport.ni";
import "interface/async_transport.ni";
import "interface/async_resolver.ni";
import "private/foundation.ny";
import "private/native_abi.ni";
import "private/native_bridge.ny";
import "private/readiness.ni";
import "private/cancellation.ny";
import "private/owned_buffer.ny";
import "ntest:ntest.ny";

/** @brief Resource-owning network facade; native functions implement only OS primitives. */
