"""Minimal local backend sharing OSCTransport and the protected GO core.

No FULL module is imported here. Construction never starts a thread. The only
workers are the loopback OSC reply server and local Set/transport refresh.
"""
import ipaddress
import math
import threading
import uuid
from pathlib import Path
from urllib.parse import urlsplit

from flask import Flask, jsonify, request, render_template
from app_mode import AppMode, LOCAL_LIGHT_ACTIONS, local_light_state
from go_core import GoContext, LocalGoConsumer, execute_go_core
from osc_transport import OSCTransport

LOOPBACK = '127.0.0.1'
LIGHT_WEB_PORT = 5050
LIGHT_ROUTES = {'/': frozenset({'GET', 'HEAD'}),
                '/status': frozenset({'GET', 'HEAD'}),
                '/action': frozenset({'POST'})}


def _scene_index(number):
    try:
        number = int(str(number).strip())
        return number - 1 if number > 0 else None
    except (TypeError, ValueError):
        return None


def local_light_request():
    try:
        if not ipaddress.ip_address(request.remote_addr or '').is_loopback:
            return False
    except ValueError:
        return False
    if urlsplit(request.host_url).hostname not in {'localhost', '127.0.0.1', '::1'}:
        return False
    origin = request.headers.get('Origin')
    return ((not origin or origin == request.host_url.rstrip('/'))
            and request.headers.get('Sec-Fetch-Site') != 'cross-site')


