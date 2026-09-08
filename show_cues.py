"""Stockage et sélection de CL ShowCue, indépendants du transport Ableton."""

from __future__ import annotations

import json
import os
import re
import shutil
import tempfile
import uuid
from pathlib import Path

SHOW_POSTS = ("FOH", "RETOURS", "PLATEAU", "LUMIERE")
SHOW_MODES = ("timed", "manual", "library")
SHOW_STATUSES = ("official", "draft")
SHOW_SECTIONS = ("SHOW", "INTERMÈDE", "PRÉPARATION", "MUSIQUE", "LIGHT", "MICROS",
                 "IEM", "ARTISTES", "COSTUMES", "TECHNIQUE")
TIMECODE_PATTERN = re.compile(r"^(\d{2}):(\d{2}):(\d{2}):(\d{2})$")
ID_PATTERN = re.compile(r"^cue_[A-Za-z0-9_-]+$")
AUDIO_FILENAME_PATTERN = re.compile(r"^cue_[A-Za-z0-9_-]+\.(webm|ogg|mp4|m4a|wav)$")
SHOW_CUE_DATA_DIRECTORY = Path("Library") / "Application Support" / "CL Audio Show Control" / "ShowCue"
SESSION_ID_PATTERN = re.compile(r"^session_[A-Za-z0-9_-]+$")
SESSION_NAME_MAX_LENGTH = 120


def persistent_show_cue_directory(home: Path | None = None) -> Path:
    """Résout la base utilisateur sans dépendre du cwd ni du bundle."""
    return (Path(home) if home is not None else Path.home()) / SHOW_CUE_DATA_DIRECTORY


def initialize_show_cue_storage(data_directory: Path, historical_directories=()):
    """Crée ou migre une seule fois la base persistante ShowCue.

    Une base persistante présente est toujours prioritaire. Les sources historiques
    sont examinées dans l'ordre explicite fourni, sans recherche sur le disque.
    """
    data_directory = Path(data_directory)
    destination = data_directory / "show_cues.json"
    audio_destination = data_directory / "show_cues_audio"
    if destination.exists():
        load_show_document(destination)
        return destination, audio_destination

    source = None
    document = None
    for directory in historical_directories:
        candidate = Path(directory) / "show_cues.json"
        if candidate == destination or not candidate.is_file():
            continue
        try:
            candidate_document = load_show_document(candidate)
        except (OSError, ValueError, json.JSONDecodeError):
            continue
        source, document = candidate, candidate_document
        break

    data_directory.mkdir(parents=True, exist_ok=True)
    copied_audio = []
    try:
        if source is not None:
            source_audio = source.parent / "show_cues_audio"
            for cue in document["cues"]:
                audio = cue.get("audio")
                if not audio:
                    continue
                source_file = source_audio / audio["filename"]
                if not source_file.is_file():
                    continue
                audio_destination.mkdir(parents=True, exist_ok=True)
                destination_file = audio_destination / audio["filename"]
                temporary_file = audio_destination / f".{audio['filename']}.migration.tmp"
                if destination_file.exists() or temporary_file.exists():
                    raise FileExistsError(f"collision audio ShowCue : {audio['filename']}")
                shutil.copyfile(source_file, temporary_file)
                with temporary_file.open("rb") as handle:
                    os.fsync(handle.fileno())
                os.replace(temporary_file, destination_file)
                copied_audio.append(destination_file)
        save_show_document(destination, document or {"version": 1, "cues": []})
        load_show_document(destination)
    except Exception:
        for path in copied_audio:
            path.unlink(missing_ok=True)
        raise
    return destination, audio_destination


def _normalize_session_name(value) -> str:
    name = str(value or "").strip()
    if not name or len(name) > SESSION_NAME_MAX_LENGTH or any(ord(char) < 32 for char in name):
        raise ValueError("nom de session invalide")
    return name


