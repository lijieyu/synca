"""Behavior checks for the dependency-free native CI gate (no Node installation needed)."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CHECKER = Path(__file__).with_name('check-markdown-bundle.py')
INPUTS = ('web/src/markdown/parse.ts', 'web/src/markdown/native.ts',
          'web/package-lock.json', 'web/scripts/build-markdown-parser.mjs')
OUTPUT = 'ios/Synca/Resources/markdown-parser.js'
MANIFEST = 'ios/Synca/Resources/markdown-parser.manifest.json'

class BundleGateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        hashes = {}
        for path in (*INPUTS, OUTPUT):
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('fixture: ' + path + '\n', encoding='utf-8')
            hashes[path] = hashlib.sha256(target.read_bytes()).hexdigest()
        self.manifest = {'version': 1, 'algorithm': 'sha256',
                         'inputs': {path: hashes[path] for path in INPUTS},
                         'output': {'path': OUTPUT, 'sha256': hashes[OUTPUT]}}
        self.write_manifest()

    def write_manifest(self):
        (self.root / MANIFEST).write_text(json.dumps(self.manifest), encoding='utf-8')

    def run_checker(self):
        return subprocess.run([sys.executable, str(CHECKER), '--root', str(self.root)],
                              capture_output=True, text=True)

    def test_accepts_matching_sources_and_bundle(self):
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_each_stale_input_and_modified_output(self):
        for path in (*INPUTS, OUTPUT):
            with self.subTest(path=path):
                target = self.root / path
                original = target.read_bytes()
                target.write_bytes(original + b'changed\n')
                result = self.run_checker()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(path, result.stderr)
                self.assertIn('markdown:bundle', result.stderr)
                target.write_bytes(original)

    def test_manifest_cannot_omit_a_required_input(self):
        del self.manifest['inputs'][INPUTS[0]]
        self.write_manifest()
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('manifest', result.stderr.lower())

    def test_missing_manifest_fails_closed(self):
        (self.root / MANIFEST).unlink()
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('manifest', result.stderr.lower())

if __name__ == '__main__':
    unittest.main()
