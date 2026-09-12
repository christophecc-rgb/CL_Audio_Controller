from __future__ import annotations

import io
import re
import unicodedata
from typing import Iterable

from pypdf import PdfReader


class PdfImportError(ValueError):
    pass


IGNORED_LINES = {
    "N°",
    "TABLEAUX",
    "TITRES",
    "MICROS",
    "NOTES",
    "ST",
    "ST PARADIS",
    "ST LÉO",
    "ST LEO",
    "ST ROXY",
    "ST EDDY",
    "ST MICHEL",
}


def _text(value) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()


def _fold(value: str) -> str:
    value = unicodedata.normalize("NFKD", _text(value))
    return "".join(
        char
        for char in value
        if not unicodedata.combining(char)
    ).upper()


def _is_ignored(line: str) -> bool:
    cleaned = _text(line)
    folded = _fold(cleaned)

    if not cleaned:
        return True

    if cleaned in IGNORED_LINES or folded in {
        _fold(item) for item in IGNORED_LINES
    }:
        return True

    # Bruit fréquent provenant des colonnes micros.
    if re.fullmatch(r"(ST\s*){1,8}", folded):
        return True

    return False


def extract_pdf_text(payload: bytes) -> str:
    if not payload:
        raise PdfImportError("PDF vide")

    try:
        reader = PdfReader(io.BytesIO(payload))
    except Exception as exc:
        raise PdfImportError(
            f"PDF illisible : {exc}"
        ) from exc

    if not reader.pages:
        raise PdfImportError("PDF sans page")

    pages = []

    for page in reader.pages:
        text = ""

        # Les versions récentes de pypdf peuvent préserver davantage
        # la disposition du tableau avec extraction_mode="layout".
        try:
            text = page.extract_text(
                extraction_mode="layout"
            ) or ""
        except (TypeError, ValueError):
            text = page.extract_text() or ""

        pages.append(text)

    result = "\n".join(pages).strip()

    if not result:
        raise PdfImportError(
            "Aucun texte exploitable trouvé dans le PDF"
        )

    return result


def _action_type(text: str) -> tuple[str, str]:
    folded = _fold(text)

    if "SCENE DE COMEDIE" in folded:
        return "AUTRE", "PARTIE PARLÉE"

    if folded.startswith("TOPER ") or " TOPER " in folded:
        return "ENTRÉE ARTISTE", "PARTIE PARLÉE"

    if (
        "AIDER " in folded
        and "CHANGEMENT" in folded
    ):
        return "CHANGEMENT COSTUME", "MUSIQUE"

    if (
        "CHECK " in folded
        or "CHECKER " in folded
        or "VERIFICATION" in folded
    ):
        return "TEST MICRO", "PRÉPARATION"

    if (
        "PREPARER " in folded
        or "DESCENDRE " in folded
        or "EQUIPER " in folded
    ):
        return "TECHNIQUE", "PRÉPARATION"

    if "ATTENTION :" in folded:
        return "TECHNIQUE", "PRÉPARATION"

    if (
        "QUICKCHANGE" in folded
        or "CHANGEMENT DE COSTUME" in folded
    ):
        return "CHANGEMENT COSTUME", "MUSIQUE"

    if "P° EAR" in folded or "IEM" in folded:
        return "ÉQUIPEMENT ARTISTE", "PRÉPARATION"

    # Les titres "Artiste - Titre" / "Titre - Artiste"
    # constituent de bons candidats TOP MUSIQUE.
    if " - " in text:
        return "TOP MUSIQUE", "MUSIQUE"

    return "AUTRE", "MUSIQUE"


def _builder_cue(
    number: int,
    source: str,
    text: str,
    *,
    cue_type: str | None = None,
    section: str | None = None,
    notes: str = "",
) -> dict:
    detected_type, detected_section = _action_type(text)

    return {
        "id": f"builder_pdf_{number:04d}",
        "number": str(number),
        "timecode": "",
        "source": _text(source),
        "type": cue_type or detected_type,
        "section": section or detected_section,
        "role": "",
        "artist": "",
        "text": _text(text),
        "microphone": "",
        "iem": "",
        "equipment": "",
        "foh": True,
        "ret": True,
        "plt": True,
        "lum": True,
        "origin": "PDF",
        "notes": _text(notes),
    }


def _looks_like_note(line: str) -> bool:
    folded = _fold(line)

    keywords = (
        "PREPARER ",
        "DESCENDRE ",
        "EQUIPER ",
        "ATTENTION ",
        "CHECK ",
        "CHECKER ",
        "TOPER ",
        "AIDER ",
        "DEBUT DU SHOW",
        "VERIFICATION",
    )

    return any(keyword in folded for keyword in keywords)


