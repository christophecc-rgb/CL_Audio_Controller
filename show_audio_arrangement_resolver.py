"""Résolution stricte Session -> Arrangement pour CL Show Audio.

Règles absolues :
- l'identité métier vient de la scène Session ;
- le locator Arrangement fournit UNIQUEMENT le début temporel ;
- la durée vient UNIQUEMENT de la référence audio réelle ;
- le locator suivant n'est JAMAIS utilisé pour déterminer la longueur ;
- aucune correspondance fuzzy en production ;
- une correspondance de titre doit être unique.
"""

from __future__ import annotations

import re
import unicodedata
from typing import Any


class ArrangementResolveError(RuntimeError):
    pass


def normalize_arrangement_title(value: Any) -> str:
    text = str(value or "").strip()

    # Retire les métadonnées :
    # "ANNONCE ; BPM ; KEY ; 0:31" -> "ANNONCE"
    text = text.split(";", 1)[0].strip()

    # Numéro Arrangement :
    # "29. Annonce" -> "Annonce"
    text = re.sub(
        r"^\s*0*\d{1,3}\s*[.\-–—:|]\s*",
        "",
        text,
    )

    # Numérotation métier Session :
    # "1 - EN ROUTE..." -> "EN ROUTE..."
    # "5-Machoire"      -> "Machoire"
    text = re.sub(
        r"^\s*\d{1,3}\s*-\s*",
        "",
        text,
    )

    text = unicodedata.normalize(
        "NFKD",
        text,
    )

    text = "".join(
        char
        for char in text
        if not unicodedata.combining(char)
    )

    text = text.casefold()

    text = re.sub(
        r"[^a-z0-9]+",
        " ",
        text,
    )

    return re.sub(
        r"\s+",
        " ",
        text,
    ).strip()


def _marker_position(marker: dict) -> float:
    value = marker.get(
        "time",
        marker.get(
            "start_beats",
            marker.get("position"),
        ),
    )

    if value is None:
        raise ArrangementResolveError(
            "position Arrangement absente"
        )

    try:
        position = float(value)
    except (TypeError, ValueError) as exc:
        raise ArrangementResolveError(
            "position Arrangement invalide"
        ) from exc

    if position < 0:
        raise ArrangementResolveError(
            "position Arrangement négative"
        )

    return position


def _positive_duration(value: Any) -> float:
    try:
        duration = float(value)
    except (TypeError, ValueError) as exc:
        raise ArrangementResolveError(
            "durée audio de référence absente ou invalide"
        ) from exc

    if duration <= 0:
        raise ArrangementResolveError(
            "durée audio de référence <= 0"
        )

    return duration


def _positive_tempo(value: Any) -> float:
    try:
        tempo = float(value)
    except (TypeError, ValueError) as exc:
        raise ArrangementResolveError(
            "tempo absent ou invalide"
        ) from exc

    if tempo <= 0:
        raise ArrangementResolveError(
            "tempo <= 0"
        )

    return tempo


def build_locator_index(
    markers: list[dict],
) -> dict[str, list[dict]]:
    index: dict[str, list[dict]] = {}

    for locator_index, marker in enumerate(markers):
        name = str(
            marker.get("name")
            or marker.get("title")
            or ""
        ).strip()

        key = normalize_arrangement_title(
            name
        )

        if not key:
            continue

        row = {
            "locator_index": locator_index,
            "name": name,
            "start_beats": _marker_position(
                marker
            ),
        }

        index.setdefault(
            key,
            [],
        ).append(row)

    return index


