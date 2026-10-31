# Copyright (c) 2026 tangxiangjiang
# SPDX-License-Identifier: MIT
"""Resolve an exact SDK target package through its authenticated JSON inventory."""
import json
from pathlib import Path, PurePosixPath


def sdk_package(sdk: Path, host: str, name: str) -> Path:
    sdk = sdk.resolve()
    metadata = json.loads((sdk / 'manifest.json').read_text())
    targets = [row for row in metadata['targets'] if row['key'] == host]
    if len(targets) != 1:
        raise ValueError('SDK target must have exactly one inventory row: ' + host)
    packages = [row for row in targets[0]['packages'] if row['name'] == name]
    if len(packages) != 1:
        raise ValueError('SDK package must have exactly one inventory row: ' + name)
    value = packages[0]['path']
    relative = PurePosixPath(value)
    if relative.is_absolute() or '..' in relative.parts or '\\' in value or ':' in value:
        raise ValueError('unsafe SDK package path')
    package = (sdk / relative).resolve()
    if not package.is_relative_to(sdk) or package == sdk or not (package / 'manifest.yaml').is_file():
        raise ValueError('missing or escaped SDK target package')
    return package
