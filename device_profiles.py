"""Configuration générique des devices, sans remplacer les chemins historiques.

La passe 1 expose des profils stables et une couche d'adaptation. Le moteur de
production continue volontairement d'utiliser ses clés ``cl5`` / ``ql1``.
"""

from __future__ import annotations

import json
import os
import re
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping, Optional


SUPPORTED_PROTOCOLS = frozenset({"midi"})
FUTURE_PROTOCOLS = frozenset({"osc"})
SUPPORTED_SIGNAL_TYPES = frozenset({"program_change"})
FUTURE_SIGNAL_TYPES = frozenset({"control_change", "note", "sysex", "osc_message"})
DEVICE_SCHEMA_VERSION = 1

DEFAULT_DEVICE_CONFIG_PATH = (
    Path.home() / "Library" / "Application Support" / "CL Audio Controller" / "devices.json"
)


@dataclass(frozen=True)
class DevicePalette:
    base: str
    accent: str

    def to_dict(self) -> dict[str, str]:
        return {"base": self.base, "accent": self.accent}


@dataclass(frozen=True)
class DeviceVisibility:
    show_control: bool = True
    remote: bool = True
    network_manager: bool = True

    def to_dict(self) -> dict[str, bool]:
        return {
            "show_control": self.show_control,
            "remote": self.remote,
            "network_manager": self.network_manager,
        }


@dataclass(frozen=True)
class DeviceProfile:
    id: str
    display_name: str
    enabled: bool
    device_type: str
    protocol: str
    signal_type: str
    midi_channel: Optional[int]
    ableton_track_aliases: tuple[str, ...]
    palette: DevicePalette
    library: Optional[str]
    visibility: DeviceVisibility
    legacy_key: Optional[str] = None
    tx_enabled: bool = True
    rx_enabled: bool = True

    @property
    def supported(self) -> bool:
        return self.protocol in SUPPORTED_PROTOCOLS and self.signal_type in SUPPORTED_SIGNAL_TYPES

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "display_name": self.display_name,
            "enabled": self.enabled,
            "device_type": self.device_type,
            "protocol": self.protocol,
            "signal_type": self.signal_type,
            "midi_channel": self.midi_channel,
            "ableton_track_aliases": list(self.ableton_track_aliases),
            "palette": self.palette.to_dict(),
            "library": self.library,
            "visibility": self.visibility.to_dict(),
            "legacy_key": self.legacy_key,
            "tx": {"enabled": self.tx_enabled},
            "rx": {"enabled": self.rx_enabled},
            "supported": self.supported,
        }


@dataclass(frozen=True)
class DeviceConfiguration:
    schema_version: int = DEVICE_SCHEMA_VERSION
    profile_id: str = "default"
    profile_name: str = "Configuration par défaut"
    devices: tuple[DeviceProfile, ...] = field(default_factory=tuple)

    def by_id(self, device_id: str) -> Optional[DeviceProfile]:
        return next((device for device in self.devices if device.id == device_id), None)

    def by_legacy_key(self, legacy_key: str) -> Optional[DeviceProfile]:
        return next((device for device in self.devices if device.legacy_key == legacy_key), None)

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "profile_id": self.profile_id,
            "profile_name": self.profile_name,
            "devices": [device.to_dict() for device in self.devices],
        }


def default_device_configuration() -> DeviceConfiguration:
    return DeviceConfiguration(devices=(
        DeviceProfile(
            id="console_a", display_name="CL5", enabled=True,
            device_type="console", protocol="midi", signal_type="program_change",
            midi_channel=1, ableton_track_aliases=("PGM CHANGE CL5",),
            palette=DevicePalette(base="#C09AF2", accent="#9B6BD6"),
            library="cl5", visibility=DeviceVisibility(), legacy_key="cl5",
        ),
        DeviceProfile(
            id="console_b", display_name="QL1", enabled=True,
            device_type="console", protocol="midi", signal_type="program_change",
            midi_channel=2, ableton_track_aliases=("PGM CHANGE QL1",),
            palette=DevicePalette(base="#63C7D4", accent="#3E9EAC"),
            library="ql1", visibility=DeviceVisibility(), legacy_key="ql1",
        ),
    ))


