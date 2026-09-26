#!/usr/bin/env python3
"""Synchronize the editable X-Fader patch with its installable AMXD container."""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEVICE_DIR = ROOT / "M4L" / "Devices" / "XFADER OSC BRIDGE v8"
SOURCE = DEVICE_DIR / "XFADER OSC BRIDGE v8.maxpat"
DEVICE = DEVICE_DIR / "XFADER OSC BRIDGE v8.amxd"
INSTALL_DEVICE = ROOT / "M4L" / "Install" / DEVICE.name
LEGACY_SOURCE = ROOT / "M4L" / "XFADER_OSC_BRIDGE_v8_OSC_REMOTE_STORE_ID.maxpat"


def read_amxd(path: Path) -> tuple[bytes, dict]:
    raw = path.read_bytes()
    if raw[:4] != b"ampf" or raw[24:28] != b"ptch":
        raise ValueError(f"Format AMXD non reconnu: {path}")
    length = struct.unpack("<I", raw[28:32])[0]
    return raw[:28], json.loads(raw[32 : 32 + length].rstrip(b"\0"))


def write_amxd(path: Path, header: bytes, payload: dict) -> None:
    patch = (json.dumps(payload, indent=2, ensure_ascii=False) + "\n").encode("utf-8") + b"\0"
    path.write_bytes(header + struct.pack("<I", len(patch)) + patch)


def synchronize_graph(compiled: dict, source: dict) -> None:
    """Use the editable live.object patch as the canonical device graph."""
    compiled.clear()
    compiled.update(json.loads(json.dumps(source)))



def main() -> None:
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    base = Path(sys.argv[1]) if len(sys.argv) > 1 else DEVICE
    header, compiled = read_amxd(base)

    synchronize_graph(compiled, source)
    write_amxd(DEVICE, header, compiled)

    INSTALL_DEVICE.write_bytes(DEVICE.read_bytes())
    LEGACY_SOURCE.write_text(
        json.dumps(source, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
