#!/usr/bin/env python3
# Ableton Web Remote - version synchro Ableton directe, sans scan de temps
# Flask + python-osc + AbletonOSC
#
# Correctifs :
# - /status ne lance aucun appel OSC bloquant.
# - Tous les scans / calculs de temps restant sont supprimés.
# - La scène sélectionnée et la scène en cours suivent aussi les changements
#   faits directement dans Ableton.
#
# Ports AbletonOSC par défaut :
# - AbletonOSC reçoit sur 11000
# - ce script reçoit les réponses sur 11001

import json
import hmac
import re
import socket
import threading
import multiprocessing
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, Optional, Tuple
from pathlib import Path

from flask import Flask, jsonify, render_template, request, send_from_directory
from build_identity import BUILD_ID, IDENTITY_PROTOCOL_VERSION, SERVICE_NAME
from ableton_targets import load_target

multiprocessing.freeze_support()

import os
import signal
import webbrowser
import threading
import multiprocessing
import socket

from pythonosc import udp_client
from osc_transport import OSCTransport
from ltc_receiver import LTCReceiver, LTC_BIND_HOST, LTC_PORT

SERVER_STARTED_MONOTONIC = time.monotonic()
SERVER_STARTED_AT = time.time()
SERVER_INSTANCE_ID = str(uuid.uuid4())
LAUNCH_ID = os.environ.get("CL_AUDIO_LAUNCH_ID")
EXPECTED_BUILD_ID = os.environ.get("CL_AUDIO_EXPECTED_BUILD_ID")
SHUTDOWN_TOKEN = os.environ.get("CL_AUDIO_SHUTDOWN_TOKEN")

if EXPECTED_BUILD_ID and EXPECTED_BUILD_ID != BUILD_ID:
    raise RuntimeError(
        f"Build serveur incompatible: attendu={EXPECTED_BUILD_ID!r}, embarque={BUILD_ID!r}"
    )

print(json.dumps({
    "source": "ServerIdentity",
    "event": "server-instance-created",
    "launchId": LAUNCH_ID,
    "serverInstanceId": SERVER_INSTANCE_ID,
    "buildId": BUILD_ID,
    "serverProcessId": os.getpid(),
    "startedAt": SERVER_STARTED_AT,
}, ensure_ascii=False, sort_keys=True), flush=True)

# Crossfader Ableton via Max for Live OSC, zéro MIDI.

# LTC Display → UDP 63123 → /status → ab.html.
# Le listener écoute toutes les interfaces; LTCReceiver filtre strictement la
# source selon le profil Ableton actif (loopback en Local, cible en Distant).
LTC_UDP_IP = LTC_BIND_HOST
LTC_UDP_PORT = LTC_PORT

# Max for Live Crossfader Bridge
M4L_IP = "127.0.0.1"
M4L_PORT = 9001
m4l_client = udp_client.SimpleUDPClient(M4L_IP, M4L_PORT)

# Compatibilité diagnostic ancienne interface — non utilisé.
MIDI_PORT_EXACT = "M4L_OSC_9001"
MIDI_CHANNEL = 0
MIDI_CC = None
mido = None



# Réglages de scan pour retrouver la scène réellement en lecture.
# Aucun scan de durée/temps de clip n’est effectué.
MAX_TRACKS_TO_SCAN = 32
SCAN_PLAYING_SCENE_FROM_TRACKS = True
PLAYING_SCAN_SECONDS = 2.0
TRACK_COUNT_CACHE_SECONDS = 10.0
CHECK_MUTE_DURING_PLAYING_SCAN = False

# Réglages anti-gel / stabilité
BACKGROUND_REFRESH_SECONDS = 0.25
FULL_REFRESH_SECONDS = 1.0
OSC_TIMEOUT = 0.06
OSC_BOOTSTRAP_DRAIN_SECONDS = 0.25
BOOTSTRAP_TRANSACTION_TIMEOUT = 2.0
BOOTSTRAP_RETRY_PAUSE_SECONDS = 0.02

# Diagnostic ciblé des changements de Set, silencieux par défaut.
# Activer ponctuellement avec CL_AUDIO_GENERATION_DEBUG=1.
GENERATION_DEBUG = os.environ.get("CL_AUDIO_GENERATION_DEBUG", "0").strip().lower() in (
    "1", "true", "on", "yes",
)


app = Flask(__name__)
ableton_target = load_target()
ableton_transport = OSCTransport(
    host=ableton_target.host,
    send_port=ableton_target.send_port,
    reply_port=ableton_target.reply_port,
)

KEYBOARD_LOG_PATH = Path("/private/tmp/CL_Audio_Controller_keyboard.log")
keyboard_log_lock = threading.Lock()
keyboard_diagnostic_session = f"server-{os.getpid()}-{int(time.time())}"
BOOTSTRAP_LOG_PATH = Path("/private/tmp/CL_Audio_Controller_bootstrap.log")
bootstrap_log_lock = threading.Lock()


def write_keyboard_diagnostic(record: Dict[str, Any]) -> None:
    """Écrit une trace clavier temporaire sans intervenir dans son traitement."""
    payload = dict(record)
    payload.setdefault("timestamp", int(time.time() * 1000))
    payload.setdefault("session", keyboard_diagnostic_session)
    line = json.dumps(payload, ensure_ascii=False, sort_keys=True, default=str)
    print(f"[KEYBOARD] {line}", flush=True)
    try:
        with keyboard_log_lock:
            with KEYBOARD_LOG_PATH.open("a", encoding="utf-8") as handle:
                handle.write(line + "\n")
    except Exception as exc:
        print(f"[KEYBOARD] écriture impossible: {exc}", flush=True)


def write_bootstrap_diagnostic(event: str, **details: Any) -> None:
    """Journal temporaire en lecture seule du cycle OSC et du bootstrap."""
    payload = {
        "timestamp": int(time.time() * 1000),
        "source": "BootstrapDiagnostic",
        "event": event,
        "processId": os.getpid(),
        "serverInstanceId": SERVER_INSTANCE_ID,
        **details,
    }
    line = json.dumps(payload, ensure_ascii=False, sort_keys=True, default=str)
    print(f"[BOOTSTRAP] {line}", flush=True)
    try:
        with bootstrap_log_lock:
            with BOOTSTRAP_LOG_PATH.open("a", encoding="utf-8") as handle:
                handle.write(line + "\n")
    except Exception as exc:
        print(f"[BOOTSTRAP] écriture impossible: {exc}", flush=True)


BOOTSTRAP_IMPLEMENTATION = "transactional-initial-bootstrap"

write_bootstrap_diagnostic(
    "bootstrap-implementation",
    implementation=BOOTSTRAP_IMPLEMENTATION,
)
write_bootstrap_diagnostic(
    "server-started",
    launchId=LAUNCH_ID,
    buildId=BUILD_ID,
    bootstrapStep="démarrage du serveur",
)

# -----------------------------------------------------------------------------
# Arrangement / conduite spectacle
# -----------------------------------------------------------------------------
# Repères Arrangement / Cue Points
# Priorité : lecture directe des cue points du Set Ableton via AbletonOSC.
# Repli : arrangement_markers.json si la version AbletonOSC ne répond pas.
ARRANGEMENT_MARKERS_FILE = "arrangement_markers.json"
CUE_POINTS_REFRESH_SECONDS = 3.0
DEFAULT_ARRANGEMENT_MARKERS = [
    {"name": "00 - Préshow", "time": 0},
    {"name": "01 - Ouverture", "time": 60},
    {"name": "02 - Tableau 1", "time": 180},
    {"name": "03 - Tableau 2", "time": 300},
    {"name": "04 - Entracte", "time": 600},
    {"name": "05 - Final", "time": 900},
    {"name": "NOIR / Sécurité", "time": 1200},
]




CL_AUDIO_REMOTE_SUBTITLES = {
    "/": "Session · Ableton Web Remote",
    "/ab": "Télécommande AB · Ableton Web Remote",
    "/arrangement": "Arrangement · Ableton Web Remote",
}

CL_AUDIO_REMOTE_CSS = """
<style id="cl-audio-show-control-style">
  .cl-audio-shell {
    width: min(100%, 312px);
    margin: 0 auto 0 auto;
    padding: 1px 6px 0 6px;
    color: #f8fafc;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", sans-serif;
  }

  .cl-audio-hero {
    display: none;
  }

  .cl-audio-header {
    text-align: center;
    padding: 1px 0 0 0;
    line-height: 1;
  }

  .cl-audio-title-line {
    display: flex;
    justify-content: center;
    align-items: center;
    gap: 3px;
  }

  .cl-audio-brand-dot {
    width: 3px;
    height: 3px;
    border-radius: 50%;
    background: rgba(248,250,252,.42);
    box-shadow: none;
  }

  .cl-audio-header h1 {
    margin: 0;
    font-size: 7px;
    letter-spacing: .02em;
    line-height: .95;
    font-weight: 700;
    color: rgba(248,250,252,.58);
  }

  .cl-audio-subtitle {
    margin-top: 0;
    color: rgba(248,250,252,.38);
    font-size: 4px;
    letter-spacing: .03em;
    line-height: .9;
    text-transform: uppercase;
  }

  @media (max-width: 430px) {
    .cl-audio-shell {
      padding-left: 10px;
      padding-right: 10px;
    }

    .cl-audio-hero {
      display: none;
    }

    .cl-audio-header h1 {
      font-size: 7px;
    }
  }
</style>
"""


def decorate_remote_page_html(response):
    """Installe le shell V2 commun autour des trois modules de la télécommande."""
    if request.path not in CL_AUDIO_REMOTE_SUBTITLES:
        return response

    content_type = response.headers.get("Content-Type", "")
    if "text/html" not in content_type.lower():
        return response

    html = response.get_data(as_text=True)
    if "v2-app" in html:
        return response

    module = {"/": "session", "/ab": "ab", "/arrangement": "arrangement"}[request.path]
    module_label = {"session": "Session", "ab": "A/B", "arrangement": "Arrangement"}[module]
    tabs = "".join(
        f'<a href="{href}" aria-current="page">{label}</a>' if key == module
        else (
            f'<a href="{href}" data-arrangement-link>{label}</a>'
            if key == "arrangement"
            else f'<a href="{href}">{label}</a>'
        )
        for key, href, label in (
            ("session", "/", "Session"),
            ("ab", "/ab", "A/B"),
            ("arrangement", "/arrangement", "Arrangement"),
        )
    )
    header_html = f"""
  <div class="v2-app" data-module="{module}">
    <header class="v2-header">
      <div class="v2-brand">
        <img src="/assets/paradis%20latin.jpg" alt="Paradis Latin Cabaret">
        <div class="v2-brand-copy">
          <div class="v2-brand-title">CL Audio Show Control</div>
          <div class="v2-brand-subtitle">Remote professionnelle · {module_label}</div>
        </div>
      </div>
      <nav class="v2-tabs" aria-label="Modes de la télécommande">{tabs}</nav>
      <div class="v2-health" role="status" aria-live="polite">
        <span class="v2-health-dot" aria-hidden="true"></span>
        <div class="v2-health-copy">
          <div class="v2-health-label" id="v2HealthLabel">Connexion…</div>
          <div class="v2-health-detail" id="v2HealthDetail">Initialisation du retour Ableton</div>
        </div>
      </div>
    </header>
    <div class="v2-workspace">
"""
    footer_html = f"""
    </div>
    <footer class="v2-statusbar" aria-label="CL Audio 2026">
      <div>CL Audio · 2026</div>
    </footer>
  </div>
"""

    if "</head>" in html:
        assets = (
            '<link rel="stylesheet" href="/static/remote-v2.css?v=2.0.4">\n'
            '<script src="/static/remote-v2.js?v=2.0.4" defer></script>\n'
        )
        html = html.replace("</head>", assets + "</head>", 1)
    else:
        html = '<link rel="stylesheet" href="/static/remote-v2.css?v=2.0.4">' + html

    if "<body" in html:
        body_end = html.find(">", html.find("<body"))
        if body_end != -1:
            html = html[:body_end + 1] + header_html + html[body_end + 1:]
    else:
        html = header_html + html

    if "</body>" in html:
        html = html.replace("</body>", footer_html + "\n</body>", 1)
    else:
        html += footer_html

    response.set_data(html)
    response.headers["Content-Length"] = str(len(response.get_data()))
    return response