def load_session_registry(path: Path):
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or payload.get("version") != 1:
        raise ValueError("registre de sessions ShowCue invalide")
    raw_sessions = payload.get("sessions")
    if not isinstance(raw_sessions, list) or not raw_sessions:
        raise ValueError("registre de sessions ShowCue vide")
    sessions, used = [], set()
    for raw in raw_sessions:
        if not isinstance(raw, dict):
            raise ValueError("session ShowCue invalide")
        session_id = str(raw.get("id") or "").strip()
        if not SESSION_ID_PATTERN.fullmatch(session_id) or session_id in used:
            raise ValueError("identifiant de session ShowCue invalide ou dupliqué")
        used.add(session_id)
        sessions.append({"id": session_id, "name": _normalize_session_name(raw.get("name"))})
    active = str(payload.get("active_session_id") or "").strip()
    if active not in used:
        raise ValueError("session active ShowCue invalide")
    return {"version": 1, "active_session_id": active, "sessions": sessions}


def save_session_registry(path: Path, registry):
    normalized = {"version": 1, "active_session_id": registry.get("active_session_id"),
                  "sessions": registry.get("sessions")}
    # Validation avant toute écriture, puis même discipline atomique que les cues.
    with tempfile.TemporaryDirectory() as directory:
        validation_path = Path(directory) / "sessions.json"
        validation_path.write_text(json.dumps(normalized, ensure_ascii=False), encoding="utf-8")
        normalized = load_session_registry(validation_path)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(normalized, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    except Exception:
        try:
            os.unlink(temporary_name)
        except OSError:
            pass
        raise


def session_directory(data_directory: Path, session_id: str) -> Path:
    if not SESSION_ID_PATTERN.fullmatch(str(session_id or "")):
        raise ValueError("identifiant de session invalide")
    return Path(data_directory) / "Sessions" / session_id


def _copy_session_content(source_directory: Path, destination_directory: Path):
    if destination_directory.exists():
        raise FileExistsError(f"session déjà présente : {destination_directory.name}")
    document = load_show_document(source_directory / "show_cues.json")
    destination_directory.mkdir(parents=True)
    try:
        audio_destination = destination_directory / "show_cues_audio"
        for cue in document["cues"]:
            audio = cue.get("audio")
            if not audio:
                continue
            source_file = source_directory / "show_cues_audio" / audio["filename"]
            if source_file.is_file():
                audio_destination.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source_file, audio_destination / audio["filename"])
        save_show_document(destination_directory / "show_cues.json", document)
    except Exception:
        shutil.rmtree(destination_directory, ignore_errors=True)
        raise


def initialize_show_cue_sessions(data_directory: Path, historical_directories=()):
    data_directory = Path(data_directory)
    registry_path = data_directory / "sessions.json"
    if registry_path.exists():
        registry = load_session_registry(registry_path)
        active_directory = session_directory(data_directory, registry["active_session_id"])
        load_show_document(active_directory / "show_cues.json")
        return registry

    legacy_path, _ = initialize_show_cue_storage(data_directory, historical_directories)
    initial_id = "session_initiale"
    initial_directory = session_directory(data_directory, initial_id)
    if not initial_directory.exists():
        _copy_session_content(legacy_path.parent, initial_directory)
    else:
        load_show_document(initial_directory / "show_cues.json")
    registry = {
        "version": 1, "active_session_id": initial_id,
        "sessions": [{"id": initial_id, "name": "Session actuelle"}],
    }
    save_session_registry(registry_path, registry)
    return registry


def active_session_paths(data_directory: Path, registry):
    directory = session_directory(data_directory, registry["active_session_id"])
    return directory / "show_cues.json", directory / "show_cues_audio"


def create_show_cue_session(data_directory: Path, registry, name: str):
    session_id = f"session_{uuid.uuid4().hex[:16]}"
    directory = session_directory(data_directory, session_id)
    directory.mkdir(parents=True)
    try:
        save_show_document(directory / "show_cues.json", {"version": 1, "cues": []})
        updated = {"version": 1, "active_session_id": session_id,
                   "sessions": [*registry["sessions"],
                                {"id": session_id, "name": _normalize_session_name(name)}]}
        save_session_registry(Path(data_directory) / "sessions.json", updated)
    except Exception:
        shutil.rmtree(directory, ignore_errors=True)
        raise
    return updated


def activate_show_cue_session(data_directory: Path, registry, session_id: str):
    if session_id not in {item["id"] for item in registry["sessions"]}:
        raise KeyError(session_id)
    load_show_document(session_directory(data_directory, session_id) / "show_cues.json")
    updated = {**registry, "active_session_id": session_id}
    save_session_registry(Path(data_directory) / "sessions.json", updated)
    return updated


