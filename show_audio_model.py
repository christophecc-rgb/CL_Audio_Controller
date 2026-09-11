#!/usr/bin/env python3

"""Modèle métier CL Show Audio.

Transforme le snapshot technique Ableton en représentation exploitable
par CL Show Audio Builder.

Principes :
- aucune communication directe avec Ableton ;
- aucune mutation ;
- la durée vient du playback réel retenu dans le snapshot ;
- une scène sans playback autorisé ON n'est pas exportable ;
- les variantes rôle/artiste/tonalité restent attachées aux variantes,
  jamais seulement au titre ;
- aucune déduction hasardeuse rôle/artiste à partir du nom d'une piste.
"""

from __future__ import annotations

import re
from typing import Any, Dict, Iterable, List, Optional, Tuple

from show_audio_builder import normalize_show_audio_document


DOCUMENT_VERSION = 1


_SHOW_NUMBER_RE = re.compile(
    r"^\s*(\d+)\s*-\s*(.+?)\s*$"
)


def _text(value: Any) -> str:
    return str(value or "").strip()


def _positive_float(value: Any) -> Optional[float]:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None

    if result <= 0:
        return None

    return result


def clean_scene_identity(
    scene_name: Any,
) -> Tuple[str, str]:
    """Retourne (numéro_show, titre) sans BPM/KEY/durée déclarée.

    Exemple :
        "2 - TABLEAU VIS A VIS ; BPM ; KEY ; 6:15"
    devient :
        ("2", "TABLEAU VIS A VIS")
    """

    raw = _text(scene_name)

    if not raw:
        return "", ""

    # La première cellule avant ";" porte le titre métier.
    title_part = raw.split(";", 1)[0].strip()

    match = _SHOW_NUMBER_RE.match(title_part)

    if match:
        return (
            match.group(1).strip(),
            match.group(2).strip(),
        )

    return "", title_part


def _variant_matches_scene(
    variant: Dict[str, Any],
    *,
    scene_index: int,
    scene_name: str,
) -> bool:
    variant_index = variant.get("scene_index")

    if variant_index is not None:
        try:
            if int(variant_index) == int(scene_index):
                return True
        except (TypeError, ValueError):
            pass

    variant_scene_name = _text(
        variant.get("scene_name")
    )

    if (
        variant_scene_name
        and scene_name
        and variant_scene_name.casefold()
        == scene_name.casefold()
    ):
        return True

    return False


def variants_for_scene(
    variants: Iterable[Dict[str, Any]],
    *,
    scene_index: int,
    scene_name: str,
) -> List[Dict[str, Any]]:
    return [
        dict(variant)
        for variant in variants
        if _variant_matches_scene(
            variant,
            scene_index=scene_index,
            scene_name=scene_name,
        )
    ]


def build_show_audio_item(
    scene: Dict[str, Any],
    *,
    variants: Iterable[Dict[str, Any]] = (),
) -> Dict[str, Any]:
    scene_index = int(
        scene.get("scene_index", -1)
    )

    scene_name = _text(
        scene.get("scene_name")
    )

    show_number, title = clean_scene_identity(
        scene_name
    )

    reference = scene.get("reference") or {}

    duration_seconds = _positive_float(
        reference.get("duration_seconds")
    )

    reference_track = _text(
        reference.get("track_name")
    )

    reference_clip = _text(
        reference.get("clip_name")
    )

    playback_on_count = int(
        scene.get("playback_on_count") or 0
    )

    active_playbacks = []

    for clip in scene.get("clips") or []:
        if clip.get("track_on") is not True:
            continue

        if clip.get("playback_track") is not True:
            continue

        duration = _positive_float(
            clip.get("duration_seconds")
        )

        if duration is None:
            continue

        active_playbacks.append({
            "track_index": clip.get("track_index"),
            "track_name": _text(
                clip.get("track_name")
            ),
            "clip_name": _text(
                clip.get("clip_name")
            ),
            "duration_seconds": duration,
        })

    scene_variants = variants_for_scene(
        variants,
        scene_index=scene_index,
        scene_name=scene_name,
    )

    if playback_on_count <= 0 or duration_seconds is None:
        status = "no_playback"
        exportable = False
    elif playback_on_count == 1:
        status = "ready"
        exportable = True
    else:
        status = "multiple_playbacks"
        exportable = True

    if not scene_variants:
        variant_status = "unconfigured"
    elif len(scene_variants) == 1:
        variant_status = "configured"
    else:
        variant_status = "multiple_variants"

    return {
        "scene_index": scene_index,
        "scene_number": scene_index + 1,
        "scene_name": scene_name,
        "show_number": show_number,
        "title": title,
        "status": status,
        "exportable": exportable,
        "duration_seconds": duration_seconds,
        "playback_on_count": playback_on_count,
        "reference_playback": {
            "track_name": reference_track,
            "clip_name": reference_clip,
            "duration_seconds": duration_seconds,
        } if duration_seconds is not None else None,
        "active_playbacks": active_playbacks,
        "variant_status": variant_status,
        "variants": [
            {
                "id": _text(
                    variant.get("id")
                ),
                "number": _text(
                    variant.get("number")
                ),
                "title": _text(
                    variant.get("title")
                ),
                "role": _text(
                    variant.get("role")
                ),
                "artist": _text(
                    variant.get("artist")
                ),
                "key": _text(
                    variant.get("key")
                ),
                "playback": _text(
                    variant.get("playback")
                ),
                "export": bool(
                    variant.get("export", True)
                ),
            }
            for variant in scene_variants
        ],
    }


def build_show_audio_model(
    snapshot: Dict[str, Any],
    config: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    config = config or {}

    normalized_config = normalize_show_audio_document(
        config
    )

    variants = list(
        normalized_config.get("variants") or []
    )

    items = [
        build_show_audio_item(
            scene,
            variants=variants,
        )
        for scene in snapshot.get("scenes") or []
    ]

    ready = [
        item
        for item in items
        if item["status"] == "ready"
    ]

    multiple = [
        item
        for item in items
        if item["status"] == "multiple_playbacks"
    ]

    no_playback = [
        item
        for item in items
        if item["status"] == "no_playback"
    ]

    exportable = [
        item
        for item in items
        if item["exportable"]
    ]

    configured = [
        item
        for item in items
        if item["variant_status"] != "unconfigured"
    ]

    return {
        "version": DOCUMENT_VERSION,
        "source_snapshot_version": snapshot.get("version"),
        "set": dict(snapshot.get("set") or {}),
        "items": items,
        "metrics": {
            "scene_count": len(items),
            "ready_count": len(ready),
            "multiple_playback_count": len(multiple),
            "no_playback_count": len(no_playback),
            "exportable_count": len(exportable),
            "configured_scene_count": len(configured),
        },
    }
