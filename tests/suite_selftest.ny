// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

/** @brief Networking values, ownership, DNS and loop contracts across real modules. */
module NetContractTests;
part "n1_foundation_selftest.ny";
part "n3_selftest.ny";
part "n3_transport_selftest.ny";
part "n3_resolver_selftest.ny";
import "stdlib:stdlib.ny";
import "interface/foundation.ni";
import "interface/transport.ni";
import "interface/async_transport.ni";
import "interface/async_resolver.ni";
import "private/foundation.ny";
import "private/native_abi.ni";
import "private/native_bridge.ny";
import "private/transport.ny";
import "private/async_resolver.ny";
import "private/cancellation.ny";
import "private/owned_buffer.ny";
import "private/resolver.ny";
import "tests/support_selftest.ny";
