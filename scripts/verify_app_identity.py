#!/usr/bin/env python3
"""Verify built application names and exact canonical ICNS resources before export."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parents[1]


def verify(directory, expected=None):
    catalogue = {a['name']: a for a in json.loads((ROOT/'resources/app_identity.json').read_text())}
    found, errors = set(), []
    directory = Path(directory)
    for app in ([directory] if directory.suffix == '.app' else sorted(directory.rglob('*.app'))):
        name = app.stem
        if name not in catalogue:
            errors.append(f'Application non répertoriée : {app.name}')
            continue
        found.add(name)
        with (app/'Contents/Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        for key in ('CFBundleName', 'CFBundleDisplayName'):
            if info.get(key) != name:
                errors.append(f'{name}: {key}={info.get(key)!r}')
        icon = app/'Contents/Resources'/info.get('CFBundleIconFile', '')
        if not icon.is_file():
            icon = icon.with_suffix('.icns')
        source = ROOT/'assets/app_icons'/(catalogue[name]['icon']+'.icns')
        if not icon.is_file() or hashlib.sha256(icon.read_bytes()).digest() != hashlib.sha256(source.read_bytes()).digest():
            errors.append(f'{name}: icône non canonique')
    for name in set(expected or []) - found:
        errors.append(f'Application absente : {name}')
    if not found:
        errors.append('Aucune application vérifiée')
    return errors


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory')
    parser.add_argument('--suite', action='store_true')
    args = parser.parse_args()
    expected = [a['name'] for a in json.loads((ROOT/'resources/app_identity.json').read_text())
                if a['icon'] not in {'CL_Kit', 'CL_Remote'}] if args.suite else None
    errors = verify(args.directory, expected)
    for error in errors:
        print(error)
    print('Identité des applications : ' + ('ÉCHEC' if errors else 'OK'))
    raise SystemExit(bool(errors))