DEVICE_PALETTE_PRESETS = {
    "Violet": DevicePalette("#C09AF2", "#9B6BD6"),
    "Cyan": DevicePalette("#63C7D4", "#3E9EAC"),
    "Bleu": DevicePalette("#79B8FF", "#397FD1"),
    "Orange": DevicePalette("#FFB067", "#D7782D"),
    "Rose": DevicePalette("#F49BC4", "#C75B8D"),
    "Jaune": DevicePalette("#F4D96B", "#C5A52E"),
    "Rouge": DevicePalette("#F08A8A", "#C64D4D"),
    "Vert": DevicePalette("#83D6A0", "#3E9B62"),
}


def _profile_from_dict(payload: Mapping[str, Any], fallback: Optional[DeviceProfile] = None) -> DeviceProfile:
    def value(name: str, default: Any) -> Any:
        return payload[name] if name in payload else default

    palette_data = payload.get("palette") if isinstance(payload.get("palette"), Mapping) else {}
    visibility_data = payload.get("visibility") if isinstance(payload.get("visibility"), Mapping) else {}
    tx_data = payload.get("tx") if isinstance(payload.get("tx"), Mapping) else {}
    rx_data = payload.get("rx") if isinstance(payload.get("rx"), Mapping) else {}
    base = fallback or DeviceProfile(
        id="", display_name="", enabled=False, device_type="console", protocol="midi",
        signal_type="program_change", midi_channel=None, ableton_track_aliases=(),
        palette=DevicePalette("#FFFFFF", "#808080"), library=None,
        visibility=DeviceVisibility(False, False, False),
    )
    aliases = value("ableton_track_aliases", base.ableton_track_aliases)
    return DeviceProfile(
        id=str(value("id", base.id)),
        display_name=str(value("display_name", base.display_name)),
        enabled=bool(value("enabled", base.enabled)),
        device_type=str(value("device_type", base.device_type)),
        protocol=str(value("protocol", base.protocol)).lower(),
        signal_type=str(value("signal_type", base.signal_type)).lower(),
        midi_channel=value("midi_channel", base.midi_channel),
        ableton_track_aliases=tuple(str(alias) for alias in aliases),
        palette=DevicePalette(
            str(palette_data.get("base", base.palette.base)),
            str(palette_data.get("accent", base.palette.accent)),
        ),
        library=value("library", base.library),
        visibility=DeviceVisibility(
            bool(visibility_data.get("show_control", base.visibility.show_control)),
            bool(visibility_data.get("remote", base.visibility.remote)),
            bool(visibility_data.get("network_manager", base.visibility.network_manager)),
        ),
        legacy_key=value("legacy_key", base.legacy_key),
        tx_enabled=bool(tx_data.get("enabled", base.tx_enabled)),
        rx_enabled=bool(rx_data.get("enabled", base.rx_enabled)),
    )


def device_configuration_from_dict(payload: Mapping[str, Any]) -> DeviceConfiguration:
    """Charge le format devices[] ou adapte doucement un ancien bloc cl5/ql1."""
    defaults = default_device_configuration()
    schema_version = int(payload.get("schema_version", DEVICE_SCHEMA_VERSION))
    if schema_version != DEVICE_SCHEMA_VERSION:
        raise ValueError(f"schema_version {schema_version} non supportée")
    raw_devices = payload.get("devices")
    if isinstance(raw_devices, list):
        profiles = []
        for raw in raw_devices:
            if not isinstance(raw, Mapping):
                continue
            fallback = defaults.by_id(str(raw.get("id") or ""))
            profiles.append(_profile_from_dict(raw, fallback))
    else:
        profiles = []
        for legacy_key in ("cl5", "ql1"):
            fallback = defaults.by_legacy_key(legacy_key)
            legacy = payload.get(legacy_key)
            profiles.append(_profile_from_dict(legacy, fallback) if isinstance(legacy, Mapping) else fallback)
    return DeviceConfiguration(
        schema_version=schema_version,
        profile_id=str(payload.get("profile_id") or defaults.profile_id),
        profile_name=str(payload.get("profile_name") or defaults.profile_name),
        devices=tuple(profile for profile in profiles if profile is not None),
    )