@app.after_request
def no_cache(response):
    response = decorate_remote_page_html(response)
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    return response

def parse_scene_duration_seconds(name: Any) -> Optional[float]:
    """Lit une durée finale mm:ss dans les métadonnées d'un nom de scène."""
    match = re.search(r"(?:^|[;|\s])(\d{1,2}):([0-5]\d)\s*$", str(name or "").strip())
    if not match:
        return None
    return float(int(match.group(1)) * 60 + int(match.group(2)))


state: Dict[str, Any] = {
    "current_set_id": None,
    "current_set_name": "",
    "set_generation": 0,
    "set_ready": False,
    "current_scene": None,
    "next_scene": None,
    "has_show_started": False,
    "selected_scene": 0,
    "selected_scene_name": "—",
    "scenes": {},
    "is_paused": False,
    "play_mode": "stopped",
    "playing_scene": -1,
    "playing_scene_name": "—",
    "last_fired_scene": -1,
    "last_fired_scene_name": "—",
    "is_playing": False,
    "scene_duration_seconds": None,
    "remaining_seconds": None,
    "playback_deadline": None,
    "connected": False,
    "bootstrap_step": "attente de /live/startup ou de Song.file_path",
    "bootstrap_running": False,
    "bootstrap_generation": None,
    "last_successful_bootstrap": None,
    "pending_request": None,
    "message": "Démarrage…",
    "sync_source": "Ableton",
    "arrangement_time": 0.0,
    "last_arrangement_time": 0.0,
    "arrangement_time_label": "00:00",
    "arrangement_marker": "—",
    "arrangement_markers": [],
    "arrangement_markers_source": "JSON",
    "ltc_timecode": "--:--:--:--",
    "timecode": "--:--:--:--",
    "ltc": "--:--:--:--",
    "smpte": "--:--:--:--",
    "ltc_connected": False,
    "ltc_listener_active": False,
    "ltc_last_received_at": None,
    "ltc_last_source": None,
    "ltc_rejected_count": 0,
    "ltc_last_rejection_reason": None,
    "ltc_last_rejected_source": None,
}


def set_set_ready_locked(new_value: bool, reason: str, function_name: str) -> None:
    """Modifie set_ready en traçant l'instance et la génération concernées."""
    old_value = bool(state.get("set_ready", False))
    normalized_value = bool(new_value)
    state["set_ready"] = normalized_value
    if old_value == normalized_value:
        return
    write_bootstrap_diagnostic(
        "set-ready-changed",
        oldValue=old_value,
        newValue=normalized_value,
        reason=reason,
        function=function_name,
        setGeneration=int(state.get("set_generation", 0)),
    )
    write_keyboard_diagnostic({
        "source": "ServerState",
        "event": "set-ready-changed",
        "oldValue": old_value,
        "newValue": normalized_value,
        "reason": reason,
        "function": function_name,
        "setGeneration": int(state.get("set_generation", 0)),
        "stateObjectId": id(state),
        "processId": os.getpid(),
    })


def set_connected_locked(new_value: bool, reason: str, function_name: str) -> None:
    old_value = bool(state.get("connected", False))
    normalized_value = bool(new_value)
    state["connected"] = normalized_value
    if old_value != normalized_value:
        write_bootstrap_diagnostic(
            "connected-changed",
            oldValue=old_value,
            newValue=normalized_value,
            reason=reason,
            function=function_name,
            setGeneration=int(state.get("set_generation", 0)),
        )


def set_bootstrap_step_locked(step: str, reason: str = "") -> None:
    old_step = str(state.get("bootstrap_step") or "")
    state["bootstrap_step"] = step
    if old_step != step:
        write_bootstrap_diagnostic(
            "bootstrap-step-changed",
            oldStep=old_step,
            newStep=step,
            reason=reason,
            setGeneration=int(state.get("set_generation", 0)),
        )


write_keyboard_diagnostic({
    "source": "ServerState",
    "event": "state-created",
    "oldValue": None,
    "newValue": bool(state.get("set_ready", False)),
    "reason": "initialisation du module app.py",
    "function": "module initialization",
    "setGeneration": int(state.get("set_generation", 0)),
    "stateObjectId": id(state),
    "processId": os.getpid(),
})


def start_ltc_udp_listener():
    """Lance le récepteur LTC filtré sans intervenir dans AbletonOSC."""
    last_print = 0.0

    def update_diagnostics(values: Dict[str, Any]) -> None:
        with lock:
            state.update(values)

    def publish(timecode: str, source_ip: str, received_at: float) -> None:
        nonlocal last_print
        with lock:
            state["ltc_timecode"] = timecode
            state["timecode"] = timecode
            state["ltc"] = timecode
            state["smpte"] = timecode
        now = time.time()
        if not last_print or now - last_print > 0.5:
            print(f"LTC -> {timecode} source={source_ip}", flush=True)
            last_print = now

    receiver = LTCReceiver(
        target_provider=lambda: ableton_target,
        publish=publish,
        diagnostics=update_diagnostics,
    )
    print(f"LTC UDP listener actif sur {LTC_UDP_IP}:{LTC_UDP_PORT}", flush=True)
    if not receiver.serve_forever():
        print(f"LTC UDP désactivé : impossible d'écouter {LTC_UDP_IP}:{LTC_UDP_PORT}", flush=True)

# -----------------------------------------------------------------------------
# Transport state normalization helper
# -----------------------------------------------------------------------------
def normalize_transport_state_locked():
    """Garde les états UI Session/Arrangement cohérents.

    Règle centrale : un seul mode visuel jaune à la fois.
    play_mode est la source de vérité UI.
    is_playing est global à Ableton et ne doit pas décider seul du mode.
    """
    is_playing = bool(state.get("is_playing", False))
    play_mode = str(state.get("play_mode", "stopped") or "stopped")

    # Un seul mode visuel actif : si l'Arrangement est le mode courant,
    # l'indicateur Session doit être éteint, même si Ableton remonte encore
    # un ancien playing_slot_index.
    if play_mode == "arrangement":
        state["playing_scene"] = -1
        state["playing_scene_name"] = "—"
        state["last_fired_scene"] = -1
        state["last_fired_scene_name"] = "—"

    # Important : is_playing est l'état global d'Ableton.
    # Une scène Session peut jouer avec is_playing=True, sans que l'Arrangement soit en lecture.
    # Donc on ne force JAMAIS play_mode="arrangement" à partir de is_playing seul.
    if is_playing and play_mode == "paused":
        state["play_mode"] = "stopped"
        state["is_paused"] = False

    if not is_playing and play_mode == "arrangement" and not bool(state.get("is_paused", False)):
        state["play_mode"] = "stopped"

lock = threading.RLock()
scene_transaction_lock = threading.Lock()

completed_go_requests: Dict[Tuple[int, str], Dict[str, Any]] = {}
last_full_refresh = 0.0
last_playing_scan = 0.0
_track_count_cache: Tuple[float, int] = (0.0, MAX_TRACKS_TO_SCAN)
_cue_points_cache: Tuple[float, list, str] = (0.0, [], "JSON")
_bootstrap_generation: Optional[int] = None
_NOT_RECEIVED = object()


@dataclass
class BootstrapTransaction:
    """Instantané privé accumulé avant l'unique publication d'un Live Set."""

    generation: int
    started_at: float
    deadline: float
    target_identity: Tuple[str, int, int]
    file_path: Any = _NOT_RECEIVED
    song_name: Any = _NOT_RECEIVED
    selected_scene: Any = _NOT_RECEIVED
    scene_names: Any = _NOT_RECEIVED
    confirmed_file_path: Any = _NOT_RECEIVED
    completed: bool = False
    cancelled: bool = False
    cancel_reason: str = ""
    attempts: Dict[str, int] = field(default_factory=dict)

    def received(self, field_name: str) -> bool:
        return getattr(self, field_name) is not _NOT_RECEIVED

    def missing(self) -> list:
        return [
            field_name
            for field_name in ("file_path", "song_name", "selected_scene", "scene_names")
            if not self.received(field_name)
        ]

    def ready_to_confirm(self) -> bool:
        return not self.missing()

    def complete(self) -> bool:
        return self.ready_to_confirm() and self.received("confirmed_file_path")


_bootstrap_transaction: Optional[BootstrapTransaction] = None


def state_snapshot_locked() -> Dict[str, Any]:
    """Publie atomiquement l'identité et la génération avec chaque état HTTP."""
    snapshot = dict(state)
    snapshot["set_generation"] = int(state.get("set_generation", 0))
    snapshot["current_set_id"] = state.get("current_set_id")
    snapshot["generation_debug"] = GENERATION_DEBUG
    snapshot["state_object_id"] = id(state)
    snapshot["server_process_id"] = os.getpid()
    snapshot["service"] = SERVICE_NAME
    snapshot["identity_protocol_version"] = IDENTITY_PROTOCOL_VERSION
    snapshot["launch_id"] = LAUNCH_ID
    snapshot["server_instance_id"] = SERVER_INSTANCE_ID
    snapshot["build_id"] = BUILD_ID
    snapshot["started_at"] = SERVER_STARTED_AT
    snapshot["uptime_ms"] = int((time.monotonic() - SERVER_STARTED_MONOTONIC) * 1000)
    snapshot["ableton_target"] = ableton_target.to_dict()
    snapshot["osc_transport"] = ableton_transport.diagnostics()
    if not snapshot.get("set_ready", False):
        snapshot.update({
            "scenes": {},
            "current_scene": None,
            "next_scene": None,
            "selected_scene_name": "—",
            "playing_scene": -1,
            "playing_scene_name": "—",
            "last_fired_scene": -1,
            "last_fired_scene_name": "—",
            "has_show_started": False,
            "arrangement_marker": "—",
            "arrangement_markers": [],
        })
    return snapshot


def generation_log(event: str, **details: Any) -> None:
    """Trace de diagnostic activable pour les changements de Live Set."""
    if not GENERATION_DEBUG:
        return
    suffix = " ".join(f"{key}={value!r}" for key, value in details.items())
    print(f"[SET_GENERATION] {event}{' ' + suffix if suffix else ''}", flush=True)


