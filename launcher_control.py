import socket, subprocess, webbrowser, threading, os, time, sys, importlib.util

try:
    import webview
except ModuleNotFoundError:
    webview = None
from pathlib import Path
from flask import Flask, jsonify, render_template_string, send_file

ROOT = Path(__file__).resolve().parent
APP = ROOT / "app.py"
PYTHON = ROOT / ".venv" / "bin" / "python"


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
OSC_PORT = 11000
RETURN_PORT = 11001
LAUNCHER_PORT = 5055
REMOTE_WINDOW_SCRIPT = ROOT / "remote_window.py"
REMOTE_ROOT_URL = f"http://127.0.0.1:{WEB_PORT}/"
REMOTE_AB_URL = f"http://127.0.0.1:{WEB_PORT}/ab"
REMOTE_ARRANGEMENT_URL = f"http://127.0.0.1:{WEB_PORT}/arrangement"
REMOTE_ROOT_LAN_URL = lambda: f"http://{get_lan_ip()}:{WEB_PORT}/"
REMOTE_APP_NAME = "Télécommande Ableton.app"
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


def start_web_server():
    if getattr(sys, "frozen", False):
        subprocess.Popen([sys.executable, "--serve"], cwd=str(ROOT))
    else:
        py = str(PYTHON if PYTHON.exists() else sys.executable)
        subprocess.Popen([py, str(APP)], cwd=str(ROOT))
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
  if(s.web){m.textContent="● SERVEUR EN MARCHE";m.className="ok";statusBox.className="status ready";}
  else{m.textContent="● SERVEUR ARRÊTÉ";m.className="off";statusBox.className="status stopped";}
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