@dataclass(frozen=True)
class DeviceConfigurationLoadResult:
    configuration: DeviceConfiguration
    source: str
    error: Optional[str] = None


class DeviceConfigurationError(ValueError):
    pass


def validate_device_configuration(configuration: DeviceConfiguration) -> None:
    if configuration.schema_version != DEVICE_SCHEMA_VERSION:
        raise DeviceConfigurationError("Version de schéma non supportée")
    ids = [device.id.strip() for device in configuration.devices]
    if any(not device_id for device_id in ids) or len(ids) != len(set(ids)):
        raise DeviceConfigurationError("Chaque ID interne doit être renseigné et unique")
    for protected in ("console_a", "console_b"):
        if protected not in ids:
            raise DeviceConfigurationError(f"Le device historique {protected} doit être conservé")
    color_pattern = re.compile(r"^#[0-9A-Fa-f]{6}$")
    enabled_midi_channels: dict[int, str] = {}
    for device in configuration.devices:
        if not device.display_name.strip():
            raise DeviceConfigurationError(f"{device.id} : nom affiché obligatoire")
        if not color_pattern.fullmatch(device.palette.base) or not color_pattern.fullmatch(device.palette.accent):
            raise DeviceConfigurationError(f"{device.id} : palette invalide")
        if device.protocol == "midi" and not isinstance(device.midi_channel, int):
            raise DeviceConfigurationError(f"{device.id} : canal MIDI obligatoire")
        if device.protocol == "midi" and not 1 <= device.midi_channel <= 16:
            raise DeviceConfigurationError(f"{device.id} : canal MIDI hors plage 1–16")
        aliases = tuple(alias.strip() for alias in device.ableton_track_aliases if alias.strip())
        if device.enabled and device.signal_type == "program_change" and not aliases:
            raise DeviceConfigurationError(f"{device.id} : au moins un alias Ableton est requis")
        if device.enabled and not device.supported:
            raise DeviceConfigurationError(
                f"{device.id} : {device.protocol}/{device.signal_type} n’est pas encore supporté"
            )
        if device.enabled and device.protocol == "midi":
            previous = enabled_midi_channels.get(device.midi_channel)
            if previous is not None:
                raise DeviceConfigurationError(
                    f"{device.id} : collision de canal MIDI avec {previous}"
                )
            enabled_midi_channels[device.midi_channel] = device.id


def _device_configuration_path(path: Optional[Path]) -> Path:
    return Path(path) if path is not None else Path(os.environ.get("CL_DEVICE_CONFIG_PATH", DEFAULT_DEVICE_CONFIG_PATH))


def load_device_configuration_result(path: Optional[Path] = None) -> DeviceConfigurationLoadResult:
    path = _device_configuration_path(path)
    if not path.exists():
        return DeviceConfigurationLoadResult(default_device_configuration(), "default")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(payload, Mapping):
            raise DeviceConfigurationError("la racine doit être un objet")
        configuration = device_configuration_from_dict(payload)
        validate_device_configuration(configuration)
        return DeviceConfigurationLoadResult(configuration, "file")
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as error:
        return DeviceConfigurationLoadResult(
            default_device_configuration(), "default", f"Configuration devices invalide : {error}"
        )


def load_device_configuration(path: Optional[Path] = None) -> DeviceConfiguration:
    """Absence ou fichier invalide : configuration historique sûre, sans écriture disque."""
    return load_device_configuration_result(path).configuration


