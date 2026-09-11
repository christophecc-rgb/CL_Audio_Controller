#!/usr/bin/env python3

import json
from pathlib import Path

from show_audio_export_plan import (
    build_export_plan,
)


CONFIG_PATH = Path(
    "show_audio.json"
)

SNAPSHOT_PATH = Path(
    "/tmp/cl_show_audio_snapshot.json"
)

OUTPUT_PATH = Path(
    "/tmp/cl_show_audio_export_plan.json"
)


def duration_text(value):
    if value is None:
        return "—"

    seconds = float(value)

    minutes = int(
        seconds // 60
    )

    seconds -= (
        minutes * 60
    )

    return (
        f"{minutes}:{seconds:05.2f}"
    )


if not CONFIG_PATH.exists():
    raise SystemExit(
        "show_audio.json absent"
    )

if not SNAPSHOT_PATH.exists():
    raise SystemExit(
        "Snapshot réel absent : "
        "/tmp/cl_show_audio_snapshot.json"
    )

config = json.loads(
    CONFIG_PATH.read_text(
        encoding="utf-8"
    )
)

snapshot = json.loads(
    SNAPSHOT_PATH.read_text(
        encoding="utf-8"
    )
)

plan = build_export_plan(
    config,
    snapshot,
)

OUTPUT_PATH.write_text(
    json.dumps(
        plan,
        ensure_ascii=False,
        indent=2,
    ) + "\n",
    encoding="utf-8",
)

metrics = (
    plan.get("metrics")
    or {}
)

print("=" * 125)
print("CL SHOW AUDIO — EXPORT PLAN")
print("=" * 125)

print(
    "Exports scènes      :",
    metrics.get(
        "scene_export_count"
    ),
)
print(
    "  scènes simples    :",
    metrics.get(
        "simple_scene_count"
    ),
)
print(
    "  parties medley    :",
    metrics.get(
        "medley_part_count"
    ),
)
print(
    "Medleys complets    :",
    metrics.get(
        "medley_full_count"
    ),
)
print(
    "TOTAL fichiers      :",
    metrics.get(
        "item_count"
    ),
)

print()
print("=" * 125)
print("PLAN")
print("=" * 125)

for item in plan.get(
    "items"
) or []:

    item_type = (
        item.get("type")
        or ""
    )

    if item_type == (
        "medley_full"
    ):
        print()
        print(
            f"MEDLEY "
            f"{item['first_scene_number']:03d}"
            f"→"
            f"{item['last_scene_number']:03d}"
            f" | COMPLET"
            f" | "
            f"{duration_text(item.get('duration_seconds')):>7}"
            f" | "
            f"{item['title']}"
        )

        print(
            "      scènes :",
            ", ".join(
                str(value)
                for value in (
                    item.get(
                        "scene_numbers"
                    )
                    or []
                )
            ),
        )

        print(
            "      mode   :",
            item.get(
                "play_mode"
            ),
        )

        print(
            "      fichier:",
            item.get(
                "filename_stem"
            ),
        )

        continue

    scene_number = int(
        item["scene_number"]
    )

    label = (
        "PARTIE MEDLEY"
        if item_type
        == "medley_part"
        else "SCÈNE"
    )

    print(
        f"{scene_number:03d}"
        f" | {label:<14}"
        f" | "
        f"{duration_text(item.get('duration_seconds')):>7}"
        f" | "
        f"{item.get('playback_track')}"
        f" | "
        f"{item.get('title')}"
    )

print()
print(
    "JSON :",
    OUTPUT_PATH,
)
