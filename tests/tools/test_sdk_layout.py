# Copyright (c) 2026 tangxiangjiang
# SPDX-License-Identifier: MIT
"""SDK package pointers survive both published layouts and reject ambiguity/escape."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from sdk_layout import sdk_package


class SDKLayoutTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.sdk = self.root / 'sdk'
        self.sdk.mkdir()
        self.host = 'linux-x86_64'

    def fixture(self, relative):
        package = self.sdk / relative
        package.mkdir(parents=True)
        (package / 'manifest.yaml').write_text('schema_version: 5\n')
        self.metadata = {'targets': [{'key': self.host, 'packages': [{'name': 'stdlib', 'path': relative}]}]}
        self.save()
        return package

    def save(self):
        (self.sdk / 'manifest.json').write_text(json.dumps(self.metadata))

    def test_package_first_pointer(self):
        expected = self.fixture('packages/stdlib/targets/linux-x86_64')
        self.assertEqual(sdk_package(self.sdk, self.host, 'stdlib'), expected)

    def test_legacy_inventory_pointer(self):
        expected = self.fixture('targets/linux-x86_64/stdlib')
        self.assertEqual(sdk_package(self.sdk, self.host, 'stdlib'), expected)

    def test_relocated_sdk_uses_its_new_root(self):
        self.fixture('packages/stdlib/targets/linux-x86_64')
        moved = self.root / 'moved SDK'
        self.sdk.rename(moved)
        self.assertEqual(sdk_package(moved, self.host, 'stdlib'), moved / 'packages/stdlib/targets/linux-x86_64')

    def test_duplicate_or_missing_target_and_package_rejected(self):
        self.fixture('packages/stdlib/targets/linux-x86_64')
        with self.assertRaises(ValueError):
            sdk_package(self.sdk, 'windows-x86_64', 'stdlib')
        with self.assertRaises(ValueError):
            sdk_package(self.sdk, self.host, 'missing')
        self.metadata['targets'][0]['packages'] *= 2
        self.save()
        with self.assertRaises(ValueError):
            sdk_package(self.sdk, self.host, 'stdlib')
        self.metadata['targets'] *= 2
        self.save()
        with self.assertRaises(ValueError):
            sdk_package(self.sdk, self.host, 'stdlib')

    def test_unsafe_and_missing_package_paths_rejected(self):
        self.fixture('packages/stdlib/targets/linux-x86_64')
        row = self.metadata['targets'][0]['packages'][0]
        for path in ('../outside', '/absolute', 'C:/outside', 'packages\\outside', 'missing'):
            row['path'] = path
            self.save()
            with self.assertRaises(ValueError):
                sdk_package(self.sdk, self.host, 'stdlib')


if __name__ == '__main__':
    unittest.main()
