#!/usr/bin/env python3
"""Generate the independent configurable v2 MIDI console monitor."""

from __future__ import annotations

import argparse
import json
import shutil
import struct
from pathlib import Path


DEVICE_NAME = "CL MIDI Console Monitor v2 Configurable"
ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "M4L" / "Devices" / DEVICE_NAME


def box(identifier, maxclass, rect, **values):
    payload = {"id": identifier, "maxclass": maxclass, "numinlets": values.pop("numinlets", 1),
               "numoutlets": values.pop("numoutlets", 1), "patching_rect": rect}
    payload.update(values)
    return {"box": payload}


def line(source, destination, outlet=0, inlet=0, order=None):
    payload = {"source": [source, outlet], "destination": [destination, inlet]}
    if order is not None:
        payload["order"] = order
    return {"patchline": payload}


def payload():
    boxes = [
        box("midi-in", "newobj", [30, 260, 45, 22], text="midiin", outlettype=["int"]),
        box("midi-out", "newobj", [30, 330, 50, 22], text="midiout", numoutlets=0),
        box("midi-parse", "newobj", [100, 330, 65, 22], text="midiparse", numoutlets=8,
            outlettype=["", "", "", "int", "int", "", "int", ""]),
        box("resolver", "newobj", [210, 330, 260, 22], text="js CLMidiConsoleConfigurable.js", numinlets=4, numoutlets=4),
        box("loadbang", "newobj", [490, 330, 60, 22], text="loadbang"),
        box("defer", "newobj", [560, 330, 58, 22], text="delay 350"),
        box("refresh", "message", [630, 330, 54, 22], text="refresh"),
        box("source-menu", "umenu", [190, 8, 330, 24], presentation=1,
            presentation_rect=[190, 8, 330, 24], varname="v2_source_track", items=["Automatique"]),
        box("console-name", "textedit", [65, 43, 190, 24], presentation=1,
            presentation_rect=[65, 43, 190, 24], varname="v2_console_name", text="Console", rounded=5),
        box("console-label", "comment", [14, 46, 48, 18], numoutlets=0, presentation=1,
            presentation_rect=[14, 46, 48, 18], text="Nom", fontsize=9.0),
        box("route-text", "newobj", [210, 375, 65, 22], text="route text"),
        box("mode-menu", "live.menu", [270, 43, 120, 24], presentation=1,
            presentation_rect=[270, 43, 120, 24], varname="v2_console_mode", items=["Commande", "Retour"],
            parameter_enable=1, saved_attribute_attributes={"valueof": {"parameter_enum": ["Commande", "Retour"],
                "parameter_longname": "Mode console", "parameter_shortname": "Mode", "parameter_type": 2}}),
        box("slot-menu", "live.menu", [400, 43, 120, 24], presentation=1,
            presentation_rect=[400, 43, 120, 24], varname="v2_console_slot",
            items=["Console 1", "Console 2", "Console 3", "Console 4", "Console 5", "Console 6"],
            parameter_enable=1, saved_attribute_attributes={"valueof": {"parameter_enum":
                ["Console 1", "Console 2", "Console 3", "Console 4", "Console 5", "Console 6"],
                "parameter_longname": "Emplacement console", "parameter_shortname": "Console", "parameter_type": 2}}),
        box("logo", "fpic", [14, 5, 160, 30], presentation=1, presentation_rect=[14, 5, 160, 30],
            pic="paradis_latin_logo.jpg", autofit=1, forceaspect=1, ignoreclick=1, outlettype=["jit_matrix"]),
        box("panel", "panel", [12, 76, 516, 60], numoutlets=0, presentation=1,
            presentation_rect=[12, 76, 516, 60], bgcolor=[0.04, 0.08, 0.12, 1], border=1, rounded=8, background=1),
        box("title", "message", [24, 87, 350, 24], presentation=1, presentation_rect=[24, 87, 350, 24],
            text="—", fontsize=12.0, fontface=1, textcolor=[0.35, 0.72, 1, 1], bgcolor=[0.03, 0.05, 0.08, 1], border=0),
        box("program", "message", [385, 87, 125, 24], presentation=1, presentation_rect=[385, 87, 125, 24],
            text="—", fontsize=11.0, fontface=1, textcolor=[0.95, 0.75, 0.3, 1], bgcolor=[0.03, 0.05, 0.08, 1], border=0),
        box("status", "message", [24, 112, 486, 20], presentation=1, presentation_rect=[24, 112, 486, 20],
            text="Sélectionnez une piste MIDI", fontsize=9.0, textcolor=[0.6, 0.7, 0.82, 1], bgcolor=[0.03, 0.05, 0.08, 1], border=0),
        box("autopattr", "newobj", [700, 330, 60, 22], text="autopattr"),
    ]
    lines = [
        line("midi-in", "midi-out", order=0), line("midi-in", "midi-parse", order=1),
        line("midi-parse", "resolver", outlet=3, inlet=1),
        line("source-menu", "resolver", inlet=0), line("resolver", "source-menu", outlet=0),
        line("console-name", "route-text"), line("route-text", "resolver", inlet=2),
        line("loadbang", "defer"), line("defer", "refresh"), line("refresh", "resolver"),
        line("resolver", "title", outlet=1), line("resolver", "program", outlet=2),
        line("resolver", "status", outlet=3),
    ]
    return {"patcher": {"fileversion": 1, "appversion": {"major": 9, "minor": 1, "revision": 4,
        "architecture": "x64", "modernui": 1}, "classnamespace": "box", "rect": [70, 70, 900, 600],
        "openinpresentation": 1, "devicewidth": 540.0,
        "description": "Configurable per-console MIDI Program Change monitor",
        "digest": "Dynamic Live track selection with persistent console configuration", "title": DEVICE_NAME,
        "project": {"version": 1, "creationdate": 0, "modificationdate": 0, "viewrect": [0, 0, 300, 500],
            "autoorganize": 1, "hideprojectwindow": 1, "showdependencies": 1, "autolocalize": 0,
            "contents": {"patchers": {}}, "layout": {}, "searchpath": {}, "detailsvisible": 0,
            "amxdtype": 1835887981, "readonly": 0, "devpathtype": 0, "devpath": ".", "sortmode": 0, "viewmode": 0},
        "bgcolor": [0.04, 0.05, 0.07, 1], "boxes": boxes, "lines": lines,
        "dependency_cache": [
            {"name": "CLMidiConsoleConfigurable.js", "bootpath": ".", "patcherrelativepath": ".", "type": "TEXT", "implicit": 1},
            {"name": "paradis_latin_logo.jpg", "bootpath": ".", "patcherrelativepath": ".", "type": "JPEG", "implicit": 1},
        ]}}


def write_amxd(path: Path, data: dict):
    patch = (json.dumps(data, indent=2, ensure_ascii=False) + "\n").encode()
    path.write_bytes(b"ampf" + struct.pack("<I", 4) + b"mmmm" + b"meta" + struct.pack("<I", 4) +
                     struct.pack("<I", 0) + b"ptch" + struct.pack("<I", len(patch)) + patch)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=SOURCE_DIR)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    data = payload()
    (args.output_dir / f"{DEVICE_NAME}.maxpat").write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    write_amxd(args.output_dir / f"{DEVICE_NAME}.amxd", data)
    for name in ("CLMidiConsoleConfigurable.js", "paradis_latin_logo.jpg"):
        source = SOURCE_DIR / name
        destination = args.output_dir / name
        if source.exists() and source.resolve() != destination.resolve(): shutil.copy2(source, destination)


if __name__ == "__main__":
    main()
