"""Configuration persistante de la cible AbletonOSC active."""

from __future__ import annotations

import ipaddress
import json
import os
import stat
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Dict


SCHEMA_VERSION = 1
LOCAL_HOST = "127.0.0.1"
DEFAULT_SEND_PORT = 11000
DEFAULT_REPLY_PORT = 11001
MAX_CONFIG_SIZE = 4096
DEFAULT_CONFIG_PATH = (
    Path.home()
    / "Library"
    / "Application Support"
    / "CL Audio Controller"
    / "network-config.json"
)


class AbletonTargetError(ValueError):
    pass


@dataclass(frozen=True)
class AbletonTarget:
    target_id: str = "primary"
    mode: str = "local"
    host: str = LOCAL_HOST
    send_port: int = DEFAULT_SEND_PORT
    reply_port: int = DEFAULT_REPLY_PORT

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


def local_target() -> AbletonTarget:
    return AbletonTarget()


def validate_target(value: Any) -> AbletonTarget:
    if isinstance(value, AbletonTarget):
        value = value.to_dict()
    if not isinstance(value, dict):
        raise AbletonTargetError("configuration Ableton invalide")
    allowed = {"target_id", "mode", "host", "send_port", "reply_port"}
    if set(value) - allowed:
        raise AbletonTargetError("champs de configuration inconnus")
    target_id = value.get("target_id", "primary")
    mode = str(value.get("mode", "local")).strip().lower()
    if target_id != "primary":
        raise AbletonTargetError("cible active inconnue")
    if mode not in {"local", "remote"}:
        raise AbletonTargetError("mode attendu : local ou remote")
    host = LOCAL_HOST if mode == "local" else str(value.get("host", "")).strip()
    if mode == "remote":
        try:
            parsed = ipaddress.ip_address(host)
        except ValueError as exc:
            raise AbletonTargetError("adresse IPv4 Ableton invalide") from exc
        if parsed.version != 4 or parsed.is_unspecified or parsed.is_multicast:
            raise AbletonTargetError("adresse IPv4 Ableton non utilisable")
    try:
        send_port = int(value.get("send_port", DEFAULT_SEND_PORT))
        reply_port = int(value.get("reply_port", DEFAULT_REPLY_PORT))
    except (TypeError, ValueError) as exc:
        raise AbletonTargetError("port OSC invalide") from exc
    if not 1 <= send_port <= 65535 or not 1 <= reply_port <= 65535:
        raise AbletonTargetError("port OSC hors limites")
    return AbletonTarget(
        target_id="primary",
        mode=mode,
        host=host,
        send_port=send_port,
        reply_port=reply_port,
    )


def _validate_directory(directory: Path, create: bool) -> None:
    if directory.exists() or directory.is_symlink():
        metadata = directory.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise AbletonTargetError("dossier de configuration non sûr")
        if metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) & 0o077:
            raise AbletonTargetError("permissions du dossier de configuration incorrectes")
        return
    if create:
        directory.mkdir(parents=True, mode=0o700)
        os.chmod(directory, 0o700)


def load_target(path: Path = DEFAULT_CONFIG_PATH) -> AbletonTarget:
    path = Path(path)
    _validate_directory(path.parent, create=False)
    if not path.exists() and not path.is_symlink():
        return local_target()
    metadata = path.lstat()
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise AbletonTargetError("fichier de configuration non sûr")
    if metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) != 0o600:
        raise AbletonTargetError("permissions du fichier de configuration incorrectes")
    if metadata.st_size > MAX_CONFIG_SIZE:
        raise AbletonTargetError("fichier de configuration trop volumineux")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AbletonTargetError("configuration réseau illisible") from exc
    if not isinstance(payload, dict) or payload.get("schema_version") != SCHEMA_VERSION:
        raise AbletonTargetError("version de configuration inconnue")
    if set(payload) != {"schema_version", "active_target"}:
        raise AbletonTargetError("schéma de configuration invalide")
    return validate_target(payload["active_target"])


def save_target(target: AbletonTarget, path: Path = DEFAULT_CONFIG_PATH) -> None:
    target = validate_target(target)
    path = Path(path)
    _validate_directory(path.parent, create=True)
    if path.exists() or path.is_symlink():
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
            raise AbletonTargetError("fichier de configuration existant non sûr")
        if metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) != 0o600:
            raise AbletonTargetError("permissions du fichier existant incorrectes")
    encoded = json.dumps(
        {"schema_version": SCHEMA_VERSION, "active_target": target.to_dict()},
        ensure_ascii=False,
        sort_keys=True,
    ).encode("utf-8")
    descriptor, temporary_name = tempfile.mkstemp(prefix=".network-config-", dir=path.parent)
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
