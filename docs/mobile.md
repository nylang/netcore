# Android and iOS builds

## Scope

net_core uses the same Nyra operation/ownership code on desktop and mobile.
Android uses the Linux poll/socketpair backend. iOS and the iOS Simulator use
kqueue/socketpair, enabled through TargetConditionals. Public APIs do not expose
JNI, Objective-C, UIKit, native socket handles or platform event queues.

This stage produces target-native adapter archives, checks native shared linking
and can precompile the Nyra package. It does not build a mobile compiler binary,
create an APK/IPA, sign an application or establish device runtime acceptance.
HTTP and TLS remain separate ecosystem packages.

## Repeatable cross build

From a macOS NyraLang workspace with Xcode and an installed Android NDK:

```sh
python3 third_party/net_core/scripts/build_mobile.py \
  --target android-arm64 --target android-x86_64 \
  --target ios-arm64 --target ios-simulator-arm64 \
  --android-ndk /absolute/path/to/android-ndk \
  --compiler /absolute/path/to/nyrac \
  --out-dir cache/net-core-mobile-001
```

Use a new/empty output directory. ANDROID_NDK_HOME can supply the NDK path.
The default Android API is 21; the default iOS minimum is 13.0. Raise deployment
versions to match the application. iOS targets require macOS/Xcode. Android
builds can use the corresponding NDK host toolkit on macOS, Linux or Windows.
The optional --compiler runs O2 Nyra package precompilation for each exact LLVM
triple and the Android/iOS source selector; the builder explicitly selects the
matching archiver and verifies every generated Core contract's target/selector.

Each target directory contains native/libnet_core_native.a, its MIT license,
native-manifest.json, a native shared-link probe, and (with --compiler)
package/lib/libpackage.a plus the compiler's package metadata. Logs and the
combined mobile-manifest.json record commands, compiler/source hashes and archive
hashes. Native shared-link probes are build checks, not deployable signed apps.
Do not combine simulator and device archives solely because both use arm64.

## Application integration

Consumers import net_core:net_core.ny through a source or matching precompiled
package dependency. Link the native adapter, the Nyra package/dependency archives,
and the target's Nyra stdlib/kernel/platform artifacts through the normal app
build. All archives must agree on platform, architecture, ABI and deployment
version. Current mobile builds do not promote these artifacts into a published
SDK. Keep generated files in cache/staging outside package source.

### Android

Package the final native application library using the app's NDK/Gradle/JNI
integration. net_core itself does not require a Java networking wrapper. Declare
android.permission.INTERNET for network operations. ACCESS_NETWORK_STATE is needed
if the app also queries Android connectivity state; net_core does not expose that
API. See [Android networking guidance](https://developer.android.com/develop/connectivity/network-ops/connecting).
Local-network permission behavior also depends on the Android release and target
SDK; follow [Android local network protections](https://developer.android.com/privacy-and-security/local-network-permission).
The package does not request platform permissions or bypass denied access.

### iOS

Link through the app's Xcode target with the matching device or Simulator SDK.
Signing and provisioning belong to the containing app. Apps accessing the local
network must provide NSLocalNetworkUsageDescription; see
[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).
Adding a usage description does not grant permission automatically. Multicast,
broadcast and discovery have additional platform requirements and are not an
accepted net_core feature in this increment. The library neither requests
background execution nor guarantees that workers or Poll continue while an app
is suspended. The application owns event-loop scheduling and lifecycle handling.

## Evidence

The implementation was cross-built with Android NDK 26.1.10909125 and Xcode's
iPhoneOS/iPhoneSimulator 27.1 SDKs. Android arm64/x86_64 (API 21), iOS arm64 and
iOS Simulator arm64 (minimum 13.0) passed strict native C compilation, native
shared linking and O2 Nyra source-package precompilation. The private workspace
receipt is cache/net-core-platform-runtime/mobile-final-02/mobile-manifest.json.

No Android emulator/device or iOS simulator/device behavior run is claimed by
these compile/link receipts. Mobile permissions, DNS behavior, background
suspension, network changes and on-device resource recovery remain runtime gates.
