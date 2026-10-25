#!/usr/bin/env python3
"""Build and run controlled N3 behavior cases; keep artifacts outside the package."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import sys
import time

PACKAGE = Path(__file__).resolve().parents[1]


def source_hashes() -> dict[str, str]:
    return {
        path.relative_to(PACKAGE).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(PACKAGE.rglob("*"))
        if path.is_file() and path.suffix in (".ny", ".ni", ".c", ".h", ".py", ".yaml")
        and ".git" not in path.relative_to(PACKAGE).parts
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--cc", default=os.environ.get("CC", "clang"))
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("this acceptance runner is macOS-only")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    compiler = args.compiler.expanduser().resolve()
    if not compiler.is_file():
        parser.error("--compiler must name an existing native Nyra compiler")
    out = args.out_dir.expanduser().resolve()
    if out == PACKAGE or PACKAGE in out.parents:
        parser.error("--out-dir must be outside the source package")
    if out.exists() and any(out.iterdir()):
        parser.error("--out-dir must be new or empty; acceptance receipts are not overwritten")
    out.mkdir(parents=True, exist_ok=True)
    inputs = source_hashes()
    report = {
        "format": "net-core-macos-n3-acceptance-v1", "status": "running",
        "host": platform.platform(), "compiler": str(compiler),
        "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
        "source_sha256": inputs, "steps": [], "case_samples": [],
        "scope": "loopback sockets and controlled DNS; no public-network dependency",
    }

    def save() -> None:
        (out / "acceptance.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(name: str, command: list[str], *, timeout: float | None = None) -> dict:
        print("BEGIN " + name, flush=True)
        started = time.monotonic()
        timed_out = False
        with (out / (name + ".log")).open("w") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            while True:
                pid, status, usage = os.wait4(process.pid, os.WNOHANG)
                if pid:
                    break
                if time.monotonic() - started >= (timeout or args.timeout):
                    timed_out = True
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    _, status, usage = os.wait4(process.pid, 0)
                    break
                time.sleep(0.01)
            process.returncode = os.waitstatus_to_exitcode(status)
        row = {
            "name": name, "command": command, "exit_code": process.returncode,
            "timed_out": timed_out, "wall_seconds": round(time.monotonic() - started, 6),
            "user_seconds": usage.ru_utime, "system_seconds": usage.ru_stime,
            "peak_rss_bytes": usage.ru_maxrss,
        }
        report["steps"].append(row)
        save()
        print("END " + name + " exit=" + str(process.returncode), flush=True)
        if process.returncode or timed_out:
            raise RuntimeError(name + " failed; see " + str(out / (name + ".log")))
        return row

    try:
        run("native", [sys.executable, str(PACKAGE / "scripts/build_native.py"),
                       "--out-dir", str(out / "native"), "--cc", args.cc,
                       "--cflag=-Dgetaddrinfo=net_core_test_getaddrinfo"])
        run("fixture", [args.cc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-c",
                        str(PACKAGE / "tests/native/n3_fixture_macos.c"), "-o", str(out / "fixture.o")])
        run("list", [str(compiler), "test", str(PACKAGE), "--tag", "net_core_n3", "--list"])
        names = [line.strip() for line in (out / "list.log").read_text().splitlines()
                 if line.startswith("test_net_core_n3_")]
        if not names or len(set(names)) != len(names):
            raise RuntimeError("missing or duplicate N3 test discovery")
        binary = out / "n3-tests"
        run("tests", [str(compiler), "test", str(PACKAGE), "--tag", "net_core_n3", "-O2", "-j", "4",
                      "--out-dir", str(out / "objects"), "-o", str(binary),
                      "--link-arg=" + str(out / "native/libnet_core_native.a"),
                      "--link-arg=" + str(out / "fixture.o"), "--report", str(out / "tests.json")])
        result = json.loads((out / "tests.json").read_text())
        if result["passed"] != len(names) or result["failed"] or result["ignored"] or result["skipped"]:
            raise RuntimeError("not all discovered N3 cases passed")
        report["tests"] = result
        # Direct child executions isolate runtime CPU/RSS from compiler/linker use.
        for index, name in enumerate(names):
            row = run("case-" + str(index), [str(binary), str(index)], timeout=20.0)
            report["case_samples"].append({"case": name, **row})
            save()
        run("production-native", [sys.executable, str(PACKAGE / "scripts/build_native.py"),
                                  "--out-dir", str(out / "production-native"), "--cc", args.cc])
        run("production-package", [str(compiler), "precompile", str(PACKAGE / "net_core.ny"), "-O2",
                                   "-j", "4", "--out-dir", str(out / "production-objects"),
                                   "-o", str(out / "production-package")])
        run("production-imports", ["nm", "-u", str(out / "production-package/lib/libpackage.a")])
        if "net_core_test_" in (out / "production-imports.log").read_text():
            raise RuntimeError("test fixture symbols leaked into the production package")
        if source_hashes() != inputs:
            raise RuntimeError("package sources changed during acceptance")
        report["production_fixture_imports"] = []
        report["status"] = "passed"
    except (OSError, ValueError, RuntimeError) as error:
        report["status"] = "failed"
        report["error"] = str(error)
        print(str(error), file=sys.stderr)
    save()
    print(out / "acceptance.json", flush=True)
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
