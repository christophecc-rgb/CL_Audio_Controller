try:
    import webview
except ModuleNotFoundError:
    webview = None

import webbrowser
import json
import threading
import time
from pathlib import Path

KEYBOARD_LOG_PATH = Path("/private/tmp/CL_Audio_Controller_keyboard.log")
keyboard_log_lock = threading.Lock()


class KeyboardDiagnosticAPI:
    def keyboard_log(self, record):
        payload = dict(record) if isinstance(record, dict) else {"message": str(record)}
        payload.setdefault("source", "Wrapper")
        payload.setdefault("timestamp", int(time.time() * 1000))
        line = json.dumps(payload, ensure_ascii=False, sort_keys=True, default=str)
        print(f"[KEYBOARD] {line}", flush=True)
        try:
            with keyboard_log_lock:
                with KEYBOARD_LOG_PATH.open("a", encoding="utf-8") as handle:
                    handle.write(line + "\n")
        except Exception as exc:
            print(f"[KEYBOARD] écriture impossible: {exc}", flush=True)
        return True

REMOTE_URL = "http://127.0.0.1:5050"
BASE_WIDTH = 390
BASE_HEIGHT = 760

HTML = f"""
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Télécommande Ableton</title>
<style>
  * {{
    box-sizing: border-box;
  }}

  html, body {{
    margin: 0;
    width: 100%;
    height: 100%;
    overflow: hidden;
    background: #05070b;
  }}

  body {{
    display: flex;
    align-items: center;
    justify-content: center;
  }}

  #stage {{
    position: relative;
    width: 100vw;
    height: 100vh;
    overflow: hidden;
    background: #05070b;
  }}

  #remote {{
    position: absolute;
    left: 50%;
    top: 50%;
    width: {BASE_WIDTH}px;
    height: {BASE_HEIGHT}px;
    transform-origin: center center;
    overflow: hidden;
    border-radius: 22px;
    background: #101215;
    box-shadow: 0 18px 70px rgba(0,0,0,.45);
  }}

  iframe {{
    width: {BASE_WIDTH}px;
    height: {BASE_HEIGHT}px;
    border: 0;
    display: block;
    background: #101215;
  }}
</style>
</head>
<body>
  <div id="stage">
    <div id="remote">
      <iframe src="{REMOTE_URL}" title="Télécommande Ableton"></iframe>
    </div>
  </div>

  <script>
    const baseWidth = {BASE_WIDTH};
    const baseHeight = {BASE_HEIGHT};
    const remote = document.getElementById('remote');

    function resizeRemote() {{
      const scale = Math.min(
        (window.innerWidth - 16) / baseWidth,
        (window.innerHeight - 16) / baseHeight
      );
      remote.style.transform = `translate(-50%, -50%) scale(${{scale}})`;
    }}

    window.addEventListener('resize', resizeRemote);
    window.addEventListener('load', resizeRemote);
    const remoteFrame = document.querySelector('#remote iframe');
    function wrapperDiagnosticLog(eventName, details = {{}}) {{
      const record = {{ source: 'Wrapper', event: eventName, ...details }};
      console.info(`[KEYBOARD][Wrapper] ${{eventName}}`, record);
      if (window.pywebview && window.pywebview.api && window.pywebview.api.keyboard_log) {{
        window.pywebview.api.keyboard_log(record).catch(() => {{}});
      }}
    }}
    function wrapperWindowHasFocus() {{
      return typeof window.hasFocus === 'function' ? window.hasFocus() : document.hasFocus();
    }}
    function wrapperFocusSnapshot() {{
      return {{
        windowHasFocus: wrapperWindowHasFocus(),
        documentHasFocus: document.hasFocus(),
        activeElement: document.activeElement && document.activeElement.tagName,
        activeElementId: document.activeElement && document.activeElement.id,
        iframeIsActiveElement: document.activeElement === remoteFrame,
        iframeMatchesFocus: remoteFrame.matches(':focus')
      }};
    }}
    window.addEventListener('pywebviewready', () => {{
      wrapperDiagnosticLog('initialized', {{
        diagnosticCase: 'INITIALIZED_CASE_4_EXCLUDED',
        timestamp: Date.now(),
        ...wrapperFocusSnapshot()
      }});
    }});
    remoteFrame.addEventListener('load', () => {{
      wrapperDiagnosticLog('iframe-loaded', {{
        timestamp: Date.now(),
        ...wrapperFocusSnapshot()
      }});
    }});
    document.addEventListener('keydown', event => {{
      wrapperDiagnosticLog('keydown', {{
        diagnosticCase: 'CASE_1_WRAPPER_RECEIVED',
        timestamp: Date.now(),
        key: event.key,
        code: event.code,
        repeat: event.repeat,
        ...wrapperFocusSnapshot()
      }});
    }});
    resizeRemote();
  </script>
</body>
</html>
"""

if __name__ == "__main__":
    if webview is None:
        fallback_url = REMOTE_URL
        print("pywebview n'est pas installé. Ouverture navigateur :", fallback_url)
        webbrowser.open(fallback_url)
        raise SystemExit(0)

    webview.create_window(
        "Télécommande Ableton",
        html=HTML,
        width=455,
        height=815,
        min_size=(390, 700),
        resizable=True,
        confirm_close=False,
        js_api=KeyboardDiagnosticAPI(),
    )
    webview.start()
