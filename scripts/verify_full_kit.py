"""Fail a FULL distribution before export if any catalog application is missing."""
import argparse
import json
from pathlib import Path
import plistlib


def verify(root, catalog, layout):
    root = Path(root)
    applications = []
    for name, release_path in catalog['full_kit_applications'].items():
        if layout == 'release' and release_path is None:
            continue  # MTC/Sync role wrappers are assembled by the transport exporter.
        relative = Path(release_path) if layout == 'release' else Path('Applications') / name
        bundle = root / relative
        plist = bundle / 'Contents/Info.plist'
        if not plist.is_file():
            raise ValueError('Application FULL absente ou incomplète : ' + str(relative))
        info = plistlib.loads(plist.read_bytes())
        executable = info.get('CFBundleExecutable', '')
        if not executable or Path(executable).name != executable or not (bundle / 'Contents/MacOS' / executable).is_file():
            raise ValueError('Exécutable FULL absent : ' + str(relative))
        applications.append(str(relative))
    if layout == 'components':
        for component in ('audio_export', 'arrangement_builder'):
            source = catalog['components'][component]['source']
            if source not in applications:
                raise ValueError('Application hors catalogue FULL : ' + source)
            for dependency in catalog['components'][component].get('required_components', []):
                path = root / catalog['components'][dependency]['source']
                if not path.exists():
                    raise ValueError('Dépendance du kit absente : ' + str(path.relative_to(root)))
    return {'ok': True, 'layout': layout, 'applications': applications}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--layout', choices=('release', 'components'), required=True)
    parser.add_argument('--catalog', type=Path, default=Path(__file__).resolve().parents[1] / 'config/installation_roles.json')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    try:
        result = verify(args.root, json.loads(args.catalog.read_text()), args.layout)
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException) as error:
        parser.exit(1, str(error) + '\n')
    output = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.report:
        args.report.write_text(output)
    print(output, end='')


if __name__ == '__main__':
    main()
