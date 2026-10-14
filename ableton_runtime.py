"""Extracted FULL Ableton tracking, using one injected state and transport.

Bindings are a compatibility seam: mutable globals remain owned by the host until
lifecycle composition is migrated. No product services or workers start here.
"""
from typing import Any, Optional, Tuple

class RuntimeBindings:

    def __init__(self, namespace, **hooks):
        object.__setattr__(self, '_namespace', namespace)
        object.__setattr__(self, '_hooks', hooks)

    def __getattr__(self, name):
        if name in self._hooks:
            return self._hooks[name]
        return self._namespace[name]

    def __setattr__(self, name, value):
        self._namespace[name] = value

class AbletonRuntime:

    def __init__(self, bindings):
        self.bindings = bindings

    def invalidated_session_state(self, identity, generation, reason):
        return invalidated_session_state(identity, generation, reason)

    def snapshot(self):
        with self.bindings.lock:
            s = self.bindings.state
            return {'set_available': bool(s.get('set_ready')), 'set_identity': s.get('current_set_id'), 'set_generation': int(s.get('set_generation', 0)), 'scenes': dict(s.get('scenes', {})), 'selected_scene': s.get('selected_scene'), 'playing_scene': s.get('playing_scene'), 'is_playing': bool(s.get('is_playing')), 'connected': bool(s.get('connected'))}

    def light_snapshot(self, timing):
        from app_mode import local_light_state
        with self.bindings.lock:
            s = self.bindings.state
            result = local_light_state(dict(s, set_ready=bool(s.get("set_ready") and s.get("connected"))))
            timing.refresh_remaining()
            valid = result['is_playing'] and result['current_scene'] is not None and bool(s.get('connected'))
            duration = s.get('scene_duration_seconds') if valid else None
            remaining = s.get('remaining_seconds') if valid else None
            result.update(error='' if s.get('connected') else 'Ableton indisponible', next_scene_name=str(s.get('scenes', {}).get(result['next_scene'], '')), mode='LOCAL_LIGHT', ableton_available=bool(s.get('connected')), current_duration_seconds=duration, current_remaining_seconds=remaining, current_position_seconds=max(0, duration - remaining) if duration is not None and remaining is not None else None, prepared_duration_seconds=s.get('selected_scene_duration_seconds') if result['set_available'] else None)
            return result

    def apply_live_set_bootstrap_locked(self, *args, **kwargs):
        return apply_live_set_bootstrap_locked(self.bindings, *args, **kwargs)

    def bootstrap_live_set(self, *args, **kwargs):
        return bootstrap_live_set(self.bindings, *args, **kwargs)

    def ensure_playing_scene_listeners(self, *args, **kwargs):
        return ensure_playing_scene_listeners(self.bindings, *args, **kwargs)

    def refresh_live_set_identity(self, *args, **kwargs):
        return refresh_live_set_identity(self.bindings, *args, **kwargs)

    def refresh_names_and_transport(self, *args, **kwargs):
        return refresh_names_and_transport(self.bindings, *args, **kwargs)

    def update_manual_scene_state_locked(self, *args, **kwargs):
        return update_manual_scene_state_locked(self.bindings, *args, **kwargs)

def ensure_playing_scene_listeners(bindings) -> None:
    """One read of track count per Set; no recurring track/clip scan.

    AbletonOSC echoes extra start_listen parameters BEFORE the property value.
    The opaque token therefore identifies the actual subscription on the wire,
    including across server restarts, rather than tagging arrivals retroactively.
    """
    if not bindings._playing_listener_install_lock.acquire(blocking=False):
        return
    try:
        with bindings.lock:
            generation = int(bindings.state.get('set_generation', 0))
            if bindings._playing_listener_shutdown or not bindings.state.get('set_ready') or bindings._playing_listener_generation == generation:
                return
        response = bindings.query('/live/song/get/num_tracks', expected_generation=generation, apply_response=False)
        if not response:
            return
        try:
            count = int(response[0])
        except (ValueError, TypeError):
            return
        if count < 0:
            return
        with bindings.lock:
            if bindings._playing_listener_shutdown or generation != int(bindings.state.get('set_generation', 0)) or (not bindings.state.get('set_ready')):
                return
            bindings.stop_playing_scene_listeners_locked()
            bindings._playing_listener_generation = generation
            bindings._playing_listener_token = f'{bindings.SERVER_INSTANCE_ID}:{generation}:{bindings.uuid.uuid4()}'
            for track in range(count):
                bindings._playing_listener_tracks[track] = None
                if bindings.ableton_transport.send('/live/track/start_listen/playing_slot_index', track, bindings._playing_listener_token) is False:
                    bindings.stop_playing_scene_listeners_locked()
                    return
    finally:
        bindings._playing_listener_install_lock.release()

