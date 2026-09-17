"""Fenêtre locale dédiée au Builder, servie par le backend CL Audio existant."""

import sys
import urllib.error
import urllib.request

import webview


BUILDER_URL = "http://127.0.0.1:5050/show-info/builder"


def backend_available():
    try:
        with urllib.request.urlopen(BUILDER_URL, timeout=2) as response:
            return response.status == 200
    except (OSError, urllib.error.URLError):
        return False


def main():
    if not backend_available():
        webview.create_window(
            "CL Cue Editor",
            html="<h2>CL Show Control n’est pas démarré.</h2>"
                 "<p>Démarrez l’application principale, puis relancez le Builder.</p>",
            width=640,
            height=300,
        )
    else:
        webview.create_window("CL Cue Editor — Préparation locale", BUILDER_URL,
                              width=1500, height=900, min_size=(900, 600))
    webview.start()
    return 0


if __name__ == "__main__":
    sys.exit(main())
