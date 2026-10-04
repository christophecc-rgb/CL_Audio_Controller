"""Portable show contents and route journeys, using synthetic temporary sessions."""
import io
import json
import tempfile
import unittest
import wave
import zipfile
from pathlib import Path
from unittest.mock import patch

import app
from security_test_helper import prepare_security, admin_client
from show_cues import initialize_show_cue_sessions, save_show_document
from showcue_builder import import_csv, import_xlsx, load_builder_document, save_builder_document


class PortableRoundtripTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        registry = initialize_show_cue_sessions(self.root)
        self.sid = registry['active_session_id']
        self.session = self.root / 'Sessions' / self.sid
        storage = patch.object(app, 'SHOW_CUES_DATA_DIRECTORY', self.root)
        storage.start(); self.addCleanup(storage.stop)
        prepare_security(self, app)
        self.client = admin_client(app)
        self.builder = save_builder_document(self.session / 'showcue_builder.json', {
            'revision': 2, 'cues': [{'id': 'builder_test', 'number': '8',
                'source': 'Été', 'type': 'AUTRE', 'role': 'CHANT',
                'text': 'Élodie — entrée à vérifier', 'timecode': '00:00:05:00',
                'foh': True, 'ret': True, 'plt': False, 'lum': True,
                'origin': 'BUILDER', 'notes': 'À confirmer'}],
            'distribution': [{'role': 'CHANT', 'artist': 'Élodie', 'active': True,
                'microphone': 'HF3', 'iem': 'IEM2', 'equipment': 'Étoile'}]})
        self.audio = self.session / 'show_cues_audio' / 'cue_test.wav'
        self.audio.parent.mkdir(exist_ok=True)
        with wave.open(str(self.audio), 'wb') as output:
            output.setnchannels(1); output.setsampwidth(2); output.setframerate(8000)
            output.writeframes(b'\0\0' * 80)
        save_show_document(self.session / 'show_cues.json', {'cues': [
            {'id': 'cue_test', 'mode': 'timed', 'timecode': '00:00:05:00',
             'text': 'Conduite — entrée', 'posts': ['FOH'], 'status': 'official',
             'audio': {'filename': 'cue_test.wav', 'mime_type': 'audio/wav'}}]})

    def test_csv_xlsx_values_accents_columns_and_preview_reimport(self):
        for format_name, loader in [('csv', import_csv), ('xlsx', import_xlsx)]:
            with self.subTest(format=format_name):
                payload = self.client.get('/show-info/builder/export.'+format_name,
                    query_string={'session_id': self.sid, 'revision': 2})
                self.assertEqual(payload.status_code, 200)
                imported, unknown = loader(payload.data)
                self.assertFalse(unknown)
                cue = imported['cues'][0]
                for key in ['number', 'source', 'role', 'text', 'timecode', 'foh', 'ret', 'plt', 'lum', 'notes']:
                    self.assertEqual(cue[key], self.builder['cues'][0][key])
                self.assertEqual(imported['distribution'][0]['artist'], 'Élodie')
                self.assertEqual(imported['distribution'][0]['equipment_slots'], self.builder['distribution'][0]['equipment_slots'])
                before = (self.session / 'showcue_builder.json').read_bytes()
                preview = self.client.post('/show-info/builder/import', data={
                    'file': (io.BytesIO(payload.data), 'tableau.'+format_name)})
                self.assertEqual(preview.status_code, 200)
                self.assertFalse(preview.json['saved'])
                self.assertEqual((self.session / 'showcue_builder.json').read_bytes(), before)

    def test_complete_archive_reimport_and_duplicate_names_are_explicit(self):
        response = self.client.get('/show-info/builder/sessions/export',
            query_string={'session_id': self.sid, 'revision': 2})
        self.assertEqual(response.status_code, 200)
        with zipfile.ZipFile(io.BytesIO(response.data)) as archive:
            self.assertEqual(set(archive.namelist()), {'manifest.json', 'show_cues.json',
                'showcue_builder.json', 'show_cues_audio/cue_test.wav'})
            self.assertEqual(json.loads(archive.read('showcue_builder.json')), self.builder)
            self.assertEqual(archive.read('show_cues_audio/cue_test.wav'), self.audio.read_bytes())
        original = {str(p.relative_to(self.session)): p.read_bytes() for p in self.session.rglob('*') if p.is_file()}
        created = []
        for suffix, number in [('.showcue', 2), ('.showcue.zip', 3)]:
            imported = self.client.post('/show-info/builder/sessions/import', data={
                'file': (io.BytesIO(response.data), 'Copie'+suffix)})
            self.assertEqual(imported.status_code, 201)
            self.assertEqual(imported.json['active_session_id'], self.sid)
            item = imported.json['imported_session']; created.append(item['id'])
            self.assertEqual(item['name'], 'Session actuelle ('+str(number)+')')
            self.assertEqual(imported.json['import_result'], {'original_name': 'Session actuelle',
                'assigned_name': item['name'], 'renamed': True})
            directory = self.root / 'Sessions' / item['id']
            self.assertEqual(load_builder_document(directory / 'showcue_builder.json'), self.builder)
            self.assertEqual((directory / 'show_cues_audio/cue_test.wav').read_bytes(), self.audio.read_bytes())
            self.assertEqual(json.loads((directory / 'show_cues.json').read_text())['cues'][0]['text'], 'Conduite — entrée')
        self.assertNotEqual(*created)
        self.assertEqual(original, {str(p.relative_to(self.session)): p.read_bytes() for p in self.session.rglob('*') if p.is_file()})
        registry_before = (self.root / 'sessions.json').read_bytes()
        stale = self.client.post('/show-info/sessions/'+created[0]+'/activate', json={'session_id': 'stale'})
        self.assertEqual(stale.status_code, 409)
        self.assertEqual((self.root / 'sessions.json').read_bytes(), registry_before)

    def test_missing_audio_blocks_export_without_issuing_a_broken_archive(self):
        self.audio.unlink()
        response = self.client.get('/show-info/builder/sessions/export',
            query_string={'session_id': self.sid, 'revision': 2})
        self.assertEqual(response.status_code, 409)
        self.assertIn('audio référencé absent', response.json['message'])
        self.assertNotIn('Content-Disposition', response.headers)
