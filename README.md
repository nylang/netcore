# net_core

Independent Nyra networking foundation. The current implementation provides:

- `IpAddress` and `NetEndpoint`: inline IPv4/IPv6 values, numeric scopes,
  strict literal parsing, comparison and canonical text formatting.
- `NetError`: stable error categories with an optional native code.
- `NetBytes` / `NetMutableBytes`: checked borrowed ranges without owning storage.
- `NetDeadline`: explicit monotonic budgets and bounded native wait conversion.
- `NetCancellation` / `NetOperationOptions`: shared atomic cancellation and
  deterministic cancellation/deadline checks.
- `Resolver`: bounded-result synchronous OS DNS and numeric interface scopes.
- `TcpConnection`, `TcpListener`, `UdpSocket`: move-only, drop-managed sockets
  with partial I/O, explicit EOF/datagram semantics and operation controls.

The socket substrate compiles on macOS; runtime and Linux/Windows acceptance
remain pending. Native event loops, HTTP and TLS/HTTPS are planned stages.
The compiler and package manager will consume public APIs; networking does not
belong in their frontend or CodeGen.
No libcurl dependency or compiler-specific API is part of this package.

## Use

Declare a `net_core` dependency and import `net_core:net_core.ny`. The source
manifest currently uses the NyraLang workspace's public stdlib at
`../../source/stdlib`; public SDK dependency locations remain a release task.

```nyra
import "stdlib:stdlib.ny";
import "net_core:net_core.ny";

func main() -> int32 {
  let result: Result<NetEndpoint, NetError> = NetEndpoint.Parse("[::1]:8080");
  let value: NetEndpoint? = result.get_if<NetEndpoint>();
  if value == nil { return 1; }
  let endpoint: NetEndpoint = value as NetEndpoint;
  Console.Println(endpoint.ToString());
  return 0;
}
```

Address parsing does not allocate or retain input strings. Formatting produces
an owned string. Byte views do not retain their owners and must not outlive the
backing memory. Cancellation is currently a pollable flag, not an OS wakeup.

See [foundation contract and compilation evidence](docs/foundation.md),
[DNS/socket contracts and native build/link instructions](docs/transport.md), and
[implementation roadmap](ROADMAP.md). Behavioral and platform acceptance remain
pending; compilation alone is not network runtime validation.

## License

Licensed under the [MIT License](LICENSE).
