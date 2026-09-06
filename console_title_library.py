"""Importation sûre et normalisation des bibliothèques de titres consoles."""

from __future__ import annotations

import csv
import json
import os
import re
import shutil
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from io import StringIO
from pathlib import Path
from typing import Any, Dict, Iterable, Optional


CONSOLES = ("cl5", "ql1")
LIBRARY_ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
MAX_FILE_SIZE = 16 * 1024 * 1024
MAX_ENTRIES = 128
SUPPORTED_EXTENSIONS = {".clf", ".csv", ".tsv", ".json", ".txt"}
SAFE_SOURCE_NAME = re.compile(r"^[^/\\\x00]{1,255}$")


class LibraryImportError(ValueError):
    pass


@dataclass(frozen=True)
class ParsedImport:
    libraries: Dict[str, Dict[int, str]]
    source_format: str
    source_name: str
    imported_at: str
    warnings: tuple[str, ...] = ()
    migrated_from: Optional[str] = None

    def canonical_for(self, console: str) -> Dict[str, Any]:
        key = normalize_console(console)
        entries = [
            {"console": key.upper(), "memory": memory, "midi_program": memory - 1, "title": title}
            for memory, title in sorted(self.libraries.get(key, {}).items())
        ]
        payload = {
            "schema_version": 1,
            "console": key.upper(),
            "source_format": self.source_format,
            "source_name": self.source_name,
            "imported_at": self.imported_at,
            "entries": entries,
            "warnings": list(self.warnings),
        }
        if self.migrated_from:
            payload["migrated_from"] = self.migrated_from
        return payload


def normalize_console(value: Any) -> str:
    """Normalise un identifiant de bibliothèque sûr.

    CL5/QL1 restent les identifiants historiques. Les profils peuvent toutefois
    déclarer d'autres bibliothèques stables, par exemple ql3.
    """
    key = str(value or "").strip().lower()
    if not LIBRARY_ID_PATTERN.fullmatch(key):
        raise LibraryImportError("identifiant de bibliothèque invalide")
    return key


def console_clf_family(value: Any) -> Optional[str]:
    """Retourne la famille Yamaha attendue pour un import CLF."""
    key = normalize_console(value)
    if key.startswith("cl"):
        return "cl5"
    if key.startswith("ql"):
        return "ql1"
    return None


def _add(rows: Dict[str, Dict[int, str]], console: Any, memory: Any, title: Any,
         warnings: list[str]) -> None:
    key = normalize_console(console)
    try:
        number = int(str(memory).strip())
    except (TypeError, ValueError):
        raise LibraryImportError(f"numéro de mémoire invalide: {memory!r}")
    if not 1 <= number <= 128:
        raise LibraryImportError(f"mémoire hors plage 1..128: {number}")
    clean_title = str(title or "").strip()
    if not clean_title:
        raise LibraryImportError(f"titre vide pour {key.upper()} mémoire {number}")
    if len(clean_title) > 255 or any(ord(char) < 32 and char != "\t" for char in clean_title):
        raise LibraryImportError(f"titre invalide pour {key.upper()} mémoire {number}")
    library = rows.setdefault(key, {})
    existing = library.get(number)
    if existing == clean_title:
        warnings.append(f"doublon exact ignoré: {key.upper()} mémoire {number}")
        return
    if existing is not None:
        raise LibraryImportError(f"doublon ambigu: {key.upper()} mémoire {number}")
    library[number] = clean_title


def _decode_text(data: bytes) -> str:
    if b"\x00" in data:
        raise LibraryImportError("contenu texte binaire ou invalide")
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise LibraryImportError("le fichier texte doit être encodé en UTF-8") from exc


def _parse_delimited(text: str, delimiter: str, assigned_console: Optional[str],
                     rows: Dict[str, Dict[int, str]], warnings: list[str]) -> None:
    reader = csv.DictReader(StringIO(text, newline=""), delimiter=delimiter)
    fields = {str(name or "").strip().lower() for name in (reader.fieldnames or [])}
    if not {"memory", "title"}.issubset(fields) or fields - {"console", "memory", "title"}:
        raise LibraryImportError("en-tête attendu: memory,title ou console,memory,title")
    for line_number, raw in enumerate(reader, 2):
        item = {str(k or "").strip().lower(): v for k, v in raw.items()}
        console = item.get("console") or assigned_console
        if not console:
            raise LibraryImportError(f"console absente à la ligne {line_number}")
        _add(rows, console, item.get("memory"), item.get("title"), warnings)


