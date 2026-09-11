"""Configuration sérialisable des futurs exports CL Show Audio.

Ce module ne capture, ne lit et n'encode aucun audio.
"""

from __future__ import annotations

import json
from typing import Any


AUDIO_PROFILES = ("clean", "mastered", "direct")
SAMPLE_RATES = (44100, 48000, 88200, 96000)
MP3_BITRATES = (192, 256, 320)
PCM_BIT_DEPTHS = (16, 24, "float32")
FLAC_BIT_DEPTHS = (16, 24)
EXPORT_FORMATS = ("mp3", "wav", "aiff", "flac")


def default_export_settings() -> dict:
    return {
        "audio_profile": "clean",
        "sample_rate": 48000,
        "normalize": False,
        "export_scenes": True,
        "export_medleys": True,
        "keep_master_wav": False,
        "formats": [{"format": "mp3", "bitrate_kbps": 320}],
    }


def _boolean(value: Any, field: str) -> bool:
    if isinstance(value, bool):
        return value
    raise ValueError(f"{field} doit être un booléen")


def _bit_depth(value: Any) -> int | str:
    aliases = {"16": 16, "24": 24, "32": "float32", "float32": "float32",
               "32-bit float": "float32", "32 bit float": "float32"}
    key = str(value).strip().casefold()
    return aliases.get(key, value)


def normalize_export_settings(values: dict | None = None) -> dict:
    if values is None:
        values = default_export_settings()
    if not isinstance(values, dict):
        raise ValueError("Export Settings invalides")

    profile = str(values.get("audio_profile") or "").strip().casefold()
    if profile not in AUDIO_PROFILES:
        raise ValueError(f"profil audio inconnu : {profile or 'vide'}")
    try:
        sample_rate = int(values.get("sample_rate"))
    except (TypeError, ValueError) as exc:
        raise ValueError("sample rate invalide") from exc
    if sample_rate not in SAMPLE_RATES:
        raise ValueError(f"sample rate non supporté : {sample_rate}")

    flags = {field: _boolean(values.get(field), field) for field in (
        "normalize", "export_scenes", "export_medleys", "keep_master_wav")}
    if not flags["export_scenes"] and not flags["export_medleys"]:
        raise ValueError("sélection vide : scènes et medleys sont tous deux désactivés")

    raw_formats = values.get("formats")
    if not isinstance(raw_formats, list) or not raw_formats:
        raise ValueError("au moins un format d’export est obligatoire")
    formats, seen = [], set()
    for index, raw in enumerate(raw_formats, 1):
        if not isinstance(raw, dict):
            raise ValueError(f"format #{index} invalide")
        name = str(raw.get("format") or "").strip().casefold()
        if name not in EXPORT_FORMATS:
            raise ValueError(f"format inconnu : {name or 'vide'}")
        if name == "mp3":
            if raw.get("bit_depth") not in (None, ""):
                raise ValueError("MP3 ne peut pas définir de profondeur PCM")
            try:
                bitrate = int(raw.get("bitrate_kbps"))
            except (TypeError, ValueError) as exc:
                raise ValueError("bitrate MP3 invalide") from exc
            if bitrate not in MP3_BITRATES:
                raise ValueError(f"bitrate MP3 non supporté : {bitrate}")
            item = {"format": name, "bitrate_kbps": bitrate}
        else:
            if raw.get("bitrate_kbps") not in (None, ""):
                raise ValueError(f"{name.upper()} ne peut pas définir de bitrate MP3")
            depth = _bit_depth(raw.get("bit_depth"))
            supported = FLAC_BIT_DEPTHS if name == "flac" else PCM_BIT_DEPTHS
            if depth not in supported:
                raise ValueError(f"profondeur {name.upper()} non supportée : {depth}")
            item = {"format": name, "bit_depth": depth}
        key = tuple(item.items())
        if key in seen:
            raise ValueError(f"format dupliqué : {name}")
        seen.add(key)
        formats.append(item)

    return {"audio_profile": profile, "sample_rate": sample_rate, **flags,
            "formats": formats}


def export_settings_json(values: dict, *, indent: int | None = 2) -> str:
    return json.dumps(normalize_export_settings(values), ensure_ascii=False,
                      indent=indent, sort_keys=True)


def load_export_settings_json(payload: str) -> dict:
    try:
        values = json.loads(payload)
    except json.JSONDecodeError as exc:
        raise ValueError("JSON Export Settings invalide") from exc
    return normalize_export_settings(values)
