#!/usr/bin/env python3
"""Regenerate the CL Audio Show Control macOS icon assets."""

from __future__ import annotations

import hashlib
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "cl_audio_show_control_icon_1024.png"
ICONSET = ROOT / "icon.iconset"
OUTPUT = ROOT / "CL_AUDIO.icns"
MIDI_SOURCE = ROOT / "assets" / "cl_midi_network_assistant_icon_1024.png"
MIDI_OUTPUT = ROOT / "assets" / "CL_MIDI_Network_Assistant.icns"

ICON_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"Icône source absente : {SOURCE}")

    source = Image.open(SOURCE).convert("RGBA")
    if source.size != (1024, 1024):
        raise SystemExit(f"Dimensions inattendues : {source.size}, attendu 1024 x 1024")

    ICONSET.mkdir(exist_ok=True)
    for filename, pixels in ICON_SIZES.items():
        resized = source.resize((pixels, pixels), Image.Resampling.LANCZOS)
        resized.save(ICONSET / filename, format="PNG", optimize=True)

    # Pillow produces a modern multi-resolution ICNS accepted by PyInstaller,
    # Finder, Dock and Launchpad. iconutil rejects valid iconsets on some recent
    # macOS releases, including the Builder's established iconset.
    source.save(OUTPUT, format="ICNS")

    if not MIDI_SOURCE.is_file():
        raise SystemExit(f"Icône source absente : {MIDI_SOURCE}")
    midi_source = Image.open(MIDI_SOURCE).convert("RGBA")
    if midi_source.size != (1024, 1024):
        raise SystemExit(
            f"Dimensions inattendues : {midi_source.size}, attendu 1024 x 1024"
        )
    midi_source.save(MIDI_OUTPUT, format="ICNS")

    print(OUTPUT)
    print(f"source sha256: {sha256(SOURCE)}")
    print(f"icns   sha256: {sha256(OUTPUT)}")
    print(MIDI_OUTPUT)
    print(f"source sha256: {sha256(MIDI_SOURCE)}")
    print(f"icns   sha256: {sha256(MIDI_OUTPUT)}")


if __name__ == "__main__":
    main()
