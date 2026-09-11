"""Modèle métier de CL Show Audio Builder.

Ce module reste volontairement indépendant :
- de Flask ;
- de la logique MIDI ;
- du LTC ;
- du transport AbletonOSC ;
- de CL ShowCue LIVE.

Il décrit uniquement les variantes audio d'un numéro de spectacle.
"""

from __future__ import annotations

from copy import deepcopy
from typing import Any


DOCUMENT_VERSION = 1


def _text(value: Any) -> str:
    return str(value or "").strip()


def _boolean(value: Any, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)

    text = str(value).strip().casefold()
    if text in {"1", "true", "yes", "oui", "on"}:
        return True
    if text in {"0", "false", "no", "non", "off", ""}:
        return False
    raise ValueError(f"valeur booléenne invalide : {value!r}")


def empty_show_audio_document() -> dict:
    return {
        "version": DOCUMENT_VERSION,
        "revision": 0,
        "variants": [],
    }


def normalize_variant(raw: dict, index: int = 1) -> dict:
    if not isinstance(raw, dict):
        raise ValueError(f"variante audio #{index} invalide")

    number = _text(raw.get("number"))
    title = _text(raw.get("title"))
    role = _text(raw.get("role"))
    artist = _text(raw.get("artist"))
    key = _text(raw.get("key"))
    playback = _text(raw.get("playback"))

    scene_index_raw = raw.get("scene_index")
    scene_index = None
    if scene_index_raw not in (None, ""):
        try:
            scene_index = int(scene_index_raw)
        except (TypeError, ValueError) as exc:
            raise ValueError(
                f"variante audio #{index} : scene_index invalide"
            ) from exc
        if scene_index < 0:
            raise ValueError(
                f"variante audio #{index} : scene_index invalide"
            )

    variant_id = _text(raw.get("id"))
    if not variant_id:
        parts = [
            number or str(index),
            title,
            role,
            artist,
        ]
        variant_id = "::".join(part.casefold() for part in parts)

    return {
        "id": variant_id,
        "number": number,
        "title": title,
        "role": role,
        "artist": artist,
        "key": key,
        "playback": playback,
        "scene_index": scene_index,
        "scene_name": _text(raw.get("scene_name")),
        "export": _boolean(raw.get("export"), True),
        "notes": _text(raw.get("notes")),
    }


def normalize_show_audio_document(document: dict) -> dict:
    if not isinstance(document, dict):
        raise ValueError("document Show Audio invalide")

    raw_variants = document.get("variants", [])
    if not isinstance(raw_variants, list):
        raise ValueError("liste variants invalide")

    variants = [
        normalize_variant(raw, index)
        for index, raw in enumerate(raw_variants, 1)
    ]

    try:
        revision = int(document.get("revision", 0))
    except (TypeError, ValueError) as exc:
        raise ValueError("révision Show Audio invalide") from exc

    if revision < 0:
        raise ValueError("révision Show Audio invalide")

    # Ce document porte aussi les sources playback, medleys et réglages
    # d'export. Éditer une variante ne doit jamais les supprimer.
    return {
        **deepcopy(document),
        "version": DOCUMENT_VERSION,
        "revision": revision,
        "variants": variants,
    }


def validate_show_audio_document(document: dict) -> dict:
    normalized = normalize_show_audio_document(document)

    duplicate_ids = []
    seen_ids = set()

    duplicate_assignments = []
    seen_assignments = set()

    incomplete = []

    for variant in normalized["variants"]:
        if variant["id"] in seen_ids:
            duplicate_ids.append(variant["id"])
        seen_ids.add(variant["id"])

        assignment_key = (
            variant["number"].casefold(),
            variant["title"].casefold(),
            variant["role"].casefold(),
            variant["artist"].casefold(),
        )
        if all(assignment_key):
            if assignment_key in seen_assignments:
                duplicate_assignments.append(variant["id"])
            seen_assignments.add(assignment_key)

        missing = [
            field
            for field in ("number", "title", "role", "artist", "playback")
            if not variant[field]
        ]

        if variant["scene_index"] is None and not variant["scene_name"]:
            missing.append("scene")

        if missing:
            incomplete.append({
                "id": variant["id"],
                "missing": missing,
            })

    return {
        "duplicate_ids": duplicate_ids,
        "duplicate_assignments": duplicate_assignments,
        "incomplete_variants": incomplete,
        "ready": not (
            duplicate_ids
            or duplicate_assignments
            or incomplete
        ),
    }


def resolve_variant(
    document: dict,
    *,
    number: str,
    role: str,
    artist: str = "",
) -> dict | None:
    """Trouve la variante correspondant au numéro + rôle + artiste.

    Si artist est vide, une variante n'est retournée que si une seule
    variante correspond au couple numéro + rôle.
    """

    normalized = normalize_show_audio_document(document)

    number_key = _text(number).casefold()
    role_key = _text(role).casefold()
    artist_key = _text(artist).casefold()

    candidates = [
        variant
        for variant in normalized["variants"]
        if variant["number"].casefold() == number_key
        and variant["role"].casefold() == role_key
    ]

    if artist_key:
        candidates = [
            variant
            for variant in candidates
            if variant["artist"].casefold() == artist_key
        ]

    if len(candidates) != 1:
        return None

    return dict(candidates[0])


def resolve_variant_for_builder_cue(
    document: dict,
    cue: dict,
    resolved_distribution: dict,
) -> dict | None:
    """Relie un cue ShowCue résolu à sa variante audio.

    Le rôle vient du cue.
    L'artiste vient de la résolution de distribution ShowCue.
    """

    return resolve_variant(
        document,
        number=_text(cue.get("number")),
        role=_text(cue.get("role")),
        artist=_text(resolved_distribution.get("resolved_artist")),
    )


import json
import os
import tempfile
from pathlib import Path


def load_show_audio_document(path: Path) -> dict:
    path = Path(path)
    if not path.exists():
        return empty_show_audio_document()

    with path.open("r", encoding="utf-8") as handle:
        return normalize_show_audio_document(json.load(handle))


def save_show_audio_document(path: Path, document: dict) -> dict:
    normalized = normalize_show_audio_document(document)

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=path.parent,
    )

    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(
                normalized,
                handle,
                ensure_ascii=False,
                indent=2,
            )
            handle.write("\n")

        os.replace(temporary_name, path)

    except Exception:
        try:
            os.unlink(temporary_name)
        except OSError:
            pass
        raise

    return normalized


def variant_display_name(variant: dict) -> str:
    variant = normalize_variant(variant)

    parts = [
        variant["number"],
        variant["title"],
        variant["role"],
        variant["artist"],
    ]

    if variant["key"]:
        parts.append(variant["key"])

    return " · ".join(part for part in parts if part)


def audio_filename_for_variant(
    variant: dict,
    *,
    extension: str = "mp3",
) -> str:
    variant = normalize_variant(variant)

    extension = _text(extension).lstrip(".").lower() or "mp3"

    parts = [
        variant["number"],
        variant["title"],
        variant["role"],
        variant["artist"],
    ]

    if variant["key"]:
        parts.append(variant["key"])

    def safe(value: str) -> str:
        value = value.strip()
        for character in '<>:"/\\|?*':
            value = value.replace(character, "-")
        return " ".join(value.split())

    stem = " - ".join(
        safe(part)
        for part in parts
        if safe(part)
    )

    return f"{stem}.{extension}"
