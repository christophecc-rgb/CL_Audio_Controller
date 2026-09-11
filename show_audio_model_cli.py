#!/usr/bin/env python3

"""Construit et affiche le modèle métier CL Show Audio."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from show_audio_model import build_show_audio_model
from show_audio_snapshot import ShowAudioSnapshotBuilder


CONFIG_PATH = Path("show_audio.json")
SNAPSHOT_PATH = Path("/tmp/cl_show_audio_snapshot.json")
MODEL_PATH = Path("/tmp/cl_show_audio_model.json")


def _load_json(path: Path):
    if not path.exists():
        return {}

    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _format_duration(value):
    if value is None:
        return "—"

    value = float(value)
    minutes = int(value // 60)
    seconds = value - minutes * 60

    return f"{minutes}:{seconds:05.2f}"


def _build_fresh_snapshot():
    builder = ShowAudioSnapshotBuilder(
        config_path=CONFIG_PATH
    )

    status = builder.status()

    scenes = status.get("scenes") or []

    if not scenes:
        raise RuntimeError(
            "Aucune scène disponible dans /status"
        )

    return builder.build(
        range(len(scenes))
    )


def main(argv):
    fresh = "--fresh" in argv

    if fresh or not SNAPSHOT_PATH.exists():
        snapshot = _build_fresh_snapshot()

        SNAPSHOT_PATH.write_text(
            json.dumps(
                snapshot,
                ensure_ascii=False,
                indent=2,
            ) + "\n",
            encoding="utf-8",
        )
    else:
        snapshot = _load_json(
            SNAPSHOT_PATH
        )

    config = _load_json(
        CONFIG_PATH
    )

    model = build_show_audio_model(
        snapshot,
        config,
    )

    MODEL_PATH.write_text(
        json.dumps(
            model,
            ensure_ascii=False,
            indent=2,
        ) + "\n",
        encoding="utf-8",
    )

    metrics = model["metrics"]

    print("=" * 110)
    print("CL SHOW AUDIO — MODÈLE MÉTIER V1")
    print("=" * 110)
    print(
        "Set                  :",
        model["set"].get("name"),
    )
    print(
        "scènes               :",
        metrics["scene_count"],
    )
    print(
        "exportables          :",
        metrics["exportable_count"],
    )
    print(
        "ready                :",
        metrics["ready_count"],
    )
    print(
        "playbacks multiples  :",
        metrics["multiple_playback_count"],
    )
    print(
        "sans playback        :",
        metrics["no_playback_count"],
    )
    print(
        "scènes configurées   :",
        metrics["configured_scene_count"],
    )

    print()
    print(
        f"{'IDX':>3} | {'SHOW':>4} | "
        f"{'DURÉE':>7} | {'PLAY':>4} | "
        f"{'VAR':>3} | {'ÉTAT':<18} | TITRE"
    )
    print("-" * 110)

    for item in model["items"]:
        reference = (
            item.get("reference_playback")
            or {}
        )

        print(
            f"{item['scene_index']:03d} | "
            f"{item.get('show_number') or '—':>4} | "
            f"{_format_duration(item.get('duration_seconds')):>7} | "
            f"{item.get('playback_on_count', 0):>4} | "
            f"{len(item.get('variants') or []):>3} | "
            f"{item.get('status', ''):<18} | "
            f"{item.get('title') or item.get('scene_name')}"
        )

        if item.get("exportable"):
            print(
                f"      ↳ "
                f"{reference.get('track_name', '')}"
                f" / "
                f"{reference.get('clip_name', '')}"
            )

        for variant in item.get("variants") or []:
            print(
                "      ↳ VAR "
                f"{variant.get('role') or '—'} | "
                f"{variant.get('artist') or '—'} | "
                f"KEY {variant.get('key') or '—'} | "
                f"{variant.get('playback') or '—'}"
            )

    print()
    print("MODEL :", MODEL_PATH)
    print("SNAP  :", SNAPSHOT_PATH)

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