def update_manual_scene_state_locked(bindings, generation, slot, name, initial):
    """Observed Session state and timing only; no console I/O or backup send."""
    duration = bindings.scene_timing.declared_duration(name)
    now = bindings.time.time()
    bindings.state.update(playing_scene=slot, playing_scene_name=name, current_scene=slot, last_fired_scene=slot, last_fired_scene_name=name, has_show_started=True, play_mode='session', is_playing=True, is_paused=False, scene_duration_seconds=duration, scene_duration_is_clip=False, remaining_seconds=None if initial else duration, playback_deadline=now + duration if duration is not None and (not initial) else None, sync_source='Ableton événement', arrangement_marker='—')
    return now

def refresh_live_set_identity(bindings, expected_generation: Optional[int]=None) -> Optional[int]:
    """Vérifie l'identité du Set pendant le rafraîchissement normal.

    /live/startup donne la réinitialisation immédiate. Cette comparaison permanente
    de file_path constitue la seconde source de détection si l'événement est perdu.
    """
    if expected_generation is None:
        with bindings.lock:
            expected_generation = int(bindings.state.get('set_generation', 0))
    with bindings.lock:
        transaction = bindings._bootstrap_transaction
        if transaction is not None and transaction.generation == int(expected_generation) and (not transaction.completed) and (not transaction.cancelled):
            return int(expected_generation)
    file_path_response = bindings.query('/live/song/get/file_path', timeout=bindings.OSC_TIMEOUT, expected_generation=expected_generation, allow_during_bootstrap=True, apply_response=False)
    if file_path_response is None:
        with bindings.lock:
            if int(bindings.state.get('set_generation', 0)) == int(expected_generation):
                bindings.set_connected_locked(
                    False,
                    'AbletonOSC ne répond pas',
                    'refresh_live_set_identity',
                )
                bindings.state['message'] = 'AbletonOSC indisponible'
        return None

    file_path_available = True
    file_path = bindings._first_text_value(file_path_response)
    if not bindings.generation_is_current(expected_generation):
        return None
    set_name_response = bindings.query('/live/song/get/name', timeout=bindings.OSC_TIMEOUT, expected_generation=expected_generation, allow_during_bootstrap=True, apply_response=False)
    set_name_available = set_name_response is not None
    set_name = bindings._first_text_value(set_name_response)
    if not bindings.generation_is_current(expected_generation):
        return None
    confirmation_response = bindings.query('/live/song/get/file_path', timeout=bindings.OSC_TIMEOUT, expected_generation=expected_generation, allow_during_bootstrap=True, apply_response=False)
    if confirmation_response is None or not bindings.generation_is_current(expected_generation):
        return None
    confirmed_file_path = bindings._first_text_value(confirmation_response)
    if confirmed_file_path != file_path:
        bindings.generation_log('identity_confirmation_mismatch', first=file_path, second=confirmed_file_path, generation=expected_generation)
        return None
    with bindings.lock:
        current_id = bindings.state.get('current_set_id')
        if current_id is None:
            generation = bindings.reset_live_set_state_locked(file_path or None, 'initial identity')
            if not file_path:
                bindings.state['current_set_id'] = f'unsaved:{generation}'
            bindings.state['current_set_name'] = set_name
            return generation
        pending = str(current_id).startswith('pending:')
        observed_id = file_path or (f'unsaved:{expected_generation}' if pending else str(current_id))
        if pending:
            bindings.state['current_set_id'] = observed_id
            bindings.state['current_set_name'] = set_name
            return int(bindings.state['set_generation'])
        current_is_temporary = str(current_id).startswith('unsaved:')
        identity_changed = file_path_available and (bool(file_path) and file_path != current_id or (not file_path and (not current_is_temporary)))
        if identity_changed:
            bindings.generation_log('file_path_changed', previous_set_id=current_id, observed_set_id=file_path or '<unsaved>', generation=expected_generation)
            generation = bindings.reset_live_set_state_locked(file_path or None, 'file_path')
            if not file_path:
                bindings.state['current_set_id'] = f'unsaved:{generation}'
            bindings.state['current_set_name'] = set_name
            return generation
        if set_name_available:
            bindings.state['current_set_name'] = set_name
        return int(bindings.state['set_generation'])

