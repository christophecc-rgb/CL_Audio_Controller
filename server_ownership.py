"""Persistance locale securisee de la propriete du serveur embarque."""

from __future__ import annotations

import json
import os
import stat
import tempfile
import uuid
from pathlib import Path
from typing import Any, Dict


SCHEMA_VERSION = 1
MAX_RECORD_SIZE = 8192
REQUIRED_FIELDS = {
    "schema_version",
    "service",
    "identity_protocol_version",
    "launch_id",
    "server_instance_id",
    "build_id",
    "server_process_id",
    "server_started_at",
    "recorded_at",
    "shutdown_token",
}
DEFAULT_RECORD_PATH = (
    Path.home()
    / "Library"
    / "Application Support"
    / "CL Audio Controller"
    / "server-ownership.json"
)


class OwnershipRecordError(RuntimeError):
    pass


def validate_record(record: Any) -> Dict[str, Any]:
    if not isinstance(record, dict) or set(record) != REQUIRED_FIELDS:
        raise OwnershipRecordError("schema de propriété invalide")
    if record["schema_version"] != SCHEMA_VERSION:
        raise OwnershipRecordError("version de schéma inconnue")
    if not isinstance(record["identity_protocol_version"], int):
        raise OwnershipRecordError("version de protocole invalide")
    for key in ("service", "build_id", "shutdown_token"):
        if not isinstance(record[key], str) or not record[key]:
            raise OwnershipRecordError(f"champ {key} invalide")
    if len(record["shutdown_token"]) < 32:
        raise OwnershipRecordError("jeton de propriété trop court")
    for key in ("launch_id", "server_instance_id"):
        try:
            uuid.UUID(record[key])
        except (ValueError, TypeError, AttributeError) as exc:
            raise OwnershipRecordError(f"champ {key} invalide") from exc
    if not isinstance(record["server_process_id"], int) or record["server_process_id"] <= 0:
        raise OwnershipRecordError("PID diagnostique invalide")
    for key in ("server_started_at", "recorded_at"):
        if not isinstance(record[key], (int, float)) or record[key] <= 0:
            raise OwnershipRecordError(f"champ {key} invalide")
    return dict(record)


def _validate_directory(directory: Path, create: bool) -> None:
    if directory.exists() or directory.is_symlink():
        metadata = directory.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise OwnershipRecordError("dossier de propriété non sûr")
        if metadata.st_uid != os.getuid():
            raise OwnershipRecordError("propriétaire du dossier incorrect")
        if stat.S_IMODE(metadata.st_mode) & 0o077:
            raise OwnershipRecordError("permissions du dossier trop ouvertes")
        return
    if not create:
        return
    directory.mkdir(parents=True, mode=0o700)
    os.chmod(directory, 0o700)


def write_record(record: Dict[str, Any], path: Path = DEFAULT_RECORD_PATH) -> None:
    normalized = validate_record(record)
    path = Path(path)
    _validate_directory(path.parent, create=True)
    if path.exists() or path.is_symlink():
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
            raise OwnershipRecordError("fichier de propriété existant non sûr")
        if metadata.st_uid != os.getuid():
            raise OwnershipRecordError("propriétaire du fichier existant incorrect")
        if stat.S_IMODE(metadata.st_mode) != 0o600:
            raise OwnershipRecordError("permissions du fichier existant incorrectes")
    encoded = json.dumps(normalized, ensure_ascii=False, sort_keys=True).encode("utf-8")
    if len(encoded) > MAX_RECORD_SIZE:
        raise OwnershipRecordError("fichier de propriété trop volumineux")
    descriptor, temporary_name = tempfile.mkstemp(prefix=".server-ownership-", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
        os.chmod(path, 0o600)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


def load_record(path: Path = DEFAULT_RECORD_PATH) -> Dict[str, Any] | None:
    path = Path(path)
    _validate_directory(path.parent, create=False)
    if not path.exists() and not path.is_symlink():
        return None
    metadata = path.lstat()
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise OwnershipRecordError("fichier de propriété non régulier")
    if metadata.st_uid != os.getuid():
        raise OwnershipRecordError("propriétaire du fichier incorrect")
    if stat.S_IMODE(metadata.st_mode) != 0o600:
        raise OwnershipRecordError("permissions du fichier incorrectes")
    if metadata.st_size > MAX_RECORD_SIZE:
        raise OwnershipRecordError("fichier de propriété trop volumineux")
    try:
        return validate_record(json.loads(path.read_text(encoding="utf-8")))
    except (OSError, json.JSONDecodeError) as exc:
        raise OwnershipRecordError("fichier de propriété illisible") from exc


def remove_record(path: Path = DEFAULT_RECORD_PATH) -> None:
    path = Path(path)
    if not path.exists() and not path.is_symlink():
        return
    metadata = path.lstat()
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise OwnershipRecordError("suppression d'un fichier non sûr refusée")
    if metadata.st_uid != os.getuid():
        raise OwnershipRecordError("propriétaire du fichier incorrect")
    path.unlink()


def record_matches_status(record: Dict[str, Any], status: Dict[str, Any]) -> bool:
    return all((
        record.get("service") == status.get("service"),
        record.get("identity_protocol_version") == status.get("identity_protocol_version"),
        record.get("launch_id") == status.get("launch_id"),
        record.get("server_instance_id") == status.get("server_instance_id"),
        record.get("build_id") == status.get("build_id"),
        record.get("server_process_id") == status.get("server_process_id"),
        record.get("server_started_at") == status.get("started_at"),
    ))


def process_alive(pid: int) -> bool:
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError, TypeError):
        return False