def kill_server():
    if getattr(sys, "frozen", False):
        subprocess.run(["pkill", "-f", f"{sys.executable} --serve"], stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "app.py"], stderr=subprocess.DEVNULL)
    subprocess.run(f"lsof -ti :{WEB_PORT} | xargs kill -9", shell=True, stderr=subprocess.DEVNULL)

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
  try{const r=await (await fetch(path)).json();status.textContent=r.message||'Terminé.';}
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
.app{width:440px;max-width:calc(100% - 16px);height:100%;margin:auto;padding:12px;display:flex;flex-direction:column;gap:10px}
.brand{height:84px;border-radius:14px;background:#020304;border:1px solid #272a31;display:flex;align-items:center;justify-content:center;overflow:hidden;box-shadow:0 10px 24px rgba(0,0,0,.28)}
.brand img{width:100%;height:100%;object-fit:contain}
.product-row{display:flex;align-items:center;justify-content:space-between;min-height:24px}
.product{font-size:13px;font-weight:760;letter-spacing:.04em;color:#d6dae3}
.show-toggle{height:25px;padding:0 10px;border:1px solid #3a3f49;border-radius:8px;background:#21252d;color:#c7ccd6;font-size:11px;cursor:pointer}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:12px;box-shadow:0 8px 20px rgba(0,0,0,.18)}
.system{display:grid;grid-template-columns:14px 1fr auto;gap:10px;align-items:center;min-height:62px;transition:.2s}
.system .dot{width:11px;height:11px;border-radius:50%;background:#69707d;box-shadow:0 0 0 4px rgba(105,112,125,.10)}
.system.ready{border-color:rgba(67,200,111,.58);background:linear-gradient(135deg,rgba(67,200,111,.12),var(--card))}
.system.ready .dot{background:var(--green);box-shadow:0 0 12px rgba(67,200,111,.75)}
.system.warning{border-color:rgba(229,166,59,.62);background:linear-gradient(135deg,rgba(229,166,59,.12),var(--card))}
.system.warning .dot{background:var(--orange);box-shadow:0 0 12px rgba(229,166,59,.65)}
.system.error{border-color:rgba(217,88,88,.64);background:linear-gradient(135deg,rgba(217,88,88,.12),var(--card))}
.system.error .dot{background:var(--red);box-shadow:0 0 12px rgba(217,88,88,.65)}
.system.busy .dot{background:var(--blue);animation:pulse 1s infinite}
@keyframes pulse{50%{opacity:.35;transform:scale(.75)}}
.state-title{font-size:18px;font-weight:820;letter-spacing:.01em}
.state-detail{font-size:12px;color:var(--muted);margin-top:3px}
.state-time{font-size:10px;color:#858c98;align-self:start;padding-top:3px}
.primary{height:48px;width:100%;border:1px solid rgba(88,162,255,.72);border-radius:12px;background:linear-gradient(180deg,#408ce7,#2868b8);color:white;font-size:15px;font-weight:790;cursor:pointer;box-shadow:0 8px 18px rgba(32,101,190,.22)}
.primary:hover{filter:brightness(1.08)}
.secondary-actions{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.action{height:38px;border-radius:10px;border:1px solid #404651;background:#252a33;color:#e2e6ed;font-size:13px;font-weight:700;cursor:pointer}
.action.start{border-color:rgba(67,200,111,.55);background:rgba(67,200,111,.16)}
.action.restart{border-color:rgba(229,166,59,.62);background:rgba(229,166,59,.17)}
.action:hover{filter:brightness(1.12)}
.action-status{min-height:18px;font-size:11px;color:var(--muted);padding:2px 3px 0}
.access-head,.tech-head{font-size:11px;font-weight:780;text-transform:uppercase;letter-spacing:.08em;color:#c9ced8;margin-bottom:8px}
.address-row{display:grid;grid-template-columns:1fr auto auto;gap:7px;align-items:center}
.address{height:34px;display:flex;align-items:center;padding:0 10px;border-radius:9px;background:#11141a;border:1px solid #303540;font:12px Menlo,monospace;color:#e4e8ee;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.mini{height:34px;padding:0 10px;border-radius:9px;border:1px solid #424853;background:#272c35;color:#e5e8ee;font-size:11px;font-weight:700;cursor:pointer}
.device-row{display:flex;justify-content:space-between;align-items:center;margin-top:9px;font-size:12px;color:var(--muted)}
.badge{padding:4px 8px;border-radius:999px;background:rgba(67,200,111,.12);color:#7ee39e;border:1px solid rgba(67,200,111,.28);font-size:10px}
details{background:var(--card2);border:1px solid #292e37;border-radius:12px;overflow:hidden}
summary{height:34px;padding:0 11px;display:flex;align-items:center;cursor:pointer;font-size:12px;color:#c5cad3;list-style:none}
summary::-webkit-details-marker{display:none}
summary::before{content:'›';font-size:18px;margin-right:7px;transition:.15s}
details[open] summary::before{transform:rotate(90deg)}
.technical{border-top:1px solid #292e37;padding:8px 11px 10px;display:grid;grid-template-columns:1fr 1fr;gap:7px}
.tech-item{display:grid;grid-template-columns:8px 1fr;gap:6px;align-items:center;font-size:10px;color:#aeb4bf}
.tech-led{width:6px;height:6px;border-radius:50%;background:#555d69}
.tech-item.on .tech-led{background:var(--green);box-shadow:0 0 7px rgba(67,200,111,.65)}
.event-list{grid-column:1/-1;border-top:1px solid #292e37;padding-top:7px;font-size:10px;color:#8f97a5;line-height:1.45;max-height:45px;overflow:hidden}
.bottom{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-top:auto}
.local{height:30px;border:0;background:transparent;color:#91a9cb;font-size:11px;cursor:pointer}
.stop{height:30px;padding:0 11px;border-radius:8px;border:1px solid rgba(217,88,88,.42);background:rgba(217,88,88,.10);color:#e68b8b;font-size:11px;cursor:pointer}
.footer{font-size:9px;color:#707784;letter-spacing:.05em;text-align:center}
body.show-mode .secondary-actions,body.show-mode details,body.show-mode .bottom{display:none}
body.show-mode .app{justify-content:center;max-height:470px}
body.show-mode .brand{height:105px}
body.show-mode .system{min-height:86px}
</style>
</head>
<body>
<main class="app">
  <div class="brand"><img src="/paradis-logo" alt="Paradis Latin Cabaret"></div>
  <div class="product-row"><div class="product">CL AUDIO SHOW CONTROL</div><button id="showMode" class="show-toggle" onclick="toggleShowMode()">Mode spectacle</button></div>

  <section id="systemCard" class="card system warning">
    <span class="dot"></span>
    <div><div id="stateTitle" class="state-title">VÉRIFICATION…</div><div id="stateDetail" class="state-detail">Contrôle des services en cours</div></div>
    <span id="stateTime" class="state-time">—</span>
  </section>

  <button class="primary" onclick="runAction('/remote-window','Ouverture de la télécommande')">OUVRIR LA TÉLÉCOMMANDE</button>

  <div class="secondary-actions">
    <button class="action start" onclick="runAction('/start','Démarrage du serveur')">▶&nbsp;&nbsp;Démarrer</button>
    <button class="action restart" onclick="runAction('/restart','Relance du serveur')">↻&nbsp;&nbsp;Relancer</button>
  </div>
  <div id="actionStatus" class="action-status">Prêt.</div>

  <section class="card">
    <div class="access-head">Accès distant</div>
    <div class="address-row">
      <div id="remoteAddress" class="address">—</div>
      <button class="mini" onclick="copyAddress()">Copier</button>
      <button class="mini" onclick="runAction('/local-page','Ouverture locale')">Ouvrir</button>
    </div>
    <div class="device-row"><span>Télécommande iPhone / iPad</span><span id="deviceBadge" class="badge">Disponible</span></div>
  </section>

  <details>
    <summary>Détails techniques et événements</summary>
    <div class="technical">
      <div id="techWeb" class="tech-item"><span class="tech-led"></span><span>Serveur Web · 5050</span></div>
      <div id="techOsc" class="tech-item"><span class="tech-led"></span><span>OSC aller · 11000</span></div>
      <div id="techReturn" class="tech-item"><span class="tech-led"></span><span>OSC retour · 11001</span></div>
      <div class="tech-item on"><span class="tech-led"></span><span id="localAddress">Adresse Mac</span></div>
      <div id="events" class="event-list">Aucun événement récent.</div>
    </div>
  </details>

  <div class="bottom"><button class="local" onclick="runAction('/local-page','Ouverture de la page locale')">↗ Page locale</button><button class="stop" onclick="confirmStop()">■ Arrêter…</button></div>
  <div class="footer">CL AUDIO · SHOW CONTROL</div>
</main>
<script>
let latestState=null;
const el=id=>document.getElementById(id);
function setTech(id,on){el(id).className='tech-item '+(on?'on':'');}
function setBusy(label){el('systemCard').className='card system busy';el('stateTitle').textContent=label.toUpperCase();el('stateDetail').textContent='Veuillez patienter…';}
function render(s){
  latestState=s;const card=el('systemCard'),title=el('stateTitle'),detail=el('stateDetail');
  if(s.web&&s.ret){card.className='card system ready';title.textContent='SYSTÈME PRÊT';detail.textContent=s.osc?'Serveur et liaisons OSC opérationnels':'Serveur prêt · attente d’AbletonOSC';}
  else if(s.web){card.className='card system warning';title.textContent='CONNEXION PARTIELLE';detail.textContent='Le serveur répond, liaison OSC incomplète';}
  else{card.className='card system error';title.textContent='SYSTÈME ARRÊTÉ';detail.textContent='Démarrez le serveur avant le spectacle';}
  const now=new Date();el('stateTime').textContent=now.toLocaleTimeString('fr-FR',{hour:'2-digit',minute:'2-digit'});
  el('remoteAddress').textContent=s.lan_url;el('localAddress').textContent=s.local_url.replace(/^https?:\/\//,'');
  setTech('techWeb',s.web);setTech('techOsc',s.osc);setTech('techReturn',s.ret);
  el('events').innerHTML=(s.events||[]).slice().reverse().join('<br>')||'Aucun événement récent.';
}
async function refresh(){try{render(await(await fetch('/state')).json());}catch(e){el('systemCard').className='card system error';el('stateTitle').textContent='PANNEAU HORS LIGNE';el('stateDetail').textContent=String(e);}}
async function runAction(path,label){setBusy(label);el('actionStatus').textContent=label+'…';try{const r=await(await fetch(path)).json();el('actionStatus').textContent='✓ '+(r.message||'Action terminée');}catch(e){el('actionStatus').textContent='! '+e;}setTimeout(refresh,450);}
function confirmStop(){if(confirm('Arrêter le serveur de télécommande ?\n\nLes appareils connectés perdront immédiatement l’accès.'))runAction('/stop','Arrêt du serveur');}
async function copyAddress(){if(!latestState)return;try{await navigator.clipboard.writeText(latestState.lan_url);el('actionStatus').textContent='✓ Adresse copiée';}catch(e){el('actionStatus').textContent='Adresse : '+latestState.lan_url;}}
function toggleShowMode(){document.body.classList.toggle('show-mode');el('showMode').textContent=document.body.classList.contains('show-mode')?'Quitter le mode spectacle':'Mode spectacle';}
refresh();setInterval(refresh,1500);
</script>
</body>
</html>
'''


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
    return jsonify(
        web=tcp_ok(WEB_PORT),
        osc=port_used(OSC_PORT),
        ret=port_used(RETURN_PORT),
        local_url=REMOTE_ROOT_URL,
        lan_url=REMOTE_ROOT_LAN_URL(),
        events=events[-5:]
    )

@app.route("/start")
def start():
    kill_server()
    start_web_server()
    event("Serveur lancé")
    return jsonify(message="Serveur lancé")

@app.route("/stop")
def stop():
    kill_server()
    event("Serveur arrêté")
    return jsonify(message="Serveur arrêté")

@app.route("/restart")
def restart():
    kill_server()
    start_web_server()
    event("Serveur relancé")
    return jsonify(message="Serveur relancé")

@app.route("/open")
def open_web():
    if not tcp_ok(WEB_PORT):
        start_web_server()
        time.sleep(1.0)
        event("Serveur lancé")
    mode = open_remote_app_window(REMOTE_ROOT_URL, "Télécommande Ableton — Session")
    event("Onglet Session ouvert")
    return jsonify(message=f"Onglet Session ouvert en {mode}", url=REMOTE_ROOT_URL)


@app.route("/local-page")
def local_page():
    if not tcp_ok(WEB_PORT):
        start_web_server()
        time.sleep(1.0)
        event("Serveur lancé")
    webbrowser.open(REMOTE_ROOT_URL)
    event("Page locale ouverte")
    return jsonify(message="Page locale ouverte dans le navigateur", url=REMOTE_ROOT_URL)

@app.route("/open-ab")
def open_ab():
    if not tcp_ok(WEB_PORT):
        start_web_server()
        time.sleep(1.0)
        event("Serveur lancé")
    desktop_url = f"{REMOTE_AB_URL}?desktop=1&v=2.0.1"
    mode = open_remote_app_window(desktop_url, "Télécommande Ableton — A/B")
    event("Onglet A/B ouvert")
    return jsonify(message=f"Onglet A/B ouvert en {mode}", url=desktop_url)


@app.route("/open-arrangement")
def open_arrangement():
    if not tcp_ok(WEB_PORT):
        start_web_server()
        time.sleep(1.0)
        event("Serveur lancé")
    mode = open_remote_app_window(REMOTE_ARRANGEMENT_URL, "Télécommande Ableton — Arrangement")
    event("Onglet Arrangement ouvert")
    return jsonify(message=f"Onglet Arrangement ouvert en {mode}", url=REMOTE_ARRANGEMENT_URL)

@app.route("/remote-window")
def remote_window():
    if not tcp_ok(WEB_PORT):
        start_web_server()
        time.sleep(1.0)
        event("Serveur lancé")

    mode = open_remote_app_window(REMOTE_ROOT_URL, "Télécommande Ableton")
    event("Télécommande ouverte sur Session")
    return jsonify(message=f"Télécommande ouverte sur Session en {mode}", url=REMOTE_ROOT_URL)

@app.route("/quit")
def quit_launcher():
    event("Launcher fermé")
    threading.Timer(0.5, lambda: os._exit(0)).start()
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
    time.sleep(1.0)

    if webview is None:
        print("ERREUR : pywebview n'est pas installé dans ce Python.", flush=True)
        print("Installe-le avec : python3 -m pip install pywebview", flush=True)
        print("Ouverture navigateur de secours :", CONTROL_URL, flush=True)
        webbrowser.open(CONTROL_URL)
        raise SystemExit(0)

    print("Ouverture du panneau de contrôle en fenêtre autonome :", CONTROL_URL, flush=True)
    webview.create_window(
        "CL AUDIO SHOW CONTROL",
        CONTROL_URL,
        width=470,
        height=580,
        min_size=(440, 540),
        resizable=True,
        confirm_close=False,
        text_select=True,
    )
    webview.start(gui="cocoa", debug=False)
