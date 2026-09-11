#!/usr/bin/env python3

"""Plan d'export CL Show Audio.

Transforme :
- le snapshot réel des scènes playback ;
- la configuration des medleys ;

en une liste d'exports métier.

Aucune communication avec Ableton.
Aucune écriture audio.
Aucun transport.
"""

from __future__ import annotations

import re
from typing import Any, Dict, Iterable, List

from show_audio_medleys import build_medleys


def _text(value: Any) -> str:
    return str(value or "").strip()


def _duration(value: Any) -> float | None:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None

    if result <= 0:
        return None

    return result


def _slug_filename(value: str) -> str:
    """Nettoyage simple pour nom de fichier lisible."""

    value = _text(value)

    value = re.sub(
        r'[\\/:*?"<>|]+',
        " - ",
        value,
    )

    value = re.sub(
        r"\s+",
        " ",
        value,
    ).strip()

    return value


def scene_title(
    scene_name: Any,
) -> str:
    """Titre utilisateur à partir du nom de scène Live.

    Le nom Ableton contient actuellement souvent :
        TITRE ; BPM ; KEY ; durée

    Pour le plan d'export on retient seulement
    la partie avant le premier point-virgule.
    """

    raw = _text(scene_name)

    if not raw:
        return ""

    title = raw.split(
        ";",
        1,
    )[0].strip()

    return title or raw


def _medley_membership(
    config: Dict[str, Any],
) -> Dict[int, str]:
    """Map numéro de scène LIVE -> id medley."""

    membership: Dict[int, str] = {}

    for raw in config.get("medleys") or []:
        medley_id = _text(
            raw.get("id")
        )

        for value in (
            raw.get("scene_numbers")
            or []
        ):
            try:
                number = int(value)
            except (TypeError, ValueError):
                continue

            if number <= 0:
                continue

            # Un numéro ne doit appartenir qu'à un seul medley.
            if number in membership:
                raise ValueError(
                    f"Scène LIVE {number} présente dans "
                    f"plusieurs medleys : "
                    f"{membership[number]} / {medley_id}"
                )

            membership[number] = medley_id

    return membership


def build_scene_export_items(
    config: Dict[str, Any],
    snapshot: Dict[str, Any],
) -> List[Dict[str, Any]]:
    membership = _medley_membership(
        config
    )

    items: List[Dict[str, Any]] = []

    scenes = sorted(
        snapshot.get("scenes") or [],
        key=lambda row: int(
            row.get("scene_index", -1)
        ),
    )

    for scene in scenes:
        try:
            scene_index = int(
                scene["scene_index"]
            )
        except (KeyError, TypeError, ValueError):
            continue

        # Source de durée :
        # - le playback réel retenu par le snapshot est prioritaire ;
        # - une référence audio générale n'est utilisée qu'en fallback ;
        # - aucune durée n'est jamais déduite du locator Arrangement suivant.
        playback_reference = (
            scene.get("reference")
            or {}
        )

        audio_reference = (
            scene.get("audio_reference")
            or {}
        )

        reference = (
            playback_reference
            or audio_reference
        )

        duration = _duration(
            reference.get(
                "duration_seconds"
            )
        )

        if duration is None:
            continue

        scene_number = (
            scene_index + 1
        )

        title = scene_title(
            scene.get("scene_name")
        )

        medley_id = membership.get(
            scene_number
        )

        item_type = (
            "medley_part"
            if medley_id
            else "scene"
        )

        filename = _slug_filename(
            f"{scene_number:03d} - {title}"
        )

        items.append({
            "id": (
                f"scene_{scene_number:03d}"
            ),
            "type": item_type,
            "scene_number": scene_number,
            "scene_index": scene_index,
            "title": title,
            "scene_name": (
                scene.get("scene_name")
                or ""
            ),
            "duration_seconds": duration,
            "playback_track": (
                playback_reference.get(
                    "track_name"
                )
                or ""
            ),
            "source_track": (
                reference.get(
                    "track_name"
                )
                or ""
            ),
            "source_clip": (
                reference.get(
                    "clip_name"
                )
                or ""
            ),
            "medley_id": medley_id,
            "filename_stem": filename,
            "status": "ready",
        })

    return items


def build_medley_export_items(
    config: Dict[str, Any],
    snapshot: Dict[str, Any],
) -> List[Dict[str, Any]]:
    items: List[Dict[str, Any]] = []

    for medley in build_medleys(
        config,
        snapshot,
    ):
        if not medley.get(
            "export_full",
            True,
        ):
            continue

        if medley.get("status") != "ready":
            continue

        numbers = (
            medley.get("scene_numbers")
            or []
        )

        if not numbers:
            continue

        first_number = int(
            numbers[0]
        )
        last_number = int(
            numbers[-1]
        )

        title = _text(
            medley.get("title")
        )

        filename = _slug_filename(
            f"MEDLEY {first_number:03d}-{last_number:03d} - {title}"
        )

        items.append({
            "id": (
                f"{medley['id']}_full"
            ),
            "type": "medley_full",
            "medley_id": medley["id"],
            "title": title,
            "scene_numbers": list(
                numbers
            ),
            "first_scene_number": (
                first_number
            ),
            "last_scene_number": (
                last_number
            ),
            "duration_seconds": (
                medley.get(
                    "duration_seconds"
                )
            ),
            "play_mode": (
                medley.get(
                    "play_mode"
                )
            ),
            "filename_stem": filename,
            "status": "ready",
        })

    return items


def build_export_plan(
    config: Dict[str, Any],
    snapshot: Dict[str, Any],
) -> Dict[str, Any]:
    scene_items = (
        build_scene_export_items(
            config,
            snapshot,
        )
    )

    medley_items = (
        build_medley_export_items(
            config,
            snapshot,
        )
    )

    items = (
        scene_items
        + medley_items
    )

    type_counts = {
        "scene": 0,
        "medley_part": 0,
        "medley_full": 0,
    }

    for item in items:
        item_type = item["type"]

        type_counts[item_type] = (
            type_counts.get(
                item_type,
                0,
            )
            + 1
        )

    return {
        "version": 1,
        "status": "ready",
        "items": items,
        "metrics": {
            "item_count": len(items),
            "scene_export_count": len(
                scene_items
            ),
            "medley_full_count": len(
                medley_items
            ),
            "simple_scene_count": (
                type_counts["scene"]
            ),
            "medley_part_count": (
                type_counts[
                    "medley_part"
                ]
            ),
        },
    }
