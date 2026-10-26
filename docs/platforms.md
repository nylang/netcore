# Platform backends

## Shared contract

The public Nyra APIs and operation policy are shared across macOS, Linux, Windows,
Android and iOS. TCP/UDP, retained transfers, numeric connect/accept, wakeable cancellation
and asynchronous DNS use the same caller-thread event loop and fixed worker pool.
No platform-specific public handle, dependency on HTTP/TLS, or compiler feature is
introduced. Queue capacity remains 1..256, with at most 512 native wait entries.

## macOS

Readiness uses a temporary kqueue per bounded snapshot. Socket registrations own
F_DUPFD_CLOEXEC duplicates. Cancellation and resolver notification channels use
nonblocking, close-on-exec AF_UNIX socket pairs. SO_NOSIGPIPE suppresses SIGPIPE.

## Linux

Readiness uses poll over the bounded snapshot. This backend does not retain a
kernel event queue between Poll calls. Each operation owns an F_DUPFD_CLOEXEC
duplicate, so closing its original socket does not invalidate the registration.
Read/write interests remain distinct even when several entries share a socket.
POLLERR/POLLHUP wake the subsequent operation or SO_ERROR check; POLLNVAL reports
Closed. EINTR returns control to Nyra so absolute deadlines can be recomputed.

Wake channels use socketpair with SOCK_NONBLOCK and SOCK_CLOEXEC at creation.
MSG_NOSIGNAL suppresses SIGPIPE during signaling. Already-cancelled entries are
excluded from the wait, and active cancellation is processed before data readiness.

The snapshot approach matches the existing bounded driver. A persistent epoll
backend can be considered if measurements justify a different registration model;
it is not needed to expose the existing APIs on Linux.

## Windows

Readiness uses WinSock select. FD_SETSIZE is explicitly 1024 in this private C
translation unit, covering the bounded 512-entry snapshot. It does not impose a
numeric SOCKET limit. Failed nonblocking connects are included in exceptfds and
then classified using SO_ERROR. This follows the
[Microsoft select contract](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-select).

Registrations use WSADuplicateSocketW and WSASocketW in the current process.
Each duplicate owns its own WSAStartup reference, is nonblocking/non-inheritable,
and can close independently of the original. The underlying connection and
socket options remain shared, as specified by
[Microsoft's socket duplication contract](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-wsaduplicatesocketw).
Do not concurrently change socket options or issue overlapping operations on
aliases; existing Nyra ownership and driver-affinity restrictions still apply.

WinSock select cannot wait on AF_UNIX socketpair or arbitrary OS event handles.
Wake channels therefore use a private IPv4 loopback TCP pair. Pair creation uses
nonblocking sockets and a bounded 1000 ms connect wait. Failure closes the
listener and any established endpoints and balances WSAStartup. The pair owns one
startup reference; separately retained registration duplicates own separate ones.
Creation requires permission to create loopback sockets and can fail explicitly.
It creates no hidden thread and exposes no listening port to the public API.

## Android and iOS

Android uses the Linux backend. iOS device/Simulator builds enable the kqueue
backend through TargetConditionals. See [mobile build/integration](mobile.md) for
verified targets, SDK requirements, permission handling and runtime limits.

## Cancellation and DNS notifications

Cancellation flags are published before signaling. Their sticky channel bytes
are never drained, so late registrations and multiple waiters observe readiness.
Resolver channels are distinct resettable channels. Their bounded drain remains
limited to eight reads of 256 bytes; completion identity comes from the worker
state scan, not notification byte counts. Windows and Linux reuse the existing
Nyra cancellation, timeout, backpressure, worker lifecycle and Future publication.

## Build

On each native host, from the NyraLang workspace:

```sh
python3 third_party/net_core/scripts/build_native.py --out-dir cache/net-core/native
```

On Linux with GCC instead of Clang:

```sh
python3 third_party/net_core/scripts/build_native.py --cc gcc --out-dir cache/net-core/native
```

On Windows use `python` if `python3` is unavailable. Clang/LLVM tools and the
Windows SDK/CRT must be configured in the build environment. Consumers link the
archive plus ws2_32 and iphlpapi on Windows. native-manifest.json now records
system_libraries and event_backend as well as the target, hashes and commands.
The ordinary Nyra stdlib/platform library is also required. See
[package build/link instructions](transport.md#build-and-link).

Cross compilation accepts --target and --sysroot but requires a matching system
SDK/CRT. Building from a native Windows or Linux machine does not establish
macOS-to-Windows/Linux cross-toolchain acceptance.

## Evidence and remaining gates

The 2026-10-26 implementation compiles and archives with C11/O2/Wall/Wextra/Werror
on macOS arm64 (Clang), Linux x86_64 (GCC), and Windows x86_64 (Clang with the
Windows SDK). Linux shared linking checks all adapter symbols for unresolved
references; Windows DLL linking resolves ws2_32/iphlpapi. The private workspace
keeps build manifests under ignored cache/net-core-cross-native/; generated
archives, objects and DLLs do not belong in package source or Git.

The current desktop source revision also passes the 38-case N3 suite and all 38
isolated replays on each of macOS arm64, Linux x86_64 and Windows x86_64, with no
failures, ignored cases or skips. Production Nyra package and native archive
symbol checks contain no net_core_test_* imports. All three source-hash maps match
each other and the four-target mobile cross-build receipt.

Windows resource checks prime the system WinSock/DNS and NLS initialization
before taking a process-handle baseline. One fixture-owned WinSock reference lasts
until process exit and is released by atexit. Investigation identified the prior
fixed +1 handle as the Windows-owned NLS Sorting/Versions registry key: an
independent CompareStringEx call reproduces it. The fixture initializes that exact
subsystem; it does not subtract an allowed leak count. Per-operation recovery still
requires exact equality with the initialized baseline. Windows startup-exhaustion
coverage injects failure at the private wake-open boundary; POSIX uses the isolated
child's actual RLIMIT_NOFILE. Neither is a claim to cover every startup-failure path.

The new large-snapshot case waits on 144 distinct read interests and checks normal
readiness versus cancellation fanout beyond WinSock's default 64-entry fd_set.
The existing suite covers TCP/UDP transfers, deadlines, cancellation, DNS worker
ownership, notification races and 64-round resource recovery. Descriptor/handle
recovery is not proof of no heap leaks. See [test evidence](../tests/README.md).

Mobile cross-compilation and SDK publication remain separate gates. No mobile
runtime acceptance is implied by desktop behavior or a successful cross build.
