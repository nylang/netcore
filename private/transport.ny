/** @brief Resource-owning network facade; native functions implement only OS primitives. */
module NetTransport;
part "native_bridge.ny";
part "socket_owner.ny";
part "resolver.ny";
part "tcp.ny";
part "udp.ny";
import "stdlib:stdlib.ny";
import "interface/foundation.ni";
import "interface/transport.ni";
