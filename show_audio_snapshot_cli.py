#!/usr/bin/env python3

"""CLI diagnostic du snapshot global CL Show Audio."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from show_audio_snapshot import (
    ShowAudioSnapshotBuilder,
    format_duration,
)


OUTPUT_PATH = Path("/tmp/cl_show_audio_snapshot.json")


def main(argv):
    if len(argv) > 1:
        try:
            scene_indices = [
                int(value)
                for value in argv[1:]
            ]
        except ValueError as exc:
            print(f"Index scène invalide : {exc}")
            return 2
    else:
        scene_indices = [2, 8, 30]

    builder = ShowAudioSnapshotBuilder()

    snapshot = builder.build(scene_indices)

    OUTPUT_PATH.write_text(
        json.dumps(
            snapshot,
            ensure_ascii=False,
            indent=2,
        ) + "\n",
        encoding="utf-8",
    )

    show = snapshot["set"]
    metrics = snapshot["metrics"]

    print("=" * 100)
    print("CL SHOW AUDIO — SNAPSHOT GLOBAL V1")
    print("=" * 100)
    print(f"Set                  : {show['name']}")
    print(f"generation           : {show['generation']}")
    print(f"scènes               : {metrics['scene_count']}")
    print(f"pistes mises en cache: {metrics['track_cache_size']}")
    print(f"temps total          : {metrics['total_seconds']:.3f} s")
    print(f"HTTP cumulé          : {metrics['http_seconds']:.3f} s")
    print(f"scene-clips cumulé   : {metrics['scene_clip_seconds']:.3f} s")
    print(f"tracks cumulé        : {metrics['track_seconds']:.3f} s")
    print()

    for scene in snapshot["scenes"]:
        print("-" * 100)
        print(
            f"SCÈNE {scene['scene_index']:03d} — "
            f"{scene.get('scene_name', '')}"
        )

        reference = scene.get("reference")

        print(
            f"clips={scene.get('clip_count')} | "
            f"playbacks ON={scene.get('playback_on_count')} | "
            f"inconnus={scene.get('unknown_track_state_count')}"
        )

        if reference:
            print(
                "RÉFÉRENCE : "
                f"{format_duration(reference.get('duration_seconds'))} | "
                f"{reference.get('track_name')} | "
                f"{reference.get('clip_name')}"
            )
        else:
            print("RÉFÉRENCE : —")

    print()
    print(f"JSON : {OUTPUT_PATH}")
    print()
    print(
        "FIN — SNAPSHOT READ-ONLY, "
        "AUCUNE COMMANDE ENVOYÉE À LIVE"
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
