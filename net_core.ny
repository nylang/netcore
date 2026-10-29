// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

/**
 * @brief Public networking foundation: addresses, errors, byte views and controls.
 * @note OS transports and protocols are separate implementation stages.
 */
export "interface/foundation.ni";
import "interface/foundation.ni";
import "private/foundation.ny";
export "interface/transport.ni";
import "interface/transport.ni";
import "private/transport.ny";
export "interface/async_transport.ni";
import "interface/async_transport.ni";
export "interface/async_resolver.ni";
import "interface/async_resolver.ni";

import "private/cancellation.ny";
import "private/owned_buffer.ny";
import "private/resolver.ny";
import "private/async_resolver.ny";
