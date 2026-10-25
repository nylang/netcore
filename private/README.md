# Closed implementation

`foundation.ny` defines the NetFoundation TU and explicitly lists its parts:
address/endpoint parsing, failures, borrowed buffers, deadlines and cancellation.
Future OS adapters belong here and are not barrel exports.
