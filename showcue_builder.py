"""Données de préparation ShowCue, isolées de la conduite et du playback."""

from __future__ import annotations

import csv
import io
import json
import os
import re
import tempfile
import uuid
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape
from show_cues import SHOW_SECTIONS, timecode_to_units

BUILDER_COLUMNS = (
    "#", "TC", "SCÈNE ABLETON", "TYPE", "SECTION", "RÔLE", "ARTISTE OVERRIDE", "TEXTE",
    "MICRO OVERRIDE", "IEM OVERRIDE", "ÉQUIPEMENT OVERRIDE", "FOH", "RET", "PLT", "LUM", "ORIGINE", "NOTES",
)
DISTRIBUTION_COLUMNS = (
    "RÔLE", "ARTISTE", "ACTIF",
    "ÉQUIPEMENT 1 TYPE", "ÉQUIPEMENT 1 VALEUR",
    "ÉQUIPEMENT 2 TYPE", "ÉQUIPEMENT 2 VALEUR",
    "ÉQUIPEMENT 3 TYPE", "ÉQUIPEMENT 3 VALEUR", "NOTES",
)
LEGACY_DISTRIBUTION_COLUMNS = ("RÔLE", "ARTISTE", "MICRO", "IEM", "ÉQUIPEMENT", "ACTIF", "NOTES")
EQUIPMENT_TYPES = ("MICRO", "IEM", "ÉQUIPEMENT", "AUTRE")
MAX_EQUIPMENT_SLOTS = 8
BUILDER_TYPES = (
    "TOP MUSIQUE", "TOP LIGHT", "CHANGEMENT MICRO", "TEST MICRO", "TEST EAR / IEM",
    "ÉQUIPEMENT ARTISTE", "ENTRÉE ARTISTE", "SORTIE ARTISTE", "CHANGEMENT COSTUME",
    "ANNONCE", "CALL / INTERCOM", "TECHNIQUE", "AUTRE",
)
BUILDER_SECTIONS = SHOW_SECTIONS
ORIGINS = ("ABLETON", "IMPORT", "BUILDER", "MANUEL")
TC_PATTERN = re.compile(r"^\d{2}:\d{2}:\d{2}:\d{2}$")
TRUE_VALUES = {"1", "true", "vrai", "oui", "yes", "x", "actif"}
FALSE_VALUES = {"", "0", "false", "faux", "non", "no", "-"}


def empty_builder_document():
    return {"version": 1, "revision": 0, "cues": [], "distribution": []}


def _text(value):
    return str(value if value is not None else "").strip()


ROLE_ALIASES = {
    "preshow punk": "punk",
}


def _role_key(value):
    """Clé de comparaison d'un rôle sans modifier son libellé affiché."""
    normalized = re.sub(r"\\s+", " ", _text(value)).strip().casefold()
    return ROLE_ALIASES.get(normalized, normalized)


def _boolean(value, field):
    if isinstance(value, bool):
        return value
    normalized = _text(value).casefold()
    if normalized in TRUE_VALUES:
        return True
    if normalized in FALSE_VALUES:
        return False
    raise ValueError(f"{field} doit valoir TRUE/FALSE")


def _valid_timecode(value):
    if not TC_PATTERN.fullmatch(value):
        return False
    hours, minutes, seconds, frames = map(int, value.split(":"))
    return hours <= 99 and minutes <= 59 and seconds <= 59 and frames <= 99


def _normalize_equipment_slots(raw, assignment_index):
    slots = raw.get("equipment_slots")
    if slots is None:
        slots = [
            {"type": kind, "value": _text(raw.get(field))}
            for kind, field in (("MICRO", "microphone"), ("IEM", "iem"),
                                ("ÉQUIPEMENT", "equipment"))
            if _text(raw.get(field))
        ]
    if not isinstance(slots, list):
        raise ValueError(f"equipment_slots de l’affectation #{assignment_index} invalide")
    if len(slots) > MAX_EQUIPMENT_SLOTS:
        raise ValueError(f"affectation #{assignment_index} : maximum {MAX_EQUIPMENT_SLOTS} équipements")
    normalized = []
    for slot_index, slot in enumerate(slots, 1):
        if not isinstance(slot, dict):
            raise ValueError(f"équipement #{slot_index} de l’affectation #{assignment_index} invalide")
        normalized.append({"type": _text(slot.get("type")).upper(),
                           "value": _text(slot.get("value"))})
    return normalized