def rename_show_cue_session(data_directory: Path, registry, session_id: str, name: str):
    if session_id not in {item["id"] for item in registry["sessions"]}:
        raise KeyError(session_id)
    updated = {**registry, "sessions": [
        {**item, "name": _normalize_session_name(name)} if item["id"] == session_id else item
        for item in registry["sessions"]
    ]}
    save_session_registry(Path(data_directory) / "sessions.json", updated)
    return updated


def duplicate_show_cue_session(data_directory: Path, registry, session_id: str, name: str):
    if session_id not in {item["id"] for item in registry["sessions"]}:
        raise KeyError(session_id)
    duplicate_id = f"session_{uuid.uuid4().hex[:16]}"
    _copy_session_content(session_directory(data_directory, session_id),
                          session_directory(data_directory, duplicate_id))
    try:
        updated = {"version": 1, "active_session_id": duplicate_id,
                   "sessions": [*registry["sessions"],
                                {"id": duplicate_id, "name": _normalize_session_name(name)}]}
        save_session_registry(Path(data_directory) / "sessions.json", updated)
    except Exception:
        shutil.rmtree(session_directory(data_directory, duplicate_id), ignore_errors=True)
        raise
    return updated


def delete_show_cue_session(data_directory: Path, registry, session_id: str):
    sessions = [item for item in registry["sessions"] if item["id"] != session_id]
    if len(sessions) == len(registry["sessions"]):
        raise KeyError(session_id)
    if not sessions:
        raise ValueError("impossible de supprimer l’unique session")
    active = (sessions[0]["id"] if registry["active_session_id"] == session_id
              else registry["active_session_id"])
    updated = {"version": 1, "active_session_id": active, "sessions": sessions}
    save_session_registry(Path(data_directory) / "sessions.json", updated)
    shutil.rmtree(session_directory(data_directory, session_id))
    return updated


def timecode_to_units(timecode: str) -> int:
    """Convertit HH:MM:SS:FF en unité ordonnable, sans créer d'horloge."""
    match = TIMECODE_PATTERN.fullmatch(str(timecode or "").strip())
    if not match:
        raise ValueError(f"timecode invalide : {timecode!r}")
    hours, minutes, seconds, frames = map(int, match.groups())
    if hours > 99 or minutes > 59 or seconds > 59 or frames > 99:
        raise ValueError(f"timecode invalide : {timecode!r}")
    return (((hours * 60) + minutes) * 60 + seconds) * 100 + frames


def _new_cue_id(existing_ids) -> str:
    existing = set(existing_ids)
    while True:
        cue_id = f"cue_{uuid.uuid4().hex[:12]}"
        if cue_id not in existing:
            return cue_id


def _normalize_posts(value, *, required=True):
    if not isinstance(value, (list, tuple)):
        raise ValueError("posts doit être une liste")
    posts = list(dict.fromkeys(str(post).strip().upper() for post in value))
    if (required and not posts) or any(post not in SHOW_POSTS for post in posts):
        raise ValueError("poste destinataire invalide")
    return posts


def normalize_new_section(value, existing=()):
    section = str(value or "").strip() or "SANS SECTION"
    for known in (*SHOW_SECTIONS, *existing):
        if section.casefold() == str(known).casefold():
            return str(known)
    return section


