#!/usr/bin/env python3
# Copyright (c) 2026 tangxiangjiang
# SPDX-License-Identifier: MIT

"""Compatibility entry for the original macOS N3 acceptance command."""
import platform
from accept import main

if __name__ == "__main__":
    if platform.system() != "Darwin":
        raise SystemExit("use accept.py on Linux or Windows")
    raise SystemExit(main())
