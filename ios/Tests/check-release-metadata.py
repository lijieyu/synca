#!/usr/bin/env python3
"""Check source metadata, and optionally an actual archived iOS app before upload."""
import json
import plistlib
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
version = json.loads((root / 'desktop/app/package.json').read_text())['version']
spec = (root / 'ios/Synca/project.yml').read_text()
project = (root / 'ios/Synca/Synca.xcodeproj/project.pbxproj').read_text()
assert re.search(r'MARKETING_VERSION:\s*' + re.escape(version) + r'\s', spec), 'Native release version differs from desktop'
assert set(re.findall(r'MARKETING_VERSION = ([\d.]+);', project)) == {version}, 'Generated project version differs from release'
assert 'UILaunchScreen: {}' in spec, 'XcodeGen must preserve the storyboard-free launch screen'
paths = [root / 'ios/Synca/iOS/Info.plist']
if len(sys.argv) > 1:
    paths.append(Path(sys.argv[1]) / 'Info.plist')
for path in paths:
    info = plistlib.loads(path.read_bytes())
    assert isinstance(info.get('UILaunchScreen'), dict), f'{path}: missing UILaunchScreen (ASC 90476)'
    assert 'UILaunchStoryboardName' not in info, f'{path}: obsolete storyboard reference'
    assert info.get('UIRequiresFullScreen') is False, f'{path}: iPad multitasking disabled'
    assert len(set(info.get('UISupportedInterfaceOrientations~ipad', []))) == 4, f'{path}: incomplete iPad orientations'
    if path != paths[0]:
        assert info['CFBundleShortVersionString'] == version, f'{path}: incorrect archived version'
        assert re.fullmatch(r'\d+(\.\d+){0,2}', info['CFBundleVersion']), f'{path}: invalid build number'
print(f'Release metadata verified: {version}; launch screen and iPad orientations valid')