class LightRuntime:
    def __init__(self, transport=None):
        self.transport = transport if transport is not None else OSCTransport(
            host=LOOPBACK, send_port=11000, reply_port=11001, collect_metrics=False)
        # Injectable transports must also be local; no saved FULL profile is read.
        if self.transport.host != LOOPBACK:
            raise ValueError('LOCAL_LIGHT requires loopback AbletonOSC')
        self.lock = threading.RLock()
        self.transaction_lock = threading.Lock()
        self.completed_go_requests = {}
        self.state = {'set_generation': 0, 'set_ready': False, 'connected': False,
                      'scenes': {}, 'playing_scene': -1, 'selected_scene': 0,
                      'next_scene': None, 'is_playing': False, 'is_paused': False,
                      'has_show_started': False}
        self.identity = None
        self.token = None
        self.slots = {}
        self.stopping = threading.Event()
        self.reply_ready = threading.Event()
        self.threads = []
        self.error = ''
        self.observed_scene = None
        self.prepared_by_navigation = False
        self.current_timing = None
        self.transport.set_unsolicited_handler(self.receive)

    def light_state_snapshot(self):
        with self.lock:
            observed = dict(self.state, playing_scene=self.observed_scene)
            result = local_light_state(observed)
            following = result['next_scene']
            result.update(
                mode=AppMode.LOCAL_LIGHT.value,
                next_scene_name=str(self.state['scenes'].get(following, '')) if following is not None else '',
                ableton_available=bool(self.state['connected']), error=self.error,
            )
            timing = self.current_timing
            valid = (timing is not None and result['is_playing'] and
                     timing[0] == (self.state['set_generation'], self.observed_scene, self.token,
                                   tuple(sorted(self.slots.items()))))
            values = timing[1] if valid else (None, None, None)
            result.update(zip(('current_duration_seconds', 'current_position_seconds',
                               'current_remaining_seconds'), values))
            return result

    def refresh_current_timing(self):
        """Optional LOCAL_LIGHT timing from a show-relevant active audio track.

        Priority:
        1. TABLEAU / TABLEAUX when it actually plays the observed scene.
        2. An active leaf inside the active branch of SAISON 8.

        Muted branches and technical tracks are never timing references.
        MIDI, warped, looped and recording clips intentionally remain unknown.
        Timing reads remain optional and never mark Ableton unavailable.
        """
        from light_timing import reference_candidates, timing_from_clip

        with self.lock:
            # Do not blank a valid timing while optional OSC refreshes are
            # in progress. STOP, scene/set changes and disconnect already
            # invalidate current_timing explicitly elsewhere.
            if (not self.state['set_ready'] or
                    not self.state['connected'] or
                    not self.state['is_playing']):
                self.current_timing = None
                return

            scene = self.observed_scene
            if scene is None:
                self.current_timing = None
                return

            slots_snapshot = tuple(sorted(self.slots.items()))
            key = (
                self.state['set_generation'],
                scene,
                self.token,
                slots_snapshot,
            )

        def query(address, *args, timeout=.25):
            response = self.transport.query(
                address, *args, timeout=timeout
            )
            if not response:
                raise ValueError('Missing OSC response')
            return response

        def track_value(prop, track):
            response = query(
                '/live/track/get/' + prop,
                track,
                timeout=.6,
            )
            if len(response) < 2 or response[0] != track:
                raise ValueError('Invalid track response')
            return response[-1]

        def clip_value(prop, track):
            response = query(
                '/live/clip/get/' + prop,
                track,
                scene,
            )
            if (len(response) != 3 or
                    response[:2] != (track, scene)):
                raise ValueError('Invalid clip response')
            return response[-1]

        try:
            layout_identity = (
                self.state['set_generation'],
                self.token,
            )

            if getattr(
                self,
                '_light_timing_layout_identity',
                None,
            ) != layout_identity:
                count_response = query('/live/song/get/num_tracks', timeout=.6)
                count = int(count_response[-1])

                layout = []

                for track in range(count):
                    layout.append({
                        'index': track,
                        'name': str(
                            track_value('name', track) or ''
                        ),
                        'foldable': bool(
                            track_value('is_foldable', track)
                        ),
                        'grouped': bool(
                            track_value('is_grouped', track)
                        ),
                    })

                self._light_timing_candidates = (
                    reference_candidates(layout)
                )
                self._light_timing_layout_identity = (
                    layout_identity
                )

            candidates = getattr(
                self,
                '_light_timing_candidates',
                (),
            )

            chosen = None

            for candidate in candidates:
                track = candidate['track']

                # La piste feuille elle-même doit être allumée.
                if bool(track_value('mute', track)):
                    continue

                # Tous les groupes parents connus doivent être allumés.
                parent_muted = False
                for parent in candidate.get(
                    'required_unmuted',
                    (),
                ):
                    if bool(track_value('mute', parent)):
                        parent_muted = True
                        break

                if parent_muted:
                    continue

                # Elle doit réellement jouer la scène observée.
                playing_slot = int(
                    track_value(
                        'playing_slot_index',
                        track,
                    )
                )

                if playing_slot != scene:
                    continue

                # Vérification du type de clip avant de choisir
                # définitivement cette référence.
                is_audio = clip_value(
                    'is_audio_clip',
                    track,
                )
                warping = clip_value(
                    'warping',
                    track,
                )
                looping = clip_value(
                    'looping',
                    track,
                )
                recording = clip_value(
                    'is_recording',
                    track,
                )

                if (float(is_audio) != 1 or
                        float(warping) != 0 or
                        float(looping) != 0 or
                        float(recording) != 0):
                    continue

                chosen = track
                break

            if chosen is None:
                return

            start = float(
                clip_value('start_marker', chosen)
            )
            end = float(
                clip_value('end_marker', chosen)
            )
            position = float(
                clip_value('playing_position', chosen)
            )

            if not all(
                math.isfinite(v)
                for v in (start, end, position)
            ):
                return

            values = timing_from_clip(
                is_audio_clip=True,
                warping=False,
                looping=False,
                start_marker=start,
                end_marker=end,
                playing_position=position,
            )

            if values is None:
                return

        except (
            OSError,
            TypeError,
            ValueError,
            IndexError,
            KeyError,
        ):
            return

        with self.lock:
            current_key = (
                self.state['set_generation'],
                self.observed_scene,
                self.token,
                tuple(sorted(self.slots.items())),
            )

            if (current_key == key and
                    self.state['is_playing'] and
                    self.state['connected']):
                self.current_timing = (key, values)

    def query(self, address, *args):
        return self.transport.query(address, *args, timeout=.2)

    def generation_is_current(self, generation):
        with self.lock:
            return generation == self.state['set_generation']

    def _go_query(self, address, *, expected_generation, apply_response):
        if not self.generation_is_current(expected_generation):
            return None
        return self.transport.query_locked(address, timeout=.2)

    def send(self, address, *args):
        if self.transport.send(address, *args) is False:
            raise OSError('Ableton indisponible')
        return True

    def go(self, payload):
        identifier = payload.get('request_id')
        generation = payload.get('set_generation')
        if not isinstance(identifier, str) or not identifier.strip() or len(identifier) > 160:
            return False, 'Identifiant de requête manquant ou invalide', 400
        if not isinstance(generation, int) or isinstance(generation, bool):
            return False, 'Génération de Live Set manquante ou invalide', 400
        context = GoContext(
            self.state, self.lock, self.transaction_lock, self.completed_go_requests,
            self.transport, _scene_index, self.generation_is_current, self.send,
            self._go_query, lambda record: None,
        )
        try:
            with self.lock:
                scene_number = payload.get('scene', self.state['selected_scene'] + 1)
            ok, message = execute_go_core(context, LocalGoConsumer(), identifier.strip(), generation, scene_number)
        except OSError:
            self.unavailable()
            return False, 'Ableton indisponible', 503
        return ok, message, 200 if ok else 409

    def action(self, payload):
        action = payload.get('action')
        if action == 'pause':
            return False, 'Pause indisponible avec le moteur Light legacy', 403
        if action not in LOCAL_LIGHT_ACTIONS:
            return False, 'Action indisponible en LOCAL_LIGHT', 403
        if action == 'go':
            return self.go(payload)
        # Navigation changes only the prepared pointer, never Live selection.
        with self.transaction_lock:
            with self.lock:
                if not self.state['set_ready']:
                    return False, 'Ableton indisponible', 409
                if action in ('prev', 'next', 'goto'):
                    prepared = self.state['selected_scene']
                    index = (_scene_index(payload.get('scene')) if action == 'goto'
                             else max(0, prepared - 1) if action == 'prev' else prepared + 1)
                    if index not in self.state['scenes']:
                        return False, 'Scène absente du Live Set courant', 400
                    self.state.update(selected_scene=index, next_scene=index)
                    self.prepared_by_navigation = True
                    return True, 'Scène préparée', 200
                generation = self.state['set_generation']
            if self.transport.send('/live/song/stop_playing') is False:
                self.unavailable()
                return False, 'Ableton indisponible', 503
            with self.lock:
                if self.state['set_generation'] != generation:
                    return False, 'Live Set modifié pendant la commande', 409
                self.state.update(is_playing=False, is_paused=False, playing_scene=-1,
                                  play_mode='stopped')
                self.observed_scene = None
                self.current_timing = None
            return True, 'Arrêt demandé', 200

    def unavailable(self):
        with self.lock:
            self.state.update(set_ready=False, connected=False, is_playing=False)
            self.error = 'Ableton indisponible'
            self.current_timing = None

    def unsubscribe(self):
        with self.lock:
            tracks = tuple(self.slots)
            token = self.token
            self.token = None
            self.slots = {}
        if token:
            for track in tracks:
                self.transport.send('/live/track/stop_listen/playing_slot_index', track, token)

    def invalidate(self):
        self.unsubscribe()
        self.transport.cancel_pending()
        with self.lock:
            self.state.update(set_ready=False, set_generation=self.state['set_generation'] + 1,
                              scenes={}, selected_scene=0, next_scene=None, playing_scene=-1,
                              has_show_started=False, is_playing=False, is_paused=False)
            self.completed_go_requests.clear()
            self.identity = None
            self.observed_scene = None
            self.current_timing = None
            self.prepared_by_navigation = False

    def refresh_once(self):
        """Acquire a coherent local Set; no duration, console or Arrangement reads."""
        with self.lock:
            generation = self.state['set_generation']
        path = self.query('/live/song/get/file_path')
        name = self.query('/live/song/get/name')
        names = self.query('/live/song/get/scenes/name')
        if path is None or name is None or names is None:
            self.unavailable()
            return
        identity = (str(path[0]) if path else '', str(name[0]) if name else '')
        with self.lock:
            if generation != self.state['set_generation']:
                return
            new_set = (self.identity != identity or
                       (self.state['set_ready'] and
                        self.state['scenes'] != dict(enumerate(str(value) for value in names))))
        if new_set:
            self.invalidate()
        with self.lock:
            generation = self.state['set_generation']
            needs_bootstrap = not self.state['set_ready']
        if needs_bootstrap:
            selected = self.query('/live/view/get/selected_scene')
            count = self.query('/live/song/get/num_tracks')
            confirmed_path = self.query('/live/song/get/file_path')
            confirmed_name = self.query('/live/song/get/name')
            confirmed_names = self.query('/live/song/get/scenes/name')
            if not selected or not count or confirmed_path != path or confirmed_name != name or confirmed_names != names:
                self.unavailable()
                return
            try:
                selected_index, track_count = int(selected[0]), int(count[0])
                if track_count < 0 or track_count > 4096:
                    raise ValueError('Invalid track count')
            except (TypeError, ValueError):
                self.unavailable()
                return
            with self.lock:
                if generation != self.state['set_generation']:
                    return
                self.identity = identity
                self.state.update(scenes=dict(enumerate(str(value) for value in names)),
                                  selected_scene=selected_index, next_scene=selected_index,
                                  set_ready=True)
            self.unsubscribe()
            with self.lock:
                self.token = f'light:{generation}:{uuid.uuid4()}'
                token = self.token
                self.slots = {track: None for track in range(track_count)}
            for track in range(track_count):
                self.transport.send('/live/track/start_listen/playing_slot_index', track, token)
        playing = self.query('/live/song/get/is_playing')
        if playing is None:
            self.unavailable()
            return
        with self.lock:
            if generation != self.state['set_generation']:
                return
            self.state.update(connected=True, is_playing=bool(int(playing[0])))
            if not self.state['is_playing']:
                self.observed_scene = None
                self.current_timing = None
            self.error = ''
            started = self.state['has_show_started']
            prepared_by_navigation = self.prepared_by_navigation
        if not started and not prepared_by_navigation:
            selected = self.query('/live/view/get/selected_scene')
            with self.lock:
                if selected and generation == self.state['set_generation']:
                    index = int(selected[0])
                    if index in self.state['scenes']:
                        self.state.update(selected_scene=index, next_scene=index)

    def receive(self, address, *args, source_host=None):
        if source_host is not None and source_host != LOOPBACK:
            return
        if address == '/live/startup':
            self.invalidate()
            return
        if address != '/live/track/get/playing_slot_index' or len(args) != 3:
            return
        track, token, slot = args
        with self.lock:
            if token != self.token or track not in self.slots or not isinstance(slot, int):
                return
            previous = self.slots[track]
            self.slots[track] = slot
            if slot < 0:
                if self.slots and all(value is not None and value < 0 for value in self.slots.values()):
                    self.state.update(is_playing=False, playing_scene=-1)
                    self.observed_scene = None
                self.current_timing = None
                return
            if slot == previous or slot not in self.state['scenes']:
                return
            following = slot + 1 if slot + 1 in self.state['scenes'] else slot
            scene_changed = slot != self.observed_scene
            self.observed_scene = slot
            updates = dict(
                playing_scene=slot,
                playing_scene_name=self.state['scenes'][slot],
                has_show_started=True,
                is_playing=True,
                is_paused=False,
            )
            # Several tracks can report the same playing scene independently.
            # Those duplicate scene observations must not overwrite a PREV/NEXT/GOTO
            # explicitly prepared by the operator. A genuinely new playing scene,
            # including a manual launch from Live, resumes automatic preparation.
            if scene_changed:
                updates.update(selected_scene=following, next_scene=following)
                self.prepared_by_navigation = False
            self.state.update(**updates)

    def refresh(self):
        while not self.stopping.is_set():
            try:
                self.refresh_once()
                self.refresh_current_timing()
            except (OSError, ValueError, TypeError, IndexError):
                self.unavailable()
            self.stopping.wait(.5)

    def start(self):
        if self.threads:
            return
        def replies():
            try:
                self.transport.serve_forever(bind_host=LOOPBACK, ready_event=self.reply_ready)
            except OSError:
                self.unavailable()
        reply = threading.Thread(target=replies, name='CL Light OSC', daemon=True)
        self.threads.append(reply)
        reply.start()
        if not self.reply_ready.wait(2):
            raise RuntimeError('Port OSC local indisponible')
        worker = threading.Thread(target=self.refresh, name='CL Light Set', daemon=True)
        self.threads.append(worker)
        worker.start()

    def close(self):
        self.stopping.set()
        self.transport.cancel_pending()
        for thread in self.threads[1:]:
            thread.join(timeout=3)
        self.unsubscribe()
        server = getattr(self.transport, '_reply_server', None)
        if server is not None:
            server.shutdown()
            server.server_close()
        for thread in self.threads[:1]:
            thread.join(timeout=3)