def save_device_configuration(configuration: DeviceConfiguration,
                              path: Optional[Path] = None) -> None:
    """Valide puis remplace atomiquement devices.json."""
    validate_device_configuration(configuration)
    path = _device_configuration_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(configuration.to_dict(), ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent,
            prefix=f".{path.name}.", suffix=".tmp", delete=False,
        ) as handle:
            temporary_path = Path(handle.name)
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        reloaded = device_configuration_from_dict(json.loads(temporary_path.read_text(encoding="utf-8")))
        validate_device_configuration(reloaded)
        os.replace(temporary_path, path)
        temporary_path = None
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def next_device_id(configuration: DeviceConfiguration) -> str:
    used = {device.id for device in configuration.devices}
    index = 3
    while f"device_{index}" in used:
        index += 1
    return f"device_{index}"


def new_disabled_device(configuration: DeviceConfiguration) -> DeviceProfile:
    return DeviceProfile(
        id=next_device_id(configuration), display_name="Nouveau device", enabled=False,
        device_type="console", protocol="midi", signal_type="program_change",
        midi_channel=3, ableton_track_aliases=("NOUVEAU DEVICE PROGRAM",),
        palette=DEVICE_PALETTE_PRESETS["Bleu"], library=None,
        visibility=DeviceVisibility(), legacy_key=None,
    )


class ProgramChangeSignalHandler:
    """Interface minimale du driver actuel, sans I/O et sans état global."""

    protocol = "midi"
    signal_type = "program_change"

    @staticmethod
    def parse_expected(value: Any) -> Optional[int]:
        return ProgramChangeSignalHandler._program(value)

    @staticmethod
    def parse_returned(value: Any) -> Optional[int]:
        return ProgramChangeSignalHandler._program(value)

    @staticmethod
    def compare(expected: Any, returned: Any) -> bool:
        parsed_expected = ProgramChangeSignalHandler.parse_expected(expected)
        return parsed_expected is not None and parsed_expected == ProgramChangeSignalHandler.parse_returned(returned)

    @staticmethod
    def format_display_value(value: Any) -> str:
        parsed = ProgramChangeSignalHandler._program(value)
        return "—" if parsed is None else str(parsed + 1)

    @staticmethod
    def _program(value: Any) -> Optional[int]:
        try:
            program = int(value)
        except (TypeError, ValueError):
            return None
        return program if 0 <= program <= 127 else None


class DeviceTestBench:
    """État de test isolé : aucune référence à l'état EXPECTED/RETURNED de production."""

    def __init__(self, configuration: DeviceConfiguration):
        self.configuration = configuration
        self._test_state: dict[str, dict[str, Any]] = {}

    def test_send(self, device_id: str, signal: Any) -> dict[str, Any]:
        device = self._supported_device(device_id)
        program = ProgramChangeSignalHandler.parse_expected(signal)
        if program is None:
            raise ValueError("Program Change invalide")
        result = {"device_id": device.id, "midi_channel": device.midi_channel, "midi_program": program}
        self._test_state.setdefault(device.id, {})["sent"] = dict(result)
        return result

    def test_receive(self, device_id: str, signal: Any) -> dict[str, Any]:
        device = self._supported_device(device_id)
        program = ProgramChangeSignalHandler.parse_returned(signal)
        if program is None:
            raise ValueError("Program Change invalide")
        result = {"device_id": device.id, "midi_channel": device.midi_channel, "midi_program": program}
        self._test_state.setdefault(device.id, {})["received"] = dict(result)
        return result

    def test_round_trip(self, device_id: str) -> bool:
        state = self._test_state.get(device_id, {})
        return ProgramChangeSignalHandler.compare(
            (state.get("sent") or {}).get("midi_program"),
            (state.get("received") or {}).get("midi_program"),
        )

    def snapshot(self) -> dict[str, dict[str, Any]]:
        return {device_id: dict(values) for device_id, values in self._test_state.items()}

    def _supported_device(self, device_id: str) -> DeviceProfile:
        device = self.configuration.by_id(device_id)
        if device is None or not device.enabled:
            raise ValueError("device absent ou inactif")
        if not device.supported:
            raise NotImplementedError(f"{device.protocol}/{device.signal_type} non supporté")
        return device