def _looks_like_continuation(line: str) -> bool:
    """
    Les extractions PDF coupent souvent un titre sur 2 ou 3 lignes.
    On fusionne les petites continuations évidentes.
    """
    if len(line) > 38:
        return False

    folded = _fold(line)

    if _looks_like_note(line):
        return False

    if re.match(r"^\d{1,3}\b", line):
        return False

    if "SCENE DE COMEDIE" in folded:
        return False

    return True


def _clean_lines(text: str) -> list[str]:
    lines = []

    for raw in text.splitlines():
        line = _text(raw)

        if _is_ignored(line):
            continue

        # Nettoyage de restes fréquents d'en-tête.
        if _fold(line) in {
            "TABLEAU",
            "TABLEAU 2",
        }:
            continue

        lines.append(line)

    return lines


def parse_pdf_text(text: str) -> dict:
    lines = _clean_lines(text)

    if not lines:
        raise PdfImportError(
            "Aucune ligne exploitable dans le PDF"
        )

    cues: list[dict] = []
    cue_number = 1

    # --------------------------------------------------------
    # Préparation avant le premier tableau numéroté
    # --------------------------------------------------------

    first_table_index = None

    for index, line in enumerate(lines):
        if re.match(r"^\d{1,3}\s+\S", line):
            first_table_index = index
            break

    if first_table_index is None:
        first_table_index = len(lines)

    for line in lines[:first_table_index]:
        if not _looks_like_note(line):
            continue

        cue_type, section = _action_type(line)

        cues.append(
            _builder_cue(
                cue_number,
                "PRÉPARATION",
                line,
                cue_type=cue_type,
                section=section,
            )
        )

        cue_number += 1

    # --------------------------------------------------------
    # Découpage des tableaux numérotés
    # --------------------------------------------------------

    blocks: list[tuple[int, list[str]]] = []
    current_number = None
    current_lines: list[str] = []

    for line in lines[first_table_index:]:
        match = re.match(
            r"^(\d{1,3})\s+(.+)$",
            line,
        )

        if match:
            if current_number is not None:
                blocks.append(
                    (current_number, current_lines)
                )

            current_number = int(match.group(1))
            current_lines = [_text(match.group(2))]
            continue

        if current_number is not None:
            current_lines.append(line)

    if current_number is not None:
        blocks.append(
            (current_number, current_lines)
        )

    # --------------------------------------------------------
    # Transformation des blocs en cues
    # --------------------------------------------------------

    for tableau_number, raw_block in blocks:
        block = [
            line
            for line in raw_block
            if not _is_ignored(line)
        ]

        if not block:
            continue

        source = block[0]
        content = block[1:]

        source_label = (
            f"T{tableau_number:02d} — {source}"
        )

        # Si le tableau ne possède aucune autre information,
        # son nom lui-même devient un cue.
        if not content:
            cue_type, section = _action_type(source)

            cues.append(
                _builder_cue(
                    cue_number,
                    source_label,
                    source,
                    cue_type=cue_type,
                    section=section,
                )
            )

            cue_number += 1
            continue

        merged: list[str] = []

        for line in content:
            if (
                merged
                and _looks_like_continuation(line)
                and _looks_like_continuation(merged[-1])
                and (
                    merged[-1].endswith("-")
                    or len(merged[-1]) < 28
                )
            ):
                merged[-1] = _text(
                    merged[-1] + " " + line
                )
            else:
                merged.append(line)

        # Certains tableaux sont eux-mêmes une action importante
        # (QUICKCHANGE, CANCAN, etc.) et possèdent ensuite une note.
        source_folded = _fold(source)

        source_is_action = any(
            token in source_folded
            for token in (
                "QUICKCHANGE",
                "CANCAN",
                "POUCE",
                "ANNIVERSAIRE",
                "BOITE MAGIQUE",
                "TRAPEZE",
                "LAC DES CYGNES",
                "OMBRE CHINOISE",
                "BOLLYWOOD",
                "TOUR DU MONDE",
                "L'ENVOL",
                "L’ENVOL",
            )
        )

        if source_is_action:
            cue_type, section = _action_type(source)

            cues.append(
                _builder_cue(
                    cue_number,
                    source_label,
                    source,
                    cue_type=cue_type,
                    section=section,
                )
            )

            cue_number += 1

        for item in merged:
            cue_type, section = _action_type(item)

            cues.append(
                _builder_cue(
                    cue_number,
                    source_label,
                    item,
                    cue_type=cue_type,
                    section=section,
                )
            )

            cue_number += 1

    if not cues:
        raise PdfImportError(
            "Le PDF a été lu, mais aucun cue n'a pu être identifié"
        )

    return {
        "version": 1,
        "revision": 0,
        "cues": cues,
        "distribution": [],
    }


def import_pdf_bytes(payload: bytes) -> dict:
    return parse_pdf_text(
        extract_pdf_text(payload)
    )