def apply_live_set_bootstrap_locked(bindings, generation: int, file_path: str, set_name: str, selected_scene: int, scene_names: Tuple[Any, ...]) -> bool:
    """Remplace en une écriture l'intégralité des données propres au nouveau Set."""
    if int(bindings.state.get('set_generation', 0)) != int(generation):
        bindings.write_bootstrap_diagnostic('bootstrap-apply-rejected', reason='generation_mismatch', transactionGeneration=generation, stateGeneration=bindings.state.get('set_generation'))
        return False
    if bindings.state.get('set_ready', False):
        bindings.write_bootstrap_diagnostic('bootstrap-apply-rejected', reason='set_already_ready', generation=generation)
        return False
    set_id = file_path or f'unsaved:{generation}'
    current_id = str(bindings.state.get('current_set_id') or '')
    temporary_same_generation = current_id == f'unsaved:{generation}'
    if current_id and (not current_id.startswith('pending:')) and (not temporary_same_generation) and (current_id != set_id):
        bindings.write_bootstrap_diagnostic('bootstrap-apply-rejected', reason='set_identity_mismatch', generation=generation, currentSetId=current_id, transactionSetId=set_id)
        return False
    new_scenes = {index: str(name) for index, name in enumerate(scene_names) if name is not None}
    selected_name = new_scenes.get(int(selected_scene), '—') or '—'
    bindings.state.update({'current_set_id': set_id, 'current_set_name': set_name, 'selected_scene': int(selected_scene), 'next_scene': int(selected_scene), 'selected_scene_name': selected_name, 'selected_scene_duration_seconds': bindings.parse_scene_duration_seconds(selected_name), 'selected_scene_duration_index': int(selected_scene), 'selected_scene_duration_is_clip': False, 'scenes': new_scenes, 'current_scene': None, 'playing_scene': -1, 'playing_scene_name': '—', 'last_fired_scene': -1, 'last_fired_scene_name': '—', 'has_show_started': False, 'message': 'Live Set prêt', 'sync_source': 'Ableton'})
    bindings.set_connected_locked(True, 'bootstrap complet', 'apply_live_set_bootstrap_locked')
    bindings.set_set_ready_locked(True, 'bootstrap complet et cohérent', 'apply_live_set_bootstrap_locked')
    bindings.set_bootstrap_step_locked('Live Set prêt', 'bootstrap complet et cohérent')
    bindings.state['bootstrap_running'] = False
    bindings.state['bootstrap_generation'] = None
    bindings.state['pending_request'] = None
    bindings.state['last_successful_bootstrap'] = {'generation': int(generation), 'completed_at': bindings.time.time(), 'current_set_id': set_id, 'scene_count': len(new_scenes), 'selected_scene': int(selected_scene)}
    bindings._bootstrap_generation = None
    bindings.generation_log('bootstrap_complete', generation=generation, current_set_id=set_id, selected_scene=selected_scene, scene_count=len(new_scenes))
    return True