# CL_SHOWCUE_ROLE_ASSIGNMENTS_CORE_V1
def _normalize_role_assignments(value):
    """
    Affectations techniques propres à chaque rôle d'un cue.

    Exemple :
    {
        "MENEUSE": {"microphone": "DPA 4088 #1"},
        "DIRECTRICE": {"microphone": "DPA 4088 #3"}
    }
    """
    if value in (None, ""):
        return {}

    if not isinstance(value, dict):
        raise ValueError("role_assignments invalide")

    result = {}

    for raw_role, raw_assignment in value.items():
        role = _text(raw_role)

        if not role:
            continue

        if not isinstance(raw_assignment, dict):
            raise ValueError(
                f"role_assignments {role} invalide"
            )

        assignment = {}

        for key in ("microphone", "iem", "equipment"):
            item = _text(raw_assignment.get(key))

            if item:
                assignment[key] = item

        if assignment:
            result[role] = assignment

    return result


def normalize_builder_document(document):
    if not isinstance(document, dict):
        raise ValueError("document Builder invalide")
    raw_cues = document.get("cues", [])
    raw_distribution = document.get("distribution", [])
    if not isinstance(raw_cues, list) or not isinstance(raw_distribution, list):
        raise ValueError("listes Builder invalides")
    cues, used = [], set()
    for index, raw in enumerate(raw_cues, 1):
        if not isinstance(raw, dict):
            raise ValueError(f"cue Builder #{index} invalide")
        cue_id = _text(raw.get("id")) or f"builder_{uuid.uuid4().hex[:12]}"
        if cue_id in used or not re.fullmatch(r"builder_[A-Za-z0-9_-]+", cue_id):
            raise ValueError(f"identifiant Builder invalide ou dupliqué : {cue_id}")
        used.add(cue_id)
        cue = {
            "id": cue_id, "number": _text(raw.get("number")) or str(index),
            "timecode": _text(raw.get("timecode")), "source": _text(raw.get("source")),
            "type": _text(raw.get("type")), "section": _text(raw.get("section")),
            "role": _text(raw.get("role")), "artist": _text(raw.get("artist")),
            "text": _text(raw.get("text")), "microphone": _text(raw.get("microphone")),
            "iem": _text(raw.get("iem")), "equipment": _text(raw.get("equipment")),
            "foh": _boolean(raw.get("foh", True), "FOH"),
            "ret": _boolean(raw.get("ret", True), "RET"),
            "plt": _boolean(raw.get("plt", True), "PLT"),
            "lum": _boolean(raw.get("lum", True), "LUM"),
            "origin": _text(raw.get("origin")) or "BUILDER", "notes": _text(raw.get("notes")),
            "role_assignments": _normalize_role_assignments(
                raw.get("role_assignments")
            ),
        }
        cues.append(cue)
    distribution = []
    for index, raw in enumerate(raw_distribution, 1):
        if not isinstance(raw, dict):
            raise ValueError(f"affectation #{index} invalide")
        distribution.append({
            "role": _text(raw.get("role")), "artist": _text(raw.get("artist")),
            "active": _boolean(raw.get("active", False), "ACTIF"),
            "equipment_slots": _normalize_equipment_slots(raw, index),
            "notes": _text(raw.get("notes")),
        })
    try:
        revision = int(document.get("revision", 0))
    except (TypeError, ValueError) as exc:
        raise ValueError("révision Builder invalide") from exc
    if revision < 0:
        raise ValueError("révision Builder invalide")
    return {"version": 1, "revision": revision, "cues": cues, "distribution": distribution}


