import socket, subprocess, webbrowser, threading, os, time, sys, importlib.util, json, uuid, secrets
import urllib.request
import urllib.error

try:
    import webview
except ModuleNotFoundError:
    webview = None
from pathlib import Path
from flask import Flask, jsonify, render_template_string, request, send_file
from build_identity import BUILD_ID, IDENTITY_PROTOCOL_VERSION, SERVICE_NAME
from ableton_targets import (
    AbletonTargetError,
    load_profiles,
    load_target,
    save_profiles,
    update_profile,
    validate_target,
)
from server_ownership import (
    DEFAULT_RECORD_PATH,
    OwnershipRecordError,
    load_record,
    process_alive,
    record_matches_status,
    remove_record,
    write_record,
)

ROOT = Path(__file__).resolve().parent
APP = ROOT / "app.py"
PYTHON = ROOT / ".venv" / "bin" / "python"
KEYBOARD_LOG_PATH = Path("/private/tmp/CL_Audio_Controller_keyboard.log")
launcher_log_lock = threading.Lock()


def launcher_diagnostic_log(record):
    payload = dict(record)
    payload.setdefault("timestamp", int(time.time() * 1000))
    payload.setdefault("processId", os.getpid())
    line = json.dumps(payload, ensure_ascii=False, sort_keys=True, default=str)
    print(f"[STATE_READY] {line}", flush=True)
    try:
        with launcher_log_lock:
            with KEYBOARD_LOG_PATH.open("a", encoding="utf-8") as handle:
                handle.write(line + "\n")
    except Exception as exc:
        print(f"[STATE_READY] écriture impossible: {exc}", flush=True)


