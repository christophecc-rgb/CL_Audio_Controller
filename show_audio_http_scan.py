#!/usr/bin/env python3

"""Diagnostic read-only Show Audio via CL Audio Controller.

Ce scanner :
- ne contacte jamais directement AbletonOSC ;
- ne lance aucune scène ;
- n'envoie aucune commande à Live ;
- lit /status ;
- lit /show-audio/scene-clips ;
- récupère ensuite l'état ON/OFF uniquement des pistes présentes ;
- combine les deux résultats ;
- applique le sélecteur de durée de référence existant.

La classification playback reste volontairement imparfaite à ce stade :
cette passe sert précisément à observer les faux candidats restants.
"""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, Iterable, List

from show_audio_plan import (
    is_playback_track,
    select_reference_playback_clip,
)


BASE_URL = "http://127.0.0.1:5050"


def get_json(path: str, timeout: float = 10.0) -> Dict[str, Any]:
    url = BASE_URL + path

    started = time.monotonic()

    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            raw = response.read()
            status = int(getattr(response, "status", 200) or 200)
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        raise RuntimeError(
            f"HTTP {exc.code} pour {path}: "
            f"{raw.decode('utf-8', errors='replace')}"
        ) from exc
    except Exception as exc:
        raise RuntimeError(f"Erreur HTTP pour {path}: {exc}") from exc

    elapsed = time.monotonic() - started

    try:
        payload = json.loads(raw.decode("utf-8"))
    except Exception as exc:
        raise RuntimeError(
            f"Réponse non JSON pour {path} "
            f"({len(raw)} octets, HTTP {status})"
        ) from exc

    payload["_http_seconds"] = elapsed
    return payload