def _parse_json(text: str, assigned_console: Optional[str], rows: Dict[str, Dict[int, str]],
                warnings: list[str]) -> None:
    try:
        payload = json.loads(text)
    except (ValueError, TypeError) as exc:
        raise LibraryImportError("JSON invalide") from exc
    groups: Iterable[tuple[Any, Any]]
    if isinstance(payload, dict) and isinstance(payload.get("scenes"), list):
        groups = ((payload.get("console") or assigned_console, payload["scenes"]),)
    elif isinstance(payload, dict) and isinstance(payload.get("consoles"), dict):
        groups = tuple(payload["consoles"].items())
    else:
        raise LibraryImportError("structure JSON non reconnue")
    for console, scenes in groups:
        if not isinstance(scenes, list):
            raise LibraryImportError("la liste scenes doit être un tableau")
        for scene in scenes:
            if not isinstance(scene, dict) or set(scene) - {"memory", "title"}:
                raise LibraryImportError("entrée JSON invalide")
            _add(rows, console, scene.get("memory"), scene.get("title"), warnings)


def _parse_txt(text: str, assigned_console: Optional[str], rows: Dict[str, Dict[int, str]],
               warnings: list[str]) -> None:
    for line_number, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        normalized_header = tuple(part.strip().lower() for part in parts)
        if normalized_header in (("memory", "title"), ("mémoire", "titre"),
                                 ("console", "memory", "title"),
                                 ("console", "mémoire", "titre")):
            continue
        if len(parts) == 2 and assigned_console:
            console, memory, title = assigned_console, parts[0], parts[1]
        elif len(parts) == 3:
            console, memory, title = parts
        else:
            raise LibraryImportError(f"ligne TXT {line_number}: séparateurs tabulation attendus")
        _add(rows, console, memory, title, warnings)


def parse_clf(data: bytes, assigned_console: Optional[str]) -> Dict[str, Dict[int, str]]:
    if len(data) < 0x38:
        raise LibraryImportError("fichier CLF trop court")
    header = data[0x10:0x30].decode("ascii", errors="ignore").strip("\x00 ").upper()
    detected = "cl5" if header.startswith("CL") else "ql1" if header.startswith("QL") else None
    console = normalize_console(assigned_console or detected)
    expected_family = console_clf_family(console)
    if assigned_console and expected_family is None:
        raise LibraryImportError(
            f"famille CLF inconnue pour la bibliothèque {console.upper()}"
        )
    if detected and expected_family and detected != expected_family:
        raise LibraryImportError(f"ce CLF semble destiné à {detected.upper()}")
    scene_count = int.from_bytes(data[0x0C:0x0E], "big")
    if not 1 <= scene_count <= 4096 or 0x38 + scene_count * 8 > len(data):
        raise LibraryImportError("structure CLF invalide")
    result = {console: {}}
    for memory in range(1, min(scene_count, MAX_ENTRIES) + 1):
        entry = 0x30 + memory * 8
        if int.from_bytes(data[entry:entry + 2], "big") != memory:
            continue
        offset = int.from_bytes(data[entry + 4:entry + 8], "big")
        if not 0 <= offset < len(data):
            continue
        block = data.find(b"MEMAPI", offset, min(len(data), offset + 32))
        if block < 0 or block + 44 > len(data):
            continue
        title = data[block + 12:block + 44].split(b"\x00", 1)[0].decode("latin-1", "replace").strip()
        if title:
            result[console][memory] = title
    if not result[console]:
        raise LibraryImportError("aucun titre CLF valide trouvé")
    return result


