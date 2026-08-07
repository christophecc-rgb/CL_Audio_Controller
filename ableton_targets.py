"""Configuration persistante des profils AbletonOSC Local et Distant."""

from __future__ import annotations

import ipaddress
import json
import os
import socket
import stat
import tempfile
from dataclasses import asdict, dataclass, replace
from pathlib import Path
from typing import Any, Dict, Optional


SCHEMA_VERSION = 2
LEGACY_SCHEMA_VERSION = 1
LOCAL_HOST = "127.0.0.1"
DEFAULT_SEND_PORT = 11000
DEFAULT_REPLY_PORT = 11001
MAX_CONFIG_SIZE = 32768
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


@dataclass(frozen=True)
class AbletonProfiles:
    active_mode: str
    local: AbletonTarget
    remote: Optional[AbletonTarget] = None
    remote_name: Optional[str] = None

    def active_target(self) -> AbletonTarget:
        if self.active_mode == "local":
            return self.local
        if self.remote is None:
            raise AbletonTargetError("profil Ableton distant non configuré")
        return self.remote

    def to_dict(self) -> Dict[str, Any]:
        remote = None
        if self.remote is not None:
            remote = _profile_dict(self.remote)
            remote["name"] = self.remote_name
        return {
            "active_mode": self.active_mode,
            "profiles": {
                "local": _profile_dict(self.local),
                "remote": remote,
            },
        }


def _profile_dict(target: AbletonTarget) -> Dict[str, Any]:
    return {
        "mode": target.mode,
        "host": target.host,
        "send_port": target.send_port,
        "reply_port": target.reply_port,
    }


def local_target(
    send_port: int = DEFAULT_SEND_PORT,
    reply_port: int = DEFAULT_REPLY_PORT,
) -> AbletonTarget:
    return validate_target({
        "mode": "local",
        "host": LOCAL_HOST,
        "send_port": send_port,
        "reply_port": reply_port,
    })


def default_profiles() -> AbletonProfiles:
    return AbletonProfiles(active_mode="local", local=local_target())


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
        if not host:
            raise AbletonTargetError("adresse ou nom du Mac Ableton manquant")

        try:
            resolved_host = socket.gethostbyname(host)
        except socket.gaierror as exc:
            raise AbletonTargetError(
                f"Mac Ableton introuvable : {host}"
            ) from exc

        try:
            parsed = ipaddress.ip_address(resolved_host)
        except ValueError as exc:
            raise AbletonTargetError(
                f"adresse résolue invalide pour {host}"
            ) from exc

        if (
            parsed.version != 4
            or parsed.is_unspecified
            or parsed.is_multicast
            or parsed.is_loopback
        ):
            raise AbletonTargetError(
                f"adresse Ableton non utilisable : {host} → {resolved_host}"
            )
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


def _validate_remote_name(value: Any) -> Optional[str]:
    if value is None:
        return None
    if not isinstance(value, str):
        raise AbletonTargetError("nom de cible distante invalide")
    value = value.strip()
    if len(value) > 120:
        raise AbletonTargetError("nom de cible distante trop long")
    return value or None


def _profiles_from_v1(payload: Dict[str, Any]) -> AbletonProfiles:
    if set(payload) != {"schema_version", "active_target"}:
        raise AbletonTargetError("schéma de configuration V1 invalide")
    active = validate_target(payload["active_target"])
    if active.mode == "remote":
        return AbletonProfiles(
            active_mode="remote",
            local=local_target(),
            remote=active,
        )
    return AbletonProfiles(
        active_mode="local",
        local=local_target(active.send_port, active.reply_port),
    )


