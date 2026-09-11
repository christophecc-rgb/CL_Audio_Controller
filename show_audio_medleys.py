#!/usr/bin/env python3

"""Modèle métier des medleys CL Show Audio.

Ce module :
- ne communique pas avec Ableton ;
- ne déclenche aucun transport ;
- ne modifie aucun snapshot ;
- travaille uniquement à partir de la configuration
  et d'un snapshot déjà acquis.
"""

from __future__ import annotations

from typing import Any, Dict, Iterable, List


def _duration(value: Any) -> float | None:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None

    if result <= 0:
        return None

    return result


def _scene_map(
    snapshot: Dict[str, Any],
) -> Dict[int, Dict[str, Any]]:
    result = {}

    for scene in snapshot.get("scenes") or []:
        try:
            index = int(scene["scene_index"])
        except (KeyError, TypeError, ValueError):
            continue

        result[index] = scene

    return result


def normalize_medley(
    raw: Dict[str, Any],
) -> Dict[str, Any]:
    scene_numbers = []

    for value in raw.get("scene_numbers") or []:
        try:
            number = int(value)
        except (TypeError, ValueError):
            continue

        if number > 0:
            scene_numbers.append(number)

    return {
        **({"numbering": "live"} if raw.get("numbering") == "live" else {}),
        "id": str(raw.get("id") or "").strip(),
        "title": str(raw.get("title") or "").strip(),
        "scene_numbers": scene_numbers,
        "export_parts": bool(
            raw.get("export_parts", True)
        ),
        "export_full": bool(
            raw.get("export_full", True)
        ),
        "play_mode": str(
            raw.get("play_mode") or "follow"
        ).strip(),
    }


def validate_medley(
    medley: Dict[str, Any],
) -> List[str]:
    errors = []

    if not medley.get("id"):
        errors.append("missing_id")

    numbers = medley.get("scene_numbers") or []

    if len(numbers) < 2:
        errors.append("not_enough_scenes")

    if len(numbers) != len(set(numbers)):
        errors.append("duplicate_scene")

    if numbers:
        expected = list(
            range(
                numbers[0],
                numbers[0] + len(numbers),
            )
        )

        if numbers != expected:
            errors.append("non_contiguous_scenes")

    if medley.get("play_mode") not in {
        "follow",
    }:
        errors.append("unsupported_play_mode")

    return errors


def build_medley(
    medley: Dict[str, Any],
    snapshot: Dict[str, Any],
) -> Dict[str, Any]:
    medley = normalize_medley(medley)
    errors = validate_medley(medley)

    scenes = _scene_map(snapshot)
    parts = []

    for live_number in medley["scene_numbers"]:
        scene_index = live_number - 1
        scene = scenes.get(scene_index)

        if scene is None:
            parts.append({
                "scene_number": live_number,
                "scene_index": scene_index,
                "status": "missing_scene",
                "duration_seconds": None,
                "scene_name": "",
                "playback_track": "",
            })
            continue

        reference = scene.get("reference") or {}

        duration = _duration(
            reference.get("duration_seconds")
        )

        if duration is None:
            status = "missing_playback"
        else:
            status = "ready"

        parts.append({
            "scene_number": live_number,
            "scene_index": scene_index,
            "status": status,
            "duration_seconds": duration,
            "scene_name": (
                scene.get("scene_name") or ""
            ),
            "playback_track": (
                reference.get("track_name") or ""
            ),
        })

    ready_parts = [
        part
        for part in parts
        if part["status"] == "ready"
    ]

    total_duration = sum(
        part["duration_seconds"]
        for part in ready_parts
    )

    complete = (
        not errors
        and len(ready_parts) == len(parts)
        and bool(parts)
    )

    return {
        **medley,
        "status": "ready" if complete else "incomplete",
        "errors": errors,
        "parts": parts,
        "part_count": len(parts),
        "ready_part_count": len(ready_parts),
        "duration_seconds": (
            total_duration if complete else None
        ),
    }


def build_medleys(
    config: Dict[str, Any],
    snapshot: Dict[str, Any],
) -> List[Dict[str, Any]]:
    return [
        build_medley(raw, snapshot)
        for raw in config.get("medleys") or []
    ]