def reset_live_set_state_locked(set_id: Optional[str], reason: str) -> int:
    """Ouvre atomiquement une génération et efface tout état propre au Set précédent."""
    global _track_count_cache, _cue_points_cache, _bootstrap_generation

    previous_generation = int(state.get("set_generation", 0))
    previous_set_id = state.get("current_set_id")
    generation = previous_generation + 1
    identity = set_id or f"pending:{generation}"
    state.update({
        "current_set_id": identity,
        "current_set_name": "",
        "set_generation": generation,
        "current_scene": None,
        "next_scene": None,
        "has_show_started": False,
        "selected_scene": 0,
        "selected_scene_name": "—",
        "scenes": {},
        "play_mode": "stopped",
        "playing_scene": -1,
        "playing_scene_name": "—",
        "last_fired_scene": -1,
        "last_fired_scene_name": "—",
        "is_playing": False,
        "is_paused": False,
        "scene_duration_seconds": None,
        "remaining_seconds": None,
        "playback_deadline": None,
        "arrangement_time": 0.0,
        "last_arrangement_time": 0.0,
        "arrangement_time_label": "00:00",
        "arrangement_marker": "—",
        "arrangement_markers": [],
        "message": f"Nouveau Live Set détecté ({reason})",
        "sync_source": "Ableton",
        "bootstrap_running": False,
        "bootstrap_generation": None,
        "pending_request": None,
    })
    set_set_ready_locked(False, reason, "reset_live_set_state_locked")
    ableton_transport.cancel_pending()
    completed_go_requests.clear()
    _bootstrap_generation = None
    _track_count_cache = (0.0, MAX_TRACKS_TO_SCAN)
    _cue_points_cache = (0.0, [], "JSON")
    generation_log(
        "new_generation",
        reason=reason,
        previous_generation=previous_generation,
        generation=generation,
        previous_set_id=previous_set_id,
        current_set_id=identity,
    )
    return generation


def generation_is_current(expected_generation: int) -> bool:
    with lock:
        return int(state.get("set_generation", 0)) == int(expected_generation)


def osc_reply(address, *args):
    if address == "/live/startup":
        write_bootstrap_diagnostic(
            "live-startup-received",
            setGeneration=int(state.get("set_generation", 0)),
        )
        generation_log("startup_received")
        with lock:
            generation = reset_live_set_state_locked(None, "startup")
            set_bootstrap_step_locked("attente de Song.file_path", "/live/startup reçu")
        start_live_set_bootstrap(generation)
        return
    generation_log("orphan_reply_ignored", address=address)


ableton_transport.set_unsolicited_handler(osc_reply)


def apply_osc_response_locked(address: str, args: Tuple[Any, ...], expected_generation: int) -> None:
    """Applique une réponse uniquement au traitement qui l'a demandée."""
    if int(state.get("set_generation", 0)) != int(expected_generation):
        return

    if address == "/live/view/get/selected_scene" and args:
        state["selected_scene"] = int(args[0])
        state["next_scene"] = int(args[0])

    elif address == "/live/scene/get/name" and len(args) >= 2:
        scene_index = int(args[0])
        name = str(args[1])
        state["scenes"][scene_index] = name
        if scene_index == state.get("selected_scene"):
            state["selected_scene_name"] = name
        if state.get("has_show_started") and scene_index == state.get("playing_scene"):
            state["playing_scene_name"] = name
            state["current_scene"] = scene_index
        if state.get("has_show_started") and scene_index == state.get("last_fired_scene"):
            state["last_fired_scene_name"] = name

    elif address == "/live/song/get/is_playing" and args:
        raw = args[0]
        playing = (
            raw.strip().lower() not in ("0", "false", "off", "no", "")
            if isinstance(raw, str)
            else bool(raw)
        )
        state["is_playing"] = playing
        if playing:
            state["is_paused"] = False
        elif state.get("play_mode") == "arrangement":
            state["is_paused"] = True
        normalize_transport_state_locked()


def start_osc_server():
    write_bootstrap_diagnostic(
        "osc-socket-opened",
        bindAddress="0.0.0.0",
        returnPort=ableton_transport.reply_port,
        abletonAddress=ableton_transport.host,
        abletonPort=ableton_transport.send_port,
    )
    print(f"OSC reply server listening on 0.0.0.0:{ableton_transport.reply_port}")
    ableton_transport.serve_forever()


def send(address: str, *args):
    ableton_transport.send(address, *args)

def show_session_view():
    for address in (
        "/live/application/view/show_view",
        "/live/app/view/show_view",
        "/live/view/show_view",
    ):
        send(address, "Session")
        send(address, "Session View")

def show_arrangement_view():
    for address in (
        "/live/application/view/show_view",
        "/live/app/view/show_view",
        "/live/view/show_view",
    ):
        send(address, "Arranger")
        send(address, "Arrangement")
        send(address, "Arrangement View")


def _query_with_query_lock_held(
    address: str,
    *args,
    timeout=OSC_TIMEOUT,
    expected_generation: Optional[int] = None,
    allow_during_bootstrap: bool = False,
    apply_response: bool = True,
):
    """
    Requête OSC protégée :
    - une seule requête à la fois pour éviter les réponses croisées ;
    - timeout court pour éviter de bloquer Flask.
    """
    if expected_generation is None:
        with lock:
            expected_generation = int(state.get("set_generation", 0))

    with lock:
        bootstrap_diagnostic = bool(allow_during_bootstrap and not state.get("set_ready", False))

    if not generation_is_current(expected_generation):
        if bootstrap_diagnostic:
            write_bootstrap_diagnostic(
                "bootstrap-query-interrupted",
                address=address,
                reason="génération périmée avant envoi",
                expectedGeneration=expected_generation,
            )
        generation_log(
            "async_discarded",
            address=address,
            expected_generation=expected_generation,
            current_generation=state.get("set_generation"),
            phase="before_send",
        )
        return None
    with lock:
        if not state.get("set_ready", False) and not allow_during_bootstrap:
            generation_log(
                "async_discarded",
                address=address,
                expected_generation=expected_generation,
                phase="set_not_ready",
            )
            return None
        sent_at = time.time()
        if bootstrap_diagnostic:
            state["pending_request"] = {
                "address": address,
                "arguments": list(args),
                "generation": int(expected_generation),
                "sent_at": sent_at,
                "timeout_ms": int(float(timeout) * 1000),
            }

    if bootstrap_diagnostic:
        write_bootstrap_diagnostic(
            "bootstrap-query-sent",
            address=address,
            arguments=list(args),
            expectedGeneration=expected_generation,
            timeoutMs=int(float(timeout) * 1000),
        )
    t0 = time.time()
    payload = ableton_transport.query_locked(
        address,
        *args,
        timeout=timeout,
        context={
            "generation": int(expected_generation),
            "allow_during_bootstrap": bool(allow_during_bootstrap),
            "apply_response": bool(apply_response),
        },
    )
    with lock:
        if bootstrap_diagnostic:
            state["pending_request"] = None
        if payload is not None and generation_is_current(expected_generation):
            if apply_response:
                apply_osc_response_locked(address, payload, expected_generation)
            if bootstrap_diagnostic:
                write_bootstrap_diagnostic(
                    "bootstrap-response-received",
                    address=address,
                    arguments=list(payload),
                    setGeneration=int(state.get("set_generation", 0)),
                )
                write_bootstrap_diagnostic(
                    "bootstrap-query-completed",
                    address=address,
                    response=list(payload),
                    expectedGeneration=expected_generation,
                    elapsedMs=int((time.time() - t0) * 1000),
                )
            return payload

    if bootstrap_diagnostic:
        if generation_is_current(expected_generation):
            write_bootstrap_diagnostic(
                "bootstrap-query-timeout",
                address=address,
                reason="aucune réponse compatible reçue avant expiration",
                expectedGeneration=expected_generation,
                timeoutMs=int(float(timeout) * 1000),
            )
        else:
            write_bootstrap_diagnostic(
                "bootstrap-query-interrupted",
                address=address,
                reason="requête active invalidée ou génération modifiée",
                expectedGeneration=expected_generation,
            )
    return None


def query(
    address: str,
    *args,
    timeout=OSC_TIMEOUT,
    expected_generation: Optional[int] = None,
    allow_during_bootstrap: bool = False,
    apply_response: bool = True,
):
    """Exécute une requête OSC corrélée, sérialisée avec les transactions de scène."""
    with ableton_transport.serialized_queries():
        return _query_with_query_lock_held(
            address,
            *args,
            timeout=timeout,
            expected_generation=expected_generation,
            allow_during_bootstrap=allow_during_bootstrap,
            apply_response=apply_response,
        )


def safe_float(value) -> Optional[float]:
    try:
        return float(value)
    except Exception:
        return None


def get_track_count(expected_generation: Optional[int] = None) -> int:
    """Retourne le nombre de pistes Ableton, avec cache pour éviter de ralentir le suivi."""
    global _track_count_cache
    if expected_generation is None:
        with lock:
            expected_generation = int(state.get("set_generation", 0))

    now = time.time()
    cached_at, cached_value = _track_count_cache
    if now - cached_at < TRACK_COUNT_CACHE_SECONDS and cached_value > 0:
        return min(int(cached_value), MAX_TRACKS_TO_SCAN)

    res = query(
        "/live/song/get/num_tracks",
        expected_generation=expected_generation,
    )
    if res:
        for item in list(res)[::-1]:
            value = safe_float(item)
            if value is not None and value > 0:
                count = min(int(value), MAX_TRACKS_TO_SCAN)
                with lock:
                    if (
                        int(state.get("set_generation", 0)) != int(expected_generation)
                        or not state.get("set_ready", False)
                    ):
                        return min(int(cached_value or MAX_TRACKS_TO_SCAN), MAX_TRACKS_TO_SCAN)
                    _track_count_cache = (now, count)
                return count

    return min(int(cached_value or MAX_TRACKS_TO_SCAN), MAX_TRACKS_TO_SCAN)


def is_track_enabled(track_index: int, expected_generation: Optional[int] = None) -> bool:
    """True si la piste peut servir à détecter la scène en lecture.

    AbletonOSC renvoie généralement mute=True quand la piste est coupée.
    Si la requête mute ne répond pas, on garde la piste pour ne pas rater un playback.
    """
    res = query(
        "/live/track/get/mute",
        track_index,
        expected_generation=expected_generation,
    )
    if not res:
        return True

    value = None
    for item in list(res)[::-1]:
        if isinstance(item, bool):
            value = item
            break
        f = safe_float(item)
        if f is not None:
            value = bool(int(f))
            break

    if value is None:
        return True

    muted = bool(value)
    return not muted


def format_time_label(seconds: float) -> str:
    seconds = max(0, int(float(seconds or 0)))
    minutes, secs = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours:02d}:{minutes:02d}:{secs:02d}"
    return f"{minutes:02d}:{secs:02d}"


def parse_cue_points_response(args):
    """Transforme la réponse AbletonOSC /live/song/get/cue_points en repères.

    Documentation AbletonOSC : réponse sous forme name, time, name, time...
    time/current_song_time sont en beats Live, pas en secondes réelles.
    """
    if not args:
        return []
    values = list(args)
    markers = []
    i = 0
    cue_index = 0
    while i < len(values):
        name = None
        pos = None

        # Format attendu : name, time, name, time...
        if i + 1 < len(values) and safe_float(values[i + 1]) is not None:
            name = str(values[i]).strip() or f"Repère {cue_index + 1}"
            pos = safe_float(values[i + 1])
            i += 2
        # Format alternatif défensif : index, name, time...
        elif i + 2 < len(values) and safe_float(values[i]) is not None and safe_float(values[i + 2]) is not None:
            name = str(values[i + 1]).strip() or f"Repère {cue_index + 1}"
            pos = safe_float(values[i + 2])
            i += 3
        else:
            i += 1
            continue

        if pos is None:
            continue
        markers.append({
            "name": name,
            "time": max(0.0, float(pos)),
            "cue_index": cue_index,
            "source": "ableton"
        })
        cue_index += 1

    markers.sort(key=lambda x: x["time"])
    for idx, marker in enumerate(markers):
        marker["cue_index"] = idx
        marker["label"] = format_time_label(marker["time"])
    return markers


