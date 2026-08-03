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
    source_boxes = {
        item["box"]["id"]: item["box"] for item in source["patcher"]["boxes"]
    }
    obsolete = {"idreg", "trig", "f", "dval", "rel", "id0"}
    compiled_boxes = compiled["patcher"]["boxes"]
    compiled["patcher"]["boxes"] = [
        item for item in compiled_boxes if item["box"]["id"] not in obsolete
    ]

    for item in compiled["patcher"]["boxes"]:
        box_id = item["box"]["id"]
        if box_id in {"note", "pulse", "value_note"}:
            item["box"]["text"] = source_boxes[box_id]["text"]

    kept_lines = []
    for item in compiled["patcher"]["lines"]:
        source_id = item["patchline"]["source"][0]
        destination_id = item["patchline"]["destination"][0]
        if source_id in obsolete or destination_id in obsolete:
            continue
        kept_lines.append(item)

    required = [
        ("lp", 0, "remote", 1),
        ("clip", 0, "sig", 0),
        ("clip", 0, "pval", 0),
    ]
    existing = {
        (
            item["patchline"]["source"][0],
            item["patchline"]["source"][1],
            item["patchline"]["destination"][0],
            item["patchline"]["destination"][1],
        )
        for item in kept_lines
    }
    for source_id, source_outlet, destination_id, destination_inlet in required:
        edge = (source_id, source_outlet, destination_id, destination_inlet)
        if edge not in existing:
            kept_lines.append(
                {
                    "patchline": {
                        "source": [source_id, source_outlet],
                        "destination": [destination_id, destination_inlet],
                    }
                }
            )
    compiled["patcher"]["lines"] = kept_lines


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