def parse_import(data: bytes, source_name: str, assigned_console: Optional[str] = None,
                 imported_at: Optional[str] = None) -> ParsedImport:
    name = Path(str(source_name or "")).name
    if name != source_name or not SAFE_SOURCE_NAME.fullmatch(name):
        raise LibraryImportError("nom de fichier dangereux")
    if not data:
        raise LibraryImportError("fichier vide")
    if len(data) > MAX_FILE_SIZE:
        raise LibraryImportError("fichier trop volumineux")
    extension = Path(name).suffix.lower()
    if extension not in SUPPORTED_EXTENSIONS:
        raise LibraryImportError("format inconnu; utiliser CLF, CSV, TSV, JSON ou TXT")
    rows = (
        {normalize_console(assigned_console): {}}
        if assigned_console
        else {console: {} for console in CONSOLES}
    )
    warnings: list[str] = []
    if extension == ".clf":
        rows = parse_clf(data, assigned_console)
    else:
        text = _decode_text(data)
        if extension == ".csv":
            _parse_delimited(text, ",", assigned_console, rows, warnings)
        elif extension == ".tsv":
            _parse_delimited(text, "\t", assigned_console, rows, warnings)
        elif extension == ".json":
            _parse_json(text, assigned_console, rows, warnings)
        else:
            _parse_txt(text, assigned_console, rows, warnings)
    if sum(map(len, rows.values())) == 0:
        raise LibraryImportError("aucune entrée valide trouvée")
    if any(len(library) > MAX_ENTRIES for library in rows.values()):
        raise LibraryImportError("trop d'entrées")
    return ParsedImport(rows, extension[1:].upper(), name,
                        imported_at or datetime.now(timezone.utc).isoformat(), tuple(warnings))


class ConsoleLibraryStore:
    def __init__(self, root: Path):
        self.root = Path(root)

    def canonical_path(self, console: str) -> Path:
        return self.root / f"{normalize_console(console).upper()}.titles.json"

    def load(self, console: str) -> Dict[str, Any]:
        path = self.canonical_path(console)
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            entries = payload["entries"]
            library = {int(item["memory"]): str(item["title"]) for item in entries}
            if payload.get("console", "").lower() != normalize_console(console):
                raise ValueError
            payload["library"] = library
            payload["path"] = str(path)
            payload["status"] = "Valide"
            return payload
        except (OSError, ValueError, TypeError, KeyError):
            return {"console": normalize_console(console).upper(), "library": {}, "path": str(path),
                    "status": "Aucun fichier installé" if not path.exists() else "Lecture impossible"}

    def install(self, parsed: ParsedImport, console: str) -> Dict[str, Any]:
        key = normalize_console(console)
        if not parsed.libraries.get(key):
            raise LibraryImportError(f"aucune entrée pour {key.upper()}")
        payload = parsed.canonical_for(key)
        self.root.mkdir(parents=True, exist_ok=True)
        target = self.canonical_path(key)
        backup = target.with_suffix(target.suffix + ".backup")
        fd, temporary_name = tempfile.mkstemp(prefix=f".{target.name}.", suffix=".tmp", dir=self.root)
        temporary = Path(temporary_name)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                json.dump(payload, stream, ensure_ascii=False, indent=2, sort_keys=True)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.chmod(temporary, 0o600)
            json.loads(temporary.read_text(encoding="utf-8"))
            if target.exists():
                shutil.copy2(target, backup)
                os.chmod(backup, 0o600)
            os.replace(temporary, target)
        except Exception:
            temporary.unlink(missing_ok=True)
            raise
        return self.load(key)

    def status(self, consoles: Iterable[str] = CONSOLES) -> Dict[str, Dict[str, Any]]:
        return {normalize_console(console): self.load(console) for console in consoles}

    def migrate_legacy(self, desktop: Path) -> Dict[str, str]:
        result: Dict[str, str] = {}
        candidates = {"cl5": (desktop / "CL5.CLF",),
                      "ql1": (desktop / "ql1.CLF", desktop / "QL1.CLF")}
        for console, paths in candidates.items():
            if self.canonical_path(console).exists():
                continue
            for source in paths:
                if not source.is_file() or source.stat().st_size > MAX_FILE_SIZE:
                    continue
                try:
                    original = parse_import(source.read_bytes(), source.name, console)
                    parsed = ParsedImport(original.libraries, original.source_format,
                                          original.source_name, original.imported_at,
                                          original.warnings, str(source))
                    self.install(parsed, console)
                    result[console] = str(source)
                    break
                except (OSError, LibraryImportError):
                    continue
        return result