def get_live_cue_points(force: bool = False, expected_generation: Optional[int] = None):
    """Lit les Locators/Cue Points du Set Ableton via AbletonOSC.

    Si AbletonOSC ne répond pas, on garde un cache court, puis on repasse au JSON.
    """
    global _cue_points_cache
    if expected_generation is None:
        with lock:
            expected_generation = int(state.get("set_generation", 0))
    with lock:
        if not state.get("set_ready", False):
            return [], "STALE"

    now = time.time()
    cached_at, cached_markers, cached_source = _cue_points_cache
    if not force and cached_markers and now - cached_at < CUE_POINTS_REFRESH_SECONDS:
        return cached_markers, cached_source

    try:
        res = query(
            "/live/song/get/cue_points",
            timeout=0.12,
            expected_generation=expected_generation,
        )
        markers = parse_cue_points_response(res)
        if markers:
            with lock:
                if (
                    int(state.get("set_generation", 0)) != int(expected_generation)
                    or not state.get("set_ready", False)
                ):
                    return [], "STALE"
                _cue_points_cache = (now, markers, "Ableton Set")
            return markers, "Ableton Set"
    except Exception as e:
        print("Erreur lecture cue points AbletonOSC :", e, flush=True)

    return [], "JSON"


def load_arrangement_markers(force_live: bool = False, expected_generation: Optional[int] = None):
    if expected_generation is None:
        with lock:
            expected_generation = int(state.get("set_generation", 0))
    with lock:
        if (
            int(state.get("set_generation", 0)) != int(expected_generation)
            or not state.get("set_ready", False)
        ):
            return []

    # 1) Priorité aux repères réellement présents dans le Set Ableton.
    live_markers, source = get_live_cue_points(
        force=force_live,
        expected_generation=expected_generation,
    )
    if live_markers:
        with lock:
            if int(state.get("set_generation", 0)) != int(expected_generation):
                return []
            state["arrangement_markers_source"] = source
        return live_markers

    # 2) Repli local si AbletonOSC ne renvoie pas les cue points.
    path = Path(__file__).with_name(ARRANGEMENT_MARKERS_FILE)
    markers = DEFAULT_ARRANGEMENT_MARKERS
    try:
        if path.exists():
            with path.open("r", encoding="utf-8") as f:
                loaded = json.load(f)
            if isinstance(loaded, list) and loaded:
                markers = loaded
    except Exception as e:
        print("Erreur lecture arrangement_markers.json :", e, flush=True)

    clean = []
    for item in markers:
        try:
            name = str(item.get("name", "Repère")).strip() or "Repère"
            t = max(0.0, float(item.get("time", 0)))
            clean.append({"name": name, "time": t, "label": format_time_label(t), "source": "json"})
        except Exception:
            continue
    clean.sort(key=lambda x: x["time"])
    with lock:
        if (
            int(state.get("set_generation", 0)) != int(expected_generation)
            or not state.get("set_ready", False)
        ):
            return []
        state["arrangement_markers_source"] = "JSON"
    return clean or DEFAULT_ARRANGEMENT_MARKERS


def build_show_from_cached_scenes(spacing_beats: float = 128.0):
    """Crée des locators Arrangement depuis les noms de scènes Session déjà scannés."""
    global _cue_points_cache

    scan_scene_names_async(limit=120, clear_before_scan=False)
    time.sleep(0.3)

    with lock:
        cached = dict(state.get("scenes", {}))

    scene_names = []
    for idx in sorted(cached):
        name = str(cached[idx]).strip()
        if not name:
            continue
        if name.upper().startswith("CL_"):
            continue
        if name.startswith("Scène ") or name.startswith("Scene "):
            continue
        scene_names.append(name)

    if not scene_names:
        return False, "Aucun nom de scène disponible"

    send("/live/song/stop_playing")
    time.sleep(0.1)

    created = 0
    for index, name in enumerate(scene_names):
        beat_time = float(index) * float(spacing_beats)
        send("/live/song/set/current_song_time", beat_time)
        time.sleep(0.08)

        send("/live/song/cue_point/add_or_delete")
        time.sleep(0.08)

        send("/live/song/cue_point/set/name", index, name)
        time.sleep(0.04)
        created += 1

    _cue_points_cache = (0.0, [], "JSON")

    with lock:
        state["message"] = f"{created} locators créés depuis les scènes"
        state["sync_source"] = "Build Show"

    return True, f"{created} locators créés depuis les scènes"

def current_arrangement_marker(seconds: float) -> str:
    with lock:
        markers = list(state.get("arrangement_markers", []))
    current = "—"
    for marker in markers:
        if float(seconds or 0) >= float(marker["time"]):
            current = marker["name"]
        else:
            break
    return current


def refresh_arrangement_time():
    """Suit la position de lecture Arrangement quand AbletonOSC répond."""
    with lock:
        generation = int(state.get("set_generation", 0))
    res = query(
        "/live/song/get/current_song_time",
        timeout=0.035,
        expected_generation=generation,
    )
    if not res:
        return
    value = None
    for item in list(res)[::-1]:
        f = safe_float(item)
        if f is not None:
            value = f
            break
    if value is None:
        return
    with lock:
        if int(state.get("set_generation", 0)) != generation:
            return
        previous_time = float(state.get("arrangement_time", 0.0))

        state["last_arrangement_time"] = previous_time
        state["arrangement_time"] = float(value)
        state["arrangement_time_label"] = format_time_label(value)
        # Ne pas recalculer les cue points ici : cela peut déclencher des appels OSC
        # dans le thread de fond et finir par bloquer /status après quelques minutes.
        # Les repères Arrangement sont rafraîchis uniquement sur demande depuis les actions.
        state["arrangement_marker"] = state.get("arrangement_marker", "—")

        # Si la tête Arrangement avance réellement, on considère
        # l'Arrangement comme en lecture même si is_playing
        # n'est pas correctement remonté par AbletonOSC.
        if abs(float(value) - previous_time) > 0.01:
            # Le temps Arrangement peut avancer pendant une lecture Session.
            # On ne déclare l'Arrangement actif que si une commande Arrangement
            # l'a explicitement mis dans ce mode.
            if state.get("play_mode") == "arrangement":
                state["is_playing"] = True
                state["is_paused"] = False

        normalize_transport_state_locked()


def set_arrangement_time(seconds: float, label: str = ""):
    seconds = max(0.0, float(seconds))
    # Adresse standard AbletonOSC pour déplacer la tête de lecture Arrangement.
    send("/live/song/set/current_song_time", seconds)
    with lock:
        state["arrangement_time"] = seconds
        state["arrangement_time_label"] = format_time_label(seconds)
        state["arrangement_marker"] = label or current_arrangement_marker(seconds)
        state["message"] = f"Arrangement : {state['arrangement_marker']}"
        state["sync_source"] = "Arrangement"


def _first_text_value(response: Optional[Tuple[Any, ...]]) -> str:
    if not response:
        return ""
    for value in reversed(response):
        if value is not None:
            return str(value).strip()
    return ""


def refresh_live_set_identity(expected_generation: Optional[int] = None) -> Optional[int]:
    """Vérifie l'identité du Set pendant le rafraîchissement normal.

    /live/startup donne la réinitialisation immédiate. Cette comparaison permanente
    de file_path constitue la seconde source de détection si l'événement est perdu.
    """
    if expected_generation is None:
        with lock:
            expected_generation = int(state.get("set_generation", 0))

    # Le bootstrap confirme lui-même file_path au début et à la fin de sa
    # transaction. Le cycle normal ne doit pas intercaler une seconde série de
    # lectures pendant cette courte fenêtre.
    with lock:
        transaction = _bootstrap_transaction
        if (
            transaction is not None
            and transaction.generation == int(expected_generation)
            and not transaction.completed
            and not transaction.cancelled
        ):
            return int(expected_generation)

    file_path_response = query(
        "/live/song/get/file_path",
        timeout=0.08,
        expected_generation=expected_generation,
        allow_during_bootstrap=True,
        apply_response=False,
    )
    file_path_available = file_path_response is not None
    file_path = _first_text_value(file_path_response)
    if not generation_is_current(expected_generation):
        return None

    set_name_response = query(
        "/live/song/get/name",
        timeout=0.06,
        expected_generation=expected_generation,
        allow_during_bootstrap=True,
        apply_response=False,
    )
    set_name_available = set_name_response is not None
    set_name = _first_text_value(set_name_response)
    if not generation_is_current(expected_generation):
        return None

    confirmation_response = query(
        "/live/song/get/file_path",
        timeout=0.08,
        expected_generation=expected_generation,
        allow_during_bootstrap=True,
        apply_response=False,
    )
    if confirmation_response is None or not generation_is_current(expected_generation):
        return None
    confirmed_file_path = _first_text_value(confirmation_response)
    if confirmed_file_path != file_path:
        generation_log(
            "identity_confirmation_mismatch",
            first=file_path,
            second=confirmed_file_path,
            generation=expected_generation,
        )
        return None

    with lock:
        current_id = state.get("current_set_id")
        if current_id is None:
            generation = reset_live_set_state_locked(file_path or None, "initial identity")
            if not file_path:
                state["current_set_id"] = f"unsaved:{generation}"
            state["current_set_name"] = set_name
            return generation

        pending = str(current_id).startswith("pending:")
        observed_id = file_path or (f"unsaved:{expected_generation}" if pending else str(current_id))

        if pending:
            state["current_set_id"] = observed_id
            state["current_set_name"] = set_name
            return int(state["set_generation"])

        current_is_temporary = str(current_id).startswith("unsaved:")
        identity_changed = (
            file_path_available
            and (
                (bool(file_path) and file_path != current_id)
                or (not file_path and not current_is_temporary)
            )
        )
        if identity_changed:
            generation_log(
                "file_path_changed",
                previous_set_id=current_id,
                observed_set_id=file_path or "<unsaved>",
                generation=expected_generation,
            )
            generation = reset_live_set_state_locked(file_path or None, "file_path")
            if not file_path:
                state["current_set_id"] = f"unsaved:{generation}"
            state["current_set_name"] = set_name
            return generation

        if set_name_available:
            state["current_set_name"] = set_name
        return int(state["set_generation"])


def _bootstrap_target_identity() -> Tuple[str, int, int]:
    return (
        str(ableton_target.host),
        int(ableton_target.send_port),
        int(ableton_target.reply_port),
    )


def _new_bootstrap_transaction(generation: int) -> BootstrapTransaction:
    started_at = time.monotonic()
    transaction = BootstrapTransaction(
        generation=int(generation),
        started_at=started_at,
        deadline=started_at + BOOTSTRAP_TRANSACTION_TIMEOUT,
        target_identity=_bootstrap_target_identity(),
    )
    write_bootstrap_diagnostic(
        "bootstrap-transaction-created",
        setGeneration=generation,
        timeoutMs=int(BOOTSTRAP_TRANSACTION_TIMEOUT * 1000),
        target=list(transaction.target_identity),
    )
    return transaction


def _bootstrap_cancel(transaction: BootstrapTransaction, reason: str, event: str = "cancelled") -> None:
    if transaction.completed or transaction.cancelled:
        return
    transaction.cancelled = True
    transaction.cancel_reason = reason
    elapsed_ms = int((time.monotonic() - transaction.started_at) * 1000)
    write_bootstrap_diagnostic(
        f"bootstrap-transaction-{event}",
        setGeneration=transaction.generation,
        reason=reason,
        missing=transaction.missing(),
        attempts=dict(transaction.attempts),
        elapsedMs=elapsed_ms,
    )
    abort_bootstrap(transaction.generation, reason)


