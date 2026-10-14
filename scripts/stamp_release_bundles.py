#!/usr/bin/env python3
"""Stamp temporary distribution copies only, before their final signature."""
import argparse
import json
import plistlib
from pathlib import Path


def stamp(root, version, build):
    entries = []
    for plist in sorted(root.rglob('*.app/Contents/Info.plist')):
        with plist.open('rb') as stream:
            data = plistlib.load(stream)
        previous = str(data.get('CFBundleVersion', '0'))
        if previous.isdecimal() and int(previous) > int(build):
            raise ValueError(f'Build downgrade refused: {plist}: {previous} > {build}')
        data['CFBundleShortVersionString'] = version
        data['CFBundleVersion'] = build
        with plist.open('wb') as stream:
            plistlib.dump(data, stream)
        entries.append({'app': str(plist.parent.parent.relative_to(root)),
                        'identifier': data.get('CFBundleIdentifier'),
                        'version': version, 'build': build})
    if not entries:
        raise ValueError('No application bundles found')
    return entries

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--manifest', type=Path)
    args = parser.parse_args()
    entries = stamp(args.root, args.version, args.build)
    if args.manifest:
        args.manifest.write_text(json.dumps({'version': args.version, 'build': args.build,
                                            'applications': entries}, indent=2) + '\n')
