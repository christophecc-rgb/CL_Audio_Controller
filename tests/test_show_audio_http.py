from unittest.mock import patch

from show_audio_http import (
    ShowAudioHTTPStatusSource,
    _scene_names_from_status,
)


def test_scene_names_from_dict():
    status = {
        "scenes": {
            "0": "Reset",
            "1": "INTRO",
            "2": "JADE",
        }
    }

    assert _scene_names_from_status(status) == [
        "Reset",
        "INTRO",
        "JADE",
    ]


def test_scene_names_preserve_missing_indices():
    status = {
        "scenes": {
            "0": "Reset",
            "2": "JADE",
        }
    }

    assert _scene_names_from_status(status) == [
        "Reset",
        "",
        "JADE",
    ]


def test_query_scene_names_from_cached_http_status():
    source = ShowAudioHTTPStatusSource()

    with patch.object(
        source,
        "fetch_status",
        return_value={
            "scenes": {
                "0": "A",
                "1": "B",
            }
        },
    ):
        result = source.query(
            "/live/song/get/scenes/name",
            apply_response=False,
        )

    assert result == ("A", "B")


def test_tracks_missing_is_empty():
    source = ShowAudioHTTPStatusSource()

    with patch.object(
        source,
        "fetch_status",
        return_value={},
    ):
        assert source.query(
            "/live/song/get/track_names"
        ) == tuple()


def test_tempo_missing_is_empty():
    source = ShowAudioHTTPStatusSource()

    with patch.object(
        source,
        "fetch_status",
        return_value={},
    ):
        assert source.query(
            "/live/song/get/tempo"
        ) == tuple()


def test_clip_length_unavailable():
    source = ShowAudioHTTPStatusSource()

    with patch.object(
        source,
        "fetch_status",
        return_value={},
    ):
        assert source.query(
            "/live/clip/get/length",
            0,
            1,
        ) == tuple()


def test_identity():
    source = ShowAudioHTTPStatusSource()

    source.last_status = {
        "connected": True,
        "set_ready": True,
        "set_generation": 7,
        "current_set_id": "abc",
        "current_set_name": "MPC V12",
        "selected_scene": 4,
        "playing_scene": -1,
        "playing_scene_name": "—",
        "server_process_id": 1234,
        "service": "CL Audio Controller",
    }

    identity = source.identity()

    assert identity["connected"] is True
    assert identity["set_ready"] is True
    assert identity["set_generation"] == 7
    assert identity["set_name"] == "MPC V12"
    assert identity["server_process_id"] == 1234


import pytest
from types import SimpleNamespace


@pytest.fixture(scope="module")
def offline_loop_app():
    from test_live_set_generation import load_app_module
    return load_app_module()


@pytest.fixture
def offline_loop_backend(offline_loop_app, monkeypatch):
    app = offline_loop_app
    state = SimpleNamespace(
        now=0.0, held=False, sends=[], reads=[], rounds=0,
        delay=0, never=False, fail_set=False, wrong_loop=None,
        silent=False, previous=(100.0, 32.0, 0), target=(25872.0, 128.0, 1),
    )

    class TransactionLock:
        def __enter__(self):
            assert not state.held
            state.held = True
        def __exit__(self, *args):
            state.held = False

    def sleep(seconds):
        assert 0 < seconds <= 0.05
        state.now += seconds

    def send(address, value):
        assert state.held
        state.sends.append((address, value))
        return not (state.fail_set and len(state.sends) == 2)

    def query(address, *, timeout, context):
        assert state.held
        assert context == {"purpose": "show-audio-offline-export"}
        state.reads.append((address, timeout))
        # Lectures initiales, puis confirmation de la cible, puis rollback.
        writes = len(state.sends)
        rollback = writes >= (5 if state.fail_set else 6)
        if not writes or rollback:
            values = state.previous
        else:
            if address.endswith("/loop_start"):
                state.rounds += 1
            if state.silent:
                state.now += timeout
                return None
            values = state.previous if state.never or state.rounds <= state.delay else state.target
            if state.wrong_loop is not None:
                values = (*values[:2], state.wrong_loop)
        field = address.rsplit("/", 1)[-1]
        return (values[("loop_start", "loop_length", "loop").index(field)],)

    monkeypatch.setattr(app, "transport_command_lock", TransactionLock())
    monkeypatch.setattr(app, "time", SimpleNamespace(monotonic=lambda: state.now, sleep=sleep))
    monkeypatch.setattr(app, "ableton_transport", SimpleNamespace(
        query=query, send=send, diagnostics=lambda: {"last_error": "set refusé"},
    ))
    state.post = lambda action="prepare", loop=True: app.app.test_client().post(
        "/show-audio/offline/live-loop", json={
            "action": action, "loop_start": 25872.0, "loop_length": 128.0, "loop": loop,
        })
    return state