def _bootstrap_query_field(
    transaction: BootstrapTransaction,
    field_name: str,
    address: str,
    technical_timeout: float,
) -> bool:
    """Tente un champ sans faire d'un timeout individuel un échec global."""
    remaining = transaction.deadline - time.monotonic()
    if remaining <= 0:
        return False

    attempt = transaction.attempts.get(field_name, 0) + 1
    transaction.attempts[field_name] = attempt
    if attempt > 1:
        write_bootstrap_diagnostic(
            "bootstrap-field-retry",
            setGeneration=transaction.generation,
            field=field_name,
            attempt=attempt,
            remainingMs=max(0, int(remaining * 1000)),
        )

    response = query(
        address,
        timeout=min(float(technical_timeout), remaining),
        expected_generation=transaction.generation,
        allow_during_bootstrap=True,
        apply_response=False,
    )
    if response is None:
        write_bootstrap_diagnostic(
            "bootstrap-field-missing",
            setGeneration=transaction.generation,
            field=field_name,
            attempt=attempt,
            missing=transaction.missing(),
        )
        return False

    if field_name in ("file_path", "song_name", "confirmed_file_path"):
        value: Any = _first_text_value(response)
    elif field_name == "selected_scene":
        value = int(response[0]) if response else 0
    else:
        value = tuple(response)
    setattr(transaction, field_name, value)
    write_bootstrap_diagnostic(
        "bootstrap-field-received",
        setGeneration=transaction.generation,
        field=field_name,
        attempt=attempt,
        value=value if field_name != "scene_names" else None,
        count=len(value) if field_name == "scene_names" else None,
        missing=transaction.missing(),
    )
    return True


def abort_bootstrap(generation: int, reason: str) -> None:
    with lock:
        if int(state.get("set_generation", 0)) == int(generation):
            set_bootstrap_step_locked(f"bootstrap interrompu : {reason}", reason)
            state["bootstrap_running"] = False
            state["bootstrap_generation"] = None
            state["pending_request"] = None
    write_bootstrap_diagnostic(
        "bootstrap-interrupted",
        reason=reason,
        expectedGeneration=generation,
        currentGeneration=int(state.get("set_generation", 0)),
    )


def apply_live_set_bootstrap_locked(
    generation: int,
    file_path: str,
    set_name: str,
    selected_scene: int,
    scene_names: Tuple[Any, ...],
) -> bool:
    """Remplace en une écriture l'intégralité des données propres au nouveau Set."""
    global _bootstrap_generation

    if int(state.get("set_generation", 0)) != int(generation):
        return False
    if state.get("set_ready", False):
        return False

    set_id = file_path or f"unsaved:{generation}"
    current_id = str(state.get("current_set_id") or "")
    if current_id and not current_id.startswith("pending:") and current_id != set_id:
        return False

    new_scenes = {
        index: str(name)
        for index, name in enumerate(scene_names)
        if name is not None
    }
    selected_name = new_scenes.get(int(selected_scene), "—") or "—"
    state.update({
        "current_set_id": set_id,
        "current_set_name": set_name,
        "selected_scene": int(selected_scene),
        "next_scene": int(selected_scene),
        "selected_scene_name": selected_name,
        "scenes": new_scenes,
        "current_scene": None,
        "playing_scene": -1,
        "playing_scene_name": "—",
        "last_fired_scene": -1,
        "last_fired_scene_name": "—",
        "has_show_started": False,
        "message": "Live Set prêt",
        "sync_source": "Ableton",
    })
    set_connected_locked(True, "bootstrap complet", "apply_live_set_bootstrap_locked")
    set_set_ready_locked(True, "bootstrap complet et cohérent", "apply_live_set_bootstrap_locked")
    set_bootstrap_step_locked("Live Set prêt", "bootstrap complet et cohérent")
    state["bootstrap_running"] = False
    state["bootstrap_generation"] = None
    state["pending_request"] = None
    state["last_successful_bootstrap"] = {
        "generation": int(generation),
        "completed_at": time.time(),
        "current_set_id": set_id,
        "scene_count": len(new_scenes),
        "selected_scene": int(selected_scene),
    }
    _bootstrap_generation = None
    generation_log(
        "bootstrap_complete",
        generation=generation,
        current_set_id=set_id,
        selected_scene=selected_scene,
        scene_count=len(new_scenes),
    )
    return True


def bootstrap_live_set(generation: int) -> None:
    """Accumule un instantané privé jusqu'à complétion ou échéance globale."""
    global _bootstrap_generation, _bootstrap_transaction

    with lock:
        transaction = _bootstrap_transaction
        if transaction is None or transaction.generation != int(generation):
            transaction = _new_bootstrap_transaction(generation)
            _bootstrap_transaction = transaction

    try:
        # Laisse arriver les datagrammes émis avant l'invalidation. Sans identifiant
        # de requête dans AbletonOSC, ils ne sont corrélables qu'une fois drainés.
        with lock:
            set_bootstrap_step_locked("purge des réponses OSC antérieures", "début du bootstrap transactionnel")
        write_bootstrap_diagnostic("bootstrap-started", setGeneration=generation)
        time.sleep(OSC_BOOTSTRAP_DRAIN_SECONDS)

        request_fields = (
            ("file_path", "/live/song/get/file_path", 0.10, "attente de Song.file_path"),
            ("song_name", "/live/song/get/name", 0.08, "attente de Song.name"),
            ("selected_scene", "/live/view/get/selected_scene", 0.10, "attente de la scène sélectionnée"),
            ("scene_names", "/live/song/get/scenes/name", 0.20, "attente des noms de scènes"),
        )

        while not transaction.completed and not transaction.cancelled:
            if not generation_is_current(generation):
                _bootstrap_cancel(transaction, "génération modifiée pendant le bootstrap")
                return
            if transaction.target_identity != _bootstrap_target_identity():
                _bootstrap_cancel(transaction, "cible OSC modifiée pendant le bootstrap")
                return
            if time.monotonic() >= transaction.deadline:
                _bootstrap_cancel(transaction, "timeout global du bootstrap", event="timeout")
                return

            progress = False
            for field_name, address, technical_timeout, step in request_fields:
                if transaction.received(field_name):
                    continue
                with lock:
                    set_bootstrap_step_locked(step, f"transaction #{generation}")
                if _bootstrap_query_field(transaction, field_name, address, technical_timeout):
                    progress = True
                if not generation_is_current(generation):
                    _bootstrap_cancel(transaction, "génération modifiée pendant une lecture")
                    return
                if time.monotonic() >= transaction.deadline:
                    break

            if transaction.ready_to_confirm() and not transaction.received("confirmed_file_path"):
                with lock:
                    set_bootstrap_step_locked("confirmation de Song.file_path", "validation finale de l'identité")
                if _bootstrap_query_field(
                    transaction,
                    "confirmed_file_path",
                    "/live/song/get/file_path",
                    0.10,
                ):
                    progress = True
                    if transaction.confirmed_file_path != transaction.file_path:
                        _bootstrap_cancel(transaction, "Song.file_path a changé pendant le bootstrap")
                        return
                    write_bootstrap_diagnostic(
                        "bootstrap-file-path-confirmed",
                        setGeneration=generation,
                        filePath=transaction.file_path,
                    )

            if transaction.complete():
                if not generation_is_current(generation):
                    _bootstrap_cancel(transaction, "génération modifiée avant publication")
                    return
                with lock:
                    applied = apply_live_set_bootstrap_locked(
                        generation,
                        str(transaction.confirmed_file_path),
                        str(transaction.song_name),
                        int(transaction.selected_scene),
                        tuple(transaction.scene_names),
                    )
                if not applied:
                    _bootstrap_cancel(transaction, "instantané cohérent refusé avant publication")
                    return
                transaction.completed = True
                elapsed_ms = int((time.monotonic() - transaction.started_at) * 1000)
                write_bootstrap_diagnostic(
                    "bootstrap-transaction-completed",
                    setGeneration=generation,
                    filePath=transaction.confirmed_file_path,
                    selectedScene=transaction.selected_scene,
                    sceneCount=len(transaction.scene_names),
                    attempts=dict(transaction.attempts),
                    elapsedMs=elapsed_ms,
                )
                return

            write_bootstrap_diagnostic(
                "bootstrap-transaction-waiting",
                setGeneration=generation,
                missing=transaction.missing(),
                attempts=dict(transaction.attempts),
                remainingMs=max(0, int((transaction.deadline - time.monotonic()) * 1000)),
            )
            if not progress:
                time.sleep(min(
                    BOOTSTRAP_RETRY_PAUSE_SECONDS,
                    max(0.0, transaction.deadline - time.monotonic()),
                ))
    except Exception as exc:
        _bootstrap_cancel(transaction, f"exception {type(exc).__name__}: {exc}")
    finally:
        with lock:
            if _bootstrap_transaction is transaction and (transaction.completed or transaction.cancelled):
                _bootstrap_transaction = None
            if _bootstrap_generation == generation and not state.get("set_ready", False):
                _bootstrap_generation = None
                state["bootstrap_running"] = False
                state["bootstrap_generation"] = None
                state["pending_request"] = None


def start_live_set_bootstrap(generation: int) -> None:
    global _bootstrap_generation, _bootstrap_transaction

    with lock:
        if int(state.get("set_generation", 0)) != int(generation):
            write_bootstrap_diagnostic(
                "bootstrap-not-started",
                reason="génération déjà périmée",
                expectedGeneration=generation,
                currentGeneration=int(state.get("set_generation", 0)),
            )
            return
        if state.get("set_ready", False) or _bootstrap_generation == generation:
            write_bootstrap_diagnostic(
                "bootstrap-not-started",
                reason="Live Set déjà prêt" if state.get("set_ready", False) else "bootstrap déjà actif",
                setGeneration=generation,
            )
            return
        _bootstrap_generation = generation
        _bootstrap_transaction = _new_bootstrap_transaction(generation)
        state["bootstrap_running"] = True
        state["bootstrap_generation"] = int(generation)
        state["pending_request"] = None
        set_bootstrap_step_locked("bootstrap planifié", "nouvelle génération à initialiser")
    threading.Thread(target=bootstrap_live_set, args=(generation,), daemon=True).start()



