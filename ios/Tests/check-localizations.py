"""Check all shipped native locales and printf contracts without a running app."""
import json
from pathlib import Path
import re

resources = Path(__file__).resolve().parents[1] / 'Synca' / 'Resources'
entry = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', re.M)
placeholder = re.compile(r'%(?!%)(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:ll|l|z)?[@diuoxXfFeEgGcs]')

for table in ['Localizable.strings', 'InfoPlist.strings']:
    parsed = {}
    for locale in ['en', 'zh-Hans', 'zh-Hant']:
        pairs = entry.findall((resources / (locale + '.lproj') / table).read_text())
        assert len(pairs) == len(dict(pairs)), f'{locale}/{table}: duplicate keys'
        parsed[locale] = dict(pairs)
    for locale, values in parsed.items():
        assert values.keys() == parsed['en'].keys(), f'{locale}/{table}: key mismatch {values.keys() ^ parsed["en"].keys()}'
        for key, value in values.items():
            assert value.strip(), f'{locale}/{key}: empty translation'
            assert sorted(placeholder.findall(value)) == sorted(placeholder.findall(parsed['en'][key])), f'{locale}/{key}: format argument mismatch'
    print(f'PASS {table}: {len(parsed["en"])} keys across English, Simplified and Traditional Chinese')