def assert_offline_rollback(state):
    assert state.sends[-3:] == [
        ("/live/song/set/loop_start", 100.0),
        ("/live/song/set/loop_length", 32.0),
        ("/live/song/set/loop", 0),
    ]


@pytest.mark.parametrize("delay", [0, 2])
def test_show_audio_loop_prepare_confirms_actual_values(offline_loop_backend, delay):
    state = offline_loop_backend
    state.delay = delay
    response = state.post()
    assert response.status_code == 200
    assert response.json["ok"] is True
    assert response.json["previous"] == {"loop_start": 100.0, "loop_length": 32.0, "loop": False}
    assert response.json["target"] == {"loop_start": 25872.0, "loop_length": 128.0, "loop": True}
    assert response.json["confirmed"] == response.json["target"]
    assert len(state.sends) == 3
    assert state.rounds == delay + 1
    assert len(state.reads) == 3 + 3 * (delay + 1)
    assert state.now <= 2
    assert not state.held


@pytest.mark.parametrize("silent", [False, True])
def test_show_audio_loop_unconfirmed_rolls_back_with_503(offline_loop_backend, silent):
    state = offline_loop_backend
    state.never, state.silent = True, silent
    response = state.post()
    assert response.status_code == 503
    assert response.json["ok"] is False
    assert "Ableton n'a pas appliqué la boucle offline demandée" in response.json["message"]
    assert_offline_rollback(state)
    assert state.now <= 2.000001
    assert all(timeout <= 0.2 for _, timeout in state.reads[3:])


def test_show_audio_loop_partial_set_failure_rolls_back(offline_loop_backend):
    state = offline_loop_backend
    state.fail_set = True
    response = state.post()
    assert response.status_code == 503
    assert "écriture AbletonOSC impossible" in response.json["message"]
    assert len(state.sends) == 5
    assert_offline_rollback(state)


@pytest.mark.parametrize("actual, requested, success", [
    (1, True, True), (0, False, True), (True, True, True), (False, False, True),
    (0, True, False), (1, False, False), (2, True, False), ("false", True, False),
])
def test_show_audio_loop_boolean_confirmation(offline_loop_backend, actual, requested, success):
    state = offline_loop_backend
    state.wrong_loop = actual
    response = state.post(loop=requested)
    assert response.status_code == (200 if success else 503)
    if not success:
        assert_offline_rollback(state)


@pytest.mark.parametrize("never", [False, True])
def test_show_audio_loop_restore_is_also_confirmed(offline_loop_backend, never):
    state = offline_loop_backend
    state.never = never
    response = state.post(action="restore")
    assert response.status_code == (503 if never else 200)
    assert response.json["ok"] is (not never)
    assert len(state.sends) == 3


@pytest.mark.parametrize("field", [0, 1])
@pytest.mark.parametrize("delta, success", [(0.0000001, True), (0.001, False)])
def test_show_audio_loop_float_confirmation_tolerance(offline_loop_backend, field, delta, success):
    state = offline_loop_backend
    target = list(state.target)
    target[field] += delta
    state.target = tuple(target)
    response = state.post()
    assert response.status_code == (200 if success else 503)
    if not success:
        assert_offline_rollback(state)