def _normalize_cue(raw, index, used_ids):
    if not isinstance(raw, dict):
        raise ValueError(f"cue #{index + 1} invalide")
    cue_id = str(raw.get("id") or "").strip()
    if not cue_id:  # Compatibilité avec le JSON du premier prototype.
        cue_id = f"cue_{index + 1:04d}"
        if cue_id in used_ids:
            cue_id = _new_cue_id(used_ids)
    if not ID_PATTERN.fullmatch(cue_id) or cue_id in used_ids:
        raise ValueError(f"cue #{index + 1} : identifiant invalide ou dupliqué")
    used_ids.add(cue_id)
    mode = str(raw.get("mode") or "timed").strip().lower()
    status = str(raw.get("status") or "official").strip().lower()
    text = str(raw.get("text") or "").strip()
    if mode not in SHOW_MODES or status not in SHOW_STATUSES or not text:
        raise ValueError(f"cue {cue_id} : mode, statut ou texte invalide")
    cue = {"id": cue_id, "mode": mode, "text": text,
           "posts": _normalize_posts(raw.get("posts", ())), "status": status}
    builder = raw.get("builder")
    if builder is not None:
        if not isinstance(builder, dict):
            raise ValueError(f"cue {cue_id} : metadata Builder invalide")
        allowed = ("builder_id", "number", "source", "type", "section", "role", "artist_override",
                   "microphone_override", "iem_override", "equipment_override",
                   "origin", "notes", "resolved_artist", "resolved_microphone",
                   "resolved_iem", "resolved_equipment")
        cue["builder"] = {key: str(builder.get(key) or "").strip()
                          for key in allowed if str(builder.get(key) or "").strip()}
        slots = builder.get("resolved_equipment_slots")
        if slots is not None:
            if not isinstance(slots, list) or len(slots) > 3 or any(
                    not isinstance(slot, dict) for slot in slots):
                raise ValueError(f"cue {cue_id} : équipements Builder invalides")
            cue["builder"]["resolved_equipment_slots"] = [
                {"type": str(slot.get("type") or "").strip(),
                 "value": str(slot.get("value") or "").strip()}
                for slot in slots
            ]
    audio = raw.get("audio")
    if audio is not None:
        if not isinstance(audio, dict):
            raise ValueError(f"cue {cue_id} : audio invalide")
        filename = str(audio.get("filename") or "").strip()
        mime_type = str(audio.get("mime_type") or "application/octet-stream").strip()
        if (not AUDIO_FILENAME_PATTERN.fullmatch(filename)
                or not filename.startswith(f"{cue_id}.")):
            raise ValueError(f"cue {cue_id} : fichier audio invalide")
        cue["audio"] = {"filename": filename, "mime_type": mime_type}
    if mode == "timed":
        cue["timecode"] = str(raw.get("timecode") or "").strip()
        cue["_position"] = timecode_to_units(cue["timecode"])
    elif mode == "manual":
        cue["section"] = str(raw.get("section") or "SANS SECTION").strip() or "SANS SECTION"
        try:
            cue["order"] = int(raw.get("order", index + 1))
        except (TypeError, ValueError) as exc:
            raise ValueError(f"cue {cue_id} : ordre invalide") from exc
        if cue["order"] < 1:
            raise ValueError(f"cue {cue_id} : ordre invalide")
        anchor_after = str(raw.get("anchor_after") or "").strip()
        if anchor_after:
            if not ID_PATTERN.fullmatch(anchor_after) or anchor_after == cue_id:
                raise ValueError(f"cue {cue_id} : ancre invalide")
            cue["anchor_after"] = anchor_after
    return cue


def load_document_data(document):
    if not isinstance(document, dict) or not isinstance(document.get("cues"), list):
        raise ValueError("document ShowCue invalide")
    used_ids = set()
    cues = [_normalize_cue(raw, index, used_ids)
            for index, raw in enumerate(document["cues"])]
    return {"version": 1, "cues": cues}


def load_show_document(path: Path):
    payload = json.loads(path.read_text(encoding="utf-8"))
    return load_document_data(payload)


def load_show_cues(path: Path):
    """Alias compatible avec le premier prototype."""
    return load_show_document(path)["cues"]


def _public_cue(cue):
    return {key: value for key, value in cue.items() if not key.startswith("_")}


