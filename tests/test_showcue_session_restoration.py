import base64
import io
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

import app
from show_cues import initialize_show_cue_sessions, load_session_registry
from showcue_builder import load_builder_document, save_builder_document
from showcue_builder_desktop import BuilderRecoveryApi

FIXTURES = Path(__file__).parent / 'fixtures'


class SessionRestorationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        initialize_show_cue_sessions(self.root)
        self.initial = self.root / 'Sessions/session_initiale'
        with zipfile.ZipFile(FIXTURES / 'legacy_v1.showcue') as archive:
            self.show = json.loads(archive.read('show_cues.json'))
        self.show['cues'] = self.show['cues'][:16]
        self.initial.joinpath('show_cues.json').write_text(json.dumps(self.show))
        self.empty = {'version': 1, 'revision': 6, 'cues': [], 'distribution': []}
        self.initial.joinpath('showcue_builder.json').write_text(json.dumps(self.empty))
        self.storage = patch.object(app, 'SHOW_CUES_DATA_DIRECTORY', self.root)
        self.storage.start()
        self.addCleanup(self.storage.stop)
        self.client = app.app.test_client()

    def upload(self, name):
        data = (FIXTURES / name).read_bytes()
        response = self.client.post('/show-info/builder/sessions/import', data={'file': (io.BytesIO(data), name)})
        self.assertEqual(response.status_code, 201, response.data)
        return response.json['imported_session']['id']

    def activate_and_check(self, sid, show_count, builder_count, revision):
        self.assertEqual(self.client.post('/show-info/sessions/' + sid + '/activate', json={}).status_code, 200)
        response = self.client.get('/show-info/builder/document')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json['session_id'], sid)
        self.assertEqual(len(response.json['document']['cues']), builder_count)
        self.assertEqual(response.json['document']['revision'], revision)
        directory = self.root / 'Sessions' / sid
        self.assertEqual(len(json.loads((directory / 'show_cues.json').read_text())['cues']), show_count)

    def test_op_mpc_import_restart_switch_and_persistence(self):
        op = self.upload('legacy_v1.showcue')
        op_files = {p.name: p.read_bytes() for p in (self.root / 'Sessions' / op).iterdir()}
        mpc = self.upload('mpc_v1.showcue')
        for name, content in op_files.items():
            self.assertEqual((self.root / 'Sessions' / op / name).read_bytes(), content)
        self.activate_and_check(op, 142, 134, 341)
        before = (self.root / 'sessions.json').read_bytes()
        # Fresh Python process: same persistent root, no in-memory registry.
        result = subprocess.check_output([sys.executable, '-c',
            'import json,sys; from show_cues import initialize_show_cue_sessions; print(json.dumps(initialize_show_cue_sessions(sys.argv[1])))', str(self.root)])
        self.assertEqual(json.loads(result), json.loads(before))
        self.assertEqual((self.root / 'sessions.json').read_bytes(), before)
        self.client = app.app.test_client()
        self.activate_and_check(mpc, 54, 56, 30)
        self.activate_and_check(op, 142, 134, 341)
        self.activate_and_check(mpc, 54, 56, 30)
        registry = load_session_registry(self.root / 'sessions.json')
        self.assertEqual([s['name'] for s in registry['sessions']], ['Session actuelle', 'OP 2026', 'MPC'])
        # Re-import creates a separate session; never overwrites MPC or OP.
        mpc_before = (self.root / 'Sessions' / mpc / 'showcue_builder.json').read_bytes()
        second_op = self.upload('legacy_v1.showcue')
        self.assertNotEqual(op, second_op)
        self.assertEqual((self.root / 'Sessions' / mpc / 'showcue_builder.json').read_bytes(), mpc_before)
        self.assertEqual(len(load_session_registry(self.root / 'sessions.json')['sessions']), 4)

    def test_16_cues_empty_builder_recovered_without_changing_show(self):
        original = (self.initial / 'show_cues.json').read_bytes()
        response = self.client.get('/show-info/builder/document')
        self.assertEqual(response.status_code, 200)
        document = response.json['document']
        self.assertEqual(len(document['cues']), 16)
        self.assertEqual(document['revision'], 6)
        self.assertEqual((self.initial / 'show_cues.json').read_bytes(), original)
        persisted = (self.initial / 'showcue_builder.json').read_bytes()
        load_builder_document(self.initial / 'showcue_builder.json')
        self.assertEqual((self.initial / 'showcue_builder.json').read_bytes(), persisted)
        for source, recovered in zip(self.show['cues'], document['cues']):
            self.assertEqual(recovered['text'], source['text'])
            self.assertEqual(recovered['timecode'], source.get('timecode', ''))
            for key, post in zip(('foh', 'ret', 'plt', 'lum'), ('FOH', 'RETOURS', 'PLATEAU', 'LUMIERE')):
                self.assertEqual(recovered[key], post in source['posts'])

    def test_empty_save_refused_and_nonempty_builder_unchanged(self):
        op = self.upload('legacy_v1.showcue')
        self.activate_and_check(op, 142, 134, 341)
        path = self.root / 'Sessions' / op / 'showcue_builder.json'
        before = path.read_bytes()
        response = self.client.put('/show-info/builder/document', json={'session_id': op, 'document': {**self.empty, 'revision': 341}})
        self.assertEqual(response.status_code, 400)
        self.assertIn('vide refusé', response.json['message'])
        self.assertEqual(path.read_bytes(), before)

    def test_missing_builder_and_empty_archive_builder_recover(self):
        (self.initial / 'showcue_builder.json').unlink()
        self.assertEqual(len(load_builder_document(self.initial / 'showcue_builder.json')['cues']), 16)
        for include_empty in (False, True):
            output = io.BytesIO()
            with zipfile.ZipFile(output, 'w') as archive:
                archive.writestr('manifest.json', json.dumps({'format': 'CL ShowCue', 'version': 1, 'name': 'Recovered'}))
                archive.writestr('show_cues.json', json.dumps(self.show))
                if include_empty: archive.writestr('showcue_builder.json', json.dumps(self.empty))
            response = self.client.post('/show-info/builder/sessions/import', data={'file': (io.BytesIO(output.getvalue()), 'restoration.showcue')})
            self.assertEqual(response.status_code, 201, response.data)
            sid = response.json['imported_session']['id']
            self.assertEqual(len(load_builder_document(self.root / 'Sessions' / sid / 'showcue_builder.json')['cues']), 16)

    def test_invalid_or_missing_registry_never_resets_existing_sessions(self):
        op = self.upload('legacy_v1.showcue')
        registry = self.root / 'sessions.json'
        registry.write_text('broken')
        with self.assertRaises(ValueError): initialize_show_cue_sessions(self.root)
        self.assertEqual(registry.read_text(), 'broken')
        registry.unlink()
        with self.assertRaisesRegex(ValueError, 'Registre absent'): initialize_show_cue_sessions(self.root)
        self.assertFalse(registry.exists())
        self.assertTrue((self.root / 'Sessions' / op / 'showcue_builder.json').exists())

    def test_historical_registry_not_ignored(self):
        fresh = self.root / 'fresh'
        with self.assertRaisesRegex(ValueError, 'Registre historique'):
            initialize_show_cue_sessions(fresh, [self.root])
        self.assertFalse((fresh / 'sessions.json').exists())

    def test_desktop_bridge_recovers_for_unchanged_legacy_server(self):
        output = io.BytesIO()
        with zipfile.ZipFile(output, 'w') as archive:
            archive.writestr('manifest.json', json.dumps({'format': 'CL ShowCue', 'version': 1, 'name': 'Session actuelle'}))
            archive.writestr('show_cues.json', json.dumps(self.show))
            archive.writestr('showcue_builder.json', json.dumps(self.empty))
        response = BuilderRecoveryApi().recover_builder(base64.b64encode(output.getvalue()).decode(), self.empty)
        self.assertTrue(response['ok'])
        self.assertEqual(len(response['document']['cues']), 16)
        self.assertEqual(response['document']['revision'], 6)  # Old server increments on PUT.
        self.assertEqual(json.loads((self.initial / 'showcue_builder.json').read_text()), self.empty)

    def test_legacy_server_export_bridge_save_then_op_mpc_import(self):
        import showcue_session_archive
        from showcue_builder import empty_builder_document, normalize_builder_document
        def legacy_load(path):
            return normalize_builder_document(json.loads(path.read_text())) if path.exists() else empty_builder_document()
        with patch.object(app, 'load_builder_document', legacy_load), patch.object(showcue_session_archive, 'load_builder_document', legacy_load):
            current = self.client.get('/show-info/builder/document').json
            self.assertEqual(len(current['document']['cues']), 0)
            exported = self.client.get('/show-info/builder/sessions/export')
            recovered = BuilderRecoveryApi().recover_builder(base64.b64encode(exported.data).decode(), current['document'])
            saved = self.client.put('/show-info/builder/document', json={'session_id': current['session_id'], 'document': recovered['document']})
            self.assertEqual(saved.status_code, 200, saved.data)
            self.assertEqual(len(saved.json['document']['cues']), 16)
            op = self.upload('legacy_v1.showcue')
            mpc = self.upload('mpc_v1.showcue')
            self.activate_and_check(op, 142, 134, 341)
            self.activate_and_check(mpc, 54, 56, 30)

    def test_invalid_archive_keeps_both_shows_and_registry(self):
        self.upload('legacy_v1.showcue')
        self.upload('mpc_v1.showcue')
        before = {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob('*.json')}
        response = self.client.post('/show-info/builder/sessions/import', data={'file': (io.BytesIO(b'bad zip'), 'bad.showcue')})
        self.assertEqual(response.status_code, 400)
        self.assertEqual({str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob('*.json')}, before)