def save_builder_document(path: Path, document):
    normalized = normalize_builder_document(document)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(normalized, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    except Exception:
        try:
            os.unlink(temporary_name)
        except OSError:
            pass
        raise
    return normalized


def load_builder_document(path: Path):
    path = Path(path)
    if not path.exists():
        return empty_builder_document()
    return normalize_builder_document(json.loads(path.read_text(encoding="utf-8")))


def validate_builder_document(document):
    document = normalize_builder_document(document)
    cues, distribution = document["cues"], document["distribution"]
    invalid_tc = [cue["id"] for cue in cues if cue["timecode"] and not _valid_timecode(cue["timecode"])]
    empty_text = [cue["id"] for cue in cues if not cue["text"]]
    known_role_keys = {_role_key(row["role"]) for row in distribution if row["role"]}
    known_artists = {row["artist"] for row in distribution if row["artist"]}

    cue_role_labels = {}
    distribution_role_labels = {}

    for row in distribution:
        if row["role"]:
            distribution_role_labels.setdefault(_role_key(row["role"]), row["role"])

    for cue in cues:
        if cue["role"]:
            cue_role_labels.setdefault(_role_key(cue["role"]), cue["role"])

    unknown_roles = sorted({
        cue["role"] for cue in cues
        if cue["role"] and _role_key(cue["role"]) not in known_role_keys
    })

    unknown_artists = sorted({
        cue["artist"] for cue in cues
        if cue["artist"] and cue["artist"] not in known_artists
    })

    role_keys = sorted(set(distribution_role_labels) | set(cue_role_labels))

    active_by_role = {
        role_key: [
            row for row in distribution
            if _role_key(row["role"]) == role_key and row["active"]
        ]
        for role_key in role_keys
    }

    def role_label(role_key):
        return cue_role_labels.get(role_key) or distribution_role_labels.get(role_key) or role_key

    missing_active = [
        role_label(role_key)
        for role_key, rows in active_by_role.items()
        if not rows
    ]

    multiple_active = [
        role_label(role_key)
        for role_key, rows in active_by_role.items()
        if len(rows) > 1
    ]
    empty_roles = [index for index, row in enumerate(distribution, 1) if not row["role"]]
    empty_artists = [index for index, row in enumerate(distribution, 1) if not row["artist"]]
    assignment_duplicates, assignment_seen = [], set()
    invalid_equipment, duplicate_equipment = [], []
    for index, row in enumerate(distribution, 1):
        assignment_key = (row["role"].casefold(), row["artist"].casefold())
        if all(assignment_key) and assignment_key in assignment_seen:
            assignment_duplicates.append(row["role"] + " · " + row["artist"])
        assignment_seen.add(assignment_key)
        slot_seen = set()
        for slot_index, slot in enumerate(row["equipment_slots"], 1):
            label = f"{row['role']} · {row['artist']} · équipement {slot_index}"
            if not slot["type"] or not slot["value"] or slot["type"] not in EQUIPMENT_TYPES:
                invalid_equipment.append(label)
            slot_key = (slot["type"].casefold(), slot["value"].casefold())
            if all(slot_key) and slot_key in slot_seen:
                duplicate_equipment.append(label)
            slot_seen.add(slot_key)
    duplicate_keys, seen = [], set()
    for cue in cues:
        key = (cue["timecode"], cue["source"].casefold(), cue["text"].casefold())
        if key in seen:
            duplicate_keys.append(cue["id"])
        seen.add(key)
    destinations = {name: sum(bool(cue[key]) for cue in cues) for name, key in
                    (("FOH", "foh"), ("RET", "ret"), ("PLT", "plt"), ("LUM", "lum"))}
    return {
        "total": len(cues), "timed": sum(bool(cue["timecode"] and _valid_timecode(cue["timecode"])) for cue in cues),
        "without_timecode": sum(not cue["timecode"] for cue in cues),
        "suggestions": sum(cue["origin"] == "BUILDER" for cue in cues),
        "possible_duplicates": duplicate_keys, "invalid_timecodes": invalid_tc,
        "empty_texts": empty_text, "unknown_roles": unknown_roles, "unknown_artists": unknown_artists,
        "roles_without_active_artist": missing_active, "roles_with_multiple_active_artists": multiple_active,
        "empty_distribution_roles": empty_roles, "empty_distribution_artists": empty_artists,
        "duplicate_role_artists": assignment_duplicates,
        "invalid_equipment_slots": invalid_equipment,
        "duplicate_equipment_slots": duplicate_equipment,
        "ambiguous_legacy_duplicates": assignment_duplicates,
        "destinations": destinations,
        "incomplete_equipment": [row["role"] + " · " + row["artist"] for row in distribution
                                 if row["active"] and not row["equipment_slots"]],
        "ready": not (invalid_tc or empty_text or multiple_active or empty_roles or empty_artists
                       or assignment_duplicates or invalid_equipment or duplicate_equipment),
    }


def _cue_row(cue):
    return [cue["number"], cue["timecode"], cue["source"], cue["type"], cue["section"],
            cue["role"], cue["artist"], cue["text"], cue["microphone"], cue["iem"],
            cue["equipment"], cue["foh"], cue["ret"], cue["plt"], cue["lum"],
            cue["origin"], cue["notes"]]


def resolve_builder_cue(cue, distribution):
    """Résout l'affectation active, puis applique les surcharges du cue."""
    cue = normalize_builder_document({"cues": [cue], "distribution": []})["cues"][0]
    rows = [row for row in normalize_builder_document(
        {"cues": [], "distribution": distribution})["distribution"]
            if cue["role"] and _role_key(row["role"]) == _role_key(cue["role"]) and row["active"]]
    active = rows[0] if len(rows) == 1 else {}
    slots = [dict(slot) for slot in active.get("equipment_slots", [])]
    overrides = {key: bool(cue[key]) for key in ("artist", "microphone", "iem", "equipment")}
    for field, kind in (("microphone", "MICRO"), ("iem", "IEM"),
                        ("equipment", "ÉQUIPEMENT")):
        if cue[field]:
            slots = [slot for slot in slots if slot["type"] != kind]
            slots.append({"type": kind, "value": cue[field]})

    def legacy_value(kind, override):
        if override:
            return override
        values = [slot["value"] for slot in slots if slot["type"] == kind]
        return values[0] if len(values) == 1 else None if len(values) > 1 else ""

    artist = cue["artist"] or active.get("artist", "")
    microphone = legacy_value("MICRO", cue["microphone"])
    iem = legacy_value("IEM", cue["iem"])
    equipment = legacy_value("ÉQUIPEMENT", cue["equipment"])
    return {
        "role": cue["role"], "artist": artist, "equipment_slots": slots,
        "microphone": microphone, "iem": iem, "equipment": equipment,
        "resolved_artist": artist, "resolved_equipment_slots": slots,
        "resolved_microphone": microphone, "resolved_iem": iem,
        "resolved_equipment": equipment,
        "distribution_status": "active" if len(rows) == 1 else "multiple" if len(rows) > 1 else "missing",
        "overrides": overrides,
    }



# CL_SHOWCUE_MULTIROLE_V1
# ------------------------------------------------------------------
# Compatibilité multi-rôles.
# Le stockage historique "MARCEL / DIRECTRICE" reste inchangé.
# ------------------------------------------------------------------

_resolve_builder_cue_single_role = resolve_builder_cue


def split_builder_roles(value):
    """Découpe un rôle composite sans modifier le libellé stocké."""
    values = []

    for item in str(value or "").split("/"):
        item = item.strip()

        if not item:
            continue

        if item.casefold() not in {
            existing.casefold()
            for existing in values
        }:
            values.append(item)

    return values


def resolve_builder_cue(cue, distribution):
    roles = split_builder_roles(
        (cue or {}).get("role", "")
    )

    # Comportement historique inchangé.
    if len(roles) <= 1:
        return _resolve_builder_cue_single_role(
            cue,
            distribution
        )

    participants = []

    for role in roles:
        subcue = dict(cue or {})

        subcue["role"] = role

        # Les overrides historiques sont globaux au cue.
        # Ils seraient ambigus s'ils étaient appliqués à plusieurs rôles.
        subcue["artist"] = ""
        subcue["microphone"] = ""
        subcue["iem"] = ""
        subcue["equipment"] = ""

        resolved = _resolve_builder_cue_single_role(
            subcue,
            distribution
        )

        participants.append({
            "role": role,
            "artist": resolved.get("artist", ""),
            "equipment_slots": list(
                resolved.get("equipment_slots") or []
            ),
            "microphone": resolved.get("microphone"),
            "iem": resolved.get("iem"),
            "equipment": resolved.get("equipment"),
            "distribution_status":
                resolved.get("distribution_status", "missing"),
        })

    active_count = sum(
        participant.get("distribution_status") == "active"
        for participant in participants
    )

    artists = [
        participant["artist"]
        for participant in participants
        if participant.get("artist")
    ]

    equipment_slots = []

    for participant in participants:
        for slot in participant.get(
            "equipment_slots",
            []
        ):
            equipment_slots.append({
                **slot,
                "role": participant["role"],
                "artist": participant["artist"],
            })

    return {
        "role": " / ".join(roles),

        "roles": roles,
        "participants": participants,

        "artist": " / ".join(artists),
        "resolved_artist": " / ".join(artists),

        # Un micro global n'a pas de sens avec plusieurs artistes.
        "microphone": None,
        "resolved_microphone": None,

        "iem": None,
        "resolved_iem": None,

        "equipment": None,
        "resolved_equipment": None,

        "equipment_slots": equipment_slots,
        "resolved_equipment_slots": equipment_slots,

        "distribution_status":
            "active"
            if active_count == len(roles)
            else "missing",

        "overrides": {
            "multi_role": True
        },
    }



# Applique les choix cue/rôle au résultat final du resolver.
_resolve_builder_cue_without_role_assignments = resolve_builder_cue


def resolve_builder_cue(cue, distribution):
    result = _resolve_builder_cue_without_role_assignments(
        cue,
        distribution
    )

    assignments = _normalize_role_assignments(
        (cue or {}).get("role_assignments")
    )

    if not assignments:
        return result

    def for_role(role):
        wanted = _role_key(role)

        for assignment_role, assignment in assignments.items():
            if _role_key(assignment_role) == wanted:
                return assignment

        return {}

    participants = result.get("participants")

    # --------------------------------------------------------
    # MULTI-RÔLES
    # --------------------------------------------------------
    if isinstance(participants, list):

        for participant in participants:
            assignment = for_role(
                participant.get("role")
            )

            if not assignment:
                continue

            if "microphone" in assignment:
                participant["microphone"] = assignment["microphone"]

            if "iem" in assignment:
                participant["iem"] = assignment["iem"]

            if "equipment" in assignment:
                participant["equipment"] = assignment["equipment"]

        result["participants"] = participants

        # Un cue multi-rôles n'a volontairement pas
        # de microphone global unique.
        return result

    # --------------------------------------------------------
    # CUE SIMPLE — compatible avec la même structure
    # --------------------------------------------------------
    assignment = for_role(
        result.get("role") or (cue or {}).get("role")
    )

    if assignment.get("microphone"):
        result["microphone"] = assignment["microphone"]
        result["resolved_microphone"] = assignment["microphone"]

    if assignment.get("iem"):
        result["iem"] = assignment["iem"]
        result["resolved_iem"] = assignment["iem"]

    if assignment.get("equipment"):
        result["equipment"] = assignment["equipment"]
        result["resolved_equipment"] = assignment["equipment"]

    return result


def resolved_builder_document(document):
    document = normalize_builder_document(document)
    return {**document, "cues": [
        {**cue, "resolved": resolve_builder_cue(cue, document["distribution"])}
        for cue in document["cues"]
    ]}


def builder_import_values(document):
    """Produit des valeurs validables par ShowCue sans inventer de timecode."""
    document = normalize_builder_document(document)
    validation = validate_builder_document(document)
    if not validation["ready"]:
        raise ValueError("document Builder non valide")
    values = []
    for cue in document["cues"]:
        posts = [post for enabled, post in ((cue["foh"], "FOH"), (cue["ret"], "RETOURS"),
                                             (cue["plt"], "PLATEAU"), (cue["lum"], "LUMIERE")) if enabled]
        if not posts:
            raise ValueError(f"cue {cue['id']} sans destinataire")
        resolved = resolve_builder_cue(cue, document["distribution"])
        metadata = {
            "builder_id": cue["id"], "number": cue["number"], "source": cue["source"],
            "type": cue["type"], "section": cue["section"],
            "role": cue["role"], "artist_override": cue["artist"],
            "microphone_override": cue["microphone"], "iem_override": cue["iem"],
            "equipment_override": cue["equipment"], "origin": cue["origin"],
            "notes": cue["notes"], "resolved_artist": resolved["artist"],
            "resolved_microphone": resolved["microphone"], "resolved_iem": resolved["iem"],
            "resolved_equipment": resolved["equipment"],
            "resolved_participants": resolved.get("participants", []),
        }
        item = {"text": cue["text"], "posts": posts, "status": "official",
                "builder": {key: value for key, value in metadata.items() if value}}
        if cue["timecode"]:
            timecode_to_units(cue["timecode"])
            item.update({"mode": "timed", "timecode": cue["timecode"]})
        else:
            item.update({"mode": "manual", "section": cue["section"] or "PRÉPARATION"})
        values.append(item)
    return values


def _distribution_row(row):
    slots = list(row["equipment_slots"])
    values = [row["role"], row["artist"], row["active"]]
    for index in range(MAX_EQUIPMENT_SLOTS):
        slot = slots[index] if index < len(slots) else {}
        values.extend((slot.get("type", ""), slot.get("value", "")))
    return [*values, row["notes"]]


def export_csv(document):
    document = normalize_builder_document(document)
    output = io.StringIO(newline="")
    writer = csv.writer(output, delimiter=";")
    writer.writerow(BUILDER_COLUMNS)
    for cue in document["cues"]:
        writer.writerow(["TRUE" if value is True else "FALSE" if value is False else value for value in _cue_row(cue)])
    writer.writerow([])
    writer.writerow(["[DISTRIBUTION]"])
    writer.writerow(DISTRIBUTION_COLUMNS)
    for row in document["distribution"]:
        writer.writerow(["TRUE" if value is True else "FALSE" if value is False else value
                         for value in _distribution_row(row)])
    return output.getvalue().encode("utf-8-sig")


def _column_name(index):
    result = ""
    while index:
        index, remainder = divmod(index - 1, 26)
        result = chr(65 + remainder) + result
    return result


def _sheet_xml(rows):
    xml_rows = []
    for row_index, row in enumerate(rows, 1):
        cells = []
        for column_index, value in enumerate(row, 1):
            reference = f"{_column_name(column_index)}{row_index}"
            text = "TRUE" if value is True else "FALSE" if value is False else str(value or "")
            cells.append(f'<c r="{reference}" t="inlineStr"><is><t xml:space="preserve">{escape(text)}</t></is></c>')
        xml_rows.append(f'<row r="{row_index}">{"".join(cells)}</row>')
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" state="frozen"/></sheetView></sheetViews>'
            f'<sheetData>{"".join(xml_rows)}</sheetData></worksheet>')


