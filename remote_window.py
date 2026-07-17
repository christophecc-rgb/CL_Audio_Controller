try:
    import webview
except ModuleNotFoundError:
    webview = None

import webbrowser

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
    )
    webview.start()
