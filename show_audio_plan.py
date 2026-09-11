"""Construction du plan d'export de CL Show Audio Builder."""

from __future__ import annotations

from typing import Any

from show_audio_builder import (
    audio_filename_for_variant,
    normalize_show_audio_document,
)
from show_audio_ableton import ShowAudioAbletonAdapter


STATUS_READY = "ready"
STATUS_MISMATCH = "mismatch"
STATUS_MISSING = "missing"
STATUS_DISABLED = "disabled"


def build_export_item(
    variant: dict,
    adapter: ShowAudioAbletonAdapter,
    *,
    extension: str = "mp3",
) -> dict:
    match = adapter.match_variant(variant)

    if not variant.get("export", True):
        status = STATUS_DISABLED
    elif match["status"] == "matched":
        status = STATUS_READY
    elif match["status"] == "mismatch":
        status = STATUS_MISMATCH
    else:
        status = STATUS_MISSING

    scene = match.get("scene") or {}

    return {
        "variant_id": variant["id"],
        "number": variant["number"],
        "title": variant["title"],
        "role": variant["role"],
        "artist": variant["artist"],
        "key": variant["key"],
        "playback": variant["playback"],
        "export": variant["export"],
        "status": status,
        "match_status": match["status"],
        "matched_by": match.get("matched_by"),
        "expected_scene_index": variant.get("scene_index"),
        "expected_scene_name": variant.get("scene_name", ""),
        "actual_scene_index": scene.get("scene_index"),
        "actual_scene_name": scene.get("scene_name", ""),
        "filename": audio_filename_for_variant(
            variant,
            extension=extension,
        ),
    }


def build_export_plan(
    document: dict,
    adapter: ShowAudioAbletonAdapter,
    *,
    extension: str = "mp3",
) -> dict:
    normalized = normalize_show_audio_document(document)

    items = [
        build_export_item(
            variant,
            adapter,
            extension=extension,
        )
        for variant in normalized["variants"]
    ]

    counts = {
        STATUS_READY: 0,
        STATUS_MISMATCH: 0,
        STATUS_MISSING: 0,
        STATUS_DISABLED: 0,
    }

    for item in items:
        counts[item["status"]] += 1

    return {
        "version": 1,
        "items": items,
        "counts": counts,
        "ready": (
            counts[STATUS_MISMATCH] == 0
            and counts[STATUS_MISSING] == 0
        ),
    }


def export_item_label(item: dict) -> str:
    parts = [
        item.get("number", ""),
        item.get("title", ""),
        item.get("role", ""),
        item.get("artist", ""),
    ]

    if item.get("key"):
        parts.append(item["key"])

    return " · ".join(
        str(part).strip()
        for part in parts
        if str(part).strip()
    )

TECHNICAL_TRACK_MARKERS = (
    "LTC",
    "CLICK",
    "CLIC",
    "PGM CHANGE",
    "TOP INFO",
    "VIDEO / LIGHT",
)


def is_technical_track(track_name):
    """True si la piste est clairement technique et ne doit pas définir la durée musicale."""
    name = str(track_name or "").strip().upper()
    if not name:
        return False
    return any(marker in name for marker in TECHNICAL_TRACK_MARKERS)


def select_reference_clip(clips):
    """Sélectionne le clip musical de référence d'une scène.

    Règle métier Show Audio :
    - ne considérer que les pistes ON ;
    - ignorer les pistes clairement techniques ;
    - parmi les clips restants avec une durée valide, prendre le plus long.

    Retourne None si aucun clip éligible n'est trouvé.
    """
    candidates = []

    for clip in clips or ():
        if not isinstance(clip, dict):
            continue

        if not bool(clip.get("track_on")):
            continue

        if is_technical_track(clip.get("track_name")):
            continue

        duration = clip.get("duration_seconds")
        try:
            duration = float(duration)
        except (TypeError, ValueError):
            continue

        if duration <= 0:
            continue

        candidates.append((duration, clip))

    if not candidates:
        return None

    duration, clip = max(candidates, key=lambda item: item[0])

    return {
        "duration_seconds": duration,
        "track_index": clip.get("track_index"),
        "track_name": clip.get("track_name"),
        "clip_name": clip.get("clip_name"),
        "length_beats": clip.get("length_beats"),
    }

def normalize_playback_track_names(values):
    """Retourne l'ensemble normalisé des noms de pistes playback autorisées."""
    result = set()

    for value in values or []:
        name = str(value or "").strip()

        if name:
            result.add(name.casefold())

    return result


def is_playback_track(track_name, playback_track_names):
    """True uniquement si la piste appartient explicitement aux playbacks autorisés."""
    name = str(track_name or "").strip()

    if not name:
        return False

    allowed = normalize_playback_track_names(playback_track_names)

    if not allowed:
        return False

    return name.casefold() in allowed


def select_reference_playback_clip(clips, playback_track_names):
    """Sélectionne le plus long clip réel parmi les pistes playback ON autorisées."""
    candidates = []

    for clip in clips or []:
        if clip.get("track_on") is not True:
            continue

        if not is_playback_track(
            clip.get("track_name", ""),
            playback_track_names,
        ):
            continue

        try:
            duration = float(
                clip.get("duration_seconds") or 0
            )
        except (TypeError, ValueError):
            continue

        if duration <= 0:
            continue

        candidates.append(clip)

    if not candidates:
        return None

    return max(
        candidates,
        key=lambda item: float(
            item.get("duration_seconds") or 0
        ),
    )