def _cue_assignment_rows(document):
    """
    Feuille SAISIE :
    une ligne simple par cue + rôle, pensée pour correction humaine.
    """
    rows = []

    distribution = document.get("distribution", []) or []

    def active_for_role(role):
        role_key = str(role or "").strip().casefold()

        for item in distribution:
            if (
                item.get("active")
                and str(item.get("role") or "").strip().casefold() == role_key
            ):
                return item

        return None

    def values_by_type(item, kind):
        if not item:
            return []

        return [
            str(slot.get("value") or "").strip()
            for slot in item.get("equipment_slots", []) or []
            if str(slot.get("type") or "").strip().upper() == kind
            and str(slot.get("value") or "").strip()
        ]

    for cue in document.get("cues", []):

        raw_role = str(cue.get("role") or "").strip()

        if "split_builder_roles" in globals():
            roles = split_builder_roles(raw_role)
        else:
            roles = [
                value.strip()
                for value in raw_role.split("/")
                if value.strip()
            ]

        if not roles:
            roles = [""]

        assignments = (
            cue.get("role_assignments")
            if isinstance(cue.get("role_assignments"), dict)
            else {}
        )

        def role_assignment(role):
            key = str(role or "").casefold()

            for name, data in assignments.items():
                if str(name).casefold() == key:
                    return data if isinstance(data, dict) else {}

            return {}

        for role in roles:

            active = active_for_role(role)

            artist = str(
                (active or {}).get("artist") or ""
            ).strip()

            micros = values_by_type(active, "MICRO")
            iems = values_by_type(active, "IEM")
            others = (
                values_by_type(active, "ÉQUIPEMENT")
                + values_by_type(active, "AUTRE")
            )

            assignment = role_assignment(role)

            current_micro = str(
                assignment.get("microphone")
                or (
                    cue.get("microphone")
                    if len(roles) == 1
                    else ""
                )
                or ""
            ).strip()

            current_iem = str(
                assignment.get("iem")
                or (
                    cue.get("iem")
                    if len(roles) == 1
                    else ""
                )
                or ""
            ).strip()

            current_other = str(
                assignment.get("equipment")
                or (
                    cue.get("equipment")
                    if len(roles) == 1
                    else ""
                )
                or ""
            ).strip()

            status = []

            if not role:
                status.append("RÔLE À RENSEIGNER")
            elif not active:
                status.append("ARTISTE ACTIF INTROUVABLE")

            if len(micros) > 1 and not current_micro:
                status.append("MICRO À CHOISIR")

            rows.append([
                cue.get("number", ""),
                cue.get("timecode", ""),
                cue.get("section", ""),
                cue.get("text", ""),

                role,
                artist,

                micros[0] if len(micros) > 0 else "",
                micros[1] if len(micros) > 1 else "",
                micros[2] if len(micros) > 2 else "",

                current_micro,

                iems[0] if len(iems) > 0 else "",
                current_iem,

                " · ".join(others),
                current_other,

                cue.get("notes", ""),
                " / ".join(status),

                cue.get("id", ""),
            ])

    return rows

