import json
import pytest
from flask import Flask
from remote_security import RemoteSecurity, SecurityError
from security_http import attach_security

PASSWORD = 'Admin session test password safe'


def test_unlock_durations_restart_lock_and_password(tmp_path):
    now = [1000.0]
    manager = RemoteSecurity(tmp_path, clock=lambda: now[0])
    manager.set_password(PASSWORD)
    password = (tmp_path/'admin-password.json').read_bytes()
    with pytest.raises(SecurityError):
        manager.unlock('wrong', duration='session')
    timed = manager.unlock(PASSWORD)
    assert manager.admin_status(timed) == {'mode': 'five_minutes', 'remaining_seconds': 300}
    now[0] += 299
    manager.admin(timed)
    now[0] += 1
    with pytest.raises(SecurityError): manager.admin(timed)
    token = manager.unlock(PASSWORD, duration='session')
    now[0] += 86400
    manager.admin(token)
    assert manager.admin_status(token) == {'mode': 'session', 'remaining_seconds': None}
    assert not manager.armed
    restarted = RemoteSecurity(tmp_path, clock=lambda: now[0])
    with pytest.raises(SecurityError): restarted.admin(token)
    manager.lock_admin()
    with pytest.raises(SecurityError): manager.admin(token)
    assert not manager.armed
    assert (tmp_path/'admin-password.json').read_bytes() == password
    assert 'admin_sessions' not in json.loads((tmp_path/'security.json').read_text())


def test_session_cookie_and_http_admin_boundaries(tmp_path):
    app = Flask(__name__)
    manager = attach_security(app, directory=tmp_path)
    manager.set_password(PASSWORD)
    client = app.test_client()
    assert client.post('/security/admin/unlock', json={'password':'wrong','duration':'session'}).status_code == 403
    for headers in ({'Host':'evil.local'}, {'Origin':'https://evil.local'}, {'Sec-Fetch-Site':'cross-site'}):
        assert client.post('/security/admin/unlock', json={'password':PASSWORD,'duration':'session'},headers=headers).status_code == 403
    timed = client.post('/security/admin/unlock', json={'password':PASSWORD})
    assert 'Max-Age=300' in timed.headers['Set-Cookie']
    result = client.post('/security/admin/unlock', json={'password':PASSWORD,'duration':'session'})
    assert result.status_code == 200
    cookie = result.headers['Set-Cookie']
    assert 'Max-Age' not in cookie and 'Expires' not in cookie
    assert 'HttpOnly' in cookie and 'SameSite=Strict' in cookie
    status = client.get('/security/status').json
    assert status['admin_unlock']['mode'] == 'session' and not status['armed']
    assert client.post('/security/admin/lock',json={}).status_code == 200
    assert client.get('/security/status').json['admin_unlock']['mode'] == 'locked'
    assert client.post('/security/admin/mode',json={'mode':'development'}).status_code == 403
