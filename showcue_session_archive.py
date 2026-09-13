"""One portable .showcue.zip envelope around existing ShowCue documents."""
import io
import json
import shutil
import tempfile
import uuid
import zipfile
from pathlib import Path
from show_cues import (session_directory, load_show_document, save_show_document,
                      save_session_registry, _normalize_session_name)
from showcue_builder import load_builder_document, save_builder_document

MAX_ARCHIVE_BYTES = 256 * 1024 * 1024


def export_session(root, registry, session_id):
    session = next((s for s in registry['sessions'] if s['id'] == session_id), None)
    if session is None:
        raise ValueError('Session inconnue')
    directory = session_directory(root, session_id)
    document = load_show_document(directory / 'show_cues.json')
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('manifest.json', json.dumps({'format': 'CL ShowCue', 'version': 1, 'name': session['name']}))
        archive.writestr('show_cues.json', json.dumps(document, ensure_ascii=False))
        if (directory / 'showcue_builder.json').is_file():
            archive.writestr('showcue_builder.json', json.dumps(load_builder_document(directory / 'showcue_builder.json'), ensure_ascii=False))
        for cue in document['cues']:
            audio = cue.get('audio')
            if audio:
                path = directory / 'show_cues_audio' / audio['filename']
                if path.is_file() and 'show_cues_audio/' + path.name not in archive.namelist():
                    archive.write(path, 'show_cues_audio/' + path.name)
    return output.getvalue()


def import_session(data, root, registry):
    if len(data) > MAX_ARCHIVE_BYTES:
        raise ValueError('Archive trop volumineuse')
    root = Path(root)
    session_id = 'session_' + uuid.uuid4().hex
    destination = session_directory(root, session_id)
    with tempfile.TemporaryDirectory() as temporary:
        staging = Path(temporary)
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                infos = archive.infolist()
                names = [i.filename for i in infos]
                if len(names) != len(set(names)) or len(names) > 10000 or sum(i.file_size for i in infos) > MAX_ARCHIVE_BYTES:
                    raise ValueError('Archive invalide ou trop volumineuse')
                for name in names:
                    if name not in ('manifest.json', 'show_cues.json', 'showcue_builder.json'):
                        from show_cues import AUDIO_FILENAME_PATTERN
                        parts = name.split('/')
                        if len(parts) != 2 or parts[0] != 'show_cues_audio' or not AUDIO_FILENAME_PATTERN.fullmatch(parts[1]):
                            raise ValueError('Chemin interdit dans l’archive')
                manifest = json.loads(archive.read('manifest.json'))
                if manifest.get('format') != 'CL ShowCue' or manifest.get('version') != 1:
                    raise ValueError('Format de session inconnu')
                name = _normalize_session_name(manifest.get('name'))
                used = {s['name'].casefold() for s in registry['sessions']}
                base, number = name, 2
                while name.casefold() in used:
                    name = base[:100] + f' ({number})'
                    number += 1
                for member in names:
                    if member == 'manifest.json':
                        continue
                    path = staging / member
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(archive.read(member))
        except (zipfile.BadZipFile, KeyError, TypeError, RuntimeError) as exc:
            raise ValueError('Archive ShowCue invalide') from exc
        document = load_show_document(staging / 'show_cues.json')
        save_show_document(staging / 'show_cues.json', document)
        if (staging / 'showcue_builder.json').exists():
            save_builder_document(staging / 'showcue_builder.json', load_builder_document(staging / 'showcue_builder.json'))
        for cue in document['cues']:
            if cue.get('audio') and not (staging / 'show_cues_audio' / cue['audio']['filename']).is_file():
                raise ValueError('Audio référencé absent de l’archive')
        updated = {**registry, 'sessions': [*registry['sessions'], {'id': session_id, 'name': name}]}
        destination.mkdir(parents=True, exist_ok=False)
        try:
            shutil.copytree(staging, destination, dirs_exist_ok=True)
            save_session_registry(root / 'sessions.json', updated)
        except Exception:
            if destination.exists():
                shutil.rmtree(destination)
            raise
    return updated
