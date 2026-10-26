# Continuous integration and draft delivery

## Public-repository boundary

The workflows run from this standalone repository. They never clone Nyra's private
compiler repository or require its source tree. scripts/ci.py downloads the public
SDK 1.0.0 binary release and verifies pinned archive, manifest and compiler hashes.
A local --sdk payload is also checked against the pinned manifest/compiler hashes.
The staged package uses the SDK's precompiled stdlib/kernel, with source fallback
disabled. The repository's workspace package.yaml is not rewritten in place.

N3 assertions are package-local helpers under tests/, backed by the SDK test
harness's AddFail counter. The four helpers preserve soft-failure behavior and
message output without requiring the workspace-only ntest source package.

## Automatic CI

.github/workflows/ci.yml runs on main pushes, pull requests, version tags and
manual workflow dispatch. Actions are pinned to commit IDs. Jobs have finite time
limits; independent platforms continue after another platform fails.

- Linux x86_64 / Ubuntu 24.04: pinned public SDK, full N3 suite, all isolated
  case replays, production package check and native delivery candidate.
- Windows x86_64 / Windows Server 2022: the same Nyra acceptance using the
  public Windows SDK and installed Windows SDK/CRT.
- macOS arm64: strict native build and standalone C smoke for direction, empty UDP,
  144 read interests, retained descriptors and 64-round resource recovery.
- iOS device/Simulator arm64: native compilation, archive construction and shared
  link probes with the Xcode SDK installed on the macOS runner.
- Android arm64/x86_64: native compilation/archive/link probes with NDK
  26.1.10909125. Android API 21 is the default native adapter floor.

The SDK compiler's Linux system dependencies are installed explicitly. Mobile
native jobs do not claim Nyra precompilation or device runtime acceptance.
The earlier four-target Nyra precompilation evidence remains separate from
hosted native CI. See [mobile integration](mobile.md).

Normal jobs have contents:read only, no checkout credential persistence, and no
repository secret requirement. Reports/logs are uploaded even after failures;
candidate archives upload only after successful gates. SDK downloads, compiler
binaries, staged source copies and object trees are excluded from artifacts.
Artifacts expire after 14 days. Reports record wall time and actual measured
POSIX CPU/RSS; Windows CPU/RSS stay null when unavailable.

## macOS SDK compatibility and manual Nyra acceptance

The published SDK 1.0.0 compiler has LC_BUILD_VERSION minos 27.0. It cannot run
on the standard macOS 15 runner. This was inspected in the actual public release
payload, rather than inferred from the LLVM target triple. As agreed, hosted
macOS CI currently uses system Clang for native checks. A compatible lower-minimum
SDK is a future distribution change, not an unreviewed binary-header patch.
GitHub's available runners are described in its
[runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

Full macOS Nyra acceptance can be run manually on a compatible Mac with Xcode:

```sh
python3 scripts/ci.py desktop --out-dir /absolute/path/outside/checkout/mac-ci-001
```

To reuse an extracted public payload, append --sdk /absolute/path/to/nyra-sdk.
Use Python 3.12 or newer and a new/empty output directory outside this checkout.
No private workspace dependency is required.

.github/workflows/macos-nyra.yml is an optional workflow_dispatch entry for a
compatible self-hosted Mac labeled self-hosted, macOS, ARM64, nyra-sdk-1.0.
It runs only for trusted main/tag refs and never on pull_request. No self-hosted
runner is registered or installed by these changes. If none is registered, run
the local command instead; dispatching that optional workflow would wait for one.

## Draft delivery

A push of a version tag matching package.yaml, such as v0.1.0, runs all automatic
jobs first. Only if every job passes does the draft-release job gain contents:write.
It downloads this run's seven native-component candidates, validates the complete
asset set and generates SHA256SUMS. scripts/ci_release.py creates a GitHub draft;
it does not publish the release or create a tag. Reruns may update an existing
draft, but refuse to modify an already published release.

Each target zip contains only libnet_core_native.a, its MIT LICENSE and the
native-manifest.json build receipt. These are native component candidates, not
complete SDKs or relocatable precompiled Nyra package releases. Tag source archives
provide the public Nyra sources. Review matching-commit manual macOS Nyra evidence
and the documented mobile acceptance scope before publishing a draft.

A release can be prepared locally without GitHub writes:

```sh
python3 scripts/ci_release.py --tag v0.1.0 --assets /path/to/seven/candidates --prepare-only
```

No tag or release has been created as part of adding these definitions.

## Validation of this implementation

The standalone CI driver was replayed using the actual public SDK payload on
macOS arm64, Linux x86_64 and Windows x86_64 with no compiler-source dependency.
Each passed the 38-case suite and all 38 isolated replays, plus production checks.
macOS native smoke and all four mobile native targets also passed. Draft packaging
was validated with --prepare-only; no GitHub release write was performed.

Workflow definitions pass actionlint 1.7.7 with the custom runner label declared
in .github/actionlint.yaml. Local receipts are under ignored private workspace
cache/net-core-ci-public/. This is local workflow-command validation. Actual
GitHub-hosted execution is recorded separately from those local receipts.

The [first hosted run](https://github.com/nylang/netcore/actions/runs/40276141772)
for commit 10a0e634676c614bdadd2e5bbaa6341658387061 passed all four automatic jobs.
Linux and Windows each passed 38 N3 cases and all 38 isolated replays, with the
production import gate also passing. macOS/iOS and Android native build jobs
passed and uploaded their candidates and receipts. The draft-release job was
correctly skipped for a main-branch push. No full hosted macOS Nyra or mobile
device runtime acceptance is implied by those native jobs.
