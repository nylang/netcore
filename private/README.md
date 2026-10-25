# Closed implementation

`foundation.ny` defines the NetFoundation TU and explicitly lists its parts:
address/endpoint parsing, failures, borrowed buffers, deadlines and cancellation.
Future OS adapters belong here and are not barrel exports.

`transport.ny` defines the NetTransport TU and lists the resolver, TCP/UDP,
resource-state and private ABI parts. `native/net_core_os.c` implements the
OS primitives; `scripts/build_native.py` builds their separate native archive.
