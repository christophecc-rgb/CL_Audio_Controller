#!/usr/bin/env python3

"""Diagnostic réel des groupes playback.

HTTP uniquement.
Aucune commande transport Live.
"""

from __future__ import annotations

import json
import urllib.parse
import urllib.request
from pathlib import Path

from show_audio_playback_sources import (
    configured_playback_groups,
    group_playback_leaf_tracks,
    resolve_playback_track_names,
)


BASE = "http://127.0.0.1:5050"


def get_json(path: str, timeout: float = 20.0):
    with urllib.request.urlopen(
        BASE + path,
        timeout=timeout,
    ) as response:
        return json.load(response)


def duration_text(value):
    if value is None:
        return "—"

    value = float(value)
    minutes = int(value // 60)
    seconds = value - minutes * 60

    return f"{minutes}:{seconds:05.2f}"


config = json.loads(
    Path("show_audio.json").read_text(
        encoding="utf-8"
    )
)

groups = configured_playback_groups(
    config
)

if not groups:
    raise SystemExit(
        "Aucun playback_groups configuré."
    )

# Pour cette validation réelle, on utilise la zone déjà
# diagnostiquée contenant SAISON 7.
hierarchy_data = get_json(
    "/show-audio/track-hierarchy"
    "?start=40&end=65",
    timeout=15.0,
)

if not hierarchy_data.get("ok"):
    raise SystemExit(
        f"Hiérarchie invalide: {hierarchy_data}"
    )

hierarchy = (
    hierarchy_data.get("tracks")
    or []
)

allowed_names = resolve_playback_track_names(
    config,
    hierarchy,
)

allowed_keys = {
    name.casefold()
    for name in allowed_names
}

print("=" * 110)
print("SOURCES PLAYBACK RÉSOLUES")
print("=" * 110)

for group_name in groups:
    print()
    print("GROUPE :", group_name)

    leaves = group_playback_leaf_tracks(
        hierarchy,
        group_name,
    )

    for track in leaves:
        print(
            f"  {int(track['track_index']):03d} | "
            f"{track['track_name']}"
        )

print()
print(
    "Nombre total de noms playback autorisés :",
    len(allowed_names),
)

bulk = get_json(
    "/show-audio/scene-clips-bulk",
    timeout=20.0,
)

if not bulk.get("ok"):
    raise SystemExit(
        f"scene-clips-bulk invalide: {bulk}"
    )

scenes = bulk.get("scenes") or []

clip_track_indices = sorted({
    int(clip["track_index"])
    for scene in scenes
    for clip in (
        scene.get("clips") or []
    )
    if clip.get("track_index") is not None
})

encoded = urllib.parse.quote(
    ",".join(
        str(value)
        for value in clip_track_indices
    ),
    safe=",",
)

track_states = get_json(
    "/show-audio/tracks-bulk"
    f"?track_indices={encoded}",
    timeout=10.0,
)

if not track_states.get("ok"):
    raise SystemExit(
        f"tracks-bulk invalide: {track_states}"
    )

state_by_index = {
    int(track["track_index"]): track
    for track in (
        track_states.get("tracks")
        or []
    )
}

results = []

for scene in scenes:
    candidates = []

    for clip in scene.get("clips") or []:
        track_index = int(
            clip["track_index"]
        )

        track_name = str(
            clip.get("track_name")
            or ""
        ).strip()

        if (
            track_name.casefold()
            not in allowed_keys
        ):
            continue

        state = state_by_index.get(
            track_index,
            {},
        )

        if state.get("track_on") is not True:
            continue

        try:
            duration = float(
                clip.get(
                    "duration_seconds"
                )
            )
        except (TypeError, ValueError):
            continue

        if duration <= 0:
            continue

        candidates.append({
            **clip,
            "duration_seconds": duration,
        })

    candidates.sort(
        key=lambda value:
            value["duration_seconds"],
        reverse=True,
    )

    reference = (
        candidates[0]
        if candidates
        else None
    )

    results.append({
        "scene_index": int(
            scene["scene_index"]
        ),
        "scene_name": scene.get(
            "scene_name"
        ),
        "playback_on_count": len(
            candidates
        ),
        "reference": reference,
    })

exportable = [
    row
    for row in results
    if row["reference"] is not None
]

print()
print("=" * 110)
print("RÉSULTAT GLOBAL")
print("=" * 110)
print(
    "scènes analysées  :",
    len(results),
)
print(
    "scènes playback   :",
    len(exportable),
)

print()
print("=" * 110)
print("CONTRÔLE DES DEUX MEDLEYS")
print("=" * 110)

# Numéros LIVE 40–43 et 63–66
wanted_indices = {
    39, 40, 41, 42,
    62, 63, 64, 65,
}

for row in results:
    index = row["scene_index"]

    if index not in wanted_indices:
        continue

    ref = row.get(
        "reference"
    ) or {}

    print(
        f"INDEX {index:03d} / "
        f"LIVE {index + 1:03d} | "
        f"{row['playback_on_count']:02d} PLAY ON | "
        f"{duration_text(ref.get('duration_seconds')):>7} | "
        f"{ref.get('track_name', '—')} | "
        f"{row.get('scene_name')}"
    )
