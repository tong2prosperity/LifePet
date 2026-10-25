#!/usr/bin/env python3
"""Check Pibo's audited export declaration and version metadata in a real archive."""
import argparse
from pathlib import Path
import plistlib

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('archive', type=Path)
args = parser.parse_args()
archive = args.archive.resolve()
archive_info = plistlib.loads((archive / 'Info.plist').read_bytes())
app = archive / 'Products' / archive_info['ApplicationProperties']['ApplicationPath']
app_info = plistlib.loads((app / 'Info.plist').read_bytes())
version = app_info['CFBundleShortVersionString']
build = app_info['CFBundleVersion']
bundles = [app] + [p for p in app.rglob('*') if p.suffix in {'.app', '.appex'}]
for bundle in bundles:
    info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    assert info.get('ITSAppUsesNonExemptEncryption') is False, f'Missing Boolean false export declaration: {bundle}'
    assert not info.get('ITSEncryptionExportComplianceCode'), f'Unexpected non-exempt export code: {bundle}'
    assert info['CFBundleShortVersionString'] == version, f'Version mismatch: {bundle}'
    assert info['CFBundleVersion'] == build, f'Build mismatch: {bundle}'
    print(f'{bundle.name}: {version} ({build}), ITSAppUsesNonExemptEncryption = false (Boolean)')
print('Release bundle metadata verified.')
