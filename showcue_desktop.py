"""Fenêtre desktop dédiée à CL ShowCue.

L'interface est servie par le backend existant CL Audio Show Control.
Aucune logique ShowCue n'est dupliquée ici.
"""

import sys
import urllib.error
import urllib.request

import webview


SHOWCUE_URL = "http://127.0.0.1:5050/show-info"


def backend_available():
    try:
        with urllib.request.urlopen(SHOWCUE_URL, timeout=2) as response:
            return response.status == 200
    except (OSError, urllib.error.URLError):
        return False


def main():
    if not backend_available():
        webview.create_window(
            "CL ShowCue",
            html="""
            <html>
            <body style="
                margin:0;
                background:#080a0e;
                color:#f6f8fb;
                font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
                display:flex;
                align-items:center;
                justify-content:center;
                min-height:100vh;
            ">
              <div style="max-width:560px;padding:40px;text-align:center">
                <h2 style="margin-bottom:18px">CL ShowCue</h2>
                <p style="color:#a9b0bb;line-height:1.5">
                  CL Audio Show Control n’est pas démarré.
                </p>
                <p style="color:#a9b0bb;line-height:1.5">
                  Démarrez l’application principale puis relancez CL ShowCue.
                </p>
              </div>
            </body>
            </html>
            """,
            width=680,
            height=380,
            min_size=(520, 300),
        )
    else:
        webview.create_window(
            "CL ShowCue",
            SHOWCUE_URL,
            width=1500,
            height=950,
            min_size=(900, 600),
        )

    webview.start()
    return 0


if __name__ == "__main__":
    sys.exit(main())
