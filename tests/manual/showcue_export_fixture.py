"""Isolated browser/native export check. All session and audio files are temporary.
Run with --native for the pywebview Save As journey; otherwise open printed URL.
No production app is imported and no CL/Ableton endpoint is contacted.
"""
import argparse
import io
import json
from pathlib import Path
import re
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlsplit, parse_qs
import uuid
import wave

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from showcue_builder import export_csv, export_xlsx, load_builder_document, save_builder_document
from show_cues import initialize_show_cue_sessions, save_show_document
from showcue_session_archive import export_session


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--native', action='store_true')
    options = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='cl-cue-test-') as directory:
        root = Path(directory)
        registry = initialize_show_cue_sessions(root)
        sid = registry['active_session_id']
        name = 'CL_Cue_Test_20261004_' + uuid.uuid4().hex[:8]
        registry['sessions'][0]['name'] = name
        session = root / 'Sessions' / sid
        builder_path = session / 'showcue_builder.json'
        initial = save_builder_document(builder_path, {'revision': 0, 'cues': [
            {'id': 'builder_test', 'number': '1', 'text': 'Élodie — entrée à vérifier',
             'source': 'Test isolé', 'type': 'AUTRE', 'role': 'TEST', 'artist': '',
             'foh': True, 'ret': True, 'plt': False, 'lum': False, 'origin': 'BUILDER',
             'notes': 'À confirmer', 'timecode': '00:00:05:00'}],
            'distribution': [{'role': 'TEST', 'artist': 'Élodie', 'active': True,
                              'microphone': 'HF3', 'iem': 'IEM2', 'equipment': 'Étoile'}]})
        audio = session / 'show_cues_audio' / 'cue_test.wav'
        audio.parent.mkdir(exist_ok=True)
        with wave.open(str(audio), 'wb') as output:
            output.setnchannels(1); output.setsampwidth(2); output.setframerate(8000)
            output.writeframes(b'\0\0' * 80)
        save_show_document(session / 'show_cues.json', {'cues': [
            {'id': 'cue_test', 'text': 'Conduite fictive — entrée', 'mode': 'timed',
             'timecode': '00:00:05:00', 'posts': ['FOH'], 'status': 'official',
             'audio': {'filename': 'cue_test.wav', 'mime_type': 'audio/wav'}}]})
        state = {'refused': False}
        source = (ROOT / 'templates/showcue_builder.html').read_text()
        base = source[source.index('async function save(){'):source.index("$('save').onclick", source.index('async function save(){'))]
        queue = source[source.index('const saveState=document.createElement'):source.index("};['cues','distribution']", source.index('const saveState=document.createElement'))] + '};'
        draft_start = source.index('<script id="showcue-builder-local-draft-v1">')+len('<script id="showcue-builder-local-draft-v1">')
        draft_script = source[draft_start:source.index('</script>', draft_start)]
        html = '''<!doctype html><meta charset="utf-8"><title>CL Cue Editor — TEST ISOLÉ</title>
<main class="shell"><h1>CL Cue Editor — TEST ISOLÉ</h1>
<p>Données fictives · aucun serveur CL ni connexion Ableton. Les fichiers portent le préfixe NAME.</p>
<div id="cues"><label>Texte du cue <textarea id="test-cue">Élodie — entrée à vérifier</textarea></label></div><div id="distribution"></div><span id="session" hidden>session_initiale</span>
<button id="save">ENREGISTRER LE BUILDER</button><button id="refuse">REFUSER LES SAUVEGARDES (TEST)</button><button id="adopt" hidden></button>
<p><a href="/show-info/builder/export.csv">EXPORTER LE TABLEAU CSV</a></p>
<p><a href="/show-info/builder/export.xlsx">EXPORTER LE TABLEAU XLSX</a></p>
<p><a href="/show-info/builder/sessions/export">SAUVEGARDER LE SHOW COMPLET .showcue</a></p>
<div id="message" role="status">Prêt pour le test isolé.</div></main>
<script>
let documentData=INITIAL,sessionId=SID,preview=null;
const $=id=>document.getElementById(id);
async function api(url,options={}){const r=await fetch(url,{headers:{'Content-Type':'application/json'},...options});const v=await r.json();if(!r.ok)throw Error(v.message);return v;}
function readTables(){return {...documentData,cues:[{...documentData.cues[0],text:$('test-cue').value}]}}
function render(){$('test-cue').value=documentData.cues[0].text}
function showValidation(){$('message').textContent='Builder enregistré dans le stockage temporaire.'}
BASE
QUEUE
render();setSaveState('BUILDER SAUVEGARDÉ');
$('test-cue').oninput=markDirty;
$('save').onclick=()=>save().catch(e=>$('message').textContent=e.message);
$('refuse').onclick=()=>fetch('/fixture/refuse',{method:'POST'});
</script><script>DRAFT_SCRIPT</script><script>LIFECYCLE</script>'''.replace('NAME', name).replace('INITIAL', json.dumps(initial)).replace('SID', json.dumps(sid)).replace('BASE', base).replace('QUEUE', queue).replace('DRAFT_SCRIPT', draft_script).replace('LIFECYCLE', (ROOT / 'static/showcue-lifecycle.js').read_text())

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass
            def reply(self, data, mime='application/json', code=200, filename=None):
                self.send_response(code)
                self.send_header('Content-Type', mime)
                self.send_header('Cache-Control', 'no-store')
                if filename:
                    self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
                self.end_headers(); self.wfile.write(data)
            def do_GET(self):
                url = urlsplit(self.path)
                if url.path == '/':
                    page = html.replace('let documentData='+json.dumps(initial), 'let documentData='+json.dumps(load_builder_document(builder_path)))
                    return self.reply(page.encode(), 'text/html; charset=utf-8')
                doc = load_builder_document(builder_path)
                query = parse_qs(url.query)
                if query.get('session_id') != [sid] or query.get('revision') != [str(doc['revision'])]:
                    return self.reply(json.dumps({'message': 'Révision de test périmée'}).encode(), code=409)
                if url.path.endswith('export.csv'):
                    return self.reply(export_csv(doc), 'text/csv; charset=utf-8', filename=name+'.csv')
                if url.path.endswith('export.xlsx'):
                    return self.reply(export_xlsx(doc), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', filename=name+'.xlsx')
                if url.path.endswith('sessions/export'):
                    return self.reply(export_session(root, registry, sid), 'application/zip', filename=name+'.showcue')
                self.reply(b'{}', code=404)
            def do_POST(self):
                state['refused']=True
                self.reply(b'{"ok":true}')
            def do_PUT(self):
                values = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                if state['refused']:
                    return self.reply(json.dumps({'message': 'Sauvegarde refusée (test isolé)'}).encode(), code=403)
                current = load_builder_document(builder_path)
                if values.get('session_id') != sid or values['document']['revision'] != current['revision']:
                    return self.reply(json.dumps({'message': 'Conflit de révision (test isolé)'}).encode(), code=409)
                doc = save_builder_document(builder_path, {**values['document'], 'revision': current['revision']+1})
                self.reply(json.dumps({'document': doc, 'validation': {}}).encode())

        server = HTTPServer(('127.0.0.1', 0), Handler)
        url = f'http://127.0.0.1:{server.server_port}/'
        print(json.dumps({'url': url, 'name': name, 'temporary_storage': str(root)}), flush=True)
        try:
            if options.native:
                import webview
                from showcue_builder_desktop import BuilderRecoveryApi, BuilderCloseGuard
                thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
                bridge = BuilderRecoveryApi()
                window = webview.create_window('CL Cue Editor — TEST ISOLÉ', url, js_api=bridge, width=950, height=650)
                bridge.window = window
                window.events.closing += BuilderCloseGuard(window)
                webview.start(localization={'global.saveFile': 'Enregistrer sous…', 'global.cancel': 'Annuler'})
                server.shutdown()
            else:
                server.serve_forever()
        finally:
            server.server_close()


if __name__ == '__main__':
    main()
