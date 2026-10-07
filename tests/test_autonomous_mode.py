"""Autonomous release changes presentation without changing remote commands."""
import pytest

@pytest.mark.parametrize('route', ['/', '/ab', '/arrangement'])
def test_autonomous_remote_hides_console_and_ltc_panels(monkeypatch, route):
    import app
    monkeypatch.setattr(app, 'AUTONOMOUS_MODE', True)
    response = app.app.test_client().get(route)
    assert response.status_code == 200
    assert '[id$=Devices]{display:none!important}' in response.text
    assert 'remote-auth.js' in response.text
    assert '/static/remote-v2.js' in response.text


def test_complete_remote_keeps_console_panels(monkeypatch):
    import app
    monkeypatch.setattr(app, 'AUTONOMOUS_MODE', False)
    response = app.app.test_client().get('/')
    assert '[id$=Devices]{display:none!important}' not in response.text


def test_autonomous_launcher_keeps_remote_arming(monkeypatch):
    import launcher_control
    monkeypatch.setattr(launcher_control, 'AUTONOMOUS_MODE', True)
    response = launcher_control.app.test_client().get('/')
    assert 'CL AUDIO SHOW CONTROL · AUTONOME' in response.text
    assert '#backupCard,.console-card' in response.text
    assert 'id="remoteArm"' in response.text
    assert 'id="remoteDisarm"' in response.text
