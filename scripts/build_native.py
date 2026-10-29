#!/usr/bin/env python3
# Copyright (c) 2026 tangxiangjiang
# SPDX-License-Identifier: MIT

"""Build net_core's private OS adapter without importing compiler build tools."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

PACKAGE = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, required=True, help="explicit cache/staging directory")
    parser.add_argument("--cc", default=os.environ.get("CC") or "clang")
    parser.add_argument("--ar", default=os.environ.get("AR") or shutil.which("llvm-ar") or "ar")
    parser.add_argument("--target", help="Clang target triple; requires a matching system SDK/CRT")
    parser.add_argument("--sysroot", type=Path)
    parser.add_argument("--cflag", action="append", default=[], help="additional compiler flag (use --cflag=VALUE)")
    args = parser.parse_args()
    output = args.out_dir.expanduser().resolve()
    # Source packages own source only; stage archives outside the implementation tree.
    if output == PACKAGE or PACKAGE in output.parents:
        parser.error("--out-dir must be outside the net_core source package")
    output.mkdir(parents=True, exist_ok=True)
    actual_target = args.target or subprocess.check_output([args.cc, "-dumpmachine"], text=True).strip()
    windows = any(marker in actual_target.lower() for marker in ("windows", "mingw", "win32"))
    source = PACKAGE / "private/native/net_core_os.c"
    header = source.with_suffix(".h")
    with tempfile.TemporaryDirectory(prefix=".native-", dir=output) as temporary:
        stage = Path(temporary)
        obj, archive = stage / "net_core_os.o", stage / "libnet_core_native.a"
        command = [args.cc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror"]
        target = args.target or ""
        if target:
            command += ["--target=" + target]
        if args.sysroot:
            command += ["--sysroot=" + str(args.sysroot.expanduser().resolve())]
        if windows:
            command += ["-mno-incremental-linker-compatible"]
        else:
            command += ["-fPIC"]
        command += [*args.cflag, "-c", str(source), "-o", str(obj)]
        subprocess.run(command, check=True)
        if Path(args.ar).name.lower() in ("lib", "lib.exe", "llvm-lib", "llvm-lib.exe"):
            ar_command = [args.ar, "/NOLOGO", "/OUT:" + str(archive), str(obj)]
        else:
            ar_command = [args.ar, "rcs", str(archive), str(obj)]
        subprocess.run(ar_command, check=True)
        os.replace(archive, output / archive.name)
    shutil.copy2(PACKAGE / "LICENSE", output / "LICENSE")
    record = {"format": "net-core-native-v1", "abi": 1, "license": "MIT", "target": actual_target,
              "archive": "libnet_core_native.a",
              "system_libraries": ["ws2_32", "iphlpapi"] if windows else [],
              "event_backend": ("select" if windows else "poll" if "linux" in actual_target else
                                "kqueue" if "darwin" in actual_target or "macos" in actual_target or "ios" in actual_target else "unsupported"),
              "compile": command, "archive_command": ar_command,
              "inputs": {p.relative_to(PACKAGE).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in (source, header, PACKAGE / "LICENSE")},
              "archive_sha256": hashlib.sha256((output / "libnet_core_native.a").read_bytes()).hexdigest()}
    staging_record = output / "native-manifest.json.tmp"
    staging_record.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    os.replace(staging_record, output / "native-manifest.json")
    print(output / "libnet_core_native.a", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
