#!/usr/bin/env python3
"""Build net_core native archives for explicit Android/iOS SDK targets."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys

PACKAGE = Path(__file__).resolve().parents[1]
TARGETS = ("android-arm64", "android-x86_64", "ios-arm64", "ios-simulator-arm64")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--target", choices=TARGETS, action="append", required=True)
    parser.add_argument("--android-ndk", type=Path, default=os.environ.get("ANDROID_NDK_HOME"))
    parser.add_argument("--android-api", type=int, default=21)
    parser.add_argument("--ios-minimum", default="13.0")
    parser.add_argument("--compiler", type=Path, help="also precompile the Nyra source package")
    args = parser.parse_args()
    output = args.out_dir.expanduser().resolve()
    if output == PACKAGE or PACKAGE in output.parents:
        parser.error("--out-dir must be outside the source package")
    if output.exists() and any(output.iterdir()):
        parser.error("--out-dir must be new or empty")
    if args.android_api < 21:
        parser.error("64-bit Android targets require API 21 or newer")
    if not args.ios_minimum or any(not part.isdigit() for part in args.ios_minimum.split(".")):
        parser.error("--ios-minimum must be a numeric version")
    if args.compiler and not args.compiler.expanduser().is_file():
        parser.error("--compiler must name an existing executable")
    plans = []
    for target in dict.fromkeys(args.target):
        if target.startswith("android-"):
            if not args.android_ndk:
                parser.error("Android requires --android-ndk or ANDROID_NDK_HOME")
            host = {"Darwin": "darwin-x86_64", "Linux": "linux-x86_64", "Windows": "windows-x86_64"}.get(platform.system())
            kit = args.android_ndk.expanduser().resolve() / "toolchains/llvm/prebuilt" / (host or "unsupported")
            ext = ".exe" if platform.system() == "Windows" else ""
            cc, ar = kit / ("bin/clang" + ext), kit / ("bin/llvm-ar" + ext)
            sysroot = kit / "sysroot"
            triple = ("aarch64-linux-android" if target.endswith("arm64") else "x86_64-linux-android") + str(args.android_api)
        else:
            if platform.system() != "Darwin":
                parser.error("iOS builds require macOS with Xcode SDKs")
            sdk = "iphonesimulator" if "simulator" in target else "iphoneos"
            def xcrun(*arguments: str) -> str:
                return subprocess.check_output(["xcrun", "--sdk", sdk, *arguments], text=True).strip()
            cc, ar = Path(xcrun("--find", "clang")), Path(xcrun("--find", "ar"))
            sysroot = Path(xcrun("--show-sdk-path"))
            triple = "arm64-apple-ios" + args.ios_minimum + ("-simulator" if "simulator" in target else "")
        if not cc.is_file() or not ar.is_file() or not sysroot.is_dir():
            parser.error("missing compiler, archiver or sysroot for " + target)
        plans.append((target, triple, cc, ar, sysroot))
    output.mkdir(parents=True, exist_ok=True)
    report = {"format": "net-core-mobile-build-v1", "status": "running", "targets": [],
              "runtime_acceptance": "not run; cross compilation only",
              "compiler_sha256": hashlib.sha256(args.compiler.expanduser().read_bytes()).hexdigest() if args.compiler else None,
              "source_sha256": {p.relative_to(PACKAGE).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in sorted(PACKAGE.rglob("*")) if p.is_file() and p.suffix in (".ny", ".ni", ".c", ".h", ".yaml", ".py") and ".git" not in p.relative_to(PACKAGE).parts}}
    def save() -> None:
        (output / "mobile-manifest.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    try:
        for target, triple, cc, ar, sysroot in plans:
            print("BEGIN " + target, flush=True)
            row = {"target": target, "triple": triple, "status": "running", "commands": []}
            report["targets"].append(row)
            commands = [[sys.executable, str(PACKAGE / "scripts/build_native.py"),
                         "--out-dir", str(output / target / "native"), "--cc", str(cc), "--ar", str(ar),
                         "--target", triple, "--sysroot", str(sysroot)]]
            link = [str(cc), "--target=" + triple, "--sysroot=" + str(sysroot), "-std=c11", "-O2",
                    "-Wall", "-Wextra", "-Werror", "-fPIC", str(PACKAGE / "private/native/net_core_os.c")]
            link += (["-shared", "-Wl,--no-undefined", "-o", str(output / target / "libnet_core_native.so")]
                     if target.startswith("android-") else
                     ["-dynamiclib", "-Wl,-undefined,error", "-o", str(output / target / "libnet_core_native.dylib")])
            commands.append(link)
            if args.compiler:
                commands.append([str(args.compiler.expanduser().resolve()), "precompile", str(PACKAGE / "net_core.ny"),
                                 "-O2", "-j", "4", "--target", "android" if target.startswith("android-") else "ios",
                                 "--llvm-target", triple, "--sysroot", str(sysroot),
                                 "--out-dir", str(output / target / "objects"), "-o", str(output / target / "package")])
            for index, command in enumerate(commands):
                row["commands"].append(command)
                save()
                with (output / (target + "-" + str(index) + ".log")).open("w", encoding="utf-8") as log:
                    environment = os.environ.copy()
                    environment["AR"] = str(ar)
                    environment["CC"] = str(cc)
                    subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=600, env=environment)
            archive = output / target / "native/libnet_core_native.a"
            row["archive_sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
            if args.compiler:
                package_archive = output / target / "package/lib/libpackage.a"
                row["package_archive_sha256"] = hashlib.sha256(package_archive.read_bytes()).hexdigest()
                contracts = list((output / target / "package/contracts").glob("*.json"))
                expected_selector = "android" if target.startswith("android-") else "ios"
                if not contracts:
                    raise ValueError("missing cross-target package contracts for " + target)
                for contract in contracts:
                    metadata = json.loads(contract.read_text(encoding="utf-8"))
                    if metadata.get("target") != triple or metadata.get("selector") != expected_selector:
                        raise ValueError("wrong target or selector in " + str(contract))
                row["package_selector"] = expected_selector
            row["status"] = "passed"
            save()
            print("END " + target + " passed", flush=True)
        current_inputs = {p.relative_to(PACKAGE).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in sorted(PACKAGE.rglob("*")) if p.is_file() and p.suffix in (".ny", ".ni", ".c", ".h", ".yaml", ".py") and ".git" not in p.relative_to(PACKAGE).parts}
        if current_inputs != report["source_sha256"]:
            raise ValueError("package sources changed during cross build")
        report["status"] = "passed"
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report["status"] = "failed"
        report["error"] = str(error)
        print(str(error), file=sys.stderr)
    save()
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
