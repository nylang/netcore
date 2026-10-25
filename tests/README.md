# macOS N3 behavioral acceptance

Run from a NyraLang workspace with an accepted native compiler and its normal
LLVM/platform environment configured:

```sh
python3 third_party/net_core/scripts/accept_macos.py \
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

`native/n3_fixture_macos.c` replaces getaddrinfo only in the acceptance adapter
build. `net-core-gated.invalid` blocks behind a bounded gate;
`net-core-failed.invalid` returns a controlled lookup failure. Numeric conversions
use the actual OS resolver. Network traffic uses local loopback sockets, never
public Internet services. One isolated test child temporarily refuses new file
descriptors, restores its own resource limit, then checks failed pool startup.

Test sources are module parts here. Native fixture code belongs in `tests/native/`,
standalone fixture data belongs in `tests/data/`, and generated files belong in
an external cache directory. This directory is not a nested package.

## Accepted coverage

The current suite has 37 cases. The complete suite and all 37 individual runtime
executions pass on macOS arm64; the latest receipt is under ignored workspace
`cache/net-core-macos-n3-final-06/acceptance.json`.

- TCP connection/accept, take-once connection results, exact/partial reads, EOF,
  200,000-byte patterned transfers and the 64 KiB per-Poll work limit.
- Darwin's OS-rejected remote port-zero connect reports AddressUnavailable,
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
- Linux/Windows event adapters and native behavior; cross-target SDK artifacts.

See `../ROADMAP.md` and the contracts in `../docs/`. These gaps stay open; this is
macOS controlled N3 acceptance, not a three-platform release gate.