def format_duration(value: Any) -> str:
    try:
        seconds = float(value)
    except (TypeError, ValueError):
        return "—"

    if seconds <= 0:
        return "—"

    minutes = int(seconds // 60)
    remainder = seconds - (minutes * 60)

    return f"{minutes}:{remainder:05.2f}"


def track_indices_for_clips(clips: Iterable[Dict[str, Any]]) -> List[int]:
    indices = set()

    for clip in clips:
        try:
            indices.add(int(clip["track_index"]))
        except (KeyError, TypeError, ValueError):
            continue

    return sorted(indices)


def read_track_snapshot(indices: List[int]) -> Dict[int, Dict[str, Any]]:
    if not indices:
        return {}

    encoded = urllib.parse.quote(
        ",".join(str(index) for index in indices),
        safe=",",
    )

    data = get_json(
        f"/show-audio/tracks?track_indices={encoded}",
        timeout=max(5.0, len(indices) * 0.35),
    )

    if not data.get("ok"):
        raise RuntimeError(
            f"/show-audio/tracks a répondu ok=false: {data}"
        )

    snapshot: Dict[int, Dict[str, Any]] = {}

    for track in data.get("tracks") or []:
        try:
            index = int(track["track_index"])
        except (KeyError, TypeError, ValueError):
            continue

        snapshot[index] = track

    return snapshot


def merge_track_states(
    clips: Iterable[Dict[str, Any]],
    tracks: Dict[int, Dict[str, Any]],
) -> List[Dict[str, Any]]:
    merged: List[Dict[str, Any]] = []

    for source_clip in clips:
        clip = dict(source_clip)

        try:
            track_index = int(clip["track_index"])
        except (KeyError, TypeError, ValueError):
            track_index = -1

        state = tracks.get(track_index) or {}

        clip["track_on"] = state.get("track_on")
        clip["track_mute"] = state.get("track_mute")

        if not clip.get("track_name") and state.get("track_name"):
            clip["track_name"] = state["track_name"]

        merged.append(clip)

    return merged


def scan_scene(scene_index: int) -> None:
    scene = get_json(
        f"/show-audio/scene-clips?scene_index={scene_index}",
        timeout=10.0,
    )

    if not scene.get("ok"):
        print()
        print("=" * 100)
        print(f"SCÈNE {scene_index:03d} — ERREUR")
        print(scene)
        return

    clips = list(scene.get("clips") or [])
    indices = track_indices_for_clips(clips)

    tracks_started = time.monotonic()
    tracks = read_track_snapshot(indices)
    tracks_seconds = time.monotonic() - tracks_started

    merged = merge_track_states(clips, tracks)

    with open("show_audio.json", "r", encoding="utf-8") as f:
        show_audio_config = json.load(f)

    playback_track_names = (
        show_audio_config.get("playback_tracks")
        or []
    )

    reference = select_reference_playback_clip(
        merged,
        playback_track_names,
    )

    on_clips = [
        clip
        for clip in merged
        if clip.get("track_on") is True
    ]

    on_playbacks = [
        clip
        for clip in on_clips
        if is_playback_track(
            clip.get("track_name", ""),
            playback_track_names,
        )
        and float(
            clip.get("duration_seconds") or 0
        ) > 0
    ]

    unknown = [
        clip
        for clip in merged
        if clip.get("track_on") is None
    ]

    print()
    print("=" * 100)
    print(
        f"SCÈNE {scene_index:03d} — "
        f"{scene.get('scene_name', '')}"
    )
    print("=" * 100)

    print(f"tempo                 : {scene.get('tempo')}")
    print(f"clips présents         : {len(merged)}")
    print(f"pistes interrogées     : {len(indices)}")
    print(f"états inconnus         : {len(unknown)}")
    print(
        "HTTP scene-clips      : "
        f"{float(scene.get('_http_seconds') or 0):.3f} s"
    )
    print(
        "HTTP tracks + parsing : "
        f"{tracks_seconds:.3f} s"
    )
    print(f"clips sur pistes ON    : {len(on_clips)}")
    print(f"playbacks ON autorisés : {len(on_playbacks)}")

    if reference:
        print(
            "durée retenue         : "
            f"{format_duration(reference.get('duration_seconds'))}"
        )
        print(
            "piste retenue         : "
            f"{reference.get('track_name', '')}"
        )
        print(
            "clip retenu           : "
            f"{reference.get('clip_name', '')}"
        )
    else:
        print("durée retenue         : —")
        print("piste retenue         : —")
        print("clip retenu           : —")

    print()
    print("TOUS LES CLIPS PRÉSENTS :")

    reference_track_index = (
        int(reference["track_index"])
        if reference and reference.get("track_index") is not None
        else None
    )

    reference_clip_name = (
        str(reference.get("clip_name") or "")
        if reference
        else ""
    )

    for clip in merged:
        index = int(clip.get("track_index", -1))
        state = clip.get("track_on")

        if state is True:
            state_text = "ON "
        elif state is False:
            state_text = "OFF"
        else:
            state_text = "???"

        playback = is_playback_track(
            clip.get("track_name", ""),
            playback_track_names,
        )

        marker = "  "

        if (
            reference_track_index == index
            and reference_clip_name
            == str(clip.get("clip_name") or "")
        ):
            marker = "=>"

        print(
            f"{marker} "
            f"{index:03d} | "
            f"{state_text} | "
            f"{format_duration(clip.get('duration_seconds')):>8} | "
            f"{'PLAY' if playback else '    '} | "
            f"{clip.get('track_name', '')} | "
            f"{clip.get('clip_name', '')}"
        )

    print()
    print("PLAYBACKS ON AUTORISÉS :")

    if not on_playbacks:
        print("  aucun")
    else:
        ordered = sorted(
            on_playbacks,
            key=lambda item: float(
                item.get("duration_seconds") or 0
            ),
            reverse=True,
        )

        for clip in ordered:
            index = int(clip.get("track_index", -1))

            selected = (
                reference_track_index == index
                and reference_clip_name
                == str(clip.get("clip_name") or "")
            )

            print(
                f"{'=>' if selected else '  '} "
                f"{index:03d} | "
                f"{format_duration(clip.get('duration_seconds')):>8} | "
                f"{clip.get('track_name', '')} | "
                f"{clip.get('clip_name', '')}"
            )


def main(argv: List[str]) -> int:
    print("=" * 100)
    print("CL SHOW AUDIO — SCAN HTTP READ-ONLY")
    print("=" * 100)

    status = get_json("/status", timeout=5.0)

    print(f"service        : {status.get('service')}")
    print(f"PID            : {status.get('server_process_id')}")
    print(f"Set            : {status.get('current_set_name')}")
    print(f"Set ready      : {status.get('set_ready')}")
    print(f"generation     : {status.get('set_generation')}")

    if len(argv) > 1:
        scene_indices = []

        for raw in argv[1:]:
            try:
                scene_indices.append(int(raw))
            except ValueError:
                print(f"Index scène invalide : {raw!r}")
                return 2
    else:
        scene_indices = [2, 8, 30]

    for scene_index in scene_indices:
        scan_scene(scene_index)

    print()
    print("=" * 100)
    print("FIN DU SCAN — AUCUNE COMMANDE ENVOYÉE À LIVE")
    print("=" * 100)

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