def bootstrap_live_set(bindings, generation: int) -> None:
    """Accumule un instantané privé jusqu'à complétion ou échéance globale."""
    with bindings.lock:
        transaction = bindings._bootstrap_transaction
        if transaction is None or transaction.generation != int(generation):
            transaction = bindings._new_bootstrap_transaction(generation)
            bindings._bootstrap_transaction = transaction
    try:
        with bindings.lock:
            bindings.set_bootstrap_step_locked('purge des réponses OSC antérieures', 'début du bootstrap transactionnel')
        bindings.write_bootstrap_diagnostic('bootstrap-started', setGeneration=generation)
        bindings.time.sleep(bindings.OSC_BOOTSTRAP_DRAIN_SECONDS)
        request_fields = (('file_path', '/live/song/get/file_path', 0.1, 'attente de Song.file_path'), ('song_name', '/live/song/get/name', 0.08, 'attente de Song.name'), ('selected_scene', '/live/view/get/selected_scene', 0.1, 'attente de la scène sélectionnée'), ('scene_names', '/live/song/get/scenes/name', 0.2, 'attente des noms de scènes'))
        while not transaction.completed and (not transaction.cancelled):
            if not bindings.generation_is_current(generation):
                bindings._bootstrap_cancel(transaction, 'génération modifiée pendant le bootstrap')
                return
            if transaction.target_identity != bindings._bootstrap_target_identity():
                bindings._bootstrap_cancel(transaction, 'cible OSC modifiée pendant le bootstrap')
                return
            if bindings.time.monotonic() >= transaction.deadline:
                bindings._bootstrap_cancel(transaction, 'timeout global du bootstrap', event='timeout')
                return
            progress = False
            for field_name, address, technical_timeout, step in request_fields:
                if transaction.received(field_name):
                    continue
                with bindings.lock:
                    bindings.set_bootstrap_step_locked(step, f'transaction #{generation}')
                if bindings._bootstrap_query_field(transaction, field_name, address, technical_timeout):
                    progress = True
                if not bindings.generation_is_current(generation):
                    bindings._bootstrap_cancel(transaction, 'génération modifiée pendant une lecture')
                    return
                if bindings.time.monotonic() >= transaction.deadline:
                    break
            if transaction.ready_to_confirm() and (not transaction.received('confirmed_file_path')):
                with bindings.lock:
                    bindings.set_bootstrap_step_locked('confirmation de Song.file_path', "validation finale de l'identité")
                if bindings._bootstrap_query_field(transaction, 'confirmed_file_path', '/live/song/get/file_path', 0.1):
                    progress = True
                    if transaction.confirmed_file_path != transaction.file_path:
                        bindings._bootstrap_cancel(transaction, 'Song.file_path a changé pendant le bootstrap')
                        return
                    bindings.write_bootstrap_diagnostic('bootstrap-file-path-confirmed', setGeneration=generation, filePath=transaction.file_path)
            if transaction.complete():
                if not bindings.generation_is_current(generation):
                    bindings._bootstrap_cancel(transaction, 'génération modifiée avant publication')
                    return
                with bindings.lock:
                    applied = bindings.apply_live_set_bootstrap_locked(generation, str(transaction.confirmed_file_path), str(transaction.song_name), int(transaction.selected_scene), tuple(transaction.scene_names))
                if not applied:
                    bindings._bootstrap_cancel(transaction, 'instantané cohérent refusé avant publication')
                    return
                transaction.completed = True
                bindings.on_set_ready(generation)
                elapsed_ms = int((bindings.time.monotonic() - transaction.started_at) * 1000)
                bindings.write_bootstrap_diagnostic('bootstrap-transaction-completed', setGeneration=generation, filePath=transaction.confirmed_file_path, selectedScene=transaction.selected_scene, sceneCount=len(transaction.scene_names), attempts=dict(transaction.attempts), elapsedMs=elapsed_ms)
                return
            bindings.write_bootstrap_diagnostic('bootstrap-transaction-waiting', setGeneration=generation, missing=transaction.missing(), attempts=dict(transaction.attempts), remainingMs=max(0, int((transaction.deadline - bindings.time.monotonic()) * 1000)))
            if not progress:
                bindings.time.sleep(min(bindings.BOOTSTRAP_RETRY_PAUSE_SECONDS, max(0.0, transaction.deadline - bindings.time.monotonic())))
    except Exception as exc:
        bindings._bootstrap_cancel(transaction, f'exception {type(exc).__name__}: {exc}')
    finally:
        with bindings.lock:
            if bindings._bootstrap_transaction is transaction and (transaction.completed or transaction.cancelled):
                bindings._bootstrap_transaction = None
            if bindings._bootstrap_generation == generation and (not bindings.state.get('set_ready', False)):
                bindings._bootstrap_generation = None
                bindings.state['bootstrap_running'] = False
                bindings.state['bootstrap_generation'] = None
                bindings.state['pending_request'] = None

