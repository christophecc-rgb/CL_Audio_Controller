"""Connection confirmation through the FULL host, with no Live or sockets."""
from unittest.mock import Mock

import pytest

from test_live_set_generation import load_app_module


@pytest.fixture
def host(monkeypatch):
    app = load_app_module()
    monkeypatch.setattr(app, 'write_bootstrap_diagnostic', Mock())
    monkeypatch.setattr(app, '_bootstrap_transaction', None)
    monkeypatch.setattr(app, '_bootstrap_generation', None)
    monkeypatch.setattr(app, 'schedule_selected_scene_duration_refresh', Mock())
    monkeypatch.setattr(app, 'start_live_set_bootstrap', Mock())
    monkeypatch.setattr(app, 'state', dict(app.state, connected=True,
        set_generation=7, set_ready=True, current_set_id='/Sets/show.als',
        current_set_name='Show', scenes={0: 'Played', 1: 'Prepared'},
        selected_scene=1, playing_scene=0, next_scene=1,
        has_show_started=True, is_playing=False))
    return app


@pytest.mark.parametrize('responses', [
    [None, ('Show',), ('/Sets/show.als',)],
    [None, ('Show',), ('',)],
    [('/Sets/show.als',), ('Show',), None],
    [('/Sets/show.als',), ('Show',), ('/Sets/other.als',)],
])
def test_unconfirmed_identity_clears_connection_without_changing_scene_state(host, monkeypatch, responses):
    before = {k: host.state[k] for k in ('set_generation', 'selected_scene',
                                       'playing_scene', 'next_scene', 'scenes')}
    monkeypatch.setattr(host, 'query', Mock(side_effect=responses))
    assert host.refresh_names_and_transport() is False
    assert host.state['connected'] is False
    assert host.state['message'] == 'AbletonOSC indisponible'
    assert {k: host.state[k] for k in before} == before
    assert host.app.test_client().get('/status').json['connected'] is False
    host.start_live_set_bootstrap.assert_not_called()


def test_old_identity_failure_does_not_disconnect_new_generation(host, monkeypatch):
    def reply(*args, **kwargs):
        host.state.update(set_generation=8, connected=True)
        return None
    monkeypatch.setattr(host, 'query', Mock(side_effect=reply))
    assert host.refresh_names_and_transport() is False
    assert host.state['connected'] is True
    assert host.state['set_generation'] == 8


def test_transport_timeout_cannot_report_a_successful_refresh(host, monkeypatch):
    monkeypatch.setattr(host, 'query', Mock(side_effect=lambda address, *args, **kwargs:
        None if address == '/live/song/get/is_playing' else
        ('/Sets/show.als',) if address.endswith('/file_path') else
        ('Show',) if address.endswith('/name') else (1,)))
    assert host.refresh_names_and_transport() is False
    assert host.state['connected'] is False


def test_identity_timeout_then_reconnection_keeps_prepared_scene(host, monkeypatch):
    replies = iter([('/Sets/show.als',), ('Show',), None])
    monkeypatch.setattr(host, 'query', Mock(side_effect=lambda *args, **kwargs: next(replies)))
    assert host.refresh_names_and_transport() is False
    assert host.state['connected'] is False
    monkeypatch.setattr(host, 'query', Mock(side_effect=lambda address, *args, **kwargs:
        ('/Sets/show.als',) if address.endswith('/file_path') else
        ('Show',) if address.endswith('/name') else (0,)))
    assert host.refresh_names_and_transport() is True
    assert host.state['connected'] is True
    assert host.state['set_generation'] == 7
    assert host.state['selected_scene'] == host.state['next_scene'] == 1
    assert host.state['playing_scene'] == 0


@pytest.mark.parametrize('late_transport_timeout', [True, False])
def test_late_reply_cannot_overwrite_new_generation_connection(host, monkeypatch, late_transport_timeout):
    def reply(address, *args, **kwargs):
        if address == '/live/song/get/is_playing' and late_transport_timeout:
            host.state.update(set_generation=8, connected=True)
            return None
        if address == '/live/scene/get/name' and not late_transport_timeout:
            host.state.update(set_generation=8, connected=False)
        return (('/Sets/show.als',) if address.endswith('/file_path') else
                ('Show',) if address.endswith('/name') else (0,))
    monkeypatch.setattr(host, 'query', Mock(side_effect=reply))
    assert host.refresh_names_and_transport() is False
    assert host.state['set_generation'] == 8
    assert host.state['connected'] is late_transport_timeout
