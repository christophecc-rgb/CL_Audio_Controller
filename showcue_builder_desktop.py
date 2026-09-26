"""Fenêtre locale dédiée au Builder, servie par le backend CL Audio existant."""

import base64
import io
import json
from pathlib import Path
import zipfile

from showcue_builder import recover_builder_document
from show_cues import load_document_data

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


# Older Show Control servers expose only .showcue.zip in their file picker.
# Keep their existing upload handler/parser, while accepting the historical suffix.
SESSION_FILE_FILTER_SCRIPT = """
(() => {
    const input = document.getElementById('cl-session-upload');
    if (input) input.accept = '.showcue,.showcue.zip';
})();
"""


def enable_legacy_session_files(window):
    window.evaluate_js(SESSION_FILE_FILTER_SCRIPT)
    window.evaluate_js((Path(__file__).resolve().parent / "static" / "showcue-sessions.js").read_text(encoding="utf-8"))


class BuilderRecoveryApi:
    def recover_builder(self, archive_base64, document):
        """Pure conversion of the server export; no direct access to user storage."""
        try:
            payload = base64.b64decode(archive_base64, validate=True)
            with zipfile.ZipFile(io.BytesIO(payload)) as archive:
                manifest = json.loads(archive.read("manifest.json"))
                if manifest.get("format") != "CL ShowCue" or manifest.get("version") != 1:
                    raise ValueError("Archive ShowCue V1 attendue")
                if archive.getinfo("show_cues.json").file_size > 256 * 1024 * 1024:
                    raise ValueError("Conduite trop volumineuse")
                show = load_document_data(json.loads(archive.read("show_cues.json")))
            return {"ok": True, "document": recover_builder_document(document, show)}
        except (ValueError, OSError, KeyError, zipfile.BadZipFile) as exc:
            return {"ok": False, "message": str(exc)}


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
        window = webview.create_window("CL Cue Editor — Préparation locale", BUILDER_URL,
                              width=1500, height=900, min_size=(900, 600),
                              js_api=BuilderRecoveryApi())
        window.events.loaded += lambda: enable_legacy_session_files(window)
    webview.start()
    return 0


if __name__ == "__main__":
    sys.exit(main())
