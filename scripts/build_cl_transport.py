"""Non-destructive assembly; existing, different files receive a numbered name."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path


def copy_resource(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    original, index = target, 2
    while target.exists():
        if source.read_bytes() == target.read_bytes():
            print('Identique :', target)
            return target
        target = original.with_name(original.stem + f' ({index})' + original.suffix)
        index += 1
    shutil.copy2(source, target)
    print('Copié :', source, '→', target)
    return target


def build(destination, libraries, sessions=()):
    destination = Path(destination)
    (destination / 'ShowCue_Sessions').mkdir(parents=True, exist_ok=True)
    for console in ('CL5', 'QL1'):
        folder = destination / 'Console_Libraries' / console
        folder.mkdir(parents=True, exist_ok=True)
        source = Path(libraries) / console / (console + '.titles.json')
        if not source.is_file():
            raise FileNotFoundError(source)
        target = folder / source.name
        # The canonical name determines runtime lookup. Never silently replace it.
        if target.exists() and target.read_bytes() != source.read_bytes():
            raise FileExistsError(f'Bibliothèque différente déjà présente : {target}')
        copy_resource(source, target)
    for directory in sessions:
        sources = sorted(
            list(Path(directory).glob('*.showcue')) +
            list(Path(directory).glob('*.showcue.zip'))
        )
        for source in sources:
            if source.is_file():
                copy_resource(source, destination / 'ShowCue_Sessions' / source.name)
    files = {str(p.relative_to(destination)): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in sorted(destination.rglob('*')) if p.is_file() and p.name != 'manifest.json'}
    (destination / 'manifest.json').write_text(json.dumps({'format': 'CL_Transport', 'version': 1, 'files': files}, indent=2) + '\n')
    print('Transport :', destination)


if __name__ == '__main__':
    project = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument('destination', nargs='?', default=str(project / 'CL_Transport'))
    parser.add_argument('--libraries', default=str(project / 'resources/Console_Libraries'))
    parser.add_argument('--sessions', action='append', default=[])
    args = parser.parse_args()
    build(args.destination, args.libraries, args.sessions or [project / 'CL_Transport/ShowCue_Sessions', project / 'Exports'])