def create_light_app(runtime=None):
    backend = Flask('cl_local_light', static_folder=str(Path(__file__).parent / 'static'),
                    template_folder=str(Path(__file__).parent / 'templates'))
    runtime = runtime if runtime is not None else LightRuntime()
    backend.extensions['cl_light_runtime'] = runtime

    @backend.before_request
    def local_boundary():
        if not local_light_request():
            return jsonify(ok=False, error='Accès local requis'), 403
        methods = LIGHT_ROUTES.get(request.path)
        if request.path.startswith('/static/'):
            methods = frozenset({'GET', 'HEAD'})
        if methods is None:
            return jsonify(ok=False, error='Route indisponible en LOCAL_LIGHT'), 404
        if request.method not in methods:
            return jsonify(ok=False, error='Méthode indisponible'), 405
        if request.content_length and request.content_length > 16384:
            return jsonify(ok=False, error='Requête trop grande'), 413

    @backend.after_request
    def headers(response):
        response.headers['Cache-Control'] = 'no-store'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Content-Security-Policy'] = "default-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
        return response

    @backend.get('/')
    def index():
        return render_template('light.html')

    @backend.get('/status')
    def status():
        return jsonify(runtime.light_state_snapshot())

    @backend.post('/action')
    def action():
        payload = request.get_json(silent=True)
        if not isinstance(payload, dict):
            return jsonify(ok=False, error='Objet JSON requis'), 400
        ok, message, code = runtime.action(payload)
        return jsonify(ok=ok, message=message, state=runtime.light_state_snapshot()), code

    return backend


def run_light(window=False):
    """Bind HTTP before starting OSC; fail rather than adopting any FULL server."""
    from werkzeug.serving import make_server
    backend = create_light_app()
    runtime = backend.extensions['cl_light_runtime']
    server = make_server(LOOPBACK, LIGHT_WEB_PORT, backend, threaded=True)
    web_thread = None
    try:
        runtime.start()
        if window:
            import webview
            web_thread = threading.Thread(target=server.serve_forever, name='CL Light Web', daemon=True)
            web_thread.start()
            webview.create_window('CL Show Control Light', f'http://{LOOPBACK}:{LIGHT_WEB_PORT}/')
            webview.start()
        else:
            server.serve_forever()
    finally:
        if web_thread is not None:
            server.shutdown()
            web_thread.join(timeout=3)
        server.server_close()
        runtime.close()
