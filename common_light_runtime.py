"""Light product host over the existing Ableton engine, timing and security.

No parallel scene tracker: the adapter owns HTTP and worker lifecycle only.
Legacy LightRuntime remains available via CL_LIGHT_ENGINE=legacy.
"""
import importlib.util
from pathlib import Path
import sys
import threading
import time
import uuid

from flask import jsonify, render_template, request
from app_mode import LOCAL_LIGHT_ACTIONS, common_light_capabilities
from go_core import GoContext
from runtime_startup import _common_host, create_common_light_controller


def load_common_host():
    token = _common_host.set(common_light_capabilities())
    name = 'cl_light_common_host_' + uuid.uuid4().hex
    try:
        source = importlib.util.find_spec("app")
        # The loader also supports PyInstaller frozen code: no loose app.py required.
        import types
        host = types.ModuleType(name)
        host.__file__ = source.origin
        host.__package__ = ""
        sys.modules[name] = host
        exec(source.loader.get_code("app"), host.__dict__)
        return host
    except BaseException:
        sys.modules.pop(name, None)
        raise
    finally:
        _common_host.reset(token)


class CommonLightRuntime:
    def __init__(self, host):
        self.host = host
        self.stopping = threading.Event()
        self.threads = []
        self.remote_enabled = False
        context = GoContext(host.state, host.lock, host.scene_transaction_lock,
                            host.completed_go_requests, host.ableton_transport,
                            host.clamp_scene_number, host.generation_is_current,
                            host.send, host._query_with_query_lock_held,
                            host.write_keyboard_diagnostic)
        self.controller = create_common_light_controller(
            host.ableton_runtime, host.scene_timing, context,
            host.ProfileGoConsumer(common_light_capabilities()))

    def snapshot(self):
        state = dict(self.controller.snapshot())
        state['remote_enabled'] = bool(self.remote_enabled)
        return state

    def action(self, payload):
        action = payload.get('action')
        if action not in LOCAL_LIGHT_ACTIONS:
            return False, 'Action indisponible en LIGHT', 403
        h = self.host
        try:
            generation = int(payload['set_generation'])
        except (KeyError, TypeError, ValueError):
            return False, 'Génération du Set requise', 400
        with h.scene_transaction_lock:
            with h.lock:
                if generation != h.state['set_generation']:
                    return False, 'Génération de Live Set obsolète', 409
                if not h.state['set_ready'] or not h.state['connected']:
                    return False, 'Ableton indisponible', 409
            if action == 'go':
                request_id = payload.get('request_id')
                if not isinstance(request_id, str) or not request_id or len(request_id) > 128:
                    return False, 'request_id requis', 400
                # Core owns its transaction lock; leave this outer lock first.
            elif action in ('prev', 'next', 'goto'):
                with h.lock:
                    selected = h.state['selected_scene']
                    try:
                        index = (int(payload['scene']) - 1 if action == 'goto'
                                 else selected + (1 if action == 'next' else -1))
                    except (KeyError, TypeError, ValueError):
                        return False, 'Scène invalide', 400
                    if index not in h.state['scenes']:
                        return False, 'Scène absente du Live Set courant', 400
                    # Prepare only. GO performs the explicit Live selection.
                    h.state.update(selected_scene=index, next_scene=index,
                                   selected_scene_name=h.state['scenes'][index],
                                   selected_scene_duration_seconds=h.scene_timing.declared_duration(h.state['scenes'][index]),
                                   selected_scene_duration_index=index,
                                   selected_scene_duration_is_clip=False,
                                   has_show_started=True)
                h.scene_timing.prepare_duration(index, generation)
                return True, 'Scène préparée', 200

            elif action == 'pause':
                with h.lock:
                    currently_playing = bool(h.state.get('is_playing', False))
                    currently_paused = bool(h.state.get('is_paused', False))
                    current_mode = str(h.state.get('play_mode', 'stopped'))

                if currently_playing:
                    if h.send('/live/song/stop_playing') is False:
                        return False, 'Ableton indisponible', 503

                    deadline = time.monotonic() + .85
                    confirmed = False

                    while time.monotonic() < deadline:
                        response = h.query(
                            '/live/song/get/is_playing',
                            timeout=.20,
                            expected_generation=generation,
                        )

                        if not h.generation_is_current(generation):
                            return False, 'Live Set modifié pendant la commande', 409

                        if response:
                            raw = response[0]
                            playing = (
                                raw.strip().lower() not in ('0', 'false', 'off', 'no', '')
                                if isinstance(raw, str)
                                else bool(raw)
                            )
                            if not playing:
                                confirmed = True
                                break

                        time.sleep(.025)

                    if not confirmed:
                        return False, 'Pause non confirmée par Ableton', 409

                    with h.lock:
                        if generation != h.state['set_generation']:
                            return False, 'Live Set modifié pendant la commande', 409

                        playback_deadline = h.state.get('playback_deadline')
                        if playback_deadline is not None:
                            h.state['remaining_seconds'] = max(
                                0.0,
                                float(playback_deadline) - time.time(),
                            )

                        h.state['is_playing'] = False
                        h.state['is_paused'] = True
                        h.state['play_mode'] = (
                            current_mode
                            if current_mode in ('arrangement', 'session')
                            else 'paused'
                        )
                        h.state['message'] = 'Pause'

                    return True, 'Pause', 200

                if currently_paused:
                    if h.send('/live/song/continue_playing') is False:
                        return False, 'Ableton indisponible', 503

                    deadline = time.monotonic() + .85
                    confirmed = False

                    while time.monotonic() < deadline:
                        response = h.query(
                            '/live/song/get/is_playing',
                            timeout=.20,
                            expected_generation=generation,
                        )

                        if not h.generation_is_current(generation):
                            return False, 'Live Set modifié pendant la commande', 409

                        if response:
                            raw = response[0]
                            playing = (
                                raw.strip().lower() not in ('0', 'false', 'off', 'no', '')
                                if isinstance(raw, str)
                                else bool(raw)
                            )
                            if playing:
                                confirmed = True
                                break

                        time.sleep(.025)

                    if not confirmed:
                        return False, 'Reprise non confirmée par Ableton', 409

                    with h.lock:
                        if generation != h.state['set_generation']:
                            return False, 'Live Set modifié pendant la commande', 409

                        remaining = h.state.get('remaining_seconds')
                        if remaining is not None:
                            h.state['playback_deadline'] = (
                                time.time() + max(0.0, float(remaining))
                            )

                        h.state['is_playing'] = True
                        h.state['is_paused'] = False
                        h.state['play_mode'] = (
                            current_mode
                            if current_mode in ('arrangement', 'session')
                            else 'arrangement'
                        )
                        h.state['message'] = 'Reprise'

                    return True, 'Reprise', 200

                return False, 'Aucune lecture à mettre en pause', 409

            else:
                if h.send('/live/song/stop_playing') is False:
                    return False, 'Ableton indisponible', 503
                deadline = time.monotonic() + .85
                confirmed = False
                while time.monotonic() < deadline:
                    response = h.query('/live/song/get/is_playing',
                                       timeout=.20, expected_generation=generation)
                    if not h.generation_is_current(generation):
                        return False, 'Live Set modifié pendant la commande', 409
                    if response:
                        raw = response[0]
                        playing = (raw.strip().lower() not in ('0', 'false', 'off', 'no', '')
                                   if isinstance(raw, str) else bool(raw))
                        if not playing:
                            confirmed = True
                            break
                    time.sleep(.025)
                with h.lock:
                    if generation != h.state['set_generation']:
                        return False, 'Live Set modifié pendant la commande', 409
                    if not confirmed:
                        return False, 'Arrêt non confirmé par Ableton', 409
                    h.state.update(is_playing=False, is_paused=False, play_mode='stopped', playing_scene=-1, current_scene=None,
                                   scene_duration_seconds=None, remaining_seconds=None,
                                   playback_deadline=None)
                return True, 'Arrêt confirmé', 200
        ok, message = self.controller.go(request_id, generation, payload.get('scene'))
        return ok, message, 200 if ok else 409

    def refresh_once(self):
        refreshed = self.host.ableton_runtime.refresh_names_and_transport()
        if not refreshed:
            with self.host.lock:
                if not self.host.state.get('bootstrap_running'):
                    self.host.set_connected_locked(False, 'Ableton indisponible', 'light_refresh')
        if refreshed:
            self.host.ableton_runtime.ensure_playing_scene_listeners()
        return refreshed

    def start(self):
        if self.threads:
            return
        ready = threading.Event()
        osc = threading.Thread(target=self.host.ableton_transport.serve_forever,
                               kwargs={'bind_host': '127.0.0.1', 'ready_event': ready},
                               name='CL Light OSC', daemon=True)
        osc.start()
        self.threads.append(osc)
        if not ready.wait(3):
            raise RuntimeError('AbletonOSC reply port indisponible')
        def refresh():
            while not self.stopping.is_set():
                self.refresh_once()
                self.stopping.wait(.5)
        worker = threading.Thread(target=refresh, name='CL Light Ableton', daemon=True)
        worker.start()
        self.threads.append(worker)
        from security_http import start_remote_tls
        start_remote_tls(self.host.app)

    def close(self):
        self.stopping.set()
        with self.host.lock:
            self.host._playing_listener_shutdown = True
            self.host.stop_playing_scene_listeners_locked()
            self.host.state['set_generation'] += 1
            self.host.state['set_ready'] = False
            transaction = self.host._bootstrap_transaction
            if transaction is not None:
                self.host._bootstrap_cancel(transaction, 'Light arrêté')
            self.host.ableton_transport.cancel_pending()
        transport = self.host.ableton_transport
        server = getattr(transport, '_reply_server', None)
        if server is not None:
            server.shutdown()
            server.server_close()
        tls = self.host.app.extensions.get('cl_remote_tls')
        if tls is not None:
            tls.stop()
        for worker in self.threads:
            worker.join(timeout=3)


