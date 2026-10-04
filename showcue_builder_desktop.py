"""Fenêtre locale dédiée au Builder, servie par le backend CL Audio existant."""

import base64
import io
import json
import os
import tempfile
import threading
from pathlib import Path
import zipfile

from showcue_builder import recover_builder_document
from show_cues import load_document_data
from showcue_session_archive import MAX_ARCHIVE_BYTES

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
    def __init__(self):
        self.window = None

    def save_export(self, filename, payload_base64):
        """Save only bytes fetched by the protected page, to a user-picked file."""
        temporary = None
        try:
            if self.window is None:
                raise ValueError("Fenêtre d’enregistrement indisponible")
            filename = Path(filename).name
            suffix = Path(filename).suffix.lower()
            if suffix not in {".csv", ".xlsx", ".showcue"}:
                raise ValueError("Format d’export non autorisé")
            if len(payload_base64) > ((MAX_ARCHIVE_BYTES + 2) // 3) * 4:
                raise ValueError("Export trop volumineux")
            payload = base64.b64decode(payload_base64, validate=True)
            selected = self.window.create_file_dialog(
                webview.FileDialog.SAVE, save_filename=filename,
                file_types=(f"Export ShowCue (*{suffix})",),
            )
            if not selected:
                return {"status": "cancelled"}
            destination = Path(selected if isinstance(selected, str) else selected[0])
            # The native dialog owns overwrite confirmation; no silent fallback path.
            descriptor, temporary = tempfile.mkstemp(prefix=".showcue-export-", dir=destination.parent)
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(payload)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, destination)
            temporary = None
            return {"status": "saved", "path": str(destination)}
        except (OSError, ValueError, TypeError) as exc:
            return {"status": "error", "message": str(exc)}
        finally:
            if temporary is not None:
                Path(temporary).unlink(missing_ok=True)

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


class BuilderCloseGuard:
    """Never wait for WebKit while Cocoa is executing windowShouldClose."""
    def __init__(self, window):
        self.window = window
        self._lock = threading.Lock()
        self._checking = False
        self._allowed = False

    def __call__(self):
        with self._lock:
            if self._allowed:
                return True
            if self._checking:
                return False
            self._checking = True
        threading.Thread(target=self._check, daemon=True).start()
        return False

    def _check(self):
        try:
            try:
                allowed = self.window.evaluate_js(
                    "window.clBuilderLifecycle ? window.clBuilderLifecycle.canClose() : null")
            except Exception:
                allowed = None
            if allowed is None:
                allowed = self.window.create_confirmation_dialog(
                    "Fermer CL Cue Editor",
                    "L’état de sauvegarde n’a pas pu être vérifié. Fermer sans garantie de sauvegarde ?")
            if allowed is True:
                with self._lock:
                    self._allowed = True
                self.window.destroy()
        finally:
            with self._lock:
                self._checking = False


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
        bridge = BuilderRecoveryApi()
        window = webview.create_window("CL Cue Editor — Préparation locale", BUILDER_URL,
                              width=1500, height=900, min_size=(900, 600),
                              js_api=bridge)
        bridge.window = window
        window.events.closing += BuilderCloseGuard(window)
        window.events.loaded += lambda: enable_legacy_session_files(window)
    webview.start(
        private_mode=False,
        storage_path=str(Path.home() / "Library/Application Support/CL Audio Show Control/CueEditorWebView"),
        localization={"global.saveFile": "Enregistrer sous…", "global.cancel": "Annuler", "global.quit": "Quitter"},
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