def refresh_names_and_transport() -> bool:
    """
    Refresh léger. Ne scanne pas toutes les pistes.
    """
    try:
        initial_generation = None
        wait_for_initial_bootstrap = False
        with lock:
            generation = int(state.get("set_generation", 0))
            transaction = _bootstrap_transaction
            bootstrap_active = (
                _bootstrap_generation is not None
                or (
                    transaction is not None
                    and not transaction.completed
                    and not transaction.cancelled
                )
            )
            if bootstrap_active and not state.get("set_ready", False):
                wait_for_initial_bootstrap = True
            elif state.get("current_set_id") is None:
                initial_generation = reset_live_set_state_locked(None, "initial bootstrap")

        # Le premier instantané est confié directement à la transaction.
        # Il ne dépend donc ni d'un /live/startup spontané, ni des trois
        # prélectures historiques aux timeouts adaptés au seul mode local.
        if initial_generation is not None:
            start_live_set_bootstrap(initial_generation)
            return False

        # Une transaction initiale déjà active reste l'unique propriétaire
        # des lectures d'identité jusqu'à sa complétion ou son annulation.
        if wait_for_initial_bootstrap:
            return False

        verified_generation = refresh_live_set_identity(generation)
        if verified_generation is None:
            return False
        if verified_generation != generation:
            start_live_set_bootstrap(verified_generation)
            return False
        generation = verified_generation

        with lock:
            ready = bool(state.get("set_ready", False))
        if not ready:
            start_live_set_bootstrap(generation)
            return False

        res = query("/live/view/get/selected_scene", expected_generation=generation)
        if res:
            selected = int(res[0])
            with lock:
                if int(state.get("set_generation", 0)) != generation:
                    return
                state["selected_scene"] = selected
                state["next_scene"] = selected
            query("/live/scene/get/name", selected, expected_generation=generation)

        query("/live/song/get/is_playing", expected_generation=generation)

        with lock:
            if int(state.get("set_generation", 0)) != generation:
                return
            playing = int(state.get("playing_scene", -1))

        with lock:
            show_started = bool(state.get("has_show_started"))
        if playing >= 0 and show_started:
            query("/live/scene/get/name", playing, expected_generation=generation)

        with lock:
            set_connected_locked(True, "rafraîchissement OSC réussi", "refresh_names_and_transport")
            state["message"] = "Connecté à AbletonOSC"
            state["sync_source"] = "Ableton"
        return True

    except Exception as e:
        with lock:
            set_connected_locked(False, str(e), "refresh_names_and_transport")
            state["message"] = f"Erreur : {e}"
        return False



def refresh_scene_name_async(scene_index: int):
    """Demande le nom d'une scène sans bloquer l'interface web.

    Utilisé après NEXT / PREV / GO pour que la carte
    “prochaine scène sélectionnée” se mette à jour rapidement.
    """
    try:
        with lock:
            generation = int(state.get("set_generation", 0))
        query(
            "/live/scene/get/name",
            int(scene_index),
            timeout=0.08,
            expected_generation=generation,
        )
        with lock:
            if int(state.get("set_generation", 0)) != generation:
                return
            set_connected_locked(True, "nom de scène reçu", "refresh_scene_name_async")
            state["message"] = "Connecté à AbletonOSC"
    except Exception as e:
        with lock:
            set_connected_locked(False, str(e), "refresh_scene_name_async")
            state["message"] = f"Erreur : {e}"
def scan_scene_names_async(limit: int = 120, clear_before_scan: bool = False):
    """Demande les noms des scènes Ableton pour alimenter le menu déroulant.

    clear_before_scan=True sert après changement de projet Ableton :
    on vide l'ancienne liste pour éviter d'afficher les scènes du projet précédent.
    """
    with lock:
        generation = int(state.get("set_generation", 0))
        if not state.get("set_ready", False):
            return

    if clear_before_scan:
        with lock:
            state["scenes"] = {}
            state["selected_scene_name"] = "—"
            state["playing_scene_name"] = "—"
            state["last_fired_scene_name"] = "—"
            state["message"] = "Rescan scènes…"

    for scene_index in range(limit):
        if not generation_is_current(generation):
            return
        try:
            query(
                "/live/scene/get/name",
                scene_index,
                timeout=0.05,
                expected_generation=generation,
            )
        except Exception:
            pass

    with lock:
        if int(state.get("set_generation", 0)) != generation:
            return
        state["message"] = "Liste des scènes actualisée"
        set_connected_locked(True, "liste des scènes actualisée", "scan_scene_names_async")
def scan_playing_scene_from_tracks():
    """
    Détection rapide de la scène en lecture, même si elle a été lancée depuis Ableton.

    Pour rester réactif, on évite le test mute piste par piste par défaut :
    /live/track/get/playing_slot_index suffit généralement à savoir quel slot joue.
    """
    with lock:
        generation = int(state.get("set_generation", 0))
        if not state.get("set_ready", False):
            return
        current = int(state.get("playing_scene", -1))

    candidate_tracks = list(range(get_track_count(expected_generation=generation)))

    detected_slot = -1
    for track_index in candidate_tracks:
        if not generation_is_current(generation):
            return
        if CHECK_MUTE_DURING_PLAYING_SCAN and not is_track_enabled(
            track_index,
            expected_generation=generation,
        ):
            continue

        res = query(
            "/live/track/get/playing_slot_index",
            track_index,
            expected_generation=generation,
        )
        if res and len(res) >= 2:
            try:
                slot = int(res[1])
            except Exception:
                continue
            if slot >= 0:
                detected_slot = slot
                break

    if detected_slot >= 0:
        should_query_name = False
        with lock:
            if int(state.get("set_generation", 0)) != generation:
                return
            # Si l'utilisateur a repris la main en Arrangement, les anciens
            # playing_slot_index Ableton ne doivent pas rallumer Session.
            if (
                state.get("play_mode") != "arrangement"
                and bool(state.get("is_playing"))
                and detected_slot != current
            ):
                state["playing_scene"] = detected_slot
                state["last_fired_scene"] = detected_slot
                state["playing_scene_name"] = f"Scène {detected_slot + 1}"
                state["last_fired_scene_name"] = f"Scène {detected_slot + 1}"
                state["current_scene"] = detected_slot
                state["has_show_started"] = True
                state["play_mode"] = "session"
                state["sync_source"] = "Ableton direct"
                should_query_name = True
        # Nom réel demandé hors verrou.
        if should_query_name:
            query(
                "/live/scene/get/name",
                detected_slot,
                timeout=0.05,
                expected_generation=generation,
            )


def background_refresh():
    global last_full_refresh
    global last_playing_scan

    while True:
        now = time.time()
        full_refresh_due = now - last_full_refresh >= FULL_REFRESH_SECONDS
        playing_scan_due = now - last_playing_scan >= PLAYING_SCAN_SECONDS

        # L'identité du Set est toujours vérifiée avant les lectures de scène,
        # de transport ou d'Arrangement du cycle.
        if full_refresh_due or (SCAN_PLAYING_SCENE_FROM_TRACKS and playing_scan_due):
            cycle_ready = refresh_names_and_transport()
            if not cycle_ready:
                if full_refresh_due:
                    last_full_refresh = now
                if playing_scan_due:
                    last_playing_scan = now
                time.sleep(BACKGROUND_REFRESH_SECONDS)
                continue

            if SCAN_PLAYING_SCENE_FROM_TRACKS and playing_scan_due:
                scan_playing_scene_from_tracks()
                last_playing_scan = now

            if full_refresh_due:
                refresh_arrangement_time()
                last_full_refresh = now

        time.sleep(BACKGROUND_REFRESH_SECONDS)



# -----------------------------------------------------------------------------
# Sortie Max for Live OSC pour piloter le vrai crossfader Ableton.
# -----------------------------------------------------------------------------
def send_crossfader_m4l(value: float):
    """Envoie A/B/Centre ou une valeur continue au patch Max for Live sur UDP 9001."""
    value = max(-1.0, min(1.0, float(value)))

    # Boutons/presets : routes dédiées lisibles dans Max.
    # Slider : route continue /xfader/value <float>.
    if value <= -0.995:
        address = "/xfader/a"
        payload = 1
    elif value >= 0.995:
        address = "/xfader/b"
        payload = 1
    elif abs(value) <= 0.005:
        address = "/xfader/center"
        payload = 1
    else:
        address = "/xfader/value"
        payload = value

    try:
        m4l_client.send_message(address, payload)
        print(f"XFADE M4L OSC envoyé : {address} {payload} -> {M4L_IP}:{M4L_PORT}", flush=True)
        return True, f"M4L OSC {address}"
    except Exception as e:
        print("XFADE M4L OSC erreur :", e, flush=True)
        return False, f"M4L OSC erreur : {e}"



# -----------------------------------------------------------------------------
# Page A/B Crossfader
# -----------------------------------------------------------------------------
# AbletonOSC expose surtout les propriétés standard Song/Track. Le crossfader
# Live peut varier selon les versions de script : on envoie donc plusieurs
# adresses possibles, sans scan lourd ni boucle de fond.
# Valeurs Live usuelles : -1 = A, 0 = centre, 1 = B.

XFADE_PRESETS = {
    "a": (-1.0, "A"),
    "center": (0.0, "Centre"),
    "b": (1.0, "B"),
}

def set_crossfader_value(value: float, label: str = ""):
    value = max(-1.0, min(1.0, float(value)))

    ok, midi_msg = send_crossfader_m4l(value)

    with lock:
        state["crossfader"] = value
        state["crossfader_label"] = label or ("A" if value <= -0.95 else "B" if value >= 0.95 else "Centre")
        state["message"] = f"Crossfader {state['crossfader_label']}" if ok else f"Crossfader non envoyé — {midi_msg}"
        state["sync_source"] = "Max for Live OSC"

    return value



def open_browser_delayed():
    try:
        time.sleep(1.5)
        webbrowser.open("http://127.0.0.1:5050/")
    except Exception as e:
        print(f"Ouverture navigateur impossible : {e}")

@app.route("/info")
def info():
    ip = get_local_ip()
    return f"""
    <html>
    <head>
      <title>Ableton Web Remote - Infos</title>
      <style>
        body {{
          background:#111827;
          color:white;
          font-family:-apple-system, BlinkMacSystemFont, sans-serif;
          padding:40px;
        }}
        .box {{
          background:#1f2937;
          border-radius:20px;
          padding:24px;
          max-width:520px;
        }}
        a {{
          color:#60a5fa;
          font-size:22px;
          font-weight:bold;
        }}
      </style>
    </head>
    <body>
      <div class="box">
        <h1>Ableton Web Remote démarré</h1>
        <p>Sur ce Mac :</p>
        <p><a href="http://127.0.0.1:5050">http://127.0.0.1:5050</a></p>
        <p>Sur iPhone / iPad :</p>
        <p><a href="http://{ip}:5050">http://{ip}:5050</a></p>
        <p>Le téléphone doit être sur le même réseau Wi-Fi ou partage de connexion.</p>
      </div>
    </body>
    </html>
    """

@app.route("/")
def index():
    show_session_view()
    return render_template("index.html")


@app.route("/assets/<path:filename>")
def remote_asset(filename):
    return send_from_directory(Path(__file__).resolve().parent / "assets", filename)


@app.route("/ab")
def ab_page():
    return render_template("ab.html")


@app.route("/arrangement")
def arrangement_page():
    try:
        with lock:
            generation = int(state.get("set_generation", 0))
        markers = load_arrangement_markers(
            force_live=True,
            expected_generation=generation,
        )
        with lock:
            if (
                int(state.get("set_generation", 0)) != generation
                or not state.get("set_ready", False)
            ):
                return render_template("arrangement.html")
            state["arrangement_markers"] = markers
            if markers:
                state["arrangement_markers_source"] = markers[0].get("source", state.get("arrangement_markers_source", "CACHE"))
            else:
                state["arrangement_markers_source"] = "CACHE"
    except Exception as e:
        print("Erreur chargement repères Arrangement :", e, flush=True)
    return render_template("arrangement.html")