def create_common_light_app(host=None):
    host = host if host is not None else load_common_host()
    backend = host.app
    runtime = CommonLightRuntime(host)
    backend.extensions['cl_common_light_runtime'] = runtime
    # Security before_request remains the same authoritative FULL boundary.
    @backend.before_request
    def light_routes():
        if request.path in ('/', '/status', '/action', '/show-info', '/light/remote') or request.path.startswith(('/static/', '/security/', '/remote/')):
            return None
        return jsonify(ok=False, message='Route indisponible en LIGHT'), 404

    def index():
        return render_template('light.html')

    def status():
        return jsonify(runtime.snapshot())

    def remote_control():
        from security_http import local_request

        if not local_request():
            return jsonify(
                ok=False,
                error='Activation de la télécommande réservée au Mac local',
                remote_enabled=bool(runtime.remote_enabled),
            ), 403

        if request.method == 'GET':
            return jsonify(
                ok=True,
                remote_enabled=bool(runtime.remote_enabled),
                state=runtime.snapshot(),
            )

        payload = request.get_json(silent=True)
        if not isinstance(payload, dict) or not isinstance(payload.get('enabled'), bool):
            return jsonify(ok=False, error='enabled booléen requis'), 400

        runtime.remote_enabled = bool(payload['enabled'])

        return jsonify(
            ok=True,
            remote_enabled=bool(runtime.remote_enabled),
            state=runtime.snapshot(),
        )

    def action():
        payload = request.get_json(silent=True)
        if not isinstance(payload, dict):
            return jsonify(ok=False, message='Objet JSON requis'), 400
        ok, message, code = runtime.action(payload)
        return jsonify(ok=ok, message=message, state=runtime.snapshot()), code
    backend.view_functions.update(index=index, show_info_page=index, status=status, action=action)
    backend.add_url_rule(
        '/light/remote',
        'light_remote_control',
        remote_control,
        methods=['GET', 'POST'],
    )
    return backend


def run_light(window=False):
    from werkzeug.serving import make_server
    backend = create_common_light_app()
    runtime = backend.extensions['cl_common_light_runtime']
    server = make_server('0.0.0.0', 5050, backend, threaded=True)
    try:
        runtime.start()
        if window:
            import webview
            worker = threading.Thread(target=server.serve_forever, name='CL Light Web', daemon=True)
            worker.start()
            webview.create_window('CL Show Control Light', 'http://127.0.0.1:5050/')
            webview.start()
            server.shutdown()
        else:
            server.serve_forever()
    finally:
        server.server_close()
        runtime.close()
