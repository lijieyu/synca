#!/usr/bin/env python3
"""Reject stale bundled Markdown in native CI using only the Python standard library."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

INPUTS = {'web/src/markdown/parse.ts', 'web/src/markdown/native.ts',
          'web/package-lock.json', 'web/scripts/build-markdown-parser.mjs'}
OUTPUT = 'ios/Synca/Resources/markdown-parser.js'
MANIFEST = 'ios/Synca/Resources/markdown-parser.manifest.json'


def check(root):
    try:
        manifest = json.loads((root / MANIFEST).read_text(encoding='utf-8'))
        if (manifest.get('version') != 1 or manifest.get('algorithm') != 'sha256'
                or set(manifest.get('inputs', {})) != INPUTS
                or manifest.get('output', {}).get('path') != OUTPUT):
            raise ValueError('invalid Markdown bundle manifest schema')
        hashes = {**manifest['inputs'], OUTPUT: manifest['output']['sha256']}
        for path, expected in hashes.items():
            if not isinstance(expected, str) or not re.fullmatch(r'[0-9a-f]{64}', expected):
                raise ValueError('invalid manifest hash for ' + path)
            actual = hashlib.sha256((root / path).read_bytes()).hexdigest()
            if actual != expected:
                raise ValueError('stale Markdown bundle input/output: ' + path)
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        print('Markdown bundle verification failed: ' + str(error)
              + '\nRun npm run markdown:bundle in web, then commit the bundle and manifest.', file=sys.stderr)
        return 1
    print('Markdown bundle manifest matches all parser inputs and bundled output.')
    return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1],
                        help='repository root (defaults to this script\'s repository)')
    sys.exit(check(parser.parse_args().root))
