import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

import cl_transport
from console_title_library import ConsoleLibraryStore
from show_cues import initialize_show_cue_sessions, active_session_paths
from showcue_builder import save_builder_document, load_builder_document
from showcue_session_archive import export_session, import_session
from scripts.build_cl_transport import build


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.transport = self.root / 'CL_Transport'
        self.roots = patch('cl_transport.transport_roots', return_value=[self.transport])
        self.roots.start()
        self.addCleanup(self.roots.stop)
        self.store = ConsoleLibraryStore(self.root / 'legacy')

    def library(self, root, console):
        root.mkdir(parents=True, exist_ok=True)
        (root / (console.upper()+'.titles.json')).write_text(json.dumps({'console':console, 'entries':[{'memory':1,'title':'REAL'}]}))

    def test_absent_empty_multiple_sessions(self):
        self.assertEqual(cl_transport.available_sessions(), [])
        sessions = self.transport / 'ShowCue_Sessions'
        sessions.mkdir(parents=True)
        self.assertEqual(cl_transport.available_sessions(), [])
        for name in ['OP.showcue','MPC.showcue.zip','ignore.zip']:
            (sessions / name).touch()
        self.assertEqual(len(cl_transport.available_sessions()), 2)
        with self.assertRaises(ValueError):
            cl_transport.session_file(str(self.transport), '../OP.showcue')

    def test_libraries_and_legacy_priority(self):
        for console in ('cl5','ql1'):
            self.library(self.store.root, console)
            self.assertEqual(cl_transport.load_library(console,self.store)['source'], 'fallback legacy')
            self.library(self.transport / 'Console_Libraries' / console.upper(), console)
            value=cl_transport.load_library(console,self.store)
            self.assertEqual(value['source'], 'CL_Transport')
            self.assertEqual(len(value['library']),1)

    def test_explicit_root_first(self):
        self.roots.stop()
        with patch.dict('os.environ',{'CL_TRANSPORT_ROOT':str(self.transport)}):
            self.assertEqual(cl_transport.transport_roots()[0],self.transport.resolve())
        self.roots.start()

    def test_roundtrip_duplicate_name_preserves_active_builder(self):
        root=self.root/'data'
        registry=initialize_show_cue_sessions(root)
        cue_path,_=active_session_paths(root,registry)
        save_builder_document(cue_path.parent/'showcue_builder.json',{'version':1,'cues':[],'distribution':[]})
        before=cue_path.read_bytes()
        data=export_session(root,registry,registry['active_session_id'])
        updated=import_session(data,root,registry)
        updated=import_session(data,root,updated)
        self.assertEqual(updated['active_session_id'],registry['active_session_id'])
        self.assertEqual([s['name'] for s in updated['sessions']],['Session actuelle','Session actuelle (2)','Session actuelle (3)'])
        self.assertEqual(cue_path.read_bytes(),before)
        self.assertTrue((root/'Sessions'/updated['sessions'][-1]['id']/'showcue_builder.json').is_file())

    def test_reject_traversal_without_registry_mutation(self):
        root=self.root/'data';registry=initialize_show_cue_sessions(root)
        before=(root/'sessions.json').read_bytes();out=io.BytesIO()
        with zipfile.ZipFile(out,'w') as archive:
            archive.writestr('../escape','bad')
        with self.assertRaises(ValueError):import_session(out.getvalue(),root,registry)
        self.assertEqual((root/'sessions.json').read_bytes(),before)

    def test_build_idempotent_and_preserves_conflicting_library(self):
        libraries=self.root/'libraries'
        for console in ('cl5','ql1'): self.library(libraries/console.upper(),console)
        build(self.transport,libraries);build(self.transport,libraries)
        target=self.transport/'Console_Libraries/CL5/CL5.titles.json'
        target.write_text('user content')
        with self.assertRaises(FileExistsError):build(self.transport,libraries)
        self.assertEqual(target.read_text(),'user content')

    def test_builder_import_route_and_remote_access(self):
        import app
        root=self.root/'data';registry=initialize_show_cue_sessions(root)
        data=export_session(root,registry,registry['active_session_id'])
        sessions=self.transport/'ShowCue_Sessions';sessions.mkdir(parents=True)
        (sessions/'OP.showcue').write_bytes(data)
        with patch.object(app,'SHOW_CUES_DATA_DIRECTORY',root):
            client=app.app.test_client()
            response=client.post('/show-info/builder/sessions/import',json={'source':str(self.transport),'name':'OP.showcue'})
            self.assertEqual(response.status_code,201,response.data)
            self.assertEqual(response.json['imported_session']['name'],'Session actuelle (2)')
            self.assertEqual(client.get('/show-info/builder/resources').status_code,200)
            self.assertEqual(client.get('/show-info/builder/resources',environ_base={'REMOTE_ADDR':'192.168.1.2'}).status_code,403)
            self.assertEqual(client.get('/show-info/builder/sessions/export').status_code,200)

    def test_save_transport_route_creates_portable_showcue(self):
        import app

        root = self.root / 'data'
        registry = initialize_show_cue_sessions(root)
        cue_path, _ = active_session_paths(root, registry)

        save_builder_document(
            cue_path.parent / 'showcue_builder.json',
            {
                'version': 1,
                'cues': [],
                'distribution': [],
            },
        )

        with (
            patch.object(app, 'SHOW_CUES_DATA_DIRECTORY', root),
            patch.object(app, 'transport_roots', return_value=[self.transport]),
        ):
            client = app.app.test_client()

            response = client.post(
                '/show-info/builder/sessions/save-transport'
            )

            self.assertEqual(response.status_code, 200, response.data)
            self.assertTrue(response.json['ok'])
            self.assertEqual(
                response.json['name'],
                'Session actuelle.showcue',
            )

            target = (
                self.transport
                / 'ShowCue_Sessions'
                / 'Session actuelle.showcue'
            )

            self.assertTrue(target.is_file())

            with zipfile.ZipFile(target, 'r') as archive:
                names = set(archive.namelist())

                self.assertIn('manifest.json', names)
                self.assertIn('show_cues.json', names)
                self.assertIn('showcue_builder.json', names)

                manifest = json.loads(
                    archive.read('manifest.json').decode('utf-8')
                )

            self.assertEqual(manifest['format'], 'CL ShowCue')
            self.assertEqual(manifest['version'], 1)
            self.assertEqual(manifest['name'], 'Session actuelle')

            remote = client.post(
                '/show-info/builder/sessions/save-transport',
                environ_base={'REMOTE_ADDR': '192.168.1.2'},
            )

            self.assertEqual(remote.status_code, 403)
