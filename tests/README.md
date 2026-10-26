# Desktop N3 behavioral acceptance

Run from a NyraLang workspace with an accepted native compiler and its normal
LLVM/platform environment configured:

```sh
python3 third_party/net_core/scripts/accept.py \
  --compiler "$NYRAC" --out-dir cache/net-core-n3-acceptance-001
```

Use a new/empty output directory for each run. The independent runner builds the
native adapter and controlled fixture, discovers the `net_core_n3` unit tag,
builds/runs the complete suite, then executes each case separately for runtime
CPU/RSS samples. It checks every discovered case passed without skips. Steps
have explicit BEGIN/END logs and timeouts; timeout cleanup kills only that step's
new process group. Commands, hashes and receipts remain in the output directory.

It also builds the ordinary production native/archive package and rejects any
undefined `net_core_test_*` fixture import. Production builds do not use DNS
interposition or the test fixture. No compiler language change is required.

## Fixture and scope

`native/n3_fixture.c` replaces getaddrinfo only in the acceptance adapter
build. `net-core-gated.invalid` blocks behind a bounded gate;
`net-core-failed.invalid` returns a controlled lookup failure. Numeric conversions
use the actual OS resolver. Network traffic uses local loopback sockets, never
public Internet services. One isolated test child uses POSIX descriptor exhaustion or a Windows native
wake-open failure injection, restores the fixture, then checks failed pool startup.

Test sources are module parts here. Native fixture code belongs in `tests/native/`,
standalone fixture data belongs in `tests/data/`, and generated files belong in
an external cache directory. This directory is not a nested package.

## Accepted coverage

The current suite has 38 cases. The complete suite and all 38 individual runtime
executions pass on each of macOS arm64, Linux x86_64 and Windows x86_64. Matching
source-hash maps were checked against the final workspace sources. Local receipts:

- cache/net-core-platform-runtime/macos-final-02/acceptance.json
- cache/net-core-platform-runtime/linux-final-02.json
- cache/net-core-platform-runtime/windows-final-02.json

All report 38 passed, zero failed/ignored/skipped, plus 38 successful isolated
replays. Windows runtime CPU/RSS fields are null (not measured); POSIX CPU/RSS
use wait4, including Linux's KiB-to-byte conversion. No wall-time-derived CPU or
RSS values are substituted.

- TCP connection/accept, take-once connection results, exact/partial reads, EOF,
  200,000-byte patterned transfers and the 64 KiB per-Poll work limit.
- The OS-rejected remote port-zero connect preserves its platform error,
  preserves that task error and retires its descriptor. This fixture does not
  depend on another process leaving an ephemeral port unused.
- Error/Close results preserve a received prefix; overlapping reads and retained
  root-byte budget exhaustion are rejected; explicit compaction admits a slice.
- Queued payload/socket ownership survives original owner Close and Future drop.
- Empty TCP operations, empty UDP datagrams, UDP truncation consumption and
  zero-capacity receive without modifying the caller's pointer.
- Direction-aware native event fanout, wakeable cancellation/fanout, late token
  registration, deadlines, task move/cancel/drop and cancellation-before-timeout.
- Close callbacks observe terminal task state; Poll callbacks reenter and Close
  safely after the original completion batch has been detached.
- Controlled DNS success/failure, copied hostname lifetime, shared result lifetime,
  bounded worker/slot admission, queued cancellation and retained running slots.
- Query controls wake DNS notifications; duplicate admission, coalescing/late
  notifications, resolver move/Close, driver-only Close and dropped Futures.
- Notification-channel startup failure and descriptor recovery after late workers.
- 64-round descriptor recovery cases for TCP owners, wakeable tokens and DNS pools;
  100 rounds of paired DNS queries exercise notification drain/scan scheduling.

Runtime CPU includes all threads in each isolated test child, with compiler/linker
work excluded. RSS is a process high-water mark, not allocated/live heap bytes.
FD baseline recovery proves those descriptors were released in these cases; it
does not establish the absence of heap leaks or every possible lifetime race.

## Remaining acceptance

- Inject failure after one worker starts, plus mutex/CV/thread creation failure.
- Force native wait/duplicate failures and descriptor reuse while registrations
  remain pending; inject deadline expiry specifically during snapshot preparation.
- Inject deferred connect errors reported by SO_ERROR and other native failures.
- Broader N1 literal/byte-range boundary matrices and N2 OS resolver/interface cases.
- Mobile runtime behavior and cross-target published SDK artifacts.

See `../ROADMAP.md` and the contracts in `../docs/`. These gaps stay open; this is
controlled desktop N3 acceptance, not a complete release gate.

## Cross-platform fixture and build notes

Use scripts/accept.py on macOS, Linux or Windows; accept_macos.py remains the
original macOS entry. Configure the native LLVM tools on PATH and CC/AR when
needed. For an SDK compiler with source dependencies staged outside its original
workspace, pass --platform-archive /absolute/path/to/libnyra_platform.a for the
matching target. Tests use local loopback traffic and controlled DNS, never a
public Internet service. All generated outputs belong outside package source.

The shared C fixture uses pthreads on POSIX and SRW/condition variables on Windows.
DNS interposition is enabled after OS header declarations using NET_CORE_TEST_DNS,
so WinSock dllimport declarations do not accidentally apply to a fixture function.
Production builds do not define that macro. Windows additionally interposes the
private wake-open function for deterministic startup-resource failure; POSIX uses
an actual child-local resource limit. No production public API gains a test hook.

Windows process-handle measurement initializes WinSock/DNS and NLS before the
baseline and retains one fixture-owned WinSock reference until atexit cleanup.
A native diagnostic identified the fixed first-use +1 as the system NLS registry
key at \REGISTRY\MACHINE\SYSTEM\ControlSet001\Control\Nls\Sorting\Versions.
An independent CompareStringEx call reproduces it; priming that exact subsystem
allows strict equality checks without tolerances or excluded per-round growth.
The temporary NT handle-inspection diagnostic remains in ignored cache only.

The new 38th case validates 144 distinct read interests and readiness/cancellation
fanout beyond WinSock's default 64-entry fd_set. Port-zero connection failure is
checked against the platform's specific mapped error (ConnectionRefused on Linux,
AddressUnavailable on macOS/Windows), including TakeConnection and retirement.

Linux/Windows native implementation and remaining gates are in
[platforms.md](../docs/platforms.md). Mobile build evidence is in
[mobile.md](../docs/mobile.md): four targets pass strict native compilation/linking
and O2 Nyra package precompilation. No mobile behavior run is claimed. The earlier
macOS-only 37-case receipts remain historical evidence, not the current count.

## Standalone public SDK CI

The tests now use four package-local soft assertion helpers in n3_assert_selftest.ny and
the SDK test harness counter, with no ntest source dependency. scripts/ci.py stages
the package against a hash-checked public SDK's precompiled stdlib/kernel. The
original workspace package manifest remains unchanged by staging. Full suites and
isolated replays also pass through this independent path on Linux, Windows and a
compatible Mac. See [CI scope, receipts and macOS limits](../docs/ci.md).
