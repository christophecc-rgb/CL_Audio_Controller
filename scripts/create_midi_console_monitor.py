#!/usr/bin/env python3
"""Generate the CL MIDI Console Monitor Max for Live MIDI device."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


DEVICE_NAME = "CL MIDI Console Monitor"
CONSOLES = ("CL5", "QL1 CC", "QL1 PGM", "CL5 retour", "QL1 retour")


def box(identifier, maxclass, rect, **values):
    payload = {
        "id": identifier,
        "maxclass": maxclass,
        "numinlets": values.pop("numinlets", 1),
        "numoutlets": values.pop("numoutlets", 1),
        "patching_rect": rect,
    }
    payload.update(values)
    return {"box": payload}


def line(source, destination, outlet=0, inlet=0, order=None):
    payload = {
        "source": [source, outlet],
        "destination": [destination, inlet],
    }
    if order is not None:
        payload["order"] = order
    return {"patchline": payload}


def device_payload():
    boxes = [
        box("midi-in", "newobj", [30.0, 250.0, 45.0, 22.0], text="midiin", outlettype=["int"]),
        box("midi-out", "newobj", [30.0, 325.0, 50.0, 22.0], text="midiout", numoutlets=0),
        box(
            "midi-parse", "newobj", [110.0, 325.0, 65.0, 22.0],
            text="midiparse", numoutlets=8,
            outlettype=["", "", "", "int", "int", "", "int", ""],
        ),
        box("event-gate", "newobj", [180.0, 510.0, 48.0, 22.0], text="gate 5", numinlets=2, numoutlets=5),
        box("lookup-cl5", "newobj", [35.0, 525.0, 220.0, 22.0], text="js CLMidiConsoleDisplay.js CL5 1"),
        box("lookup-ql1-cc", "newobj", [200.0, 525.0, 235.0, 22.0], text="js CLMidiConsoleDisplay.js QL1_CC 1"),
        box("lookup-ql1-pgm", "newobj", [365.0, 525.0, 245.0, 22.0], text="js CLMidiConsoleDisplay.js QL1_PGM 1"),
        # With no full-packet argument, Max's udpreceive already decodes OSC
        # into ordinary Max messages. Feeding that output through oscparse a
        # second time discards the address before it can be routed.
        box("scene-udp", "newobj", [610.0, 250.0, 108.0, 22.0], text="udpreceive 9002"),
        box("scene-route", "newobj", [610.0, 285.0, 290.0, 22.0], text="route /cl/midi-monitor/scene /cl/midi-monitor/reset", numoutlets=3),
        box("scene-prepend", "newobj", [610.0, 320.0, 92.0, 22.0], text="prepend scene"),
        box("scene-reset", "message", [720.0, 320.0, 72.0, 22.0], text="reset"),
        box("scene-send", "newobj", [610.0, 355.0, 210.0, 22.0], text="s CL_MIDI_MON_SCENE_CONTEXT", numoutlets=0),
        box("scene-recv", "newobj", [610.0, 395.0, 210.0, 22.0], text="r CL_MIDI_MON_SCENE_CONTEXT"),
        box("status-plus-cl5", "newobj", [35.0, 575.0, 32.0, 22.0], text="+ 1"),
        box("status-plus-ql1-cc", "newobj", [195.0, 575.0, 32.0, 22.0], text="+ 1"),
        box("status-plus-ql1-pgm", "newobj", [370.0, 575.0, 32.0, 22.0], text="+ 1"),
        box("status-label-cl5", "newobj", [35.0, 700.0, 150.0, 22.0], text="prepend MIDI · CL5 · Scène"),
        box("status-label-ql1-cc", "newobj", [195.0, 700.0, 175.0, 22.0], text="prepend MIDI · QL1 via CC · Scène"),
        box("status-label-ql1-pgm", "newobj", [370.0, 700.0, 185.0, 22.0], text="prepend MIDI · QL1 direct · Scène"),
        box("status-send", "newobj", [610.0, 700.0, 165.0, 22.0], text="s CL_MIDI_MON_STATUS", numoutlets=0),
        box("status-recv", "newobj", [610.0, 735.0, 165.0, 22.0], text="r CL_MIDI_MON_STATUS"),
        box("status-set", "newobj", [785.0, 735.0, 72.0, 22.0], text="prepend set"),
        box("send-cl5", "newobj", [80.0, 550.0, 125.0, 22.0], text="s CL_MIDI_MON_CL5", numoutlets=0),
        box("send-ql1-cc", "newobj", [215.0, 550.0, 145.0, 22.0], text="s CL_MIDI_MON_QL1", numoutlets=0),
        box("send-ql1-pgm", "newobj", [370.0, 550.0, 155.0, 22.0], text="s CL_MIDI_MON_QL1", numoutlets=0),
        box("request-cl5", "newobj", [35.0, 780.0, 185.0, 22.0], text="s CL_MIDI_MON_CL5_REQUEST", numoutlets=0),
        box("request-ql1-cc", "newobj", [230.0, 780.0, 185.0, 22.0], text="s CL_MIDI_MON_QL1_REQUEST", numoutlets=0),
        box("request-ql1-pgm", "newobj", [425.0, 780.0, 185.0, 22.0], text="s CL_MIDI_MON_QL1_REQUEST", numoutlets=0),
        box("confirm-cl5", "newobj", [620.0, 780.0, 190.0, 22.0], text="s CL_MIDI_MON_CL5_CONFIRM", numoutlets=0),
        box("confirm-ql1", "newobj", [820.0, 780.0, 190.0, 22.0], text="s CL_MIDI_MON_QL1_CONFIRM", numoutlets=0),
        box("confirm-plus-cl5", "newobj", [620.0, 700.0, 32.0, 22.0], text="+ 1"),
        box("confirm-plus-ql1", "newobj", [820.0, 700.0, 32.0, 22.0], text="+ 1"),
        box("confirm-label-cl5", "newobj", [620.0, 735.0, 180.0, 22.0], text="prepend RETOUR · CL5 · Scène"),
        box("confirm-label-ql1", "newobj", [820.0, 735.0, 180.0, 22.0], text="prepend RETOUR · QL1 · Scène"),
        box("request-recv-cl5", "newobj", [35.0, 825.0, 185.0, 22.0], text="r CL_MIDI_MON_CL5_REQUEST"),
        box("confirm-recv-cl5", "newobj", [35.0, 860.0, 185.0, 22.0], text="r CL_MIDI_MON_CL5_CONFIRM"),
        box("confirmation-js-cl5", "newobj", [230.0, 825.0, 245.0, 22.0], text="js CLMidiConsoleConfirmation.js CL5 1", numinlets=2, numoutlets=2),
        box("request-recv-ql1", "newobj", [500.0, 825.0, 185.0, 22.0], text="r CL_MIDI_MON_QL1_REQUEST"),
        box("confirm-recv-ql1", "newobj", [500.0, 860.0, 185.0, 22.0], text="r CL_MIDI_MON_QL1_CONFIRM"),
        box("confirmation-js-ql1", "newobj", [695.0, 825.0, 245.0, 22.0], text="js CLMidiConsoleConfirmation.js QL1 1", numinlets=2, numoutlets=2),
        box("confirm-set-cl5", "newobj", [230.0, 860.0, 72.0, 22.0], text="prepend set"),
        box("confirm-set-ql1", "newobj", [695.0, 860.0, 72.0, 22.0], text="prepend set"),
        box("confirm-match-cl5", "newobj", [315.0, 860.0, 36.0, 22.0], text="sel 1"),
        box("confirm-match-ql1", "newobj", [780.0, 860.0, 36.0, 22.0], text="sel 1"),
        box(
            "role-menu", "live.menu", [330.0, 250.0, 170.0, 22.0],
            numoutlets=2, parameter_enable=1, presentation=1,
            presentation_rect=[348.0, 6.0, 178.0, 24.0],
            varname="console_role", items=list(CONSOLES),
            saved_attribute_attributes={"valueof": {
                "parameter_enum": list(CONSOLES),
                "parameter_longname": "Console surveillée",
                "parameter_shortname": "Console",
                "parameter_type": 2,
            }},
        ),
        box("role-index", "newobj", [330.0, 285.0, 30.0, 22.0], text="+ 1"),
        box("role-default", "newobj", [380.0, 285.0, 75.0, 22.0], text="loadmess 1"),
        box("role-loadbang", "newobj", [465.0, 285.0, 60.0, 22.0], text="loadbang"),
        box("role-defer", "newobj", [465.0, 320.0, 58.0, 22.0], text="deferlow"),
        box("recv-cl5", "newobj", [35.0, 605.0, 125.0, 22.0], text="r CL_MIDI_MON_CL5"),
        box("recv-ql1", "newobj", [195.0, 605.0, 145.0, 22.0], text="r CL_MIDI_MON_QL1"),
        box("set-cl5", "newobj", [35.0, 640.0, 72.0, 22.0], text="prepend set"),
        box("set-ql1", "newobj", [195.0, 640.0, 72.0, 22.0], text="prepend set"),
        box(
            "logo", "fpic", [14.0, 4.0, 100.0, 28.0],
            presentation=1, presentation_rect=[14.0, 2.0, 100.0, 30.0],
            pic="paradis_latin_logo.jpg", autofit=1, forceaspect=1, ignoreclick=1,
            outlettype=["jit_matrix"],
        ),
        box(
            "title", "comment", [122.0, 8.0, 215.0, 20.0], numoutlets=0,
            presentation=1, presentation_rect=[122.0, 7.0, 215.0, 20.0],
            text="cl midi console monitor", fontsize=10.0, fontface=0,
            textcolor=[0.56, 0.59, 0.65, 1.0],
        ),
        box(
            "midi-led", "button", [326.0, 9.0, 16.0, 16.0],
            presentation=1, presentation_rect=[326.0, 9.0, 16.0, 16.0],
            bgcolor=[0.08, 0.11, 0.10, 1.0],
            blinkcolor=[0.20, 0.95, 0.42, 1.0],
            outlinecolor=[0.20, 0.40, 0.28, 1.0],
        ),
        box(
            "subtitle", "comment", [16.0, 35.0, 430.0, 18.0], numoutlets=0,
            presentation=0, presentation_rect=[14.0, 33.0, 360.0, 18.0],
            text="Transit MIDI transparent · Program Change uniquement",
            fontsize=10.0, textcolor=[0.55, 0.60, 0.68, 1.0],
        ),
        box("panel-cl5", "panel", [12.0, 39.0, 516.0, 29.0], numoutlets=0, presentation=1, presentation_rect=[12.0, 38.0, 516.0, 29.0], bgcolor=[0.08, 0.16, 0.22, 1.0], border=1, rounded=8, background=1),
        box("panel-ql1", "panel", [12.0, 72.0, 516.0, 29.0], numoutlets=0, presentation=1, presentation_rect=[12.0, 71.0, 516.0, 29.0], bgcolor=[0.12, 0.16, 0.20, 1.0], border=1, rounded=8, background=1),
        box("label-cl5", "comment", [25.0, 44.0, 92.0, 20.0], numoutlets=0, presentation=1, presentation_rect=[24.0, 43.0, 95.0, 20.0], text="CL5", fontsize=11.0, textcolor=[0.35, 0.72, 1.0, 1.0]),
        box("label-ql1", "comment", [25.0, 77.0, 92.0, 20.0], numoutlets=0, presentation=1, presentation_rect=[24.0, 76.0, 95.0, 20.0], text="QL1", fontsize=11.0, textcolor=[0.60, 0.82, 1.0, 1.0]),
        box("display-cl5", "message", [125.0, 43.0, 255.0, 22.0], presentation=1, presentation_rect=[125.0, 42.0, 258.0, 22.0], text="—", fontsize=11.0, fontface=1, textcolor=[0.35, 0.72, 1.0, 1.0], bgcolor=[0.03, 0.06, 0.09, 1.0], border=0, rounded=5),
        box("display-ql1", "message", [125.0, 76.0, 255.0, 22.0], presentation=1, presentation_rect=[125.0, 75.0, 258.0, 22.0], text="—", fontsize=11.0, fontface=1, textcolor=[0.60, 0.82, 1.0, 1.0], bgcolor=[0.04, 0.07, 0.10, 1.0], border=0, rounded=5),
        box("confirmation-cl5", "message", [390.0, 43.0, 122.0, 22.0], presentation=1, presentation_rect=[390.0, 42.0, 123.0, 22.0], text="EN ATTENTE", fontsize=9.0, fontface=1, textcolor=[0.95, 0.72, 0.32, 1.0], bgcolor=[0.03, 0.06, 0.09, 1.0], border=0, rounded=5),
        box("confirmation-ql1", "message", [390.0, 76.0, 122.0, 22.0], presentation=1, presentation_rect=[390.0, 75.0, 123.0, 22.0], text="EN ATTENTE", fontsize=9.0, fontface=1, textcolor=[0.35, 0.92, 0.55, 1.0], bgcolor=[0.04, 0.07, 0.10, 1.0], border=0, rounded=5),
        box("midi-status", "message", [14.0, 106.0, 430.0, 22.0], presentation=1, presentation_rect=[14.0, 104.0, 430.0, 20.0], text="MIDI · en attente", fontsize=9.0, textcolor=[0.95, 0.72, 0.32, 1.0], bgcolor=[0.04, 0.05, 0.07, 1.0], border=0),
        box("clear-button", "textbutton", [455.0, 106.0, 72.0, 22.0], numoutlets=1, presentation=1, presentation_rect=[455.0, 104.0, 72.0, 20.0], text="EFFACER", fontsize=9.0),
        box("clear-message", "message", [455.0, 675.0, 48.0, 22.0], text="set —"),
    ]

    lines = [
        line("midi-in", "midi-out", order=0),
        line("midi-in", "midi-parse", order=1),
        line("midi-parse", "event-gate", outlet=3, inlet=1),
        line("role-menu", "role-index"),
        line("role-index", "event-gate", inlet=0),
        line("role-default", "event-gate", inlet=0),
        line("role-loadbang", "role-defer"),
        line("role-defer", "role-menu"),
        line("role-defer", "lookup-cl5"),
        line("role-defer", "lookup-ql1-cc"),
        line("role-defer", "lookup-ql1-pgm"),
        line("event-gate", "lookup-cl5", outlet=0),
        line("event-gate", "midi-led", outlet=0),
        line("event-gate", "status-plus-cl5", outlet=0),
        line("status-plus-cl5", "status-label-cl5"),
        line("status-label-cl5", "status-send"),
        line("lookup-cl5", "send-cl5"),
        line("event-gate", "request-cl5", outlet=0),
        line("event-gate", "lookup-ql1-cc", outlet=1),
        line("event-gate", "midi-led", outlet=1),
        line("event-gate", "status-plus-ql1-cc", outlet=1),
        line("status-plus-ql1-cc", "status-label-ql1-cc"),
        line("status-label-ql1-cc", "status-send"),
        line("lookup-ql1-cc", "send-ql1-cc"),
        line("event-gate", "request-ql1-cc", outlet=1),
        line("event-gate", "lookup-ql1-pgm", outlet=2),
        line("event-gate", "midi-led", outlet=2),
        line("event-gate", "status-plus-ql1-pgm", outlet=2),
        line("status-plus-ql1-pgm", "status-label-ql1-pgm"),
        line("status-label-ql1-pgm", "status-send"),
        line("lookup-ql1-pgm", "send-ql1-pgm"),
        line("event-gate", "request-ql1-pgm", outlet=2),
        line("event-gate", "confirm-cl5", outlet=3),
        line("event-gate", "midi-led", outlet=3),
        line("event-gate", "confirm-plus-cl5", outlet=3),
        line("confirm-plus-cl5", "confirm-label-cl5"),
        line("confirm-label-cl5", "status-send"),
        line("event-gate", "confirm-ql1", outlet=4),
        line("event-gate", "midi-led", outlet=4),
        line("event-gate", "confirm-plus-ql1", outlet=4),
        line("confirm-plus-ql1", "confirm-label-ql1"),
        line("confirm-label-ql1", "status-send"),
        line("request-recv-cl5", "confirmation-js-cl5", inlet=0),
        line("confirm-recv-cl5", "confirmation-js-cl5", inlet=1),
        line("confirmation-js-cl5", "confirm-set-cl5", outlet=0),
        line("confirm-set-cl5", "confirmation-cl5"),
        line("confirmation-js-cl5", "confirm-match-cl5", outlet=1),
        line("confirm-match-cl5", "midi-led"),
        line("request-recv-ql1", "confirmation-js-ql1", inlet=0),
        line("confirm-recv-ql1", "confirmation-js-ql1", inlet=1),
        line("confirmation-js-ql1", "confirm-set-ql1", outlet=0),
        line("confirm-set-ql1", "confirmation-ql1"),
        line("confirmation-js-ql1", "confirm-match-ql1", outlet=1),
        line("confirm-match-ql1", "midi-led"),
        line("status-recv", "status-set"),
        line("status-set", "midi-status"),
        line("recv-cl5", "set-cl5"),
        line("set-cl5", "display-cl5"),
        line("recv-ql1", "set-ql1"),
        line("set-ql1", "display-ql1"),
        line("clear-button", "clear-message"),
        line("clear-message", "display-cl5", order=0),
        line("clear-message", "display-ql1", order=1),
        line("scene-udp", "scene-route"),
        line("scene-route", "scene-prepend", outlet=0),
        line("scene-route", "scene-reset", outlet=1),
        line("scene-prepend", "scene-send"),
        line("scene-reset", "scene-send"),
        line("scene-recv", "lookup-cl5", order=0),
        line("scene-recv", "lookup-ql1-cc", order=1),
        line("scene-recv", "lookup-ql1-pgm", order=2),
    ]

    return {"patcher": {
        "fileversion": 1,
        "appversion": {"major": 9, "minor": 1, "revision": 4, "architecture": "x64", "modernui": 1},
        "classnamespace": "box",
        "rect": [70.0, 70.0, 960.0, 680.0],
        "openinpresentation": 1,
        "devicewidth": 540.0,
        "description": "Three-console MIDI Program Change monitor",
        "digest": "Transparent MIDI monitor for CL5 and QL1 control tracks",
        "title": DEVICE_NAME,
        "project": {
            "version": 1,
            "creationdate": 0,
            "modificationdate": 0,
            "viewrect": [0.0, 0.0, 300.0, 500.0],
            "autoorganize": 1,
            "hideprojectwindow": 1,
            "showdependencies": 1,
            "autolocalize": 0,
            "contents": {"patchers": {}},
            "layout": {},
            "searchpath": {},
            "detailsvisible": 0,
            "amxdtype": 1835887981,
            "readonly": 0,
            "devpathtype": 0,
            "devpath": ".",
            "sortmode": 0,
            "viewmode": 0,
        },
        "bgcolor": [0.04, 0.05, 0.07, 1.0],
        "boxes": boxes,
        "lines": lines,
        "dependency_cache": [
            {
                "name": "CLMidiConsoleDisplay.js",
                "bootpath": ".",
                "patcherrelativepath": ".",
                "type": "TEXT",
                "implicit": 1,
            },
            {
                "name": "CLMidiConsoleConfirmation.js",
                "bootpath": ".",
                "patcherrelativepath": ".",
                "type": "TEXT",
                "implicit": 1,
            },
            {
                "name": "paradis_latin_logo.jpg",
                "bootpath": ".",
                "patcherrelativepath": ".",
                "type": "JPEG",
                "implicit": 1,
            },
        ],
    }}


def write_amxd(path: Path, payload: dict):
    patch = (json.dumps(payload, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    container = (
        b"ampf" + struct.pack("<I", 4)
        # Match Live's editable "Max MIDI Effect.amxd" template exactly.
        # Frozen devices use meta 7 plus an mx@c payload; editable MIDI effects
        # use mmmm/meta 0 followed directly by the patch JSON.
        + b"mmmm" + b"meta" + struct.pack("<I", 4) + struct.pack("<I", 0)
        + b"ptch" + struct.pack("<I", len(patch)) + patch
    )
    path.write_bytes(container)


def _json_end(raw: bytes, start: int) -> int:
    depth = 0
    in_string = False
    escaped = False
    for index in range(start, len(raw)):
        value = raw[index]
        if in_string:
            if escaped:
                escaped = False
            elif value == 0x5C:
                escaped = True
            elif value == 0x22:
                in_string = False
            continue
        if value == 0x22:
            in_string = True
        elif value in (0x7B, 0x5B):
            depth += 1
        elif value in (0x7D, 0x5D):
            depth -= 1
            if depth == 0:
                return index + 1
    raise ValueError("Unable to locate the end of the base device patch JSON")


def write_frozen_amxd(path: Path, payload: dict, base_path: Path):
    """Replace only the primary patch in a Max-frozen MIDI device container."""
    raw = bytearray(base_path.read_bytes())
    if raw[:4] != b"ampf" or raw[32:36] != b"mx@c":
        raise ValueError("The base is not a Max-frozen AMXD container")
    json_start = 48
    json_end = _json_end(raw, json_start)
    patch = (json.dumps(payload, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    delta = len(patch) - (json_end - json_start)
    result = bytearray(raw[:json_start]) + patch + raw[json_end:]
    result[28:32] = struct.pack("<I", len(result) - 32)
    embedded_length = int.from_bytes(raw[44:48], "big") + delta
    result[44:48] = embedded_length.to_bytes(4, "big")
    path.write_bytes(result)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--frozen-base", type=Path)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    payload = device_payload()
    maxpat = args.output_dir / (DEVICE_NAME + ".maxpat")
    amxd = args.output_dir / (DEVICE_NAME + ".amxd")
    maxpat.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.frozen_base:
        write_frozen_amxd(amxd, payload, args.frozen_base)
    else:
        write_amxd(amxd, payload)
    print(maxpat)
    print(amxd)


if __name__ == "__main__":
    main()
