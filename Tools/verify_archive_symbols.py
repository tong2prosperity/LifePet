#!/usr/bin/env python3
"""Check executable dSYM UUIDs and Core's static linkage in a Pibo archive."""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('archive', type=Path)
args = parser.parse_args()
archive = args.archive.resolve()
info = plistlib.loads((archive / 'Info.plist').read_bytes())
app = archive / 'Products' / info['ApplicationProperties']['ApplicationPath']
assert not list(app.rglob('PiboCoreFFI.framework')), 'Static Core must not embed a runtime framework stub'

def uuids(path):
    result = subprocess.check_output(['xcrun', 'dwarfdump', '--uuid', str(path)], text=True)
    return set(re.findall(r'UUID: ([0-9A-F-]+)', result))

symbols = {}
for dwarf in (archive / 'dSYMs').glob('*.dSYM/Contents/Resources/DWARF/*'):
    if dwarf.is_file():
        for uuid in uuids(dwarf):
            symbols[uuid] = dwarf

bundles = [app] + [p for p in app.rglob('*') if p.suffix in {'.app', '.appex', '.framework'}]
for bundle in bundles:
    metadata = plistlib.loads((bundle / 'Info.plist').read_bytes())
    executable = bundle / metadata['CFBundleExecutable']
    binary_uuids = uuids(executable)
    assert binary_uuids, f'Missing Mach-O UUID: {executable}'
    assert binary_uuids <= set(symbols), f'Missing matching dSYM: {executable}: {binary_uuids - set(symbols)}'
    print(f'UUID/dSYM matched: {bundle.name}')

main = app / plistlib.loads((app / 'Info.plist').read_bytes())['CFBundleExecutable']
dependencies = subprocess.check_output(['xcrun', 'otool', '-L', str(main)], text=True)
assert 'PiboCoreFFI.framework' not in dependencies, 'Core must be statically linked'
main_dwarf = symbols[next(iter(uuids(main)))]
core_debug = subprocess.check_output([
    'xcrun', 'dwarfdump', '--debug-info', '--name', 'pibo_growth_level', str(main_dwarf)
], text=True)
assert 'DW_TAG_subprogram' in core_debug and '"pibo_growth_level"' in core_debug, 'Missing Rust Core debug information in app dSYM'
print('Core is statically linked; real Rust debug information is present in the app dSYM.')