def _material_catalog_rows(document):
    """Référence simple de tout le matériel connu du spectacle."""
    rows = []
    seen = set()

    catalog = document.get("equipment_catalog") or []

    for item in catalog:
        if not isinstance(item, dict):
            continue

        typ = str(item.get("type") or "").strip()
        value = str(item.get("value") or "").strip()

        if not value:
            continue

        key = (typ.casefold(), value.casefold())

        if key in seen:
            continue

        seen.add(key)
        rows.append([typ, value])

    # Sécurité/migration : tout matériel réellement affecté
    # apparaît aussi, même s'il manque au catalogue.
    for assignment in document.get("distribution", []):
        for slot in assignment.get("equipment_slots", []) or []:
            typ = str(slot.get("type") or "").strip()
            value = str(slot.get("value") or "").strip()

            if not value:
                continue

            key = (typ.casefold(), value.casefold())

            if key in seen:
                continue

            seen.add(key)
            rows.append([typ, value])

    rows.sort(
        key=lambda row: (
            str(row[0]).casefold(),
            str(row[1]).casefold(),
        )
    )

    return rows


def export_xlsx(document):
    document = normalize_builder_document(document)

    assignment_columns = (
        "#",
        "TC",
        "SECTION",
        "CUE",

        "RÔLE À UTILISER",
        "ARTISTE ACTIF",

        "MICRO DISPO 1",
        "MICRO DISPO 2",
        "MICRO DISPO 3",

        "MICRO UTILISÉ",

        "IEM DISPO",
        "IEM UTILISÉ",

        "AUTRE MATÉRIEL DISPO",
        "AUTRE MATÉRIEL UTILISÉ",

        "OBSERVATION",
        "À CORRIGER",

        "BUILDER ID — NE PAS MODIFIER",
    )

    material_columns = (
        "TYPE",
        "MATÉRIEL",
    )

    sheets = [
        (
            "SAISIE",
            [
                assignment_columns,
                *_cue_assignment_rows(document),
            ],
        ),
        (
            "CONDUITE — RÉF",
            [
                BUILDER_COLUMNS,
                *[
                    _cue_row(cue)
                    for cue in document["cues"]
                ],
            ],
        ),
        (
            "CASTING — RÉF",
            [
                DISTRIBUTION_COLUMNS,
                *[
                    _distribution_row(row)
                    for row in document["distribution"]
                ],
            ],
        ),
        (
            "MATÉRIEL — RÉF",
            [
                material_columns,
                *_material_catalog_rows(document),
            ],
        ),
    ]

    output = io.BytesIO()

    content_types = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
        '<Default Extension="xml" ContentType="application/xml"/>',
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>',
    ]

    workbook_sheets = []
    workbook_relationships = []

    for index, (name, _rows) in enumerate(sheets, 1):
        content_types.append(
            f'<Override PartName="/xl/worksheets/sheet{index}.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        )

        workbook_sheets.append(
            f'<sheet name="{escape(name)}" '
            f'sheetId="{index}" r:id="rId{index}"/>'
        )

        workbook_relationships.append(
            f'<Relationship Id="rId{index}" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
            f'Target="worksheets/sheet{index}.xml"/>'
        )

    content_types.append("</Types>")

    with zipfile.ZipFile(
        output,
        "w",
        zipfile.ZIP_DEFLATED,
    ) as archive:

        archive.writestr(
            "[Content_Types].xml",
            "".join(content_types),
        )

        archive.writestr(
            "_rels/.rels",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships '
            'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
            'Target="xl/workbook.xml"/>'
            '</Relationships>',
        )

        archive.writestr(
            "xl/workbook.xml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<workbook '
            'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets>'
            + "".join(workbook_sheets)
            + '</sheets></workbook>',
        )

        archive.writestr(
            "xl/_rels/workbook.xml.rels",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships '
            'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            + "".join(workbook_relationships)
            + '</Relationships>',
        )

        for index, (_name, rows) in enumerate(
            sheets,
            1,
        ):
            archive.writestr(
                f"xl/worksheets/sheet{index}.xml",
                _sheet_xml(rows),
            )

    return output.getvalue()

def _rows_to_document(conduite_rows, distribution_rows, unknown_columns=None):
    if not conduite_rows:
        raise ValueError("feuille CONDUITE vide")
    headers = [_text(value).upper() for value in conduite_rows[0]]
    required = {"TEXTE", "TC"}
    missing = sorted(required - set(headers))
    if missing:
        raise ValueError("colonnes obligatoires manquantes : " + ", ".join(missing))
    aliases = {
        "SCÈNE / SOURCE": "SCÈNE ABLETON", "ARTISTE": "ARTISTE OVERRIDE",
        "MICRO": "MICRO OVERRIDE", "IEM": "IEM OVERRIDE", "IEM / EAR": "IEM OVERRIDE",
        "ÉQUIPEMENT": "ÉQUIPEMENT OVERRIDE",
    }
    headers = [aliases.get(value, value) for value in headers]
    mapping = {name: index for index, name in enumerate(headers)}
    known = set(BUILDER_COLUMNS)
    extras = [name for name in headers if name and name not in known]
    if extras and unknown_columns is not None:
        unknown_columns.extend(extras)
    cues = []
    keys = ("number", "timecode", "source", "type", "section", "role", "artist", "text",
            "microphone", "iem", "equipment", "foh", "ret", "plt", "lum", "origin", "notes")
    for values in conduite_rows[1:]:
        if not any(_text(value) for value in values):
            continue
        raw = {key: values[mapping[column]] if column in mapping and mapping[column] < len(values) else ""
               for key, column in zip(keys, BUILDER_COLUMNS)}
        raw["id"] = f"builder_{uuid.uuid4().hex[:12]}"
        for key in ("foh", "ret", "plt", "lum"):
            if not _text(raw[key]):
                raw[key] = False
        cues.append(raw)
    distribution = []
    if distribution_rows:
        d_headers = [_text(value).upper() for value in distribution_rows[0]]
        d_mapping = {name: index for index, name in enumerate(d_headers)}
        legacy = any(column in d_mapping for column in ("MICRO", "IEM", "ÉQUIPEMENT"))
        for values in distribution_rows[1:]:
            if not any(_text(value) for value in values):
                continue
            value = lambda column: values[d_mapping[column]] if column in d_mapping and d_mapping[column] < len(values) else ""
            raw = {"role": value("RÔLE"), "artist": value("ARTISTE"),
                   "active": value("ACTIF"), "notes": value("NOTES")}
            if legacy:
                raw.update({"microphone": value("MICRO"), "iem": value("IEM"),
                            "equipment": value("ÉQUIPEMENT")})
            else:
                raw["equipment_slots"] = [
                    {"type": value(f"ÉQUIPEMENT {index} TYPE"),
                     "value": value(f"ÉQUIPEMENT {index} VALEUR")}
                    for index in range(1, MAX_EQUIPMENT_SLOTS + 1)
                    if _text(value(f"ÉQUIPEMENT {index} TYPE"))
                    or _text(value(f"ÉQUIPEMENT {index} VALEUR"))
                ]
            distribution.append(raw)
    return normalize_builder_document({"cues": cues, "distribution": distribution})


def import_csv(payload):
    text = payload.decode("utf-8-sig")
    sample = text[:4096]
    first_line = sample.splitlines()[0] if sample.splitlines() else ""
    if first_line.count(";") > first_line.count(","):
        dialect = csv.excel()
        dialect.delimiter = ";"
    else:
        try:
            dialect = csv.Sniffer().sniff(sample, delimiters=",;")
        except csv.Error:
            dialect = csv.excel
    rows = list(csv.reader(io.StringIO(text), dialect))
    marker = next((index for index, row in enumerate(rows)
                   if row and _text(row[0]).upper() == "[DISTRIBUTION]"), None)
    distribution_rows = rows[marker + 1:] if marker is not None else []
    conduite_rows = rows[:marker] if marker is not None else rows
    while conduite_rows and not any(_text(value) for value in conduite_rows[-1]):
        conduite_rows.pop()
    unknown = []
    return _rows_to_document(conduite_rows, distribution_rows, unknown), unknown


def _read_xlsx_sheet(archive, target, shared_strings):
    normalized_target = target.lstrip("/")
    if not normalized_target.startswith("xl/"):
        normalized_target = "xl/" + normalized_target
    root = ET.fromstring(archive.read(normalized_target))
    ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    rows = []
    for row in root.findall(".//m:sheetData/m:row", ns):
        values, position = [], 0
        for cell in row.findall("m:c", ns):
            reference = cell.get("r", "A1")
            letters = re.match(r"[A-Z]+", reference).group(0)
            column = 0
            for letter in letters:
                column = column * 26 + ord(letter) - 64
            while position < column - 1:
                values.append("")
                position += 1
            if cell.get("t") == "inlineStr":
                value = "".join(node.text or "" for node in cell.findall(".//m:t", ns))
            else:
                node = cell.find("m:v", ns)
                value = node.text if node is not None else ""
                if cell.get("t") == "s" and value:
                    value = shared_strings[int(value)]
            values.append(value)
            position += 1
        rows.append(values)
    return rows


def import_xlsx(payload):
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        shared = []
        if "xl/sharedStrings.xml" in archive.namelist():
            root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
            ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
            shared = ["".join(node.text or "" for node in item.findall(".//m:t", ns))
                      for item in root.findall("m:si", ns)]
        workbook = ET.fromstring(archive.read("xl/workbook.xml"))
        relationships = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
        rels = {node.get("Id"): node.get("Target") for node in relationships}
        ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
              "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships"}
        sheets = {sheet.get("name").upper(): _read_xlsx_sheet(
            archive, rels[sheet.get("{%s}id" % ns["r"])], shared)
            for sheet in workbook.findall("m:sheets/m:sheet", ns)}
    if "CONDUITE" not in sheets:
        raise ValueError("feuille CONDUITE manquante")
    unknown = []
    return _rows_to_document(sheets["CONDUITE"], sheets.get("DISTRIBUTION", []), unknown), unknown


