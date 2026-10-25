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
