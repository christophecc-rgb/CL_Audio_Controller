"""Regression coverage using the historical OP 2026 V1 archive (revision 341)."""
import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch
from security_test_helper import prepare_security, admin_client

from show_cues import initialize_show_cue_sessions, active_session_paths, load_document_data
from showcue_session_archive import import_session, export_session
from showcue_builder import normalize_builder_document

FIXTURE = Path(__file__).parent / 'fixtures' / 'legacy_v1.showcue'


class LegacyImportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.registry = initialize_show_cue_sessions(self.root)
        self.payload = FIXTURE.read_bytes()
        with zipfile.ZipFile(io.BytesIO(self.payload)) as archive:
            self.original = {name: json.loads(archive.read(name)) for name in archive.namelist()}

    def assert_preserved(self, registry):
        self.assertEqual(
            registry['active_session_id'],
            self.registry['active_session_id'],
        )

        imported = registry['sessions'][-1]
        self.assertEqual(imported['name'], 'OP 2026')
        directory = self.root / 'Sessions' / imported['id']

        def normalized_expected(name):
            expected = self.original[name]

            if name == 'show_cues.json':
                normalized = load_document_data(expected)
                return {
                    'version': 1,
                    'cues': [
                        {
                            key: value
                            for key, value in cue.items()
                            if not key.startswith('_')
                        }
                        for cue in normalized['cues']
                    ],
                }

            if name == 'showcue_builder.json':
                return normalize_builder_document(expected)

            raise AssertionError(f"document inattendu : {name}")

        for name in ('show_cues.json', 'showcue_builder.json'):
            actual = json.loads((directory / name).read_text())
            self.assertEqual(actual, normalized_expected(name))

        self.assertEqual(
            self.original['showcue_builder.json']['revision'],
            341,
        )
        self.assertEqual(
            {
                cue['mode']
                for cue in self.original['show_cues.json']['cues']
            },
            {'manual', 'library', 'timed', 'realtime'},
        )

        exported = export_session(
            self.root,
            registry,
            imported['id'],
        )

        with zipfile.ZipFile(io.BytesIO(exported)) as archive:
            for name in ('show_cues.json', 'showcue_builder.json'):
                actual = json.loads(archive.read(name))
                self.assertEqual(actual, normalized_expected(name))

    def test_v1_import_and_export_preserve_documents(self):
        self.assertEqual(self.original['manifest.json'], {'format': 'CL ShowCue', 'version': 1, 'name': 'OP 2026'})
        cue_path, _ = active_session_paths(self.root, self.registry)
        before = cue_path.read_bytes()
        self.assert_preserved(import_session(self.payload, self.root, self.registry))
        self.assertEqual(cue_path.read_bytes(), before)

    def test_multipart_historical_filename(self):
        import app
        prepare_security(self, app)
        with patch.object(app, 'SHOW_CUES_DATA_DIRECTORY', self.root):
            client = admin_client(app)
            response = client.post('/show-info/builder/sessions/import',
                                   data={'file': (io.BytesIO(self.payload), 'Oiseau de Paradis.showcue')})
            self.assertEqual(response.status_code, 201, response.data)
            self.assert_preserved(response.json)
            page = client.get('/show-info/builder').get_data(as_text=True)
            self.assertIn('/static/showcue-sessions.js', page)
            self.assertIn('accept=".showcue,.showcue.zip"', (Path(__file__).parents[1] / 'static/showcue-sessions.js').read_text())

    def test_desktop_repairs_old_server_filter_on_every_load(self):
        import showcue_builder_desktop as desktop
        from unittest.mock import MagicMock
        window = MagicMock()
        callbacks = []
        window.events.loaded.__iadd__.side_effect = lambda callback: callbacks.append(callback)
        with patch.object(desktop, 'backend_available', return_value=True), \
             patch.object(desktop.webview, 'create_window', return_value=window), \
             patch.object(desktop.webview, 'start'):
            self.assertEqual(desktop.main(), 0)
        self.assertEqual(len(callbacks), 1)
        callbacks[0]()
        callbacks[0]()
        self.assertEqual(window.evaluate_js.call_count, 4)
        self.assertIn("input.accept = '.showcue,.showcue.zip'", window.evaluate_js.call_args_list[0].args[0])

    def test_desktop_filter_script_executes_without_changing_upload_handler(self):
        import subprocess
        import showcue_builder_desktop as desktop
        script = """
const assert = require('node:assert/strict');
const vm = require('node:vm');
const handler = () => {};
const input = {accept: '.showcue.zip', onchange: handler};
const context = {document: {getElementById: id => {
    assert.equal(id, 'cl-session-upload'); return input;
}}};
const script = SCRIPT;
vm.runInNewContext(script, context);
assert.equal(input.accept, '.showcue,.showcue.zip');
assert.equal(input.onchange, handler);
vm.runInNewContext(script, context);
vm.runInNewContext(script, {document: {getElementById: () => null}});
""".replace('SCRIPT', json.dumps(desktop.SESSION_FILE_FILTER_SCRIPT))
        subprocess.run(['node', '-e', script], check=True, capture_output=True)
