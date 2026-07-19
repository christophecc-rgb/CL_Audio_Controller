#!/usr/bin/env python3
"""Extrait LTC Display v1.9 et produit la version Max v2.0 configurable.

Le script ne modifie jamais le périphérique d'origine. Il produit la source
`.maxpat` ou, avec ``--amxd``, un nouveau périphérique conservant les ressources
figées de v1.9 sous un nom distinct.
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


VERSION_NAME = "LTC Display v2.0 Remote Config"


def parse_port_text(value: str) -> int | None:
    """Reproduit la validation décimale stricte du graphe Max."""
    if not isinstance(value, str) or not value or not value.isascii() or not value.isdecimal():
        return None
    port = int(value, 10)
    return port if 1 <= port <= 65535 else None


def load_amxd(path: Path) -> tuple[bytes, dict, int, int]:
    raw = path.read_bytes()
    start = raw.find(b"{")
    if start < 0:
        raise ValueError("aucun patcher JSON trouvé dans le périphérique")
    text = raw[start:].decode("utf-8", errors="ignore")
    payload, character_count = json.JSONDecoder().raw_decode(text)
    json_end = start + len(text[:character_count].encode("utf-8"))
    return raw, payload, start, json_end


def box(identifier: str, maxclass: str, rect: list, **values) -> dict:
    payload = {
        "id": identifier,
        "maxclass": maxclass,
        "numinlets": values.pop("numinlets", 1),
        "numoutlets": values.pop("numoutlets", 1),
        "patching_rect": rect,
    }
    payload.update(values)
    return {"box": payload}


def line(source: str, destination: str, outlet: int = 0, inlet: int = 0) -> dict:
    return {"patchline": {
        "source": [source, outlet],
        "destination": [destination, inlet],
    }}


def configure(payload: dict) -> dict:
    patcher = payload["patcher"]
    patcher.pop("deviceheight", None)
    patcher["description"] = "LTC v2 UDP configurable"

    udp_container = None
    for item in patcher["boxes"]:
        candidate = item["box"]
        if candidate.get("text") == "p udp-send":
            udp_container = candidate
    if udp_container is None:
        raise ValueError("sous-patch p udp-send introuvable")

    udp_container["numinlets"] = 4
    udp_patcher = udp_container["patcher"]
    if not any(
        item["box"].get("id") == "obj-ltc-config-in"
        for item in udp_patcher["boxes"]
    ):
        udp_patcher["boxes"].append(box(
            "obj-ltc-config-in",
            "inlet",
            [220.0, 40.0, 30.0, 30.0],
            numinlets=0,
            numoutlets=1,
            index=4,
            outlettype=[""],
            comment="LTC UDP",
        ))
        udp_patcher["lines"].append(line("obj-ltc-config-in", "obj-10"))

    # Permet de régénérer v2.0 à partir de son propre conteneur sans dupliquer
    # les contrôles ni leurs connexions. Les objets historiques restent intacts.
    custom_ids = {
        item["box"].get("id")
        for item in patcher["boxes"]
        if item["box"].get("id", "").startswith(("obj-ltc-", "z"))
    }
    patcher["boxes"] = [
        item for item in patcher["boxes"]
        if item["box"].get("id") not in custom_ids
    ]
    patcher["lines"] = [
        item for item in patcher["lines"]
        if item["patchline"]["source"][0] not in custom_ids
        and item["patchline"]["destination"][0] not in custom_ids
    ]

    additions = [
        box(
            "obj-ltc-destination-label", "comment", [314.0, 1040.0, 36.0, 18.0],
            numoutlets=0, presentation=1,
            presentation_rect=[330.0, 145.0, 28.0, 18.0],
            text="LTC→",
        ),
        box(
            "obj-ltc-host", "textedit", [360.0, 1040.0, 105.0, 20.0],
            numoutlets=4, outlettype=["", "int", "", ""],
            parameter_enable=0, presentation=1,
            presentation_rect=[360.0, 143.0, 105.0, 20.0],
            text="127.0.0.1", varname="ltc_destination",
        ),
        box(
            "obj-ltc-port", "textedit", [468.0, 1040.0, 50.0, 20.0],
            numoutlets=4, outlettype=["", "int", "", ""],
            parameter_enable=0, presentation=1,
            presentation_rect=[468.0, 143.0, 50.0, 20.0],
            text="63123", varname="ltc_port_input",
        ),
        box("obj-ltc-route-text", "newobj", [314.0, 1080.0, 62.0, 22.0], text="route text"),
        box("obj-ltc-tosymbol", "newobj", [385.0, 1080.0, 55.0, 22.0], text="tosymbol"),
        box("obj-ltc-host-restore-trigger", "newobj", [500.0, 1080.0, 40.0, 22.0], text="t s s"),
        box("obj-ltc-host-message", "newobj", [550.0, 1080.0, 85.0, 22.0], text="prepend host"),
        box("obj-ltc-host-set", "newobj", [645.0, 1080.0, 75.0, 22.0], text="prepend set"),
        box(
            "obj-ltc-host-pattr", "newobj", [314.0, 1110.0, 420.0, 22.0],
            text=(
                "pattr ltc_destination_state @bindto ltc_destination "
                "@initial 127.0.0.1 @type symbol @parameter_enable 1"
            ),
            saved_object_attributes={
                "parameter_enable": 1,
            },
            saved_attribute_attributes={
                "valueof": {
                    "parameter_invisible": 1,
                    "parameter_longname": "LTC Destination",
                    "parameter_shortname": "LTC Destination",
                    "parameter_type": 3,
                },
            },
        ),
        box("obj-ltc-port-route-text", "newobj", [314.0, 1150.0, 62.0, 22.0], text="route text"),
        box("obj-ltc-port-fromsymbol", "newobj", [385.0, 1150.0, 72.0, 22.0], text="fromsymbol"),
        box("obj-ltc-port-int", "newobj", [465.0, 1150.0, 58.0, 22.0], text="route int"),
        box("obj-ltc-port-split", "newobj", [535.0, 1150.0, 80.0, 22.0], text="split 1 65535"),
        box("obj-ltc-port-invalid", "newobj", [545.0, 1180.0, 28.0, 22.0], text="t b"),
        box("obj-ltc-port-restore-int", "newobj", [575.0, 1150.0, 20.0, 22.0], text="i"),
        box("obj-ltc-port-restore-split", "newobj", [605.0, 1150.0, 80.0, 22.0], text="split 1 65535"),
        box("obj-ltc-port-restore-trigger", "newobj", [695.0, 1150.0, 40.0, 22.0], text="t i i"),
        box("obj-ltc-port-message", "newobj", [745.0, 1150.0, 82.0, 22.0], text="prepend port"),
        box("obj-ltc-port-set", "newobj", [835.0, 1150.0, 75.0, 22.0], text="prepend set"),
        box(
            "obj-ltc-port-pattr", "newobj", [314.0, 1180.0, 320.0, 22.0],
            text=(
                "pattr ltc_port_state @initial 63123. "
                "@type float @min 1. @max 65535. @parameter_enable 1"
            ),
            saved_object_attributes={
                "parameter_enable": 1,
            },
            saved_attribute_attributes={
                "valueof": {
                    "parameter_invisible": 1,
                    "parameter_longname": "LTC Port",
                    "parameter_mmin": 1.0,
                    "parameter_mmax": 65535.0,
                    "parameter_shortname": "LTC Port",
                    "parameter_type": 0,
                    "parameter_unitstyle": 0,
                },
            },
        ),
    ]
    patcher["boxes"].extend(additions)
    patcher["lines"].extend([
        line("obj-ltc-host", "obj-ltc-route-text"),
        line("obj-ltc-route-text", "obj-ltc-tosymbol"),
        line("obj-ltc-tosymbol", "obj-ltc-host-pattr"),
        line("obj-ltc-host-pattr", "obj-ltc-host-restore-trigger"),
        line("obj-ltc-host-restore-trigger", "obj-ltc-host-message", outlet=0),
        line("obj-ltc-host-restore-trigger", "obj-ltc-host-set", outlet=1),
        line("obj-ltc-host-set", "obj-ltc-host"),
        line("obj-ltc-host-message", "obj-51", inlet=3),
        line("obj-ltc-port", "obj-ltc-port-route-text"),
        line("obj-ltc-port-route-text", "obj-ltc-port-fromsymbol"),
        line("obj-ltc-port-fromsymbol", "obj-ltc-port-int"),
        line("obj-ltc-port-int", "obj-ltc-port-split"),
        line("obj-ltc-port-int", "obj-ltc-port-invalid", outlet=1),
        line("obj-ltc-port-split", "obj-ltc-port-pattr", outlet=0),
        line("obj-ltc-port-split", "obj-ltc-port-invalid", outlet=1),
        line("obj-ltc-port-invalid", "obj-ltc-port-pattr"),
        line("obj-ltc-port-pattr", "obj-ltc-port-restore-int"),
        line("obj-ltc-port-restore-int", "obj-ltc-port-restore-split"),
        line("obj-ltc-port-restore-split", "obj-ltc-port-restore-trigger", outlet=0),
        line("obj-ltc-port-restore-trigger", "obj-ltc-port-message", outlet=0),
        line("obj-ltc-port-restore-trigger", "obj-ltc-port-set", outlet=1),
        line("obj-ltc-port-set", "obj-ltc-port"),
        line("obj-ltc-port-message", "obj-51", inlet=3),
    ])
    return payload


def compact_generated_ids(patcher: dict) -> None:
    """Réduit seulement les identifiants v2.0 dans le conteneur binaire.

    Le segment JSON d'un AMXD existant a une taille fixe afin de ne pas déplacer
    ses ressources embarquées. Les identifiants lisibles restent conservés dans
    le `.maxpat`; leur forme compacte est sans effet sur le graphe Max.
    """
    identifiers = [
        item["box"].get("id")
        for item in patcher["boxes"]
        if item["box"].get("id", "").startswith("obj-ltc-")
    ]
    mapping = {
        identifier: f"z{index}"
        for index, identifier in enumerate(identifiers, 1)
    }
    for item in patcher["boxes"]:
        identifier = item["box"].get("id")
        if identifier in mapping:
            item["box"]["id"] = mapping[identifier]
    for item in patcher["lines"]:
        patchline = item["patchline"]
        patchline["source"][0] = mapping.get(
            patchline["source"][0], patchline["source"][0]
        )
        patchline["destination"][0] = mapping.get(
            patchline["destination"][0], patchline["destination"][0]
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--amxd",
        action="store_true",
        help="préserve les ressources embarquées et produit un nouveau .amxd",
    )
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit(f"refus d'écraser le fichier existant : {args.output}")
    raw, payload, json_start, json_end = load_amxd(args.source)
    payload = configure(payload)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    encoded = (json.dumps(payload, ensure_ascii=False, indent=1) + "\n").encode("utf-8")
    if args.amxd:
        if args.output.suffix.lower() != ".amxd":
            raise SystemExit("la sortie --amxd doit porter l'extension .amxd")
        # Les ressources figées du conteneur utilisent des offsets internes.
        # On conserve donc exactement la longueur du segment JSON historique :
        # sérialisation compacte puis remplissage inerte avant les ressources.
        compact_generated_ids(payload["patcher"])
        compact = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        original_json_size = json_end - json_start
        if len(compact) > original_json_size:
            raise SystemExit("le patch modifié dépasse le segment JSON historique")
        padded = compact + b" " * (original_json_size - len(compact) - 1) + b"\n"
        rebuilt = bytearray(raw[:json_start] + padded + raw[json_end:])
        rebuilt[28:32] = struct.pack("<I", len(rebuilt) - 32)
        args.output.write_bytes(rebuilt)
    else:
        args.output.write_bytes(encoded)
    print(f"{VERSION_NAME}: {args.output}")


if __name__ == "__main__":
    main()
