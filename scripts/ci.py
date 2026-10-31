#!/usr/bin/env python3
# Copyright (c) 2026 tangxiangjiang
# SPDX-License-Identifier: MIT

"""Run net_core CI using only this checkout and a pinned public binary SDK."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request
import zipfile

from sdk_layout import sdk_package
PACKAGE = Path(__file__).resolve().parents[1]
SDK_LOCK = json.loads((PACKAGE / "release.lock.json").read_text())["sdk"]
SDK_VERSION = SDK_LOCK["version"]
SDK_PINS = {host: (row["archive_sha256"], row["manifest_sha256"])
            for host, row in SDK_LOCK["hosts"].items()}


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def sdk_path(root: Path, relative: str) -> Path:
    path = (root / relative).resolve()
    if root.resolve() not in path.parents:
        raise ValueError("SDK path escapes payload: " + relative)
    return path


def obtain_sdk(output: Path, host: str, supplied: Path | None) -> Path:
    if host not in SDK_PINS:
        raise ValueError("qualified SDK " + SDK_VERSION + " pins are pending for " + host)
    archive_hash, manifest_hash = SDK_PINS[host]
    name = f"nyra-sdk-{SDK_VERSION}-{host}"
    if supplied:
        sdk = supplied.expanduser().resolve()
    else:
        suffix = ".zip" if host.startswith("windows-") else ".tar.gz"
        archive = output / (name + suffix)
        url = f"https://github.com/nylang/sdk/releases/download/v{SDK_VERSION}/{archive.name}"
        print("DOWNLOAD " + url, flush=True)
        with urllib.request.urlopen(url, timeout=120) as response, archive.open("wb") as destination:
            shutil.copyfileobj(response, destination, 1024 * 1024)
        if digest(archive) != archive_hash:
            raise ValueError("SDK archive SHA-256 mismatch")
        extracted = output / "sdk"
        extracted.mkdir()
        if suffix == ".zip":
            with zipfile.ZipFile(archive) as bundle:
                for member in bundle.infolist():
                    parts = PurePosixPath(member.filename).parts
                    if not parts or parts[0] != name or ".." in parts or "\\" in member.filename or ":" in member.filename:
                        raise ValueError("unsafe SDK archive path")
                    if (member.external_attr >> 16) & 0o170000 == 0o120000:
                        raise ValueError("unexpected symbolic link in Windows SDK")
                bundle.extractall(extracted)
        else:
            with tarfile.open(archive, "r:gz") as bundle:
                for member in bundle.getmembers():
                    parts = PurePosixPath(member.name).parts
                    if not parts or parts[0] != name or ".." in parts or "\\" in member.name:
                        raise ValueError("unsafe SDK archive path")
                bundle.extractall(extracted, filter="data")
        sdk = extracted / name
    if digest(sdk / "manifest.json") != manifest_hash:
        raise ValueError("SDK manifest SHA-256 mismatch")
    manifest = json.loads((sdk / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("host") != host or manifest.get("version") != SDK_VERSION:
        raise ValueError("SDK host/version mismatch")
    tool = manifest["tools"]["nyrac"]
    if digest(sdk_path(sdk, tool["path"])) != tool["sha256"]:
        raise ValueError("SDK compiler SHA-256 mismatch")
    return sdk


def stage_manifest(project: Path, stdlib: Path, version: str) -> None:
    if not (stdlib / "manifest.yaml").is_file():
        raise ValueError("missing precompiled SDK stdlib: " + str(stdlib))
    (project / "package.yaml").write_text(
        "name: net_core\nversion: " + version + "\nlicense: MIT\ndependencies:\n  stdlib:\n    precompiled: "
        + json.dumps(str(stdlib)) + "\ndirectories:\n  interface:\n    - interface\n  public:\n    - public\n  private:\n    - private\n    - tests\n", encoding="utf-8")


def candidate(native: Path, output: Path, version: str, target: str) -> None:
    directory = output / "candidates"
    directory.mkdir(exist_ok=True)
    prefix = f"net-core-{version}-{target}-native"
    with zipfile.ZipFile(directory / (prefix + ".zip"), "w", zipfile.ZIP_DEFLATED) as archive:
        for name in ("libnet_core_native.a", "LICENSE", "native-manifest.json"):
            archive.write(native / name, prefix + "/" + name)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("desktop", "native", "mobile-native"))
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--sdk", type=Path, help="local public SDK payload, still checked against pinned hashes")
    parser.add_argument("--target", choices=("android-arm64", "android-x86_64", "ios-arm64", "ios-simulator-arm64"), action="append")
    parser.add_argument("--android-ndk", type=Path)
    args = parser.parse_args()
    output = args.out_dir.expanduser().resolve()
    if output == PACKAGE or PACKAGE in output.parents:
        parser.error("outputs must be outside the source checkout")
    if output.exists() and any(output.iterdir()):
        parser.error("--out-dir must be new or empty")
    if args.mode == "mobile-native" and not args.target:
        parser.error("mobile-native requires --target")
    version_match = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$", (PACKAGE / "package.yaml").read_text(), re.M)
    if not version_match:
        parser.error("package version must be a semantic release version")
    version = version_match.group(1)
    output.mkdir(parents=True, exist_ok=True)
    project = output / "project"
    shutil.copytree(PACKAGE, project, ignore=shutil.ignore_patterns(".git", "__pycache__", "cache", "bin", "lib", "out", ".tmp", ".DS_Store"))
    report = {"format": "net-core-ci-v1", "status": "running", "mode": args.mode, "version": version,
              "host": platform.platform(), "commands": [], "sdk": None}
    environment = os.environ.copy()
    def save() -> None:
        (output / "ci-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    def run(command: list[str]) -> None:
        index = len(report["commands"])
        report["commands"].append(command)
        save()
        print("BEGIN CI step " + str(index), flush=True)
        with (output / ("step-" + str(index) + ".log")).open("w", encoding="utf-8") as log:
            subprocess.run(command, cwd=project, env=environment, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=1200)
        print("END CI step " + str(index), flush=True)
    try:
        run([sys.executable, str(PACKAGE / "tests/tools/test_sdk_layout.py")])
        if args.mode == "desktop":
            arch = {"aarch64": "arm64", "amd64": "x86_64"}.get(platform.machine().lower(), platform.machine().lower())
            host = platform.system().lower() + "-" + arch
            sdk = obtain_sdk(output, host, args.sdk)
            metadata = json.loads((sdk / "manifest.json").read_text(encoding="utf-8"))
            compiler = sdk_path(sdk, metadata["tools"]["nyrac"]["path"])
            toolkit = sdk / "hosts" / host / "llvm/bin"
            extension = ".exe" if host.startswith("windows-") else ""
            for key in tuple(environment):
                if key.startswith(("NYRA", "DYLD_", "LD_")) or key == "LLVM_PREFIX":
                    environment.pop(key, None)
            environment.update(CC=str(toolkit / ("clang" + extension)), AR=str(toolkit / ("llvm-ar" + extension)))
            environment["PATH"] = str(toolkit) + os.pathsep + environment.get("PATH", "")
            environment["NYRA_KERNEL_ROOT"] = str(output / "source-fallback-disabled")
            if host.startswith("darwin-"):
                environment["SDKROOT"] = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
            stdlib = sdk_package(sdk, host, 'stdlib')
            stage_manifest(project, stdlib, version)
            report["sdk"] = {"version": SDK_VERSION, "manifest_sha256": digest(sdk / "manifest.json"), "source_fallback_disabled": True}
            run([sys.executable, str(project / "scripts/accept.py"), "--compiler", str(compiler),
                 "--platform-archive", str(stdlib / "lib/libnyra_platform.a"), "--timeout", "600",
                 "--out-dir", str(output / "acceptance")])
            candidate(output / "acceptance/production-native", output, version, host)
        elif args.mode == "native":
            if platform.system() not in ("Darwin", "Linux"):
                raise ValueError("native smoke mode supports POSIX hosts; use desktop on Windows")
            host = platform.system().lower() + "-" + platform.machine().lower()
            run([sys.executable, str(project / "scripts/build_native.py"), "--out-dir", str(output / "native")])
            cc = environment.get("CC") or "clang"
            run([cc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-pthread",
                 str(project / "tests/native/ci_smoke.c"), str(project / "tests/native/n3_fixture.c"),
                 str(output / "native/libnet_core_native.a"), "-o", str(output / "native-smoke")])
            run([str(output / "native-smoke")])
            candidate(output / "native", output, version, host)
        else:
            command = [sys.executable, str(project / "scripts/build_mobile.py"), "--out-dir", str(output / "mobile")]
            for target in args.target:
                command += ["--target", target]
            if args.android_ndk:
                command += ["--android-ndk", str(args.android_ndk.resolve())]
            run(command)
            for target in dict.fromkeys(args.target):
                candidate(output / "mobile" / target / "native", output, version, target)
        report["status"] = "passed"
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        report["status"] = "failed"
        report["error"] = str(error)
        print(str(error), file=sys.stderr)
    save()
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
