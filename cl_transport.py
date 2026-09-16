"""Discovery of external CL resources, independent of the working directory."""
import os
import sys
from pathlib import Path


def transport_roots():
    candidates = []
    if os.environ.get('CL_TRANSPORT_ROOT'):
        candidates.append(Path(os.environ['CL_TRANSPORT_ROOT']).expanduser())
    if getattr(sys, 'frozen', False):
        for parent in Path(sys.executable).resolve().parents:
            if parent.suffix == '.app':
                candidates.extend([parent.parent / 'CL_Transport', parent.parent / 'CL Audio/CL_Transport'])
                break
    candidates.extend([Path.home() / 'Applications/CL Audio/CL_Transport',
                       Path('/Applications/CL Audio/CL_Transport'),
                       Path(__file__).resolve().parent / 'CL_Transport'])
    return list(dict.fromkeys(p.resolve() for p in candidates))


def available_sessions():
    result = []
    for root in transport_roots():
        directory = root / 'ShowCue_Sessions'
        if directory.is_dir():
            for path in sorted([*directory.glob('*.showcue'), *directory.glob('*.showcue.zip')]):
                if path.is_file() and not path.is_symlink():
                    result.append({'name': path.name, 'source': str(root)})
    return result


def session_file(source, name):
    for item in available_sessions():
        if item['source'] == source and item['name'] == name:
            return Path(source) / 'ShowCue_Sessions' / name
    raise ValueError('Session transportable introuvable')


def load_library(console, legacy_store):
    from console_title_library import ConsoleLibraryStore
    key = str(console).lower()
    if key in ('cl5', 'ql1'):
        for root in transport_roots():
            value = ConsoleLibraryStore(root / 'Console_Libraries' / key.upper()).load(key)
            if value.get('library'):
                return {**value, 'source': 'CL_Transport', 'transport_root': str(root)}
    value = legacy_store.load(key)
    if value.get('library'):
        return {**value, 'source': 'fallback legacy'}
    fallback = ConsoleLibraryStore(Path(__file__).resolve().parent / 'resources/Console_Libraries' / key.upper()).load(key)
    return {**fallback, 'source': 'fallback embarqué' if fallback.get('library') else 'indisponible'}