def refresh_names_and_transport(bindings) -> bool:
    """
    Refresh léger. Ne scanne pas toutes les pistes.
    """
    try:
        initial_generation = None
        recovery_generation = None
        wait_for_initial_bootstrap = False
        with bindings.lock:
            generation = int(bindings.state.get('set_generation', 0))
            transaction = bindings._bootstrap_transaction
            bootstrap_active = bindings._bootstrap_generation is not None or (transaction is not None and (not transaction.completed) and (not transaction.cancelled))
            if bootstrap_active and (not bindings.state.get('set_ready', False)):
                wait_for_initial_bootstrap = True
            elif bindings.state.get('current_set_id') is None:
                initial_generation = bindings.reset_live_set_state_locked(None, 'initial bootstrap')
            elif not bindings.state.get('set_ready', False):
                recovery_generation = generation
        if initial_generation is not None:
            bindings.start_live_set_bootstrap(initial_generation)
            return False
        if recovery_generation is not None:
            bindings.start_live_set_bootstrap(recovery_generation)
            return False
        if wait_for_initial_bootstrap:
            return False
        verified_generation = bindings.refresh_live_set_identity(generation)
        if verified_generation is None:
            return False
        if verified_generation != generation:
            bindings.start_live_set_bootstrap(verified_generation)
            return False
        generation = verified_generation
        with bindings.lock:
            ready = bool(bindings.state.get('set_ready', False))
        if not ready:
            bindings.start_live_set_bootstrap(generation)
            return False
        res = bindings.query('/live/view/get/selected_scene', expected_generation=generation)
        if res:
            selected = int(res[0])
            with bindings.lock:
                if int(bindings.state.get('set_generation', 0)) != generation:
                    return
                sync_live_selection = not bool(bindings.state.get('has_show_started'))
                if sync_live_selection:
                    selection_changed = int(bindings.state.get('selected_scene', -1)) != selected
                    bindings.state['selected_scene'] = selected
                    bindings.state['next_scene'] = selected
                    if selection_changed:
                        selected_name = str(bindings.state.get('scenes', {}).get(selected, '') or '')
                        bindings.state['selected_scene_duration_seconds'] = bindings.parse_scene_duration_seconds(selected_name)
                        bindings.state['selected_scene_duration_index'] = selected
                        bindings.state['selected_scene_duration_is_clip'] = False
                    should_refresh_selected_duration = selection_changed or int(bindings.state.get('selected_scene_duration_index', -1)) != selected or (not bool(bindings.state.get('selected_scene_duration_is_clip', False)))
                else:
                    should_refresh_selected_duration = False
            if sync_live_selection:
                bindings.query('/live/scene/get/name', selected, expected_generation=generation)
                if should_refresh_selected_duration:
                    bindings.schedule_selected_scene_duration_refresh(selected, generation)
        transport_response = bindings.query(
            '/live/song/get/is_playing',
            expected_generation=generation,
        )
        if transport_response is None:
            with bindings.lock:
                if int(bindings.state.get('set_generation', 0)) != generation:
                    return False
                bindings.set_connected_locked(
                    False,
                    'AbletonOSC ne répond pas',
                    'refresh_names_and_transport',
                )
                bindings.state['message'] = 'AbletonOSC indisponible'
            return False

        with bindings.lock:
            if int(bindings.state.get('set_generation', 0)) != generation:
                return
            playing = int(bindings.state.get('playing_scene', -1))
            transport_playing = bool(bindings.state.get('is_playing'))
        if transport_playing and playing < 0:
            bindings.scan_playing_scene_from_tracks()
            with bindings.lock:
                if int(bindings.state.get('set_generation', 0)) != generation:
                    return
                playing = int(bindings.state.get('playing_scene', -1))
        with bindings.lock:
            show_started = bool(bindings.state.get('has_show_started'))
        if playing >= 0 and show_started:
            bindings.query('/live/scene/get/name', playing, expected_generation=generation)
        with bindings.lock:
            bindings.set_connected_locked(True, 'rafraîchissement OSC réussi', 'refresh_names_and_transport')
            bindings.state['message'] = 'Connecté à AbletonOSC'
            bindings.state['sync_source'] = 'Ableton'
        return True
    except Exception as e:
        with bindings.lock:
            bindings.set_connected_locked(False, str(e), 'refresh_names_and_transport')
            bindings.state['message'] = f'Erreur : {e}'
        return False


class CommonLightController:
    """Test/migration facade over the existing engine, never a second tracker."""
    def __init__(self, runtime, timing, go_context, consumer):
        self.runtime = runtime
        self.timing = timing
        self.go_context = go_context
        self.consumer = consumer

    def snapshot(self):
        return self.runtime.light_snapshot(self.timing)

    def go(self, request_id, generation, scene):
        from go_core import execute_go_core
        return execute_go_core(self.go_context, self.consumer, request_id, generation, scene)


def invalidated_session_state(identity, generation, reason):
    """Pure generation reset fields; product state stays in the host."""
    return {'current_set_id': identity, 'current_set_name': '', 'set_generation': generation, 'current_scene': None, 'next_scene': None, 'has_show_started': False, 'selected_scene': 0, 'selected_scene_name': '—', 'selected_scene_duration_seconds': None, 'selected_scene_duration_index': None, 'selected_scene_duration_is_clip': False, 'scenes': {}, 'play_mode': 'stopped', 'playing_scene': -1, 'playing_scene_name': '—', 'last_fired_scene': -1, 'last_fired_scene_name': '—', 'is_playing': False, 'is_paused': False, 'scene_duration_seconds': None, 'scene_duration_is_clip': False, 'remaining_seconds': None, 'playback_deadline': None, 'last_arrangement_time': 0.0, 'message': f'Nouveau Live Set détecté ({reason})', 'sync_source': 'Ableton', 'bootstrap_running': False, 'bootstrap_generation': None, 'pending_request': None}
