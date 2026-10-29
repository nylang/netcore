#!/usr/bin/env python3
# Copyright (c) 2026 tangxiangjiang
# SPDX-License-Identifier: MIT

"""Validate successful native CI candidates and create a GitHub draft release."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

PACKAGE = Path(__file__).resolve().parents[1]
TARGETS = ('darwin-arm64', 'linux-x86_64', 'windows-x86_64', 'android-arm64',
           'android-x86_64', 'ios-arm64', 'ios-simulator-arm64')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--assets', type=Path, required=True)
    parser.add_argument('--prepare-only', action='store_true', help='validate and write checksums/notes without contacting GitHub')
    args = parser.parse_args()
    version = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$', (PACKAGE / 'package.yaml').read_text(), re.M)
    if not version or args.tag != 'v' + version.group(1):
        parser.error('tag must exactly match package.yaml version')
    files = sorted(args.assets.glob('*.zip'))
    expected = {f'net-core-{version.group(1)}-{target}-native.zip' for target in TARGETS}
    if {p.name for p in files} != expected:
        parser.error('expected exactly the seven successful target-native candidates')
    checksums = args.assets / 'SHA256SUMS'
    checksums.write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n' for p in files), encoding='utf-8')
    notes = args.assets / 'RELEASE-NOTES.md'
    notes.write_text('''# Native component candidates

These MIT-licensed assets contain net_core native adapters, licenses and build
receipts. They are not complete Nyra SDKs or relocatable precompiled Nyra packages.
Use this tag's source checkout and the matching public SDK to build applications.

Linux/Windows candidates passed the N3 Nyra behavior suite and isolated replays.
macOS and Android/iOS candidates passed native build/link gates as documented.
The public SDK 1.0.0 macOS compiler requires macOS 27. Before publishing this draft,
review matching-commit macOS Nyra acceptance on a compatible Mac. Mobile device
runtime acceptance, signing, and published SDK integration are separate gates.
This workflow creates a draft; it never publishes it automatically.
''', encoding='utf-8')
    if not args.prepare_only:
        existing = subprocess.run(['gh', 'release', 'view', args.tag, '--json', 'isDraft'],
                                  cwd=PACKAGE, text=True, capture_output=True)
        if existing.returncode == 0:
            if json.loads(existing.stdout).get('isDraft') is not True:
                parser.error('refusing to modify an already published release')
            subprocess.run(['gh', 'release', 'upload', args.tag, *map(str, files), str(checksums), '--clobber'], cwd=PACKAGE, check=True)
            subprocess.run(['gh', 'release', 'edit', args.tag, '--notes-file', str(notes)], cwd=PACKAGE, check=True)
        else:
            subprocess.run(['gh', 'release', 'create', args.tag, *map(str, files), str(checksums),
                            '--draft', '--verify-tag', '--title', 'net_core ' + version.group(1),
                            '--notes-file', str(notes)], cwd=PACKAGE, check=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
