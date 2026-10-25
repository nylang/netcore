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
- macOS `NetEventLoop`: bounded caller-thread readiness Futures, plus nonblocking
  `Try*` I/O and `NetCancellation.NewWakeable()` for active cancellation wakeup.
- `NetBuffer` and retained transfer Futures: TCP partial/exact reads and
  partial/full writes, UDP messages, numeric async connect and accept tasks.
- Explicit queue/payload limits, progress on failure and take-once connection ownership.
- `AsyncResolver`: an explicit fixed DNS worker pool with bounded admission,
  immutable endpoint results and caller-thread Future publication.
- macOS DNS progress notifications integrate with `NetEventLoop`, including
  query-deadline budgets and bounded cancellation observation.

The macOS N3 socket/async/DNS layer passes 37 controlled behavioral cases and
individual runtime replays. See [acceptance and remaining coverage](tests/README.md).
Additional fault injection and Linux/Windows event adapters remain open. HTTP
will live in a separate package; TLS is planned as a separate reusable layer.
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
backing memory. New cancellation tokens remain flag-only; NewWakeable returns a
macOS OS-backed token or an explicit failure.

See [foundation contract and compilation evidence](docs/foundation.md),
[DNS/socket contracts and native build/link instructions](docs/transport.md), and
[macOS event/Future contracts](docs/events.md),
[retained asynchronous transport](docs/async-transport.md),
[bounded asynchronous DNS](docs/async-resolver.md), and [implementation roadmap](ROADMAP.md).
The acceptance scope and remaining fault/platform cases are listed explicitly.

## License

Licensed under the [MIT License](LICENSE).
