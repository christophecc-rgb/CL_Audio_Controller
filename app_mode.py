"""Central product capabilities. FULL remains the default.

The selected runtime is resolved before importing any FULL services.
"""
from dataclasses import dataclass
from enum import Enum
from types import MappingProxyType
import os


class AppMode(str, Enum):
    FULL = "FULL"
    LOCAL_LIGHT = "LOCAL_LIGHT"


APP_MODE = AppMode(os.environ.get("CL_APP_MODE", "FULL"))


@dataclass(frozen=True)
class Capabilities:
    mode: AppMode
    showcue_enabled: bool = True
    builder_enabled: bool = True
    ableton_local_enabled: bool = True
    go_enabled: bool = True
    console_enabled: bool = True
    program_change_enabled: bool = True
    ltc_enabled: bool = True
    mtc_enabled: bool = True
    remote_enabled: bool = True
    hot_backup_enabled: bool = True
    network_discovery_enabled: bool = True
    console_feedback_enabled: bool = True
    duration_enabled: bool = True
    scenes_enabled: bool = True
    arrangement_enabled: bool = True


CAPABILITIES = MappingProxyType({
    AppMode.FULL: Capabilities(AppMode.FULL),
    AppMode.LOCAL_LIGHT: Capabilities(
        AppMode.LOCAL_LIGHT,
        console_enabled=False, program_change_enabled=False,
        ltc_enabled=False, mtc_enabled=False, remote_enabled=False,
        hot_backup_enabled=False, network_discovery_enabled=False,
        console_feedback_enabled=False, duration_enabled=False, arrangement_enabled=False,
    ),
})


def capabilities_for(mode=None):
    return CAPABILITIES[AppMode(APP_MODE if mode is None else mode)]


# Light transport volontairement limité aux commandes d'exploitation essentielles.
LOCAL_LIGHT_ACTIONS = ("go", "prev", "next", "goto", "stop", "pause")


def local_light_state(state):
    """Pure projection; scene indices are zero-based, absent scenes are None.

    No console snapshot, clock, file access or transport query is performed.
    Playback describes the controller state, not an audio-start guarantee.
    """
    available = bool(state.get("set_ready", False))
    scenes = state.get("scenes") or {}

    def scene(value):
        return value if available and isinstance(value, int) and value in scenes else None

    current = scene(state.get("playing_scene"))
    prepared = scene(state.get("selected_scene"))
    playing = available and bool(state.get("is_playing", False))
    paused = available and bool(state.get("is_paused", False))
    return {
        "set_available": available,
        "set_generation": int(state.get("set_generation", 0)),
        "current_scene": current,
        "current_scene_name": str(scenes.get(current, "")) if current is not None else "",
        "prepared_scene": prepared,
        "prepared_scene_name": str(scenes.get(prepared, "")) if prepared is not None else "",
        "next_scene": scene(state.get("next_scene")),
        "is_playing": playing,
        "is_paused": paused,
        "allowed_actions": list(LOCAL_LIGHT_ACTIONS) if available else [],
        "state": ("unavailable" if not available else "paused" if paused
                  else "playing" if playing else "ready"),
    }


def common_light_capabilities():
    """Migration target only; does not switch the existing standalone runtime."""
    from dataclasses import replace
    return replace(CAPABILITIES[AppMode.LOCAL_LIGHT], duration_enabled=True, remote_enabled=True)