def _validate_profile_payload(payload: Any) -> AbletonProfiles:
    if not isinstance(payload, dict):
        raise AbletonTargetError("configuration réseau invalide")
    if set(payload) != {"schema_version", "active_mode", "profiles"}:
        raise AbletonTargetError("schéma de configuration V2 invalide")
    if payload.get("schema_version") != SCHEMA_VERSION:
        raise AbletonTargetError("version de configuration inconnue")
    active_mode = payload.get("active_mode")
    if active_mode not in {"local", "remote"}:
        raise AbletonTargetError("profil actif invalide")
    raw_profiles = payload.get("profiles")
    if not isinstance(raw_profiles, dict) or set(raw_profiles) != {"local", "remote"}:
        raise AbletonTargetError("profils Ableton invalides")

    raw_local = raw_profiles["local"]
    if not isinstance(raw_local, dict) or set(raw_local) != {
        "mode", "host", "send_port", "reply_port"
    }:
        raise AbletonTargetError("profil Local invalide")
    if raw_local.get("mode") != "local" or raw_local.get("host") != LOCAL_HOST:
        raise AbletonTargetError("profil Local non conforme")
    local = validate_target(raw_local)

    raw_remote = raw_profiles["remote"]
    remote = None
    remote_name = None
    if raw_remote is not None:
        if not isinstance(raw_remote, dict) or set(raw_remote) != {
            "mode", "name", "host", "send_port", "reply_port"
        }:
            raise AbletonTargetError("profil Distant invalide")
        if raw_remote.get("mode") != "remote":
            raise AbletonTargetError("mode du profil Distant invalide")
        remote_name = _validate_remote_name(raw_remote.get("name"))
        remote = validate_target({key: value for key, value in raw_remote.items() if key != "name"})
    if active_mode == "remote" and remote is None:
        raise AbletonTargetError("profil Distant actif mais non configuré")
    return AbletonProfiles(
        active_mode=active_mode,
        local=local,
        remote=remote,
        remote_name=remote_name,
    )


def _validate_profiles(profiles: AbletonProfiles) -> AbletonProfiles:
    if not isinstance(profiles, AbletonProfiles):
        raise AbletonTargetError("profils Ableton invalides")
    return _validate_profile_payload({"schema_version": SCHEMA_VERSION, **profiles.to_dict()})


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


def _read_payload(path: Path) -> Optional[Dict[str, Any]]:
    _validate_directory(path.parent, create=False)
    if not path.exists() and not path.is_symlink():
        return None
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
    if not isinstance(payload, dict):
        raise AbletonTargetError("configuration réseau invalide")
    return payload


def load_profiles(path: Path = DEFAULT_CONFIG_PATH) -> AbletonProfiles:
    """Lit V1 ou V2 et migre V1 en mémoire, sans réécrire le fichier."""
    path = Path(path)
    payload = _read_payload(path)
    if payload is None:
        return default_profiles()
    version = payload.get("schema_version")
    if version == LEGACY_SCHEMA_VERSION:
        return _profiles_from_v1(payload)
    if version == SCHEMA_VERSION:
        return _validate_profile_payload(payload)
    raise AbletonTargetError("version de configuration inconnue")


def load_target(path: Path = DEFAULT_CONFIG_PATH) -> AbletonTarget:
    """Façade historique : retourne uniquement la cible actuellement active."""
    return load_profiles(path).active_target()


def select_active_profile(profiles: AbletonProfiles, mode: str) -> AbletonProfiles:
    mode = str(mode).strip().lower()
    if mode not in {"local", "remote"}:
        raise AbletonTargetError("profil actif invalide")
    candidate = replace(_validate_profiles(profiles), active_mode=mode)
    return _validate_profiles(candidate)


def update_profile(
    profiles: AbletonProfiles,
    target: Any,
    *,
    name: Optional[str] = None,
    activate: bool = False,
) -> AbletonProfiles:
    profiles = _validate_profiles(profiles)
    target = validate_target(target)
    if target.mode == "local":
        candidate = replace(profiles, local=target)
    else:
        candidate = replace(
            profiles,
            remote=target,
            remote_name=_validate_remote_name(name),
        )
    if activate:
        candidate = replace(candidate, active_mode=target.mode)
    return _validate_profiles(candidate)


def save_profiles(
    profiles: AbletonProfiles,
    path: Path = DEFAULT_CONFIG_PATH,
) -> None:
    profiles = _validate_profiles(profiles)
    path = Path(path)
    _validate_directory(path.parent, create=True)
    if path.exists() or path.is_symlink():
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
            raise AbletonTargetError("fichier de configuration existant non sûr")
        if metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) != 0o600:
            raise AbletonTargetError("permissions du fichier existant incorrectes")
    encoded = json.dumps(
        {"schema_version": SCHEMA_VERSION, **profiles.to_dict()},
        ensure_ascii=False,
        sort_keys=True,
    ).encode("utf-8")
    if len(encoded) > MAX_CONFIG_SIZE:
        raise AbletonTargetError("configuration réseau trop volumineuse")
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


def save_target(target: AbletonTarget, path: Path = DEFAULT_CONFIG_PATH) -> None:
    """Compatibilité : met à jour et active un profil sans altérer l'autre."""
    target = validate_target(target)
    profiles = load_profiles(path)
    profiles = update_profile(profiles, target, activate=True)
    save_profiles(profiles, path)