@app.route("/status")
def status():
    # IMPORTANT : /status doit rester non bloquant.
    # Si un thread OSC tient le lock trop longtemps, on renvoie le dernier état connu
    # au lieu de bloquer l'interface web jusqu'au timeout navigateur.
    acquired = lock.acquire(timeout=0.05)
    try:
        if acquired:
            normalize_transport_state_locked()

            # Garde-fou final : une lecture Session ne doit pas allumer l'Arrangement.
            # is_playing est global à Live ; play_mode reste la source de vérité UI.
            if bool(state.get("is_playing", False)) and state.get("play_mode") == "paused":
                state["play_mode"] = "stopped"
                state["is_paused"] = False

            deadline = state.get("playback_deadline")
            if deadline is not None and bool(state.get("is_playing", False)) and not bool(state.get("is_paused", False)):
                state["remaining_seconds"] = max(0.0, float(deadline) - time.time())

            data = state_snapshot_locked()
        else:
            # Ne jamais déclarer l'interface non connectée juste parce que le lock
            # est occupé : on renvoie le dernier état connu et on signale seulement
            # que le serveur est en actualisation.
            data = state_snapshot_locked()
            data["server_busy"] = True
            if data.get("connected"):
                data["message"] = "Connecté à AbletonOSC — actualisation…"
            else:
                data["message"] = "Serveur occupé — actualisation…"
    finally:
        if acquired:
            lock.release()

    data["arrangement_markers"] = data.get("arrangement_markers", [])
    data["arrangement_markers_source"] = data.get("arrangement_markers_source", "CACHE")
    return jsonify(data)


@app.route("/transport/test", methods=["POST"])
def test_ableton_transport():
    """Teste le transport sans appliquer la réponse à l'état métier."""
    started = time.monotonic()
    response = ableton_transport.query(
        "/live/application/get/version",
        timeout=0.5,
        context={"purpose": "connection-test"},
    )
    elapsed_ms = int((time.monotonic() - started) * 1000)
    if response is None:
        return jsonify(
            ok=False,
            message="Aucune réponse d'Ableton",
            latency_ms=None,
            target=ableton_target.to_dict(),
        ), 504
    return jsonify(
        ok=True,
        message="Connexion OK",
        latency_ms=elapsed_ms,
        response=list(response),
        target=ableton_target.to_dict(),
    )


@app.route("/shutdown", methods=["POST"])
def shutdown():
    """Arrete uniquement l'instance dont le launcher connait le jeton de possession."""
    identity_matches = (
        bool(LAUNCH_ID)
        and request.headers.get("X-CL-Launch-ID") == LAUNCH_ID
        and request.headers.get("X-CL-Server-Instance-ID") == SERVER_INSTANCE_ID
        and request.headers.get("X-CL-Build-ID") == BUILD_ID
        and bool(SHUTDOWN_TOKEN)
        and hmac.compare_digest(
            request.headers.get("X-CL-Shutdown-Token", ""),
            SHUTDOWN_TOKEN,
        )
    )
    if not identity_matches:
        print(json.dumps({
            "source": "ServerIdentity",
            "event": "shutdown-refused",
            "serverInstanceId": SERVER_INSTANCE_ID,
            "buildId": BUILD_ID,
            "serverProcessId": os.getpid(),
            "reason": "server ownership not validated",
        }, ensure_ascii=False, sort_keys=True), flush=True)
        return jsonify(error="server ownership not validated"), 403

    shutdown_callback = request.environ.get("werkzeug.server.shutdown")

    def stop_process():
        time.sleep(0.1)
        if callable(shutdown_callback):
            shutdown_callback()
        else:
            os.kill(os.getpid(), signal.SIGTERM)

    threading.Thread(target=stop_process, daemon=True).start()
    print(json.dumps({
        "source": "ServerIdentity",
        "event": "shutdown-accepted",
        "launchId": LAUNCH_ID,
        "serverInstanceId": SERVER_INSTANCE_ID,
        "buildId": BUILD_ID,
        "serverProcessId": os.getpid(),
    }, ensure_ascii=False, sort_keys=True), flush=True)
    return jsonify(message="server shutdown requested", server_instance_id=SERVER_INSTANCE_ID)


@app.route("/ownership/verify", methods=["POST"])
def verify_ownership():
    """Prouve la possession sans jamais exposer le jeton secret."""
    identity_matches = (
        bool(LAUNCH_ID)
        and request.headers.get("X-CL-Launch-ID") == LAUNCH_ID
        and request.headers.get("X-CL-Server-Instance-ID") == SERVER_INSTANCE_ID
        and request.headers.get("X-CL-Build-ID") == BUILD_ID
        and bool(SHUTDOWN_TOKEN)
        and hmac.compare_digest(
            request.headers.get("X-CL-Shutdown-Token", ""),
            SHUTDOWN_TOKEN,
        )
    )
    return jsonify(
        owned=bool(identity_matches),
        server_instance_id=SERVER_INSTANCE_ID,
    )


@app.route("/keyboard-log", methods=["POST"])
def keyboard_log():
    record = request.get_json(force=True, silent=True)
    if not isinstance(record, dict):
        return jsonify({"ok": False, "message": "Trace clavier invalide"}), 400
    write_keyboard_diagnostic(record)
    return jsonify({"ok": True})


@app.route("/rescan-scenes", methods=["POST", "GET"])
def rescan_scenes():
    """Force la reconstruction de la liste des scènes après changement de projet Ableton."""
    threading.Thread(
        target=scan_scene_names_async,
        kwargs={"limit": 120, "clear_before_scan": True},
        daemon=True,
    ).start()
    with lock:
        state["message"] = "Rescan scènes lancé"
        data = state_snapshot_locked()
    return jsonify({"ok": True, "message": "Rescan scènes lancé", "state": data})



@app.route("/build-show", methods=["POST", "GET"])
def build_show():
    try:
        data = request.get_json(force=True, silent=True) or {}
    except Exception:
        data = {}

    try:
        spacing_beats = float(data.get("spacing_beats", 128.0))
    except Exception:
        spacing_beats = 128.0

    ok, message = build_show_from_cached_scenes(spacing_beats=spacing_beats)

    with lock:
        response_state = state_snapshot_locked()

    return jsonify({"ok": ok, "message": message, "state": response_state})

def clamp_scene_number(value: Any) -> Optional[int]:
    """Convertit un numéro de scène utilisateur en index Ableton 0-based."""
    try:
        scene_number = int(str(value).strip())
    except Exception:
        return None
    if scene_number < 1:
        return None
    return scene_number - 1


def select_scene(scene_index: int, source: str = "Télécommande"):
    """Sélectionne une scène sans la lancer, puis met le nom à jour en arrière-plan."""
    scene_index = max(0, int(scene_index))
    with scene_transaction_lock:
        send("/live/view/set/selected_scene", scene_index)
        with lock:
            cached_name = str(state.get("scenes", {}).get(scene_index, "") or "").strip()
            state["selected_scene"] = scene_index
            state["next_scene"] = scene_index
            # Le bootstrap fournit déjà la table complète des scènes. Publier
            # immédiatement son titre évite d'afficher « Scène N » pendant
            # l'aller-retour OSC de confirmation.
            state["selected_scene_name"] = cached_name or f"Scène {scene_index + 1}"
            state["message"] = f"Scène {scene_index + 1} sélectionnée"
            state["sync_source"] = source
    threading.Thread(target=refresh_scene_name_async, args=(scene_index,), daemon=True).start()


def execute_go_transaction(request_id: str, expected_generation: int, scene_number: Any) -> Tuple[bool, str]:
    """Sélectionne, confirme puis lance explicitement une scène dans une génération donnée."""
    scene_index = clamp_scene_number(scene_number)
    if scene_index is None:
        return False, "Numéro de scène invalide"

    request_key = (int(expected_generation), request_id)
    with scene_transaction_lock:
        with lock:
            cached = completed_go_requests.get(request_key)
            if cached is not None:
                return bool(cached["ok"]), str(cached["message"])
            if int(state.get("set_generation", 0)) != int(expected_generation):
                return False, "Génération de Live Set obsolète"
            if not state.get("set_ready", False):
                return False, "Live Set en cours de chargement"
            scenes_snapshot = dict(state.get("scenes", {}))
            requested_name = scenes_snapshot.get(scene_index)

        if requested_name is None:
            return False, "Scène absente du Live Set courant"

        show_session_view()
        confirmed = False
        confirmation_deadline = time.monotonic() + 0.8

        with ableton_transport.serialized_queries():
            while time.monotonic() < confirmation_deadline:
                if not generation_is_current(expected_generation):
                    return False, "Live Set modifié pendant le GO"
                with lock:
                    if not state.get("set_ready", False):
                        return False, "Live Set en cours de chargement"

                send("/live/view/set/selected_scene", scene_index)
                response = _query_with_query_lock_held(
                    "/live/view/get/selected_scene",
                    expected_generation=expected_generation,
                    apply_response=False,
                )
                if response:
                    try:
                        confirmed = int(response[0]) == scene_index
                    except (TypeError, ValueError, IndexError):
                        confirmed = False
                if confirmed:
                    break

            if not confirmed:
                return False, "Sélection de scène non confirmée par Ableton"
            if not generation_is_current(expected_generation):
                return False, "Live Set modifié pendant le GO"

            # Le lancement utilise l'index de la transaction, jamais selected_scene.
            send("/live/scene/fire_as_selected", scene_index)

            next_scene = scene_index + 1 if (scene_index + 1) in scenes_snapshot else scene_index
            send("/live/view/set/selected_scene", next_scene)

        now = time.time()
        with lock:
            if (
                int(state.get("set_generation", 0)) != int(expected_generation)
                or not state.get("set_ready", False)
            ):
                return False, "Live Set modifié pendant le GO"

            duration_seconds = parse_scene_duration_seconds(requested_name)
            state["last_fired_scene"] = scene_index
            state["last_fired_scene_name"] = requested_name
            state["playing_scene"] = scene_index
            state["playing_scene_name"] = requested_name
            state["current_scene"] = scene_index
            state["has_show_started"] = True
            state["play_mode"] = "session"
            state["is_playing"] = True
            state["is_paused"] = False
            state["scene_duration_seconds"] = duration_seconds
            state["remaining_seconds"] = duration_seconds
            state["playback_deadline"] = (now + duration_seconds) if duration_seconds is not None else None
            state["arrangement_marker"] = "—"
            state["selected_scene"] = next_scene
            state["next_scene"] = next_scene
            state["selected_scene_name"] = scenes_snapshot.get(next_scene, requested_name)
            state["message"] = f"Scène {scene_index + 1} lancée"
            state["sync_source"] = "Télécommande"
            completed_go_requests[request_key] = {
                "ok": True,
                "message": state["message"],
            }

        return True, f"Scène {scene_index + 1} lancée"


def confirm_live_playing_state(expected_generation: int) -> Tuple[Optional[bool], bool]:
    """Lit l'état de lecture réel avant une commande à bascule.

    Le booléen de retour indique si la valeur a été confirmée par Ableton.
    En l'absence de réponse, le dernier cache cohérent reste disponible comme
    secours, mais jamais si la génération a changé pendant la lecture.
    """
    response = query(
        "/live/song/get/is_playing",
        timeout=0.20,
        expected_generation=expected_generation,
    )

    with lock:
        if (
            int(state.get("set_generation", 0)) != int(expected_generation)
            or not state.get("set_ready", False)
        ):
            return None, False
        cached_playing = bool(state.get("is_playing", False))

    if not response:
        return cached_playing, False

    raw = response[0]
    confirmed_playing = (
        raw.strip().lower() not in ("0", "false", "off", "no", "")
        if isinstance(raw, str)
        else bool(raw)
    )
    return confirmed_playing, True


