# net_core

[![Network CI](https://github.com/nylang/netcore/actions/workflows/ci.yml/badge.svg)](https://github.com/nylang/netcore/actions/workflows/ci.yml)

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
- `NetEventLoop` on macOS, Linux, Windows, Android and iOS: bounded caller-thread readiness Futures, plus nonblocking
  `Try*` I/O and `NetCancellation.NewWakeable()` for active cancellation wakeup.
- `NetBuffer` and retained transfer Futures: TCP partial/exact reads and
  partial/full writes, UDP messages, numeric async connect and accept tasks.
- Explicit queue/payload limits, progress on failure and take-once connection ownership.
- `AsyncResolver`: an explicit fixed DNS worker pool with bounded admission,
  immutable endpoint results and caller-thread Future publication.
- DNS progress notifications integrate with `NetEventLoop`, including
  query-deadline budgets and bounded cancellation observation.

The desktop N3 socket/async/DNS layer passes 38 controlled behavioral cases and
38 individual runtime replays on each of macOS arm64, Linux x86_64 and Windows
x86_64. Android arm64/x86_64 and iOS device/Simulator arm64 pass native compile/link
checks and O2 Nyra package precompilation; mobile runtime acceptance remains open. See [acceptance and remaining coverage](tests/README.md).
A subsequent macOS public-SDK run passes 45 cases and 45 isolated replays after
adding seven foundation boundary cases; Linux/Windows retain the earlier 38-case
evidence. Additional fault injection and mobile runtime acceptance remain open. HTTP
will live in a separate package; TLS is planned as a separate reusable layer.
The compiler and package manager will consume public APIs; networking does not
belong in their frontend or CodeGen.
No libcurl dependency or compiler-specific API is part of this package.

## Use

Declare a `net_core` dependency and import `net_core:net_core.ny`. The source
manifest uses implicit stdlib from the installed SDK; no NyraLang private source
layout is required. Native networking adapters still require the documented
platform build/link setup.

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
OS-backed token on the supported desktop/mobile platforms, or an explicit failure.

See [foundation contract and compilation evidence](docs/foundation.md),
[DNS/socket contracts and native build/link instructions](docs/transport.md), and
[event/Future contracts](docs/events.md),
[retained asynchronous transport](docs/async-transport.md),
[bounded asynchronous DNS](docs/async-resolver.md), and [implementation roadmap](ROADMAP.md).
The acceptance scope and remaining fault/platform cases are listed explicitly.

See [platform backends, build commands and evidence](docs/platforms.md), and
[Android/iOS build and application integration](docs/mobile.md).

## Continuous integration

See [CI and draft delivery](docs/ci.md) for standalone public-SDK testing, native
mobile builds, macOS compatibility and manual acceptance, and version-tag draft
releases. The workflows do not fetch private compiler sources.

## Portable Git dependency

Source imports use the installed SDK's implicit runtime packages (SDK 1.0.2 or
later); package manifests contain no paths into the private compiler checkout.
For automatic Git preparation use native `nyra` 1.0.3 or later. That manager's
public SDK publication is separate from this package; SDK 1.0.2 does not ship it.
With SDK 1.0.2, a manual clone and explicit local consumer path remain usable.

Add this dependency to your application's `package.yaml`:

```yaml
dependencies:
  net_core:
    git: https://github.com/nylang/netcore.git
    rev: main
```

Then run `nyra lock ./app` and commit `nyra.lock`; use
`nyra fetch ./app --frozen` to prepare the pinned graph again. `main` above is
an initial selector; the lock fixes the exact commit/content. Normal compiler
and analyzer operations do not fetch dependencies. Historical tags are immutable
and may retain older workspace-specific manifests.


SDK-v2 portable-lock compilation requires the SDK runtime-lock loading fix in
newer compiler builds. The unchanged originally qualified SDK 1.0.3 bootstrap
does not contain that follow-up. Source-only use with public SDK 1.0.2 and the
historical prepared TLS source asset retain their documented limits; this
manifest migration does not release a corrected compiler.

For local multi-package development, list package-file pointers in a common
`workspace.yaml`. Workspace replacements keep Git declarations shareable;
origin lock updates deliberately disable replacements. A package entry and its
SDK can move without rewriting publisher paths.

## License

Licensed under the [MIT License](LICENSE).
