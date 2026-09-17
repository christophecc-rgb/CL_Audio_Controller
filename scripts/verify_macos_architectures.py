#!/usr/bin/env python3
"""Fail closed if any shipped Mach-O lacks a requested CPU architecture."""
import argparse
import json
from pathlib import Path
import subprocess

MAGICS = {bytes.fromhex(h) for h in ('cffaedfe', 'cefaedfe', 'feedfacf', 'feedface',
                                    'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}
TARGETS = {'arm64': {'arm64'}, 'x86_64': {'x86_64'}, 'universal2': {'arm64', 'x86_64'}}


def audit(root, target):
    root = Path(root).resolve()
    if not root.exists():
        raise FileNotFoundError(root)
    rows, errors = [], []
    for path in sorted(root.rglob('*')) if root.is_dir() else [root]:
        if path.is_symlink() or not path.is_file():
            continue
        with path.open('rb') as stream:
            if stream.read(4) not in MAGICS:
                continue
        result = subprocess.run(['/usr/bin/lipo', '-archs', str(path)],
                                capture_output=True, text=True)
        archs = result.stdout.strip().split()
        name = str(path.relative_to(root)) if root.is_dir() else path.name
        rows.append({'path': name, 'architectures': archs})
        if result.returncode or not TARGETS[target].issubset(archs):
            errors.append(f'{name}: {archs or result.stderr.strip()} (attendu: {target})')
    if not rows:
        errors.append('Aucun binaire Mach-O trouvé')
    return {'target': target, 'binaries': rows, 'errors': errors, 'ok': not errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--target', choices=TARGETS, default='universal2')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    report = audit(args.root, args.target)
    if args.report:
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(f"{args.root}: {len(report['binaries'])} binaires, cible {args.target}")
    for error in report['errors']:
        print(error)
    raise SystemExit(0 if report['ok'] else 1)


if __name__ == '__main__':
    main()