@app.route("/action", methods=["POST"])
def action():
    data = request.get_json(force=True, silent=True) or {}
    action_name = data.get("action")
    print("ACTION REÇUE :", action_name, flush=True)

    with lock:
        action_ready = bool(state.get("set_ready", False))
        action_generation = int(state.get("set_generation", 0))
        action_state_id = id(state)
        write_keyboard_diagnostic({
            "source": "ServerAction",
            "event": "action-entry",
            "action": action_name,
            "setReady": action_ready,
            "setGeneration": action_generation,
            "stateObjectId": action_state_id,
            "processId": os.getpid(),
            "clientGeneration": data.get("set_generation"),
            "requestId": data.get("request_id"),
        })
        if not action_ready and action_name not in ("xfade", "xfade_value"):
            write_keyboard_diagnostic({
                "source": "ServerAction",
                "event": "action-rejected",
                "action": action_name,
                "httpStatus": 409,
                "reason": "set_ready est false à l'entrée de /action",
                "setReady": action_ready,
                "setGeneration": action_generation,
                "stateObjectId": action_state_id,
                "processId": os.getpid(),
            })
            return jsonify({
                "ok": False,
                "message": "Live Set en cours de chargement",
                "state": state_snapshot_locked(),
            }), 409
        selected = int(state.get("selected_scene", 0))

    if action_name == "go":
        request_id = str(data.get("request_id", "")).strip()
        try:
            expected_generation = int(data.get("set_generation"))
        except (TypeError, ValueError):
            return jsonify({"ok": False, "message": "Génération de Live Set manquante"}), 400
        if not request_id:
            return jsonify({"ok": False, "message": "Identifiant de requête manquant"}), 400

        ok, message = execute_go_transaction(request_id, expected_generation, data.get("scene"))
        if not ok:
            with lock:
                write_keyboard_diagnostic({
                    "source": "ServerAction",
                    "event": "action-rejected",
                    "action": action_name,
                    "httpStatus": 409,
                    "reason": message,
                    "setReady": bool(state.get("set_ready", False)),
                    "setGeneration": int(state.get("set_generation", 0)),
                    "stateObjectId": id(state),
                    "processId": os.getpid(),
                    "clientGeneration": expected_generation,
                    "requestId": request_id,
                })
        with lock:
            response_state = state_snapshot_locked()
        return jsonify({
            "ok": ok,
            "message": message,
            "request_id": request_id,
            "state": response_state,
        }), (200 if ok else 409)
    elif action_name == "arrangement_toggle":
        # Bouton dédié Arrangement :
        # - si l'Arrangement joue, on met en pause
        # - sinon on reprend la lecture Arrangement à la position courante
        confirmed_playing, _ = confirm_live_playing_state(action_generation)
        if confirmed_playing is None:
            return jsonify({
                "ok": False,
                "message": "Live Set modifié pendant la commande",
            }), 409
        with lock:
            arrangement_is_playing = (
                confirmed_playing
                and str(state.get("play_mode", "")) == "arrangement"
                and not bool(state.get("is_paused", False))
            )

        if arrangement_is_playing:
            send("/live/song/stop_playing")
            with lock:
                state["is_playing"] = False
                state["is_paused"] = True
                state["play_mode"] = "arrangement"
                state["playing_scene"] = -1
                state["playing_scene_name"] = "—"
                state["last_fired_scene"] = -1
                state["last_fired_scene_name"] = "—"
                state["message"] = "Pause Arrangement"
                state["sync_source"] = "Télécommande"
        else:
            show_arrangement_view()
            send("/live/song/set/back_to_arranger", 0)
            send("/live/song/continue_playing")
            with lock:
                state["is_playing"] = True
                state["is_paused"] = False
                state["play_mode"] = "arrangement"
                state["playing_scene"] = -1
                state["playing_scene_name"] = "—"
                state["last_fired_scene"] = -1
                state["last_fired_scene_name"] = "—"
                state["message"] = "Lecture Arrangement"
                state["sync_source"] = "Télécommande"

    elif action_name == "pause":
        confirmed_playing, _ = confirm_live_playing_state(action_generation)
        if confirmed_playing is None:
            return jsonify({
                "ok": False,
                "message": "Live Set modifié pendant la commande",
            }), 409
        with lock:
            is_playing = confirmed_playing
            is_paused = bool(state.get("is_paused", False))
            current_mode = str(state.get("play_mode", "stopped"))

        if is_playing:
            send("/live/song/stop_playing")
            with lock:
                deadline = state.get("playback_deadline")
                if deadline is not None:
                    state["remaining_seconds"] = max(0.0, float(deadline) - time.time())
                state["is_playing"] = False
                state["is_paused"] = True
                state["play_mode"] = current_mode if current_mode in ("arrangement", "session") else "paused"
                state["message"] = "Pause"
                state["sync_source"] = "Télécommande"
        else:
            send("/live/song/continue_playing")
            with lock:
                remaining_seconds = state.get("remaining_seconds")
                if remaining_seconds is not None:
                    state["playback_deadline"] = time.time() + max(0.0, float(remaining_seconds))
                state["is_playing"] = True
                state["is_paused"] = False
                state["play_mode"] = current_mode if current_mode in ("arrangement", "session") else "arrangement"
                state["message"] = "Reprise" if is_paused else "Lecture"
                state["sync_source"] = "Télécommande"

    elif action_name == "stop":
        send("/live/song/stop_playing")
        with lock:
            state["is_playing"] = False
            state["is_paused"] = False
            state["play_mode"] = "stopped"
            state["message"] = "Stop"
            state["sync_source"] = "Télécommande"

    elif action_name == "back_to_arrangement":
        send("/live/song/set/back_to_arranger", 0)

    elif action_name == "arrangement_start":
        set_arrangement_time(0, "Début")

    elif action_name in ("arrangement_goto", "arrangement_play_marker"):
        show_arrangement_view()
        marker_name = str(data.get("name", "")).strip()
        play_after_jump = action_name == "arrangement_play_marker"

        try:
            seconds = float(data.get("time"))
        except Exception:
            return jsonify({"ok": False, "message": "Position Arrangement invalide"}), 400

        if not play_after_jump:
            send("/live/song/stop_playing")

        send("/live/song/set/back_to_arranger", 0)
        set_arrangement_time(seconds, marker_name)

        if play_after_jump:
            time.sleep(0.04)
            send("/live/song/continue_playing")

        with lock:
            state["arrangement_time"] = seconds
            state["arrangement_time_label"] = format_time_label(seconds)
            state["arrangement_marker"] = marker_name or format_time_label(seconds)
            state["message"] = ("Lecture : " if play_after_jump else "Cue : ") + state["arrangement_marker"]
            state["sync_source"] = "Arrangement time"
            state["playing_scene"] = -1
            state["playing_scene_name"] = "—"
            state["last_fired_scene"] = -1
            state["last_fired_scene_name"] = "—"

            if play_after_jump:
                state["is_playing"] = True
                state["is_paused"] = False
                state["play_mode"] = "arrangement"
            else:
                state["is_playing"] = False
                state["is_paused"] = False
                state["play_mode"] = "stopped"

    elif action_name in ("arrangement_prev", "arrangement_next"):
        show_arrangement_view()
        send("/live/song/stop_playing")

        with lock:
            markers = list(state.get("arrangement_markers", []))
            now_time = float(state.get("arrangement_time", 0.0))

        if not markers:
            with lock:
                generation = int(state.get("set_generation", 0))
            markers = load_arrangement_markers(
                force_live=True,
                expected_generation=generation,
            )
            with lock:
                if (
                    int(state.get("set_generation", 0)) != generation
                    or not state.get("set_ready", False)
                ):
                    markers = []
                else:
                    state["arrangement_markers"] = markers

        if not markers:
            return jsonify({"ok": False, "message": "Repères Arrangement indisponibles"}), 409

        if action_name == "arrangement_prev":
            previous = [m for m in markers if float(m["time"]) < now_time - 1.0]
            marker = previous[-1] if previous else markers[0]
        else:
            following = [m for m in markers if float(m["time"]) > now_time + 1.0]
            marker = following[0] if following else markers[-1]

        set_arrangement_time(float(marker["time"]), marker["name"])

    elif action_name == "prev":
        select_scene(max(0, selected - 1))

    elif action_name == "next":
        select_scene(selected + 1)

    elif action_name == "goto":
        scene_index = clamp_scene_number(data.get("scene"))
        if scene_index is None:
            return jsonify({"ok": False, "message": "Numéro de scène invalide"}), 400
        select_scene(scene_index)

    elif action_name == "xfade":
        target = str(data.get("target", "")).strip().lower()
        if target not in XFADE_PRESETS:
            return jsonify({"ok": False, "message": "Position A/B invalide"}), 400
        value, label = XFADE_PRESETS[target]
        set_crossfader_value(value, label)

    elif action_name == "xfade_value":
        try:
            value = float(data.get("value"))
        except Exception:
            return jsonify({"ok": False, "message": "Valeur crossfader invalide"}), 400
        set_crossfader_value(value)

    else:
        return jsonify({"ok": False, "message": "Action inconnue"}), 400

    # On ne bloque pas l'action avec un refresh complet.
    with lock:
        return jsonify({"ok": True, "state": state_snapshot_locked()})



def build_server_info():
    ip = get_local_ip()
    return {
        "ip": ip,
        "port": 5050,
        "url": f"http://{ip}:5050",
        "local_url": "http://127.0.0.1:5050",
        "osc_in": ableton_transport.send_port,
        "osc_reply": ableton_transport.reply_port,
        "midi_port": "M4L_OSC_9001",
        "midi_cc": None,
        "midi_channel": None,
        "checklist": [
            "Ableton Live ouvert",
            "AbletonOSC installé et sélectionné dans les surfaces de contrôle",
            "Ordinateur et iPhone/iPad sur le même Wi-Fi",
            "Pour A/B : device Max for Live v8 sur MASTER, udpreceive 9001",
            "Pour Arrangement : créer/nommer les Locators dans Ableton Live",
            "Repli possible : arrangement_markers.json si AbletonOSC ne renvoie pas les cue points"
        ]
    }

@app.route("/ip")
def ip():
    return jsonify({"ip": get_local_ip()})


@app.route("/server_info")
def server_info():
    return jsonify(build_server_info())


def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


if __name__ == "__main__":
    threading.Thread(target=start_osc_server, daemon=True).start()
    threading.Thread(target=start_ltc_udp_listener, daemon=True).start()
    threading.Thread(target=background_refresh, daemon=True).start()
    threading.Thread(target=scan_scene_names_async, kwargs={"limit": 120, "clear_before_scan": True}, daemon=True).start()
    info = build_server_info()
    print("\n" + "=" * 68)
    print("  ABLETON WEB REMOTE - SERVEUR DÉMARRÉ")
    print("=" * 68)
    print("")
    print("  Adresse à ouvrir sur iPhone / iPad :")
    print(f"  >>> {info['url']} <<<")
    print("")
    print("  Adresse locale sur cet ordinateur :")
    print(f"  {info['local_url']}")
    print("")
    print("  Vérifications utiles :")
    print("  1. Ableton Live doit être ouvert.")
    print("  2. AbletonOSC doit être installé et actif dans Ableton.")
    print(f"  3. AbletonOSC reçoit sur le port {ableton_transport.send_port}.")
    print(f"  4. Ce serveur reçoit les réponses OSC sur le port {ableton_transport.reply_port}.")
    print(f"  5. Crossfader A/B : mapper le CC{MIDI_CC} canal {MIDI_CHANNEL + 1} au crossfader Live.")
    print(f"  6. Port MIDI attendu : {MIDI_PORT_EXACT}")
    print("")
    print("  Garde cette fenêtre ouverte pendant l'utilisation.")
    print("=" * 68 + "\n")

    # threaded=True permet à Flask de répondre même si une autre requête est en cours.
    threading.Thread(target=open_browser_delayed, daemon=True).start()
    app.run(host="0.0.0.0", port=5050, debug=False, threaded=True)
