"""Configuration générique des devices, sans remplacer les chemins historiques.

La passe 1 expose des profils stables et une couche d'adaptation. Le moteur de
production continue volontairement d'utiliser ses clés ``cl5`` / ``ql1``.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping, Optional


SUPPORTED_PROTOCOLS = frozenset({"midi"})
FUTURE_PROTOCOLS = frozenset({"osc"})
SUPPORTED_SIGNAL_TYPES = frozenset({"program_change"})
FUTURE_SIGNAL_TYPES = frozenset({"control_change", "note", "sysex", "osc_message"})

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
    profile_id: str = "default"
    profile_name: str = "Configuration par défaut"
    devices: tuple[DeviceProfile, ...] = field(default_factory=tuple)

    def by_id(self, device_id: str) -> Optional[DeviceProfile]:
        return next((device for device in self.devices if device.id == device_id), None)

    def by_legacy_key(self, legacy_key: str) -> Optional[DeviceProfile]:
        return next((device for device in self.devices if device.legacy_key == legacy_key), None)

    def to_dict(self) -> dict[str, Any]:
        return {
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
        profile_id=str(payload.get("profile_id") or defaults.profile_id),
        profile_name=str(payload.get("profile_name") or defaults.profile_name),
        devices=tuple(profile for profile in profiles if profile is not None),
    )


def load_device_configuration(path: Path = DEFAULT_DEVICE_CONFIG_PATH) -> DeviceConfiguration:
    """Absence ou fichier invalide : configuration historique sûre, sans écriture disque."""
    try:
        payload = json.loads(Path(path).read_text(encoding="utf-8"))
        if not isinstance(payload, Mapping):
            raise ValueError("la racine doit être un objet")
        return device_configuration_from_dict(payload)
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return default_device_configuration()


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