# CL_SHOWCUE_EQUIPMENT_CATALOG_V1
# ------------------------------------------------------------------
# Extension du document Builder :
# catalogue matériel indépendant des affectations.
# ------------------------------------------------------------------

_normalize_builder_document_without_equipment_catalog = normalize_builder_document


def _normalize_equipment_catalog(values):
    result = []
    seen = set()

    for item in values or []:
        if not isinstance(item, dict):
            continue

        equipment_type = str(
            item.get("type") or "ÉQUIPEMENT"
        ).strip().upper()

        if equipment_type not in {
            "MICRO",
            "IEM",
            "ÉQUIPEMENT",
            "AUTRE",
        }:
            equipment_type = "ÉQUIPEMENT"

        value = str(
            item.get("value") or ""
        ).strip()

        if not value:
            continue

        key = (
            equipment_type.casefold(),
            value.casefold(),
        )

        if key in seen:
            continue

        seen.add(key)

        result.append({
            "type": equipment_type,
            "value": value,
        })

    return result


def normalize_builder_document(document):
    source = document if isinstance(document, dict) else {}

    result = _normalize_builder_document_without_equipment_catalog(
        source
    )

    supplied = source.get("equipment_catalog")

    # Migration transparente des anciens documents :
    # le catalogue initial est déduit des affectations existantes.
    if supplied is None:
        supplied = []

        for row in result.get("distribution", []):
            for slot in row.get("equipment_slots", []) or []:
                supplied.append({
                    "type": slot.get("type"),
                    "value": slot.get("value"),
                })

    result["equipment_catalog"] = _normalize_equipment_catalog(
        supplied
    )

    return result
