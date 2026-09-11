"""Parseur tolérant des noms de scènes Ableton pour CL Show Audio Builder."""

from __future__ import annotations

import re
from typing import Any, Optional


_DURATION_RE = re.compile(
    r"(?<!\d)(\d{1,2})\s*:\s*(\d{1,2})\s*$"
)

_LEADING_NUMBER_RE = re.compile(
    r"^\s*(\d+)\s*-\s*(.+?)\s*$"
)


def _text(value: Any) -> str:
    return str(value or "").strip()


def parse_duration_label(
    value: Any,
) -> Optional[float]:
    text = _text(value)

    match = _DURATION_RE.search(text)

    if not match:
        return None

    minutes = int(match.group(1))
    seconds = int(match.group(2))

    if seconds >= 60:
        return None

    return float(
        minutes * 60 + seconds
    )


def _clean_title(value: str) -> str:
    text = value.strip()

    # Retire uniquement les séparateurs laissés
    # par la partie metadata.
    text = re.sub(
        r"\s*;\s*$",
        "",
        text,
    )

    return text.strip()


def parse_scene_name(
    scene_index: int,
    scene_name: Any,
) -> dict:
    raw = _text(scene_name)

    duration_seconds = parse_duration_label(
        raw
    )

    working = raw

    if duration_seconds is not None:
        working = _DURATION_RE.sub(
            "",
            working,
        ).strip()

        working = re.sub(
            r"\s*;\s*$",
            "",
            working,
        )

    # Les tokens BPM / KEY sont aujourd'hui
    # souvent des placeholders. On les reconnaît
    # mais on n'invente aucune valeur.
    metadata_tokens = []

    parts = [
        part.strip()
        for part in working.split(";")
    ]

    title_parts = []

    for part in parts:
        token = part.strip()

        if not token:
            continue

        upper = token.upper()

        if upper == "BPM":
            metadata_tokens.append("BPM")
            continue

        if upper == "KEY":
            metadata_tokens.append("KEY")
            continue

        title_parts.append(token)

    title = _clean_title(
        " ; ".join(title_parts)
    )

    show_number = None

    match = _LEADING_NUMBER_RE.match(
        title
    )

    if match:
        show_number = int(match.group(1))
        title = match.group(2).strip()

    return {
        "scene_index": int(scene_index),
        "scene_number": int(scene_index) + 1,
        "raw_name": raw,
        "show_number": show_number,
        "title": title,
        "declared_bpm": None,
        "declared_key": None,
        "declared_duration_seconds": duration_seconds,
        "has_bpm_placeholder": (
            "BPM" in metadata_tokens
        ),
        "has_key_placeholder": (
            "KEY" in metadata_tokens
        ),
        "empty": not bool(raw),
    }


def parse_scene_inventory(
    scenes: list[dict],
) -> list[dict]:
    return [
        parse_scene_name(
            scene["scene_index"],
            scene.get("scene_name", ""),
        )
        for scene in scenes
    ]