def read_remote_state_diagnostic(timeout=0.3):
    try:
        with urllib.request.urlopen(f"{REMOTE_ROOT_URL}status", timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
            return payload if isinstance(payload, dict) else {}
    except Exception as exc:
        return {"diagnostic_error": str(exc)}


def bundled_resource(*parts):
    candidates = [ROOT.joinpath(*parts)]
    if getattr(sys, "frozen", False):
        try:
            resources_dir = Path(sys.executable).resolve().parents[1] / "Resources"
            candidates.insert(0, resources_dir.joinpath(*parts))
        except Exception:
            pass
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


LOGO = bundled_resource("cl_audio_logo.png")
PARADIS_LOGO = bundled_resource("assets", "paradis latin.jpg")

WEB_PORT = 5050
MIDI_CONSOLE_STATE_PATH = Path("/private/tmp/CL_MIDI_Console_State.json")
MIDI_CONSOLE_MONITOR_PROCESS = None
OSC_PORT = 11000
RETURN_PORT = 11001
LTC_PORT = 63123
LAUNCHER_PORT = 5055
REMOTE_WINDOW_SCRIPT = ROOT / "remote_window.py"
REMOTE_ROOT_URL = f"http://127.0.0.1:{WEB_PORT}/"
REMOTE_AB_URL = f"http://127.0.0.1:{WEB_PORT}/ab"
REMOTE_ARRANGEMENT_URL = f"http://127.0.0.1:{WEB_PORT}/arrangement"
REMOTE_ROOT_LAN_URL = lambda: f"http://{get_lan_ip()}:{WEB_PORT}/"
REMOTE_APP_NAME = "Télécommande Ableton.app"
server_ownership_lock = threading.RLock()
owned_server = None
claimable_server = None
ignored_orphan_instance_id = None
rtp_agent_lock = threading.RLock()
rtp_agent_state = {}
rtp_agent_listener_started = False


def _rtp_agent_listener():
    global rtp_agent_state
    listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        listener.bind(("", 50021))
        while True:
            data, address = listener.recvfrom(65536)
            try:
                payload = json.loads(data.decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                continue
            if payload.get("service") != "cl-midi-rtp-agent":
                continue
            payload["address"] = address[0]
            payload["received_at"] = time.time()
            with rtp_agent_lock:
                rtp_agent_state = payload
    except OSError:
        return
    finally:
        listener.close()


def read_rtp_agent_state(expected_host=None):
    global rtp_agent_listener_started
    with rtp_agent_lock:
        if not rtp_agent_listener_started:
            rtp_agent_listener_started = True
            threading.Thread(target=_rtp_agent_listener, daemon=True, name="rtp-agent-listener").start()
        payload = dict(rtp_agent_state)
    if not payload or time.time() - float(payload.get("received_at", 0)) > 6:
        return {}
    if expected_host not in (None, "", "127.0.0.1", "localhost") and payload.get("address") != expected_host:
        return {}
    connections = payload.get("connections") or []
    targets = payload.get("targets") or []
    return {
        "peer": payload.get("host") or payload.get("address") or "Mac Ableton Lecteur",
        "available": True,
        "validated": bool(connections),
        "connections": connections,
        "targets": targets,
        "last_test": "Agent RTP Ableton actif",
    }


def read_midi_console_state(expected_agent_host=None):
    try:
        if MIDI_CONSOLE_STATE_PATH.stat().st_size > 65536:
            return {}
        payload = json.loads(MIDI_CONSOLE_STATE_PATH.read_text(encoding="utf-8"))
        if not (isinstance(payload, dict) and payload.get("service") == "cl-midi-console-monitor"):
            payload = {}
        agent = read_rtp_agent_state(expected_agent_host)
        if agent:
            payload = dict(payload)
            payload["rtp"] = agent
        elif expected_agent_host not in (None, "", "127.0.0.1", "localhost"):
            payload = dict(payload)
            payload.pop("rtp", None)
        return payload
    except (OSError, ValueError, TypeError):
        agent = read_rtp_agent_state(expected_agent_host)
        return {"rtp": agent} if agent else {}


def find_midi_network_assistant():
    candidates = [
        Path.home() / "Applications" / "CL MIDI Network Assistant.app",
        Path("/Applications/CL MIDI Network Assistant.app"),
    ]
    return next((candidate for candidate in candidates if candidate.exists()), None)


def ensure_midi_console_monitor():
    """Démarre l'écoute CoreMIDI sans afficher la fenêtre de diagnostic."""
    global MIDI_CONSOLE_MONITOR_PROCESS
    if MIDI_CONSOLE_MONITOR_PROCESS and MIDI_CONSOLE_MONITOR_PROCESS.poll() is None:
        return True
    assistant = find_midi_network_assistant()
    if assistant is None:
        return False
    executable = assistant / "Contents" / "MacOS" / "CL MIDI Network Assistant"
    if not executable.exists():
        return False
    MIDI_CONSOLE_MONITOR_PROCESS = subprocess.Popen(
        [str(executable), "--background-monitor"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return True


def stop_midi_console_monitor():
    """Arrête uniquement le moniteur démarré par cette instance du launcher."""
    global MIDI_CONSOLE_MONITOR_PROCESS
    process = MIDI_CONSOLE_MONITOR_PROCESS
    MIDI_CONSOLE_MONITOR_PROCESS = None
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        launcher_diagnostic_log({
            "source": "MidiConsoleMonitor",
            "event": "monitor-stop-timeout",
            "monitorProcessId": process.pid,
        })


def ownership_headers(record):
    return {
        "X-CL-Launch-ID": record["launch_id"],
        "X-CL-Server-Instance-ID": record["server_instance_id"],
        "X-CL-Build-ID": record["build_id"],
        "X-CL-Shutdown-Token": record["shutdown_token"],
    }


def verify_server_ownership(record, status, timeout=1.0):
    """Confirme le fichier, l'identité publiée et le secret du serveur actif."""
    if not record_matches_status(record, status):
        return False, "identity-mismatch"
    request_verify = urllib.request.Request(
        f"{REMOTE_ROOT_URL}ownership/verify",
        method="POST",
        headers=ownership_headers(record),
    )
    try:
        with urllib.request.urlopen(request_verify, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except Exception:
        return False, "ownership-proof-failed"
    if (
        payload.get("owned") is True
        and payload.get("server_instance_id") == status.get("server_instance_id")
    ):
        return True, "ownership-verified"
    return False, "ownership-proof-failed"


def validate_server_identity(payload, expected_launch_id=None, expected_instance_id=None):
    """Valide l'identite logique; le PID reste strictement diagnostique."""
    if not isinstance(payload, dict):
        return {"valid": False, "code": "invalid-response", "message": "Réponse /status invalide"}
    if payload.get("service") != SERVICE_NAME:
        return {"valid": False, "code": "unknown-service", "message": "Service inconnu sur le port 5050"}

    protocol = payload.get("identity_protocol_version")
    if not isinstance(protocol, int):
        return {"valid": False, "code": "unknown-protocol", "message": "Protocole d'identité absent ou inconnu"}
    if protocol < IDENTITY_PROTOCOL_VERSION:
        return {"valid": False, "code": "older-protocol", "message": f"Protocole serveur plus ancien ({protocol})"}
    if protocol > IDENTITY_PROTOCOL_VERSION:
        return {"valid": False, "code": "newer-protocol", "message": f"Protocole serveur plus récent ({protocol})"}
    if payload.get("build_id") != BUILD_ID:
        return {"valid": False, "code": "different-build", "message": "Instance issue d'un autre build"}

    launch_id = payload.get("launch_id")
    instance_id = payload.get("server_instance_id")
    try:
        uuid.UUID(str(launch_id))
        uuid.UUID(str(instance_id))
    except (ValueError, TypeError, AttributeError):
        return {"valid": False, "code": "invalid-identity", "message": "Identifiants d'instance absents ou invalides"}
    if expected_launch_id is not None and launch_id != expected_launch_id:
        return {"valid": False, "code": "different-launch", "message": "Ancienne instance du même build encore active"}
    if expected_instance_id is not None and instance_id != expected_instance_id:
        return {"valid": False, "code": "different-instance", "message": "L'instance serveur a changé depuis sa validation"}
    return {"valid": True, "code": "valid", "message": "Serveur validé"}


def current_identity_status():
    global claimable_server
    payload = read_remote_state_diagnostic()
    with server_ownership_lock:
        ownership = owned_server
        expected_launch = ownership["launch_id"] if ownership else None
        expected_instance = ownership.get("server_instance_id") if ownership else None
    validation = validate_server_identity(payload, expected_launch, expected_instance)
    if ownership is not None and validation["valid"]:
        validation = {"valid": True, "code": "owned-current", "message": "Serveur possédé et validé"}
    if ownership is None and validation["valid"]:
        try:
            record = load_record()
        except OwnershipRecordError as exc:
            claimable_server = None
            validation = {"valid": False, "code": "identity-mismatch", "message": f"Fichier de propriété non sûr : {exc}"}
        else:
            if record is None:
                claimable_server = None
                validation = {"valid": False, "code": "valid-unowned", "message": "Instance CL Audio valide sans preuve locale de propriété"}
            elif not process_alive(record["server_process_id"]):
                claimable_server = None
                validation = {"valid": False, "code": "stale-record", "message": "Fichier de propriété obsolète"}
            elif not record_matches_status(record, payload):
                claimable_server = None
                validation = {"valid": False, "code": "identity-mismatch", "message": "Le fichier de propriété ne correspond pas au serveur actif"}
            else:
                proof_ok, proof_reason = verify_server_ownership(record, payload)
                if proof_ok:
                    claimable_server = dict(record)
                    if ignored_orphan_instance_id == record["server_instance_id"]:
                        validation = {"valid": False, "code": "valid-unowned", "message": "Instance récupérable ignorée par l’utilisateur"}
                    else:
                        validation = {"valid": False, "code": "orphan-claimable", "message": "Instance CL Audio orpheline récupérable"}
                else:
                    claimable_server = None
                    validation = {"valid": False, "code": "identity-mismatch", "message": f"Preuve de propriété refusée ({proof_reason})"}
    return payload, validation


def run_embedded_server():
    """Exécute le serveur inclus dans le bundle, sans Python externe ni Terminal."""
    spec = importlib.util.spec_from_file_location("cl_audio_embedded_server", APP)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Serveur intégré introuvable : {APP}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if getattr(sys, "frozen", False):
        resources_dir = Path(sys.executable).resolve().parents[1] / "Resources"
        module.app.template_folder = str(resources_dir / "templates")
    for target_name in ("start_osc_server", "start_ltc_udp_listener", "background_refresh", "scan_scene_names_async"):
        target = getattr(module, target_name, None)
        if callable(target):
            kwargs = {"limit": 120, "clear_before_scan": True} if target_name == "scan_scene_names_async" else {}
            threading.Thread(target=target, kwargs=kwargs, daemon=True).start()

    module.app.run(host="0.0.0.0", port=WEB_PORT, debug=False, use_reloader=False, threaded=True)


def start_web_server(timeout=6.0):
    """Lance et valide exactement le processus enfant créé par ce launcher."""
    global owned_server
    with server_ownership_lock:
        if owned_server is not None:
            payload, validation = current_identity_status()
            if validation["valid"]:
                return True, validation["message"]
            process = owned_server.get("process")
            if process is not None and process.poll() is None:
                return False, validation["message"]
            owned_server = None

        if tcp_ok(WEB_PORT):
            payload, validation = current_identity_status()
            launcher_diagnostic_log({
                "source": "ServerIdentity",
                "event": "existing-service-classified",
                "classification": validation["code"],
                "reason": validation["message"],
                "launchId": payload.get("launch_id"),
                "serverInstanceId": payload.get("server_instance_id"),
                "buildId": payload.get("build_id"),
                "serverProcessId": payload.get("server_process_id"),
            })
            return False, validation["message"]

        try:
            stale = load_record()
            if stale is not None and not process_alive(stale["server_process_id"]):
                remove_record()
        except OwnershipRecordError as exc:
            return False, f"Fichier de propriété non sûr : {exc}"

        launch_id = str(uuid.uuid4())
        shutdown_token = secrets.token_urlsafe(32)
        child_environment = os.environ.copy()
        child_environment.update({
            "CL_AUDIO_LAUNCH_ID": launch_id,
            "CL_AUDIO_EXPECTED_BUILD_ID": BUILD_ID,
            "CL_AUDIO_SHUTDOWN_TOKEN": shutdown_token,
        })
        if getattr(sys, "frozen", False):
            command = [sys.executable, "--serve"]
        else:
            py = str(PYTHON if PYTHON.exists() else sys.executable)
            command = [py, str(APP)]
        process = subprocess.Popen(command, cwd=str(ROOT), env=child_environment)
        owned_server = {
            "process": process,
            "launch_id": launch_id,
            "server_instance_id": None,
            "shutdown_token": shutdown_token,
            "build_id": BUILD_ID,
        }

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            return False, f"Le serveur s'est arrêté pendant son démarrage (code {process.returncode})"
        if tcp_ok(WEB_PORT):
            payload = read_remote_state_diagnostic(timeout=0.5)
            validation = validate_server_identity(payload, launch_id)
            if validation["valid"]:
                with server_ownership_lock:
                    if owned_server and owned_server["launch_id"] == launch_id:
                        owned_server["server_instance_id"] = payload["server_instance_id"]
                        owned_server["server_process_id"] = payload["server_process_id"]
                        owned_server["server_started_at"] = payload["started_at"]
                try:
                    write_record({
                        "schema_version": 1,
                        "service": SERVICE_NAME,
                        "identity_protocol_version": IDENTITY_PROTOCOL_VERSION,
                        "launch_id": launch_id,
                        "server_instance_id": payload["server_instance_id"],
                        "build_id": BUILD_ID,
                        "server_process_id": payload["server_process_id"],
                        "server_started_at": payload["started_at"],
                        "recorded_at": time.time(),
                        "shutdown_token": shutdown_token,
                    })
                except OwnershipRecordError as exc:
                    return False, f"Identité validée mais propriété non sécurisée : {exc}"
                launcher_diagnostic_log({
                    "source": "ServerIdentity",
                    "event": "identity-validated",
                    "launchId": launch_id,
                    "serverInstanceId": payload["server_instance_id"],
                    "buildId": payload.get("build_id"),
                    "serverProcessId": payload.get("server_process_id"),
                    "launcherProcessId": os.getpid(),
                })
                return True, "Serveur lancé et identité validée"
            if validation["code"] not in {"invalid-response"} and "diagnostic_error" not in payload:
                return False, validation["message"]
        time.sleep(0.05)
    return False, "Délai dépassé avant validation de l'identité du serveur"
def find_remote_app():
    candidates = []

    # Mode développement : depuis le dossier projet
    candidates.append(ROOT / "dist" / REMOTE_APP_NAME)

    # Mode app PyInstaller : app télécommande placée à côté du panneau dans dist/
    try:
        exe = Path(sys.executable).resolve()
        control_app = exe.parents[2]
        candidates.append(control_app.parent / REMOTE_APP_NAME)
    except Exception:
        pass

    # Mode pack zip : app télécommande placée à côté du panneau dans le même dossier
    try:
        candidates.append(Path.cwd() / REMOTE_APP_NAME)
    except Exception:
        pass

    for candidate in candidates:
        if candidate.exists():
            return candidate

    return None

events = ["Launcher prêt"]

app = Flask(__name__)

HTML = r'''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>CL Audio Controller</title>
<style>
*{box-sizing:border-box}
body{
  margin:0; min-height:100vh;
  background:radial-gradient(circle at top,#153c70 0%,#071426 42%,#02050a 100%);
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif;
  color:#f6f8fb; overflow:hidden;
}
.control-shell{
  position:fixed;
  left:50%;
  top:50%;
  transform:translate(-50%,-50%) scale(1);
  transform-origin:center center;
}
.window{
  width:450px; border-radius:26px; padding:20px;
  background:linear-gradient(180deg,rgba(19,33,55,.97),rgba(6,11,21,.99));
  box-shadow:0 28px 80px rgba(0,0,0,.58), inset 0 0 0 1px rgba(255,255,255,.08);
}
.header{text-align:center;margin-bottom:12px}
.logo{
  display:flex; justify-content:center; align-items:center;
  min-height:68px; margin-bottom:7px;
}
.logo img{
  width:min(310px,88%); max-height:86px; object-fit:contain;
  border-radius:8px;
  filter:drop-shadow(0 9px 18px rgba(0,0,0,.46));
}
.logo-fallback{color:#ef3340;font-size:28px;font-weight:900;letter-spacing:.06em}
.title{font-size:19px;font-weight:850;margin-top:3px;color:#e9edf5;letter-spacing:.02em}
.addresses{
  display:grid; grid-template-columns:1fr 92px; gap:12px; align-items:center;
  padding:15px; border-radius:20px;
  background:linear-gradient(135deg,rgba(31,140,255,.18),rgba(31,140,255,.07));
  border:1px solid rgba(80,170,255,.55);
  box-shadow:0 0 24px rgba(31,140,255,.14);
  margin-bottom:14px;
}
.brand{
  height:100%; border-radius:16px;
  display:flex; align-items:center; justify-content:center;
  background:rgba(31,140,255,.10);
  border:1px solid rgba(255,255,255,.08);
  padding:8px;
}
.brand img{max-width:74px; max-height:58px; object-fit:contain; filter:drop-shadow(0 0 10px rgba(31,140,255,.18))}
.brand-fallback{color:#1f8cff; font-weight:900; font-size:18px; line-height:1.05; text-align:center; letter-spacing:.05em}
.label{color:#9fb2cc;font-size:11px;text-transform:uppercase;letter-spacing:.06em;margin-bottom:3px}
.addr{font-family:Menlo,monospace;font-size:13px;margin-bottom:10px;word-break:break-all}
.status{
  text-align:center;padding:10px;border-radius:16px;
  background:rgba(255,255,255,.055);margin-bottom:14px;
  font-size:16px;font-weight:850;
  border:1px solid rgba(255,255,255,.10);
  box-shadow:inset 0 0 0 1px rgba(255,255,255,.03);
  transition:border-color .25s ease, box-shadow .25s ease, background .25s ease;
}
.status.ready{
  border-color:rgba(52,255,114,.88);
  box-shadow:0 0 18px rgba(52,255,114,.22), inset 0 0 0 1px rgba(52,255,114,.12);
  background:rgba(52,255,114,.075);
}
.status.stopped{
  border-color:rgba(255,77,90,.88);
  box-shadow:0 0 18px rgba(255,77,90,.20), inset 0 0 0 1px rgba(255,77,90,.12);
  background:rgba(255,77,90,.065);
}
.status.warning{
  border-color:rgba(255,204,51,.82);
  box-shadow:0 0 18px rgba(255,204,51,.16), inset 0 0 0 1px rgba(255,204,51,.10);
  background:rgba(255,204,51,.060);
}
.ok{color:#34ff72}.warn{color:#ffcc33}.off{color:#ff4d5a}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}
button{
  border:0;border-radius:17px;min-height:62px;color:white;
  font-size:15px;font-weight:850;cursor:pointer;
  box-shadow:0 12px 28px rgba(0,0,0,.30), inset 0 0 0 1px rgba(255,255,255,.12);
  transition:transform .12s ease, filter .12s ease;
}
button:hover{filter:brightness(1.08)}
button:active{transform:scale(.985)}
.start{background:linear-gradient(145deg,#2ee66f,#119647)}
.open{background:linear-gradient(145deg,#2d9cff,#0b56b7)}
.remote{background:linear-gradient(145deg,#00d86e,#0e8c3c)}
.restart{background:linear-gradient(145deg,#ffbe3b,#e45b16)}
.stop{background:linear-gradient(145deg,#ff5b66,#a91424)}
.quit{background:linear-gradient(145deg,#8b5cf6,#4c1d95);grid-column:1/3;min-height:54px}
.ports,.journal{
  margin-top:12px;padding:9px 10px;border-radius:15px;
  background:rgba(255,255,255,.040);
  border:1px solid rgba(80,170,255,.30);
  box-shadow:0 0 14px rgba(31,140,255,.07), inset 0 0 0 1px rgba(255,255,255,.020);
}
.ports{
  border-color:rgba(80,170,255,.42);
}
.journal{
  border-color:rgba(139,92,246,.38);
  box-shadow:0 0 18px rgba(139,92,246,.08), inset 0 0 0 1px rgba(255,255,255,.025);
}
.row{display:grid;grid-template-columns:1fr 58px 44px;align-items:center;padding:5px 7px;font-size:12px;border-radius:10px;background:rgba(255,255,255,.025);margin-bottom:4px}
.row:last-child{margin-bottom:0}
.name{color:#e7eefc}.port{color:#96a8c1;font-family:Menlo,monospace}.state{font-weight:850;text-align:right}
.jtitle{color:#9fb2cc;font-size:10px;text-transform:uppercase;letter-spacing:.06em;margin-bottom:5px}
#events{font-family:Menlo,monospace;font-size:11px;color:#cbd5e1;line-height:1.30;min-height:28px;max-height:52px;overflow:hidden;padding:6px 7px;border-radius:10px;background:rgba(0,0,0,.16)}
.footer{margin-top:12px;text-align:center;color:#5fa8ff;font-size:12px}
</style>
</head>
<body>
<div id="controlShell" class="control-shell">
<div class="window">
  <div class="header">
    <div class="logo">
      <img src="/paradis-logo" alt="Paradis Latin Cabaret"
           onerror="this.outerHTML='<div class=&quot;logo-fallback&quot;>PARADIS LATIN</div>'">
    </div>
    <div class="title">Panneau de contrôle serveur</div>
  </div>

  <div class="addresses">
    <div>
      <div class="label">Adresse sur ce Mac</div>
      <div class="addr" id="localurl">...</div>
      <div class="label">Adresse iPhone / iPad</div>
      <div class="addr" id="lanurl">...</div>
    </div>
    <div class="brand"><img src="/logo" alt="CL AUDIO" onerror="this.outerHTML='<div class=&quot;brand-fallback&quot;>CL<br>AUDIO</div>'"></div>
  </div>

  <div id="statusBox" class="status warning"><div id="main" class="warn">● Vérification...</div></div>

  <div class="grid">
  <button class="remote" style="grid-column:1/3;min-height:78px;font-size:18px"
          onclick="call('/remote-window')">
    OUVRIR TÉLÉCOMMANDE
    </button>
    <button class="restart" onclick="call('/restart')">RECHARGER SERVEUR</button>
    <button class="stop" onclick="call('/stop')">ARRÊTER</button>
    <button class="quit" onclick="call('/quit')">QUITTER</button>
    </div>

  <div class="ports">
    <div class="row"><div class="name">Web Server</div><div class="port">5050</div><div id="web" class="state">...</div></div>
    <div class="row"><div class="name">AbletonOSC</div><div class="port">11000</div><div id="osc" class="state">...</div></div>
    <div class="row"><div class="name">Retour OSC</div><div class="port">11001</div><div id="ret" class="state">...</div></div>
  </div>

  <div class="journal">
    <div class="jtitle">Journal</div>
    <div id="events">...</div>
  </div>

  <div class="footer">Ableton Web Remote</div>
</div>
</div>

<script>
const CONTROL_BASE_WIDTH = 500;
const CONTROL_BASE_HEIGHT = 720;

function resizeControlPanel(){
  const shell = document.getElementById('controlShell');
  if(!shell) return;
  const margin = 18;
  const scale = Math.min(
    (window.innerWidth - margin) / CONTROL_BASE_WIDTH,
    (window.innerHeight - margin) / CONTROL_BASE_HEIGHT
  );
  shell.style.transform = `translate(-50%, -50%) scale(${Math.max(0.55, scale)})`;
}

window.addEventListener('resize', resizeControlPanel);
window.addEventListener('load', resizeControlPanel);

async function call(path){ await fetch(path); refresh(); }
function setState(id, ok, warn=false){
  const e=document.getElementById(id);
  e.textContent = ok ? "OK" : "OFF";
  e.className = "state " + (ok ? "ok" : (warn ? "warn" : "off"));
}
async function refresh(){
  const r = await fetch('/state');
  const s = await r.json();
  document.getElementById('localurl').textContent = s.local_url;
  document.getElementById('lanurl').textContent = s.lan_url;
  document.getElementById('events').innerHTML = s.events.join("<br>");
  setState('web', s.web);
  setState('osc', s.osc, true);
  setState('ret', s.ret);
  const m=document.getElementById('main');
  const statusBox=document.getElementById('statusBox');
  if(s.system_ready){m.textContent="● SYSTÈME PRÊT";m.className="ok";statusBox.className="status ready";}
  else if(s.server_valid){m.textContent="● CHARGEMENT DU LIVE SET";m.className="off";statusBox.className="status stopped";}
  else{m.textContent="● SERVEUR NON VALIDÉ";m.className="off";statusBox.className="status stopped";}
}
setInterval(refresh,1500);
resizeControlPanel();
refresh();
</script>
</body>
</html>
'''

def event(msg):
    from datetime import datetime
    events.append(f"{datetime.now().strftime('%H:%M:%S')}  {msg}")
    del events[:-5]

def get_lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:
        return "IP_INCONNUE"
    finally:
        s.close()

def tcp_ok(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.2)
    try:
        return s.connect_ex(("127.0.0.1", port)) == 0
    finally:
        s.close()

def port_used(port):
    return bool(subprocess.run(["lsof", "-i", f":{port}"], capture_output=True, text=True).stdout.strip())

def stop_owned_server(graceful_timeout=3.0, terminate_timeout=2.0):
    """Arrête une instance prouvée, sans action globale ni terminaison forcée."""
    global owned_server
    with server_ownership_lock:
        ownership = owned_server
    if ownership is None:
        return False, "Aucune instance possédée par ce launcher"

    instance_id = ownership.get("server_instance_id")
    process = ownership.get("process")
    pid = ownership.get("server_process_id") or getattr(process, "pid", None)
    if not instance_id:
        return False, "Arrêt refusé : identité serveur incomplète"

    payload = read_remote_state_diagnostic()
    validation = validate_server_identity(payload, ownership["launch_id"], instance_id)
    if not validation["valid"]:
        return False, f"Arrêt refusé : {validation['message']}"
    proof_record = {
        "schema_version": 1,
        "service": SERVICE_NAME,
        "identity_protocol_version": IDENTITY_PROTOCOL_VERSION,
        "launch_id": ownership["launch_id"],
        "server_instance_id": instance_id,
        "build_id": ownership["build_id"],
        "server_process_id": payload.get("server_process_id"),
        "server_started_at": payload.get("started_at"),
        "recorded_at": ownership.get("recorded_at", time.time()),
        "shutdown_token": ownership["shutdown_token"],
    }
    proof_ok, proof_reason = verify_server_ownership(proof_record, payload)
    if not proof_ok:
        return False, f"Arrêt refusé : {proof_reason}"
    return_port = int((payload.get("ableton_target") or {}).get("reply_port", RETURN_PORT))

    request_shutdown = urllib.request.Request(
        f"{REMOTE_ROOT_URL}shutdown",
        method="POST",
        headers=ownership_headers(ownership),
    )
    try:
        with urllib.request.urlopen(request_shutdown, timeout=1.0):
            launcher_diagnostic_log({
                "source": "ServerIdentity",
                "event": "graceful-shutdown-accepted",
                "launchId": ownership["launch_id"],
                "serverInstanceId": instance_id,
                "buildId": ownership["build_id"],
                "serverProcessId": payload.get("server_process_id"),
            })
    except (urllib.error.URLError, TimeoutError) as exc:
        return False, f"Arrêt propre non confirmé : {exc}"

    deadline = time.monotonic() + graceful_timeout
    while time.monotonic() < deadline:
        process_stopped = process is None or process.poll() is not None
        pid_stopped = not pid or not process_alive(pid)
        if process_stopped and pid_stopped and not tcp_ok(WEB_PORT) and not port_used(return_port):
            break
        time.sleep(0.05)
    else:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=terminate_timeout)
            except subprocess.TimeoutExpired:
                return False, "Le processus exact résiste à l’arrêt normal ; terminaison forcée non exécutée"
        else:
            return False, "Arrêt demandé mais libération des ports non confirmée"

    if tcp_ok(WEB_PORT) or port_used(return_port):
        return False, f"Processus arrêté mais ports 5050/{return_port} encore occupés"
    try:
        remove_record()
    except OwnershipRecordError as exc:
        return False, f"Serveur arrêté, mais fichier de propriété non supprimé : {exc}"

    with server_ownership_lock:
        if owned_server is ownership:
            owned_server = None
    return True, "Serveur arrêté proprement"


def ensure_valid_server():
    payload, validation = current_identity_status() if tcp_ok(WEB_PORT) else ({}, {"valid": False})
    if validation.get("valid"):
        return True, validation["message"]
    if tcp_ok(WEB_PORT):
        return False, validation.get("message", "Serveur non identifiable sur le port 5050")
    return start_web_server()


def adopt_claimable_server():
    """Adopte explicitement une instance après une nouvelle preuve complète."""
    global owned_server, claimable_server, ignored_orphan_instance_id
    payload, validation = current_identity_status()
    if validation.get("code") != "orphan-claimable" or claimable_server is None:
        return False, validation.get("message", "Instance non récupérable")
    record = dict(claimable_server)
    proof_ok, proof_reason = verify_server_ownership(record, payload)
    if not proof_ok or not record_matches_status(record, payload):
        return False, f"Reprise refusée : {proof_reason}"
    with server_ownership_lock:
        owned_server = {
            **record,
            "process": None,
            "adopted": True,
        }
        claimable_server = None
        ignored_orphan_instance_id = None
    return True, "Instance orpheline reprise après validation de propriété"


def stop_claimable_server():
    """Arrête explicitement une instance orpheline après revérification."""
    global owned_server, claimable_server
    payload, validation = current_identity_status()
    if validation.get("code") != "orphan-claimable" or claimable_server is None:
        return False, validation.get("message", "Instance non récupérable")
    record = dict(claimable_server)
    proof_ok, proof_reason = verify_server_ownership(record, payload)
    if not proof_ok or not record_matches_status(record, payload):
        return False, f"Arrêt refusé : {proof_reason}"
    with server_ownership_lock:
        owned_server = {**record, "process": None, "adopted": True}
    ok, message = stop_owned_server()
    if not ok:
        with server_ownership_lock:
            if owned_server and owned_server.get("server_instance_id") == record["server_instance_id"]:
                owned_server = None
        return False, message
    claimable_server = None
    return True, message

def open_remote_app_window(url, title="Télécommande Ableton"):
    """Ouvre la télécommande dans une fenêtre autonome si pywebview est disponible."""
    if webview is not None:
        try:
            webview.create_window(
                title,
                url,
                width=430,
                height=820,
                min_size=(360, 620),
                resizable=True,
                text_select=True,
            )
            return "fenêtre autonome"
        except Exception as exc:
            print(f"Impossible d'ouvrir une fenêtre autonome ({exc}), ouverture navigateur.", flush=True)

    webbrowser.open(url)
    return "navigateur"

PANEL_HTML = r'''
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>CL AUDIO SHOW CONTROL</title>
<style>
*{box-sizing:border-box}
html,body{margin:0;width:100%;height:100%;overflow:hidden}
body{
  color:#d2d7e2;
  background:linear-gradient(180deg,#070810 0%,#090c16 54%,#06080e 100%);
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif;
}
.wrap{
  width:340px;max-width:calc(100% - 12px);height:100%;
  margin:0 auto;padding:10px 10px 8px;
  display:flex;flex-direction:column;gap:6px;
}
.hero{
  height:76px;flex:0 0 76px;border-radius:12px;overflow:hidden;
  background:#020306;border:1px solid rgba(255,255,255,.12);
  box-shadow:0 8px 18px rgba(0,0,0,.30);
  display:flex;align-items:center;justify-content:center;
}
.hero img{width:100%;height:100%;object-fit:contain}
.header{text-align:center;flex:0 0 auto}
h1{font-size:13px;margin:0;font-weight:760;color:rgba(214,219,231,.76)}
.subtitle{font-size:8px;color:rgba(220,228,245,.50);margin:2px 0 0}
.main{display:flex;flex-direction:column;gap:6px;min-height:0;flex:1}
.card{
  background:rgba(3,6,13,.42);border:1px solid rgba(255,255,255,.13);
  border-radius:13px;padding:8px;box-shadow:0 10px 24px rgba(0,0,0,.22);
}
.card h2{
  margin:0 0 5px;font-size:9px;text-transform:uppercase;
  letter-spacing:.75px;color:rgba(235,240,255,.70);
}
.commands{display:grid;grid-template-columns:1fr 1fr;gap:5px}
button{
  height:26px;border-radius:10px;cursor:pointer;font-weight:720;
  letter-spacing:.1px;font-size:9px;color:rgba(220,225,235,.76);
  border:1px solid rgba(255,255,255,.20);
  box-shadow:inset 0 1px 0 rgba(255,255,255,.10);
}
button:hover{filter:brightness(1.13)}
button:active{transform:scale(.985)}
.primary{
  grid-column:1/-1;height:30px;background:rgba(60,150,68,.48);
  border-color:rgba(100,225,108,.52);
}
.blue{background:rgba(19,89,201,.72);border-color:rgba(50,117,235,.64)}
.orange{background:rgba(184,112,18,.78);border-color:rgba(235,158,44,.66)}
.purple{background:rgba(92,54,158,.80);border-color:rgba(139,90,220,.62)}
.red{background:rgba(139,28,37,.78);border-color:rgba(222,57,67,.64)}
.status{min-height:17px;color:rgba(220,228,245,.72);font-size:9px;padding-top:6px}
.statusPanel{padding:6px 8px;flex:0 0 auto}
.lamps{display:grid;grid-template-columns:1fr 1fr;gap:2px 7px}
.lampWide{grid-column:1/-1}
.lamp{
  display:grid;grid-template-columns:8px 43px 1fr;align-items:center;
  column-gap:4px;min-height:11px;
}
.led{width:5px;height:5px;border-radius:50%;background:#252a35;box-shadow:inset 0 0 0 1px rgba(255,255,255,.16)}
.lamp.on .led{background:#6dff47;box-shadow:0 0 8px rgba(109,255,71,.88)}
.lampTitle{font-size:7px;font-weight:760;color:rgba(235,240,255,.62);text-transform:uppercase;letter-spacing:.2px}
.lampSub{font-size:7px;color:rgba(220,228,245,.47);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.footer{
  display:flex;align-items:center;justify-content:space-between;gap:10px;
  color:rgba(255,255,255,.44);font-size:9px;letter-spacing:.4px;
  flex:0 0 auto;padding:0 1px;
}
.footer strong{color:rgba(255,255,255,.68);font-weight:700}
</style>
</head>
<body>
<div class="wrap">
  <div class="hero"><img src="/paradis-logo" alt="Paradis Latin Cabaret"></div>
  <div class="header">
    <h1>CL AUDIO SHOW CONTROL</h1>
    <p class="subtitle">Panneau de contrôle · Ableton Web Remote</p>
  </div>
  <div class="main">
    <div class="card">
      <h2>Commandes</h2>
      <div class="commands">
        <button class="primary" onclick="action('/remote-window','Ouverture télécommande')">OUVRIR LA TÉLÉCOMMANDE</button>
        <button class="blue" onclick="action('/start','Démarrage serveur')">Lancer serveur</button>
        <button class="orange" onclick="action('/restart','Relance serveur')">Relancer serveur</button>
        <button class="purple" onclick="action('/local-page','Ouverture page locale')">Page locale</button>
        <button class="red" onclick="action('/stop','Arrêt serveur')">Arrêter</button>
      </div>
      <div id="status" class="status">Prêt.</div>
    </div>
    <div class="card statusPanel">
      <h2>Connexions</h2>
      <div class="lamps">
        <div id="serverLamp" class="lamp"><span class="led"></span><span class="lampTitle">Serveur</span><span class="lampSub">port 5050</span></div>
        <div class="lamp on"><span class="led"></span><span class="lampTitle">Adresse</span><span id="address" class="lampSub">—</span></div>
        <div id="oscLamp" class="lamp"><span class="led"></span><span class="lampTitle">OSC aller</span><span class="lampSub">port 11000</span></div>
        <div id="returnLamp" class="lamp"><span class="led"></span><span class="lampTitle">OSC retour</span><span class="lampSub">port 11001</span></div>
        <div class="lamp lampWide on"><span class="led"></span><span class="lampTitle">iPhone</span><span id="iphone" class="lampSub">—</span></div>
        <div class="lamp lampWide on"><span class="led"></span><span class="lampTitle">Appareils</span><span class="lampSub">0 connecté</span></div>
      </div>
    </div>
  </div>
  <div class="footer"><span><strong>CL AUDIO</strong> · SHOW CONTROL</span><span id="footerUrl">—</span></div>
</div>
<script>
const setLamp=(id,on)=>document.getElementById(id).className='lamp '+(on?'on':'');
async function refresh(){
  try{
    const s=await (await fetch('/state')).json();
    setLamp('serverLamp',s.web);setLamp('oscLamp',s.osc);setLamp('returnLamp',s.ret);
    document.getElementById('address').textContent=s.lan_url.replace(/^https?:\/\//,'');
    document.getElementById('iphone').textContent=s.lan_url;
    document.getElementById('footerUrl').textContent=s.lan_url;
  }catch(e){document.getElementById('status').textContent='Panneau hors ligne';}
}
async function action(path,label){
  const status=document.getElementById('status');status.textContent=label+'…';
  try{const response=await fetch(path);const r=await response.json();status.textContent=response.ok?(r.message||'Terminé.'):('Refus : '+(r.error||response.status));}
  catch(e){status.textContent='Erreur : '+e;}
  await refresh();
}
refresh();setInterval(refresh,1500);
</script>
</body>
</html>
'''


PANEL_HTML_V2 = r'''
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>CL AUDIO SHOW CONTROL</title>
<style>
:root{
  color-scheme:dark;
  --bg:#101217;--card:#1a1d24;--card2:#15181e;--line:#30343d;
  --text:#f2f4f7;--muted:#aeb4bf;--blue:#4b8fe8;--green:#43c86f;
  --orange:#e5a63b;--red:#d95858;--violet:#8069c9;
}
*{box-sizing:border-box}
html,body{margin:0;width:100%;height:100%;overflow:hidden}
body{background:linear-gradient(180deg,#0e1015,#11141a);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display","Segoe UI",sans-serif}
button{font:inherit}
.app{width:590px;max-width:calc(100% - 16px);height:100%;margin:auto;padding:9px;display:flex;flex-direction:column;gap:7px;overflow-y:auto;overflow-x:hidden;scrollbar-gutter:stable}
.app>*{flex-shrink:0}
.app::-webkit-scrollbar{width:9px}
.app::-webkit-scrollbar-track{background:#11141a;border-radius:8px}
.app::-webkit-scrollbar-thumb{background:#4a5260;border:2px solid #11141a;border-radius:8px}
.app::-webkit-scrollbar-thumb:hover{background:#657082}
.topbar{display:grid;grid-template-columns:150px 1fr;gap:10px;align-items:center}
.brand{height:56px;border-radius:11px;background:#020304;border:1px solid #272a31;display:flex;align-items:center;justify-content:center;overflow:hidden;box-shadow:0 8px 18px rgba(0,0,0,.25)}
.brand img{width:100%;height:100%;object-fit:contain}
.product-row{display:flex;align-items:center;justify-content:space-between;min-height:38px;padding:0 2px;gap:10px}
.product-copy{display:flex;align-items:baseline;gap:8px;min-width:0;white-space:nowrap}
.product{font-size:15px;font-weight:790;letter-spacing:.04em;color:#e6e9ef}
.product-subtitle{font-size:10px;color:#858d9b;letter-spacing:.025em}
.show-toggle{height:32px;padding:0 14px;border:1px solid rgba(88,162,255,.68);border-radius:9px;background:linear-gradient(180deg,rgba(64,140,231,.28),rgba(40,104,184,.20));color:#dceaff;font-size:11px;font-weight:760;cursor:pointer;box-shadow:0 5px 14px rgba(32,101,190,.16)}
.show-toggle:hover{filter:brightness(1.14)}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:9px;box-shadow:0 7px 18px rgba(0,0,0,.17)}
.system{display:grid;grid-template-columns:14px 1fr auto;gap:9px;align-items:center;min-height:54px;transition:.2s}
.system .dot{width:11px;height:11px;border-radius:50%;background:#69707d;box-shadow:0 0 0 4px rgba(105,112,125,.10)}
.system.ready{border-color:rgba(67,200,111,.58);background:linear-gradient(135deg,rgba(67,200,111,.12),var(--card))}
.system.ready .dot{background:var(--green);box-shadow:0 0 12px rgba(67,200,111,.75)}
.system.warning{border-color:rgba(229,166,59,.62);background:linear-gradient(135deg,rgba(229,166,59,.12),var(--card))}
.system.warning .dot{background:var(--orange);box-shadow:0 0 12px rgba(229,166,59,.65)}
.system.error{border-color:rgba(217,88,88,.64);background:linear-gradient(135deg,rgba(217,88,88,.12),var(--card))}
.system.error .dot{background:var(--red);box-shadow:0 0 12px rgba(217,88,88,.65)}
.system.busy .dot{background:var(--blue);animation:pulse 1s infinite}
@keyframes pulse{50%{opacity:.35;transform:scale(.75)}}
.state-title{font-size:16px;font-weight:820;letter-spacing:.01em}
.state-detail{font-size:11px;color:var(--muted);margin-top:2px}
.state-time{font:18px Menlo,monospace;font-weight:780;line-height:1;color:#f1f4f8;letter-spacing:.015em;font-variant-numeric:tabular-nums}
.system-side{display:grid;grid-template-rows:1fr 1fr;align-items:center;justify-items:end;align-self:stretch;min-width:142px}
.system-ltc{min-width:0;padding:0;color:#70dc94;text-align:right;font:18px Menlo,monospace;font-weight:780;line-height:1;letter-spacing:.015em;font-variant-numeric:tabular-nums}
.system-ltc::before{content:'LTC  ';font:7px -apple-system,BlinkMacSystemFont,"SF Pro Display",sans-serif;font-weight:760;letter-spacing:.11em;color:#68717d}
.system-ltc.offline{color:#707985}
.command-row{display:flex;flex-direction:column;gap:8px}
.primary{height:41px;width:100%;border:1px solid rgba(88,162,255,.72);border-radius:10px;background:linear-gradient(180deg,#408ce7,#2868b8);color:white;font-size:13px;font-weight:790;cursor:pointer;box-shadow:0 8px 18px rgba(32,101,190,.22)}
.primary:hover{filter:brightness(1.08)}
.secondary-actions{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.action{height:41px;border-radius:9px;border:1px solid #404651;background:#252a33;color:#e2e6ed;font-size:11px;font-weight:700;cursor:pointer}
.action.start{border-color:rgba(67,200,111,.55);background:rgba(67,200,111,.16)}
.action.restart{border-color:rgba(229,166,59,.62);background:rgba(229,166,59,.17)}
.action:hover{filter:brightness(1.12)}
.action-status{min-height:13px;font-size:10px;color:var(--muted);padding:0 3px}
.orphan{display:none;border-color:rgba(229,166,59,.62);background:rgba(229,166,59,.09)}
.orphan.show{display:block}.orphan-actions{display:grid;grid-template-columns:1fr 1fr 1fr;gap:6px;margin-top:8px}
.content-grid{display:grid;grid-template-columns:.88fr 1.42fr;gap:7px;align-items:stretch}
.content-grid>.card{height:100%}
.access-head,.tech-head{font-size:9px;font-weight:780;text-transform:uppercase;letter-spacing:.075em;color:#c9ced8;margin-bottom:6px}
.access-card{border-color:#3a4453;background:linear-gradient(145deg,#1b2028,#171a20)}
.access-card .access-head{color:#a9c9f4}
.address-row{display:grid;grid-template-columns:1fr auto;gap:6px;align-items:center}
.address-actions{display:grid;grid-template-columns:1fr 1fr;gap:6px}
.address{height:31px;display:flex;align-items:center;padding:0 8px;border-radius:8px;background:#11141a;border:1px solid #303540;font:10px Menlo,monospace;color:#e4e8ee;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.mini{height:31px;padding:0 8px;border-radius:8px;border:1px solid #424853;background:#272c35;color:#e5e8ee;font-size:10px;font-weight:700;cursor:pointer}
.device-row{display:flex;justify-content:space-between;align-items:center;margin-top:8px;font-size:11px;color:var(--muted)}
.network-card{border-width:2px;transition:.2s;box-shadow:0 0 0 1px rgba(255,255,255,.035),0 8px 20px rgba(0,0,0,.20)}.network-card.local{border-color:rgba(105,217,143,.72);background:linear-gradient(145deg,rgba(67,200,111,.11),#171b21)}.network-card.remote{border-color:rgba(229,166,59,.78);background:linear-gradient(145deg,rgba(229,166,59,.14),#1a1b20)}
.network-title-row{display:grid;grid-template-columns:1fr auto 1fr;align-items:center;gap:10px;margin-bottom:9px}.network-title-row .access-head{margin:0;justify-self:start}.mode-badge{justify-self:center;min-width:102px;padding:6px 10px;border-radius:8px;text-align:center;font-size:11px;font-weight:880;letter-spacing:.045em;box-shadow:0 4px 12px rgba(0,0,0,.20)}.network-card.local .mode-badge{color:#092015;border:1px solid #a4edbc;background:#89dfa6}.network-card.remote .mode-badge{color:#211605;border:1px solid #f2c56f;background:#e5a63b}.network-timecode{justify-self:end;min-width:116px;padding:6px 9px;border-radius:8px;border:1px solid rgba(84,224,132,.62);background:rgba(46,154,84,.18);color:#72e49a;text-align:center;font:14px Menlo,monospace;font-weight:820;letter-spacing:.015em;box-shadow:0 4px 12px rgba(0,0,0,.18)}.network-timecode.offline{color:#7c8490;border-color:#3a414c;background:#171b21}
.network-grid{display:grid;grid-template-columns:.85fr 1.25fr;gap:7px}.network-grid label{font-size:8px;color:var(--muted)}
.network-grid input,.network-grid select{width:100%;height:28px;margin-top:2px;border-radius:7px;border:1px solid #353b45;background:#11141a;color:#e4e8ee;padding:0 7px;font-size:10px}
.ports-readonly{grid-column:1/-1;display:flex;justify-content:space-between;align-items:center;min-height:28px;padding:0 8px;border-radius:7px;background:#11141a;border:1px solid #353b45;font-size:9px;color:var(--muted)}.ports-readonly strong{font:11px Menlo,monospace;color:#d6dbe4}
.ltc-destination{grid-column:1/-1;display:flex;justify-content:space-between;align-items:center;min-height:30px;padding:0 8px;border-radius:7px;border:1px solid rgba(84,224,132,.42);background:rgba(46,154,84,.10);font-size:9px;color:#9aa2ae;cursor:pointer;user-select:none}.ltc-destination:hover{border-color:#72e49a;background:rgba(46,154,84,.18)}.ltc-destination strong{font:11px Menlo,monospace;color:#72e49a}.ltc-destination span:first-child{font-weight:760;letter-spacing:.035em}
.network-buttons{display:grid;grid-template-columns:1fr 1fr;gap:5px;margin-top:6px}.network-buttons .action{height:31px;font-size:10px}
.badge{padding:4px 8px;border-radius:999px;background:rgba(67,200,111,.12);color:#7ee39e;border:1px solid rgba(67,200,111,.28);font-size:10px}
.console-card{padding:10px}.console-head{display:flex;justify-content:space-between;align-items:center;margin-bottom:7px}.console-head strong{font-size:10px;letter-spacing:.075em}.rtp-control{display:flex;align-items:center;gap:6px}.rtp-badge{font-size:9px;color:#d7a64c}.rtp-badge.ok{color:#70d89a}.rtp-badge.error{color:#ed7e7e}.rtp-open{height:24px;padding:0 8px;border:1px solid #3f4b5d;border-radius:7px;background:#242b35;color:#cfd6e1;font-size:9px;cursor:pointer}.console-grid{display:grid;grid-template-columns:1fr 1fr;gap:7px}.console-return{border:1px solid #343b47;border-radius:9px;background:#12161c;padding:8px}.console-program{font-size:15px;font-weight:800;color:#edc65b}.console-title{font-size:10px;color:#c4cad4;margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.console-state{font-size:9px;color:#7d8592;margin-top:4px}.console-return.ok{border-color:rgba(80,196,123,.76);box-shadow:inset 0 0 0 1px rgba(80,196,123,.16)}.console-return.ok .console-state{color:#70d89a}.console-return.remembered{border-color:rgba(80,196,123,.38)}.console-return.remembered .console-state{color:#9eb8a8}
details{background:var(--card2);border:1px solid #292e37;border-radius:12px;overflow:hidden}
details[open]{overflow:visible}
summary{height:34px;padding:0 11px;display:flex;align-items:center;cursor:pointer;font-size:12px;color:#c5cad3;list-style:none}
summary::-webkit-details-marker{display:none}
summary::before{content:'›';font-size:18px;margin-right:7px;transition:.15s}
details[open] summary::before{transform:rotate(90deg)}
.technical{border-top:1px solid #292e37;padding:8px 11px 10px;display:grid;grid-template-columns:1fr 1fr;gap:7px}
.tech-item{display:grid;grid-template-columns:8px 1fr;gap:6px;align-items:center;font-size:10px;color:#aeb4bf}
.tech-led{width:6px;height:6px;border-radius:50%;background:#555d69}
.tech-item.on .tech-led{background:var(--green);box-shadow:0 0 7px rgba(67,200,111,.65)}
.event-list{grid-column:1/-1;border-top:1px solid #292e37;padding-top:7px;font-size:10px;color:#8f97a5;line-height:1.45;max-height:140px;overflow-y:auto}
.bottom{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-top:auto}
.local{height:30px;border:0;background:transparent;color:#91a9cb;font-size:11px;cursor:pointer}
.stop{height:30px;padding:0 11px;border-radius:8px;border:1px solid rgba(217,88,88,.42);background:rgba(217,88,88,.10);color:#e68b8b;font-size:11px;cursor:pointer}
.footer{font-size:9px;color:#707784;letter-spacing:.05em;text-align:center}
body.show-mode .secondary-actions,body.show-mode details,body.show-mode .bottom,body.show-mode .network-card,body.show-mode .action-status{display:none}
body.show-mode .app{justify-content:center;max-height:430px;max-width:600px}
body.show-mode .topbar{grid-template-columns:190px 1fr}
body.show-mode .brand{height:72px}
body.show-mode .system{min-height:78px}
body.show-mode .state-time,body.show-mode .system-ltc{font-size:22px}
body.show-mode .show-toggle{border-color:rgba(229,166,59,.72);background:rgba(229,166,59,.18);color:#f3ce85}
@media(max-width:520px){
  .app{width:100%;max-width:100%;gap:7px;padding:7px}
  .topbar{display:flex;flex-direction:column;gap:8px}
  .brand{width:100%;height:78px}.product-row{width:100%;min-height:34px}.product{font-size:15px}
  .product-copy{gap:6px}.product-subtitle{font-size:9px}
  .content-grid{grid-template-columns:1fr}
  .network-grid{grid-template-columns:1fr 1fr}
  .primary{height:42px}.action{height:38px}
}
</style>
</head>
<body>
<main class="app">
  <div class="topbar">
    <div class="brand"><img src="/paradis-logo" alt="Paradis Latin Cabaret"></div>
    <div class="product-row"><div class="product-copy"><div class="product">CL AUDIO SHOW CONTROL</div></div><button id="showMode" class="show-toggle" onclick="toggleShowMode()">Mode spectacle</button></div>
  </div>

  <section id="systemCard" class="card system warning">
    <span class="dot"></span>
    <div><div id="stateTitle" class="state-title">VÉRIFICATION…</div><div id="stateDetail" class="state-detail">Contrôle des services en cours</div></div>
    <div class="system-side"><span id="stateTime" class="state-time">—</span><span id="systemLtc" class="system-ltc offline">--:--:--:--</span></div>
  </section>

  <div class="command-row">
    <div class="secondary-actions">
      <button class="action start" onclick="runAction('/start','Démarrage du serveur')">▶&nbsp;&nbsp;Démarrer</button>
      <button class="action restart" onclick="runAction('/restart','Relance du serveur')">↻&nbsp;&nbsp;Relancer</button>
    </div>
    <button class="primary" onclick="runAction('/remote-window','Ouverture de la télécommande')">OUVRIR LA TÉLÉCOMMANDE</button>
  </div>
  <div id="actionStatus" class="action-status"></div>

  <section id="orphanCard" class="card orphan">
    <div class="access-head">Instance précédente détectée</div>
    <div id="orphanDetail" class="state-detail">—</div>
    <div class="orphan-actions">
      <button class="action start" onclick="runPostAction('/orphan/adopt','Reprise de l’instance')">Reprendre</button>
      <button class="action restart" onclick="runPostAction('/orphan/stop','Arrêt de l’instance')">Arrêter</button>
      <button class="action" onclick="runPostAction('/orphan/cancel','Annulation')">Annuler</button>
    </div>
  </section>

  <div class="content-grid">
    <section class="card access-card">
      <div class="access-head">Accès distant</div>
      <div class="address-row">
        <div id="remoteAddress" class="address">—</div>
        <div class="address-actions"><button class="mini" onclick="copyAddress()">Copier</button><button class="mini" onclick="runAction('/local-page','Ouverture locale')">Ouvrir</button></div>
      </div>
      <div class="device-row"><span>Télécommande iPhone / iPad</span><span id="deviceBadge" class="badge">Disponible</span></div>
    </section>

    <section id="networkCard" class="card network-card local">
      <div class="network-title-row"><div class="access-head">Connexion AbletonOSC</div><span id="modeBadge" class="mode-badge">MODE LOCAL</span><span id="networkLtc" class="network-timecode offline">--:--:--:--</span></div>
      <div class="network-grid">
        <label>Mode<select id="abletonMode" onchange="updateNetworkFields()"><option value="local">Local</option><option value="remote">Ableton distant</option></select></label>
        <label>Adresse Ableton<input id="abletonHost" value="127.0.0.1"></label>
        <div class="ports-readonly"><span>Ports AbletonOSC fixes</span><strong><span id="abletonSendPort">11000</span> → <span id="abletonReplyPort">11001</span></strong></div>
        <div class="ltc-destination" role="button" tabindex="0" onclick="copyLtcDestination()" onkeydown="if(event.key==='Enter'||event.key===' '){event.preventDefault();copyLtcDestination();}"><span id="ltcDestinationLabel">Destination LTC Display v2 · cliquer pour copier</span><strong id="ltcDestination">127.0.0.1:63123</strong></div>
      </div>
      <div class="network-buttons">
        <button class="action" onclick="saveNetworkConfig()">Appliquer</button>
        <button class="action" onclick="testAbletonConnection()">Tester la connexion</button>
      </div>
    </section>
  </div>

  <section class="card console-card">
    <div class="console-head"><strong>MIDI &amp; CONSOLES</strong><div class="rtp-control"><span id="rtpBadge" class="rtp-badge">RTP · attente</span><button class="rtp-open" onclick="runAction('/midi-network-assistant','Ouverture du diagnostic RTP')">Diagnostic</button></div></div>
    <div class="console-grid">
      <div id="cl5Return" class="console-return"><div id="cl5Program" class="console-program">CL5 · scène n° —</div><div id="cl5Title" class="console-title">Contexte Ableton en attente</div><div id="cl5State" class="console-state">En attente du premier retour</div></div>
      <div id="ql1Return" class="console-return"><div id="ql1Program" class="console-program">QL1 · scène n° —</div><div id="ql1Title" class="console-title">Contexte Ableton en attente</div><div id="ql1State" class="console-state">En attente du premier retour</div></div>
    </div>
  </section>

  <details>
    <summary>Détails techniques et événements</summary>
    <div class="technical">
      <div id="techWeb" class="tech-item"><span class="tech-led"></span><span>Serveur Web · 5050</span></div>
      <div id="techOsc" class="tech-item"><span class="tech-led"></span><span id="techOscLabel">OSC aller · 11000</span></div>
      <div id="techReturn" class="tech-item"><span class="tech-led"></span><span id="techReturnLabel">OSC retour · 11001</span></div>
      <div class="tech-item on"><span class="tech-led"></span><span id="techAbletonMode">Ableton · Local</span></div>
      <div class="tech-item on"><span class="tech-led"></span><span id="techAbletonAddress">127.0.0.1:11000</span></div>
      <div class="tech-item on"><span class="tech-led"></span><span id="techAbletonLatency">Dernière réponse · —</span></div>
      <div class="tech-item on"><span class="tech-led"></span><span id="techAbletonTimeouts">Timeouts · 0</span></div>
      <div class="tech-item on"><span class="tech-led"></span><span id="localAddress">Adresse Mac</span></div>
      <div id="events" class="event-list">Aucun événement récent.</div>
    </div>
  </details>

  <div class="bottom"><button class="local" onclick="runAction('/local-page','Ouverture de la page locale')">↗ Page locale</button><button class="stop" onclick="confirmStop()">■ Arrêter…</button></div>
  <div class="footer">CL AUDIO · SHOW CONTROL</div>
</main>
<script>
let latestState=null;
let networkFormInitialized=false;
let networkFormDirty=false;
let networkVisibleMode=null;
let networkDrafts={local:null,remote:null};
const el=id=>document.getElementById(id);
function setTech(id,on){el(id).className='tech-item '+(on?'on':'');}
function setBusy(label){el('systemCard').className='card system busy';el('stateTitle').textContent=label.toUpperCase();el('stateDetail').textContent='Veuillez patienter…';}
function render(s){
  latestState=s;const card=el('systemCard'),title=el('stateTitle'),detail=el('stateDetail');
  if(s.system_ready){card.className='card system ready';title.textContent='SYSTÈME PRÊT';detail.textContent='Serveur validé · Live Set prêt · OSC retour disponible';}
  else if(s.server_valid&&!s.live_set_ready){card.className='card system warning';title.textContent='CHARGEMENT DU LIVE SET';detail.textContent='Serveur validé · '+(s.bootstrap_step||'attente de l’état Ableton');}
  else if(s.server_valid){card.className='card system warning';title.textContent='SERVEUR VALIDÉ';detail.textContent='Attente de la liaison OSC retour';}
  else if(s.web){card.className='card system error';title.textContent='SERVEUR NON VALIDÉ';detail.textContent=s.identity_message||'Instance inconnue ou incompatible sur le port 5050';}
  else{card.className='card system error';title.textContent='SYSTÈME ARRÊTÉ';detail.textContent='Démarrez le serveur avant le spectacle';}
  const now=new Date();el('stateTime').textContent=now.toLocaleTimeString('fr-FR',{hour:'2-digit',minute:'2-digit'});
  el('remoteAddress').textContent=s.lan_url;el('localAddress').textContent=s.local_url.replace(/^https?:\/\//,'');
  setTech('techWeb',s.web);setTech('techOsc',s.osc);setTech('techReturn',s.ret);
  el('events').innerHTML=(s.events||[]).slice().reverse().join('<br>')||'Aucun événement récent.';
  el('orphanCard').className='card orphan '+(s.orphan_actions_available?'show':'');
  if(s.orphan_actions_available)el('orphanDetail').textContent='Instance '+s.orphan_instance_id+' · PID '+s.orphan_process_id+' · '+s.build_id;
  if(!networkFormInitialized&&s.ableton_profiles)initializeNetworkForm(s);
  if(s.ableton_config){el('techAbletonMode').textContent='Ableton · '+(s.ableton_config.mode==='local'?'Local':'Distant');el('techAbletonAddress').textContent=s.ableton_config.host+':'+s.ableton_config.send_port+' → '+s.ableton_config.reply_port;el('techOscLabel').textContent='OSC aller · '+s.ableton_config.send_port;el('techReturnLabel').textContent='OSC retour · '+s.ableton_config.reply_port;}
  el('ltcDestination').textContent=s.ltc_destination+':'+s.ltc_port;
  if(s.osc_transport){el('techAbletonLatency').textContent='Dernière réponse · '+(s.osc_transport.last_latency_ms==null?'—':Math.round(s.osc_transport.last_latency_ms)+' ms');el('techAbletonTimeouts').textContent='Timeouts · '+s.osc_transport.timeout_count;}
  const midi=s.midi_console||{},cl5=midi.cl5||{},ql1=midi.ql1||{};
  const rtp=midi.rtp||{},rtpBadge=el('rtpBadge');
  rtpBadge.textContent=rtp.validated?('RTP VALIDÉ · '+(rtp.peer||'cible')):(rtp.loop_detected?'RTP · BOUCLE':(rtp.available?('RTP DISPONIBLE · '+(rtp.peer||'cible')):'RTP HORS LIGNE'));
  rtpBadge.className='rtp-badge '+(rtp.validated?'ok':(rtp.loop_detected?'error':''));
  const formatMidiAge=(seconds)=>{seconds=Math.max(0,Math.floor(seconds));if(seconds<60)return seconds<2?'à l’instant':'il y a '+seconds+' s';const minutes=Math.floor(seconds/60);if(minutes<60)return'il y a '+minutes+' min';const hours=Math.floor(minutes/60),rest=minutes%60;return'il y a '+hours+' h'+(rest?' '+rest+' min':'');};
  const returnPresentation=(value)=>{const at=Number(value.received_at||0),age=at?Math.max(0,Date.now()/1000-at):Infinity,recent=value.received&&age<=12;if(!value.received)return {className:'',text:'En attente du premier retour'};return {className:recent?'ok':'remembered',text:recent?'✓ Scène reçue · '+formatMidiAge(age):'Dernière scène reçue · '+(at?formatMidiAge(age):'heure inconnue')};};
  const cl5Return=returnPresentation(cl5),ql1Return=returnPresentation(ql1);
  el('cl5Return').className='console-return '+cl5Return.className;el('ql1Return').className='console-return '+ql1Return.className;
  el('cl5Program').textContent='CL5 · scène n° '+(cl5.program??'—');el('ql1Program').textContent='QL1 · scène n° '+(ql1.program??'—');
  el('cl5Title').textContent=cl5.title||s.playing_scene_name||'Titre en attente';el('ql1Title').textContent=ql1.title||s.playing_scene_name||'Titre en attente';
  el('cl5State').textContent=cl5Return.text;el('ql1State').textContent=ql1Return.text;
  const ltc=s.ltc_connected?s.ltc_timecode:'--:--:--:--';
  el('systemLtc').textContent=ltc;el('systemLtc').className='system-ltc'+(s.ltc_connected?'':' offline');
  el('networkLtc').textContent=ltc;el('networkLtc').className='network-timecode'+(s.ltc_connected?'':' offline');
}
async function refresh(){try{render(await(await fetch('/state')).json());}catch(e){el('systemCard').className='card system error';el('stateTitle').textContent='PANNEAU HORS LIGNE';el('stateDetail').textContent=String(e);}}
async function runAction(path,label){setBusy(label);el('actionStatus').textContent=label+'…';try{const response=await fetch(path);const r=await response.json();el('actionStatus').textContent=response.ok?('✓ '+(r.message||'Action terminée')):('! Refus : '+(r.error||response.status));}catch(e){el('actionStatus').textContent='! '+e;}setTimeout(refresh,450);}
async function runPostAction(path,label){setBusy(label);el('actionStatus').textContent=label+'…';try{const response=await fetch(path,{method:'POST'});const r=await response.json();el('actionStatus').textContent=response.ok?('✓ '+(r.message||'Action terminée')):('! Refus : '+(r.error||response.status));}catch(e){el('actionStatus').textContent='! '+e;}setTimeout(refresh,450);}
function copyNetworkDraft(value,mode){
  if(!value)return mode==='local'?{name:'',host:'127.0.0.1',send_port:11000,reply_port:11001}:{name:'',host:'',send_port:11000,reply_port:11001};
  return {name:value.name||'',host:mode==='local'?'127.0.0.1':(value.host||''),send_port:Number(value.send_port),reply_port:Number(value.reply_port)};
}
function initializeNetworkForm(s){
  networkDrafts.local=copyNetworkDraft(s.ableton_profiles.local,'local');
  networkDrafts.remote=copyNetworkDraft(s.ableton_profiles.remote,'remote');
  networkVisibleMode=s.ableton_active_mode;
  el('abletonMode').value=networkVisibleMode;
  restoreNetworkDraft(networkVisibleMode);
  networkFormDirty=false;networkFormInitialized=true;
}
function captureVisibleNetworkDraft(){
  if(!networkVisibleMode)return;
  const previous=networkDrafts[networkVisibleMode]||copyNetworkDraft(null,networkVisibleMode);
  networkDrafts[networkVisibleMode]={
    name:previous.name||'',
    host:networkVisibleMode==='local'?'127.0.0.1':el('abletonHost').value,
    send_port:Number(previous.send_port||11000),
    reply_port:Number(previous.reply_port||11001)
  };
}
function restoreNetworkDraft(mode){
  const draft=networkDrafts[mode]||copyNetworkDraft(null,mode),local=mode==='local';
  el('abletonHost').value=local?'127.0.0.1':draft.host;
  el('abletonHost').disabled=local;
  el('abletonSendPort').textContent=draft.send_port;
  el('abletonReplyPort').textContent=draft.reply_port;
  applyNetworkCardMode(mode);
}
function applyNetworkCardMode(mode){const remote=mode==='remote';el('networkCard').className='card network-card '+(remote?'remote':'local');el('modeBadge').textContent=remote?'ABLETON DISTANT':'MODE LOCAL';}
function updateNetworkFields(){
  captureVisibleNetworkDraft();
  networkVisibleMode=el('abletonMode').value;
  restoreNetworkDraft(networkVisibleMode);
  networkFormDirty=true;
}
function markNetworkDraftDirty(){captureVisibleNetworkDraft();networkFormDirty=true;}
async function saveNetworkConfig(){
  captureVisibleNetworkDraft();const draft=networkDrafts[networkVisibleMode];
  const payload={mode:networkVisibleMode,name:draft.name,host:draft.host,send_port:draft.send_port,reply_port:draft.reply_port};
  el('actionStatus').textContent='Application de la configuration OSC…';
  try{const response=await fetch('/network-config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});const r=await response.json();el('actionStatus').textContent=response.ok?('✓ '+r.message):('! Refus : '+(r.error||response.status));if(response.ok){networkFormInitialized=false;networkFormDirty=false;setTimeout(refresh,500);}}
  catch(e){el('actionStatus').textContent='! '+e;}
}
async function testAbletonConnection(){
  el('actionStatus').textContent='Test de connexion Ableton…';
  try{const response=await fetch('/test-ableton',{method:'POST'});const r=await response.json();el('actionStatus').textContent=response.ok?('✓ Connexion OK · '+r.latency_ms+' ms'):('! '+(r.error||'Aucune réponse d’Ableton'));}
  catch(e){el('actionStatus').textContent='! '+e;}
}
function confirmStop(){if(confirm('Arrêter le serveur de télécommande ?\n\nLes appareils connectés perdront immédiatement l’accès.'))runAction('/stop','Arrêt du serveur');}
async function copyAddress(){if(!latestState)return;try{await navigator.clipboard.writeText(latestState.lan_url);el('actionStatus').textContent='✓ Adresse copiée';}catch(e){el('actionStatus').textContent='Adresse : '+latestState.lan_url;}}
async function copyLtcDestination(){const value=el('ltcDestination').textContent;if(!value)return;try{await navigator.clipboard.writeText(value);el('ltcDestinationLabel').textContent='✓ Destination copiée';setTimeout(()=>el('ltcDestinationLabel').textContent='Destination LTC Display v2 · cliquer pour copier',1400);}catch(e){el('actionStatus').textContent='Destination LTC : '+value;}}
async function resizePanelWindow(width,height){
  try{
    if(window.pywebview&&window.pywebview.api&&window.pywebview.api.resize_panel){await window.pywebview.api.resize_panel(width,height);return;}
    window.resizeTo(width,height);
  }catch(e){console.warn('Redimensionnement natif indisponible',e);}
}
async function toggleShowMode(){
  const enabled=document.body.classList.toggle('show-mode');
  el('showMode').textContent=enabled?'Quitter le mode spectacle':'Mode spectacle';
  await resizePanelWindow(500,enabled?500:900);
}
['abletonHost'].forEach(id=>el(id).addEventListener('input',markNetworkDraftDirty));
let telemetryBusy=false;
async function refreshTelemetry(){if(telemetryBusy)return;telemetryBusy=true;try{const t=await(await fetch('/telemetry')).json();const ltc=t.ltc_connected?t.ltc_timecode:'--:--:--:--';el('systemLtc').textContent=ltc;el('systemLtc').className='system-ltc'+(t.ltc_connected?'':' offline');el('networkLtc').textContent=ltc;el('networkLtc').className='network-timecode'+(t.ltc_connected?'':' offline');}catch(e){}finally{telemetryBusy=false;}}
refresh();refreshTelemetry();setInterval(refresh,1500);setInterval(refreshTelemetry,100);
</script>
</body>
</html>
'''


class ControlPanelWindowApi:
    """Pont minimal permettant au bouton Mode spectacle de redimensionner la fenêtre native."""

    def __init__(self):
        self.window = None

    def resize_panel(self, width, height):
        if self.window is None:
            return False
        self.window.resize(int(width), int(height))
        return True


@app.route("/")
def index():
    return render_template_string(PANEL_HTML_V2)

@app.route("/logo")
def logo():
    if LOGO.exists():
        return send_file(LOGO)
    return "", 404


@app.route("/paradis-logo")
def paradis_logo():
    if PARADIS_LOGO.exists():
        return send_file(PARADIS_LOGO, mimetype="image/jpeg")
    return "", 404

@app.route("/state")
def state():
    web_ready = tcp_ok(WEB_PORT)
    if web_ready:
        remote_state, identity = current_identity_status()
    else:
        remote_state = {}
        identity = {"valid": False, "code": "offline", "message": "Serveur HTTP absent"}
    server_valid = bool(identity["valid"])
    try:
        configured_profiles = load_profiles()
        configured_target = configured_profiles.active_target().to_dict()
        public_profiles = configured_profiles.to_dict()["profiles"]
        active_mode = configured_profiles.active_mode
        network_config_error = None
    except AbletonTargetError as exc:
        configured_profiles = None
        configured_target = None
        public_profiles = None
        active_mode = None
        network_config_error = str(exc)
    ltc_destination = "127.0.0.1" if active_mode == "local" else get_lan_ip()
    live_set_ready = bool(remote_state.get("set_ready")) if server_valid else False
    reply_port = int((configured_target or {}).get("reply_port", RETURN_PORT))
    send_port = int((configured_target or {}).get("send_port", OSC_PORT))
    osc_return_ready = port_used(reply_port)
    transport_connected = bool((remote_state.get("osc_transport") or {}).get("connected"))
    osc_send_ready = port_used(send_port) if (configured_target or {}).get("mode", "local") == "local" else transport_connected
    system_ready = server_valid and live_set_ready and osc_return_ready
    response_payload = dict(
        web=web_ready,
        osc=osc_send_ready,
        ret=osc_return_ready,
        local_url=REMOTE_ROOT_URL,
        lan_url=REMOTE_ROOT_LAN_URL(),
        events=events[-5:],
        set_ready=remote_state.get("set_ready"),
        set_generation=remote_state.get("set_generation"),
        state_object_id=remote_state.get("state_object_id"),
        server_process_id=remote_state.get("server_process_id"),
        launcher_process_id=os.getpid(),
        remote_state_error=remote_state.get("diagnostic_error"),
        server_valid=server_valid,
        live_set_ready=live_set_ready,
        system_ready=system_ready,
        identity_status=identity["code"],
        identity_message=identity["message"],
        launch_id=remote_state.get("launch_id"),
        server_instance_id=remote_state.get("server_instance_id"),
        build_id=remote_state.get("build_id"),
        identity_protocol_version=remote_state.get("identity_protocol_version"),
        bootstrap_step=remote_state.get("bootstrap_step"),
        bootstrap_running=remote_state.get("bootstrap_running"),
        bootstrap_generation=remote_state.get("bootstrap_generation"),
        last_successful_bootstrap=remote_state.get("last_successful_bootstrap"),
        pending_request=remote_state.get("pending_request"),
        ableton_config=configured_target,
        ableton_active_mode=active_mode,
        ableton_profiles=public_profiles,
        ableton_server_target=remote_state.get("ableton_target"),
        network_config_error=network_config_error,
        osc_transport=remote_state.get("osc_transport"),
        playing_scene_name=remote_state.get("playing_scene_name"),
        ltc_connected=remote_state.get("ltc_connected", False),
        ltc_timecode=remote_state.get("ltc_timecode", "--:--:--:--"),
        ltc_destination=ltc_destination,
        ltc_port=LTC_PORT,
        midi_console=read_midi_console_state((configured_target or {}).get("host")),
        orphan_actions_available=identity["code"] == "orphan-claimable",
        orphan_instance_id=(remote_state.get("server_instance_id") or "")[:8] or None,
        orphan_process_id=remote_state.get("server_process_id") if identity["code"] == "orphan-claimable" else None,
        orphan_started_at=remote_state.get("started_at") if identity["code"] == "orphan-claimable" else None,
    )
    launcher_diagnostic_log({
        "source": "LauncherState",
        "event": "state-response",
        "panelSystemReady": system_ready,
        "serverValid": server_valid,
        "liveSetReady": live_set_ready,
        "systemReady": system_ready,
        "identityStatus": identity["code"],
        "identityReason": identity["message"],
        "launchId": remote_state.get("launch_id"),
        "serverInstanceId": remote_state.get("server_instance_id"),
        "buildId": remote_state.get("build_id"),
        "setReady": response_payload["set_ready"],
        "setGeneration": response_payload["set_generation"],
        "stateObjectId": response_payload["state_object_id"],
        "serverProcessId": response_payload["server_process_id"],
        "launcherProcessId": response_payload["launcher_process_id"],
        "webPortReady": response_payload["web"],
        "oscSendPortPresent": response_payload["osc"],
        "oscReturnPortPresent": response_payload["ret"],
    })
    return jsonify(response_payload)


@app.route("/telemetry")
def telemetry():
    """Relais minimal et non bloquant pour l'affichage fluide du LTC."""
    remote_state = read_remote_state_diagnostic(timeout=0.12)
    return jsonify(
        ltc_connected=bool(remote_state.get("ltc_connected")),
        ltc_timecode=remote_state.get("ltc_timecode", "--:--:--:--"),
    )


@app.route("/network-config", methods=["GET", "POST"])
def network_config():
    if request.method == "GET":
        try:
            profiles = load_profiles()
            return jsonify({
                **profiles.to_dict(),
                "active_target": profiles.active_target().to_dict(),
            })
        except AbletonTargetError as exc:
            return jsonify(error=str(exc)), 409

    payload = request.get_json(silent=True)
    try:
        previous_profiles = load_profiles()
        previous = previous_profiles.active_target()
        if not isinstance(payload, dict):
            raise AbletonTargetError("configuration Ableton invalide")
        allowed = {"mode", "name", "host", "send_port", "reply_port"}
        if set(payload) - allowed:
            raise AbletonTargetError("champs de configuration inconnus")
        candidate = validate_target({key: value for key, value in payload.items() if key != "name"})
        candidate_profiles = update_profile(
            previous_profiles,
            candidate,
            name=payload.get("name"),
            activate=True,
        )
    except AbletonTargetError as exc:
        return jsonify(error=str(exc)), 400
    if candidate_profiles == previous_profiles:
        return jsonify(
            message="Configuration OSC inchangée",
            target=candidate.to_dict(),
            profiles=candidate_profiles.to_dict(),
        )

    server_was_running = tcp_ok(WEB_PORT)
    if server_was_running:
        _, identity = current_identity_status()
        if not identity.get("valid"):
            return jsonify(error="Configuration refusée : le serveur actif n'est pas possédé par ce launcher"), 409
    try:
        save_profiles(candidate_profiles)
    except AbletonTargetError as exc:
        return jsonify(error=str(exc)), 400

    if server_was_running:
        stopped, stop_message = stop_owned_server()
        if not stopped:
            save_profiles(previous_profiles)
            return jsonify(error=f"Configuration annulée : {stop_message}"), 409
        started, start_message = start_web_server()
        if not started:
            save_profiles(previous_profiles)
            restored, restore_message = start_web_server()
            suffix = "ancienne configuration restaurée" if restored else f"restauration impossible : {restore_message}"
            return jsonify(error=f"Nouvelle configuration non démarrée : {start_message} ; {suffix}"), 409
    event(f"AbletonOSC configuré en mode {candidate.mode} ({candidate.host}:{candidate.send_port})")
    return jsonify(
        message="Configuration OSC appliquée" + (" et serveur redémarré" if server_was_running else ""),
        target=candidate.to_dict(),
        profiles=candidate_profiles.to_dict(),
    )


@app.route("/test-ableton", methods=["POST"])
def test_ableton():
    ok, message = ensure_valid_server()
    if not ok:
        return jsonify(error=message), 409
    request_test = urllib.request.Request(f"{REMOTE_ROOT_URL}transport/test", method="POST")
    try:
        with urllib.request.urlopen(request_test, timeout=1.5) as response:
            payload = json.loads(response.read().decode("utf-8"))
            return jsonify(payload)
    except urllib.error.HTTPError as exc:
        try:
            payload = json.loads(exc.read().decode("utf-8"))
        except Exception:
            payload = {"error": "Aucune réponse d'Ableton"}
        return jsonify(error=payload.get("message") or payload.get("error"), latency_ms=None), 504
    except Exception as exc:
        return jsonify(error=f"Test Ableton impossible : {exc}"), 504

@app.route("/start")
def start():
    ok, message = ensure_valid_server()
    if not ok:
        event(f"Démarrage refusé : {message}")
        return jsonify(error=message), 409
    event(message)
    return jsonify(message=message)


@app.route("/orphan/adopt", methods=["POST"])
def orphan_adopt():
    ok, message = adopt_claimable_server()
    event(message)
    return jsonify(message=message) if ok else (jsonify(error=message), 409)


@app.route("/orphan/stop", methods=["POST"])
def orphan_stop():
    ok, message = stop_claimable_server()
    event(message)
    return jsonify(message=message) if ok else (jsonify(error=message), 409)


@app.route("/orphan/cancel", methods=["POST"])
def orphan_cancel():
    global ignored_orphan_instance_id
    payload, identity = current_identity_status()
    if identity.get("code") != "orphan-claimable":
        return jsonify(error="Aucune instance orpheline récupérable"), 409
    ignored_orphan_instance_id = payload.get("server_instance_id")
    event("Instance orpheline laissée intacte")
    return jsonify(message="Instance orpheline laissée intacte")

@app.route("/stop")
def stop():
    ok, message = stop_owned_server()
    if not ok:
        event(message)
        return jsonify(error=message), 409
    event(message)
    return jsonify(message=message)

@app.route("/restart")
def restart():
    if tcp_ok(WEB_PORT):
        ok, message = stop_owned_server()
        if not ok:
            event(f"Redémarrage refusé : {message}")
            return jsonify(error=message), 409
    ok, message = start_web_server()
    if not ok:
        event(f"Redémarrage impossible : {message}")
        return jsonify(error=message), 409
    event("Serveur relancé et validé")
    return jsonify(message="Serveur relancé et validé")

@app.route("/open")
def open_web():
    ok, message = ensure_valid_server()
    if not ok:
        return jsonify(error=message), 409
    mode = open_remote_app_window(REMOTE_ROOT_URL, "Télécommande Ableton — Session")
    event("Onglet Session ouvert")
    return jsonify(message=f"Onglet Session ouvert en {mode}", url=REMOTE_ROOT_URL)


@app.route("/local-page")
def local_page():
    ok, message = ensure_valid_server()
    if not ok:
        return jsonify(error=message), 409
    webbrowser.open(REMOTE_ROOT_URL)
    event("Page locale ouverte")
    return jsonify(message="Page locale ouverte dans le navigateur", url=REMOTE_ROOT_URL)

@app.route("/open-ab")
def open_ab():
    ok, message = ensure_valid_server()
    if not ok:
        return jsonify(error=message), 409
    desktop_url = f"{REMOTE_AB_URL}?desktop=1&v=2.0.1"
    mode = open_remote_app_window(desktop_url, "Télécommande Ableton — A/B")
    event("Onglet A/B ouvert")
    return jsonify(message=f"Onglet A/B ouvert en {mode}", url=desktop_url)


@app.route("/open-arrangement")
def open_arrangement():
    ok, message = ensure_valid_server()
    if not ok:
        return jsonify(error=message), 409
    mode = open_remote_app_window(REMOTE_ARRANGEMENT_URL, "Télécommande Ableton — Arrangement")
    event("Onglet Arrangement ouvert")
    return jsonify(message=f"Onglet Arrangement ouvert en {mode}", url=REMOTE_ARRANGEMENT_URL)

@app.route("/remote-window")
def remote_window():
    ok, message = ensure_valid_server()
    if not ok:
        return jsonify(error=message), 409

    mode = open_remote_app_window(REMOTE_ROOT_URL, "Télécommande Ableton")
    event("Télécommande ouverte sur Session")
    return jsonify(message=f"Télécommande ouverte sur Session en {mode}", url=REMOTE_ROOT_URL)


@app.route("/midi-network-assistant")
def open_midi_network_assistant():
    assistant = find_midi_network_assistant()
    if assistant is None:
        return jsonify(error="CL MIDI Network Assistant n’est pas installé"), 404
    subprocess.Popen(["/usr/bin/open", str(assistant)])
    event("Diagnostic RTP ouvert depuis Show Control")
    return jsonify(message="Diagnostic RTP ouvert")

@app.route("/quit")
def quit_launcher():
    event("Launcher fermé")

    def close_owned_processes():
        stop_owned_server()
        stop_midi_console_monitor()
        os._exit(0)

    threading.Timer(0.5, close_owned_processes).start()
    return jsonify(message="Launcher fermé")


if __name__ == "__main__":
    if "--serve" in sys.argv:
        run_embedded_server()
        raise SystemExit(0)

    print("=== LAUNCHER_CONTROL VERSION WEBVIEW ACTIVE ===", flush=True)
    print("Fichier exécuté :", __file__, flush=True)
    print("Python utilisé :", sys.executable, flush=True)
    CONTROL_URL = f"http://127.0.0.1:{LAUNCHER_PORT}"

    def run_control_server():
        app.run(host="127.0.0.1", port=LAUNCHER_PORT, debug=False, use_reloader=False, threaded=True)

    server_thread = threading.Thread(target=run_control_server, daemon=True)
    server_thread.start()
    ensure_midi_console_monitor()
    time.sleep(1.0)

    if webview is None:
        print("ERREUR : pywebview n'est pas installé dans ce Python.", flush=True)
        print("Installe-le avec : python3 -m pip install pywebview", flush=True)
        print("Ouverture navigateur de secours :", CONTROL_URL, flush=True)
        webbrowser.open(CONTROL_URL)
        raise SystemExit(0)

    print("Ouverture du panneau de contrôle en fenêtre autonome :", CONTROL_URL, flush=True)
    panel_api = ControlPanelWindowApi()
    panel_window = webview.create_window(
        "CL AUDIO SHOW CONTROL",
        CONTROL_URL,
        width=500,
        height=900,
        min_size=(460, 420),
        resizable=True,
        confirm_close=False,
        text_select=True,
        js_api=panel_api,
    )
    panel_api.window = panel_window
    webview.start(gui="cocoa", debug=False)
    stop_owned_server()
    stop_midi_console_monitor()