def save_show_document(path: Path, document):
    """Valide puis remplace atomiquement le JSON, dans son répertoire final."""
    normalized = load_document_data(document)
    public = {"version": 1, "cues": [_public_cue(cue) for cue in normalized["cues"]]}
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(public, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    except Exception:
        try:
            os.unlink(temporary_name)
        except OSError:
            pass
        raise


def create_show_cue(document, values):
    cues = list(document["cues"])
    data = dict(values or {})
    data["id"] = _new_cue_id(cue["id"] for cue in cues)
    data.setdefault("status", "draft")
    if str(data.get("mode") or "") == "manual":
        section = normalize_new_section(data.get("section"),
                                        [cue.get("section") for cue in cues if cue["mode"] == "manual"])
        orders = [int(cue["order"]) for cue in cues
                  if cue["mode"] == "manual" and cue.get("section") == section]
        data["section"] = section
        data.setdefault("order", max(orders, default=0) + 1)
    cue = _normalize_cue(data, len(cues), {item["id"] for item in cues})
    cues.append(cue)
    return {"version": 1, "cues": cues}, _public_cue(cue)


def update_show_cue(document, cue_id, values):
    cues = list(document["cues"])
    for index, current in enumerate(cues):
        if current["id"] != cue_id:
            continue
        updated = _public_cue(current)
        for key in ("mode", "text", "posts", "status", "timecode", "section", "order",
                    "anchor_after", "audio", "builder"):
            if key in values:
                updated[key] = values[key]
        used_ids = {cue["id"] for position, cue in enumerate(cues) if position != index}
        if str(updated.get("mode") or "") == "manual" and "section" in values:
            updated["section"] = normalize_new_section(values["section"], [
                cue.get("section") for position, cue in enumerate(cues)
                if position != index and cue["mode"] == "manual"])
        normalized = _normalize_cue(updated, index, used_ids)
        cues[index] = normalized
        return {"version": 1, "cues": cues}, _public_cue(normalized)
    raise KeyError(cue_id)


def delete_show_cue(document, cue_id):
    """Retire un cue et renvoie sa vue publique; le fichier reste géré par l'appelant."""
    cues = list(document["cues"])
    for index, cue in enumerate(cues):
        if cue["id"] == cue_id:
            removed = _public_cue(cues.pop(index))
            return {"version": 1, "cues": cues}, removed
    raise KeyError(cue_id)


def select_timed_cues(cues, timecode, post=None):
    """Sélectionne une fenêtre timed avec la même règle de franchissement."""
    position = timecode_to_units(timecode)
    if post is not None:
        post = str(post or "").strip().upper()
        if post not in SHOW_POSTS:
            raise ValueError(f"poste invalide : {post!r}")
    filtered = [cue for cue in cues if cue.get("mode", "timed") == "timed"
                and (post is None or post in cue.get("posts", ()))]
    filtered.sort(key=lambda cue: (
        cue["_position"] if "_position" in cue else timecode_to_units(cue["timecode"]),
        cue["id"],
    ))
    current_index = -1
    for index, cue in enumerate(filtered):
        cue_position = cue["_position"] if "_position" in cue else timecode_to_units(cue["timecode"])
        if int(cue_position) <= position:
            current_index = index
        else:
            break
    def at(index):
        return _public_cue(filtered[index]) if 0 <= index < len(filtered) else None
    return {
        "previous_second": at(current_index - 2),
        "previous": at(current_index - 1),
        "current": at(current_index),
        "next": at(current_index + 1),
        "following": at(current_index + 2),
    }


def select_show_cues(cues, timecode, post):
    return select_timed_cues(cues, timecode, post)


def show_cues_for_post(cues, post, mode):
    post = str(post or "").strip().upper()
    if post not in SHOW_POSTS or mode not in SHOW_MODES:
        raise ValueError("filtre ShowCue invalide")
    filtered = [cue for cue in cues if cue["mode"] == mode and post in cue["posts"]]
    if mode == "manual":
        filtered.sort(key=lambda cue: (cue.get("section", "").casefold(), cue["order"], cue["id"]))
    return [_public_cue(cue) for cue in filtered]


def show_cues_for_conduite(cues, mode):
    """Expose un mode complet pour l'organisation, sans dépendre du poste local."""
    if mode not in SHOW_MODES:
        raise ValueError("mode ShowCue invalide")
    filtered = [cue for cue in cues if cue["mode"] == mode]
    if mode == "timed":
        filtered.sort(key=lambda cue: (
            cue.get("_position", timecode_to_units(cue["timecode"])), cue["id"]))
    elif mode == "manual":
        filtered.sort(key=lambda cue: (
            cue.get("section", "").casefold(), cue["order"], cue["id"]))
    return [_public_cue(cue) for cue in filtered]


def select_manual_cue(cues, post, section, index):
    manual = [cue for cue in show_cues_for_post(cues, post, "manual")
              if cue["section"] == section]
    if not manual:
        return {"current": None, "previous": None, "next": None, "index": 0}
    position = max(0, min(int(index), len(manual) - 1))
    return {
        "current": manual[position],
        "previous": manual[position - 1] if position > 0 else None,
        "next": manual[position + 1] if position + 1 < len(manual) else None,
        "index": position,
    }