def resolve_scene_zone(
    scene: dict,
    markers: list[dict],
    *,
    expected_duration_seconds: float,
    tempo: float,
) -> dict:
    """Résout une scène vers une zone d'export offline.

    IMPORTANT :
    le locator fournit start_beats seulement.
    duration/end sont calculés depuis la durée audio réelle.
    """

    scene_name = str(
        scene.get("scene_name")
        or scene.get("name")
        or scene.get("title")
        or ""
    ).strip()

    scene_index = scene.get(
        "scene_index",
        scene.get("index"),
    )

    key = normalize_arrangement_title(
        scene_name
    )

    if not key:
        raise ArrangementResolveError(
            f"titre Session vide pour scene_index={scene_index!r}"
        )

    duration_seconds = _positive_duration(
        expected_duration_seconds
    )

    bpm = _positive_tempo(
        tempo
    )

    locator_index = build_locator_index(
        markers
    )

    matches = locator_index.get(
        key,
        [],
    )

    if not matches:
        raise ArrangementResolveError(
            f"aucun locator Arrangement pour {scene_name!r}"
        )

    if len(matches) != 1:
        raise ArrangementResolveError(
            f"locator Arrangement ambigu pour {scene_name!r}: "
            f"{len(matches)} correspondances"
        )

    match = matches[0]

    start_beats = float(
        match["start_beats"]
    )

    # RÈGLE MÉTIER :
    # la longueur vient du playback réel,
    # jamais du locator suivant.
    duration_beats = (
        duration_seconds
        * bpm
        / 60.0
    )

    end_beats = (
        start_beats
        + duration_beats
    )

    return {
        "type": "scene",
        "scene_index": scene_index,
        "name": scene_name,
        "locator_name": match["name"],
        "locator_index": int(
            match["locator_index"]
        ),
        "start_beats": start_beats,
        "end_beats": end_beats,
        "duration_beats": duration_beats,
        "expected_duration_seconds": duration_seconds,
        "duration_source": "audio_reference",
    }


def resolve_scene_zones(
    scenes: list[dict],
    markers: list[dict],
    *,
    tempo: float,
    duration_by_scene_index: dict[Any, float],
) -> dict:
    """Résout une collection sans jamais déduire une durée des locators."""

    if not isinstance(
        duration_by_scene_index,
        dict,
    ):
        raise ArrangementResolveError(
            "duration_by_scene_index invalide"
        )

    resolved = []
    rejected = []

    for scene in scenes:
        scene_index = scene.get(
            "scene_index",
            scene.get("index"),
        )

        duration = duration_by_scene_index.get(
            scene_index
        )

        try:
            if duration is None:
                raise ArrangementResolveError(
                    "durée audio de référence absente"
                )

            zone = resolve_scene_zone(
                scene,
                markers,
                expected_duration_seconds=duration,
                tempo=tempo,
            )

        except ArrangementResolveError as exc:
            rejected.append({
                "scene_index": scene_index,
                "name": (
                    scene.get("scene_name")
                    or scene.get("name")
                    or scene.get("title")
                    or ""
                ),
                "reason": str(exc),
            })

        else:
            resolved.append(
                zone
            )

    return {
        "resolved": resolved,
        "rejected": rejected,
        "resolved_count": len(
            resolved
        ),
        "rejected_count": len(
            rejected
        ),
    }


def resolve_medley_zone(medley: dict, scenes: list[dict], markers: list[dict], *, tempo: float) -> dict:
    """Une zone continue, résolue depuis les débuts et durées audio des membres."""
    import math

    numbers = medley.get("scene_numbers") or []
    if (len(numbers) < 2 or numbers != list(range(numbers[0], numbers[0] + len(numbers)))):
        raise ArrangementResolveError("Medley incomplet ou scènes non contiguës")
    zones = []
    for number in numbers:
        matches = [scene for scene in scenes if scene.get("scene_index") == number - 1]
        if len(matches) != 1:
            raise ArrangementResolveError(f"Medley incomplet ou ambigu : scène {number}")
        scene = matches[0]
        reference = scene.get("reference") or scene.get("audio_reference") or {}
        zone = resolve_scene_zone(scene, markers,
            expected_duration_seconds=reference.get("duration_seconds"), tempo=tempo)
        if not all(math.isfinite(zone[key]) for key in ("start_beats", "end_beats", "duration_beats")):
            raise ArrangementResolveError("Medley non résolvable : position ou durée non finie")
        zones.append(zone)
    start, end = zones[0]["start_beats"], zones[-1]["end_beats"]
    if end <= start:
        raise ArrangementResolveError("Medley non résolvable : fin audio <= début Arrangement")
    # La zone globale inclut les espaces et chevauchements internes.
    duration_beats = end - start
    return {"type": "medley", "title": medley.get("title"), "scene_numbers": list(numbers),
            "start_beats": start, "end_beats": end, "duration_beats": duration_beats,
            "expected_duration_seconds": duration_beats * 60.0 / float(tempo),
            "duration_source": "audio_reference"}
