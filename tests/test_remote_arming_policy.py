"""Pairing, role and persisted command arming remain separate gates."""
import json
import pytest
from remote_security import RemoteSecurity, SecurityError, device_permissions
from tests.test_permanent_devices import security, pair, signed, PASSWORD
from flask import Flask, jsonify
from security_http import attach_security


@pytest.mark.parametrize('role', ['admin', 'operator'])
def test_approved_command_device_armed_by_default_and_on_restart(security, tmp_path, role):
    manager, now = security
    device = pair(manager, role=role)
    assert manager.armed
    assert signed(manager, device)['role'] == role
    restored = RemoteSecurity(tmp_path, clock=lambda: now[0])
    assert signed(restored, device, nonce='newnonce12345678')['role'] == role
    assert restored.snapshot()['devices'][0]['armed']


def test_explicit_disarm_persists_and_new_approval_does_not_override(security, tmp_path):
    manager, now = security
    device = pair(manager)
    manager.set_armed(False)
    other = pair(manager, role='admin')
    assert not manager.armed
    restored = RemoteSecurity(tmp_path, clock=lambda: now[0])
    for item in (device, other):
        with pytest.raises(SecurityError, match='désarmées'):
            signed(restored, item)
    restored.set_armed(True)
    assert RemoteSecurity(tmp_path, clock=lambda: now[0]).snapshot()['armed']


def test_show_rearms_known_devices_without_changing_roles_or_grants(security, tmp_path):
    manager, now = security
    operator = pair(manager)
    reader = pair(manager, role='reader')
    before = json.loads((tmp_path/'security.json').read_text())['devices']
    manager.set_armed(False)
    manager.set_mode('development')
    manager.set_mode('show')
    assert manager.armed and manager.mode == 'show'
    assert json.loads((tmp_path/'security.json').read_text())['devices'] == before
    assert signed(manager, operator)['role'] == 'operator'
    assert signed(manager, reader, permission='read', critical=True)['role'] == 'reader'
    manager.set_armed(False)
    assert signed(manager, reader, nonce='readerread1234567', permission='read')['role'] == 'reader'
    assert not manager.snapshot()['devices'][1]['armed']


def test_reader_cannot_trigger_commands_even_with_stored_grants(security):
    manager, _ = security
    reader = pair(manager, role='reader')
    manager.change_permissions(reader['device_id'], {'go':True,'edit_cues':True,'edit_notes':True}, ['FOH'])
    manager.set_armed(True)
    assert not any(device_permissions(manager.devices[reader['device_id']]).values())
    for permission in ('go','show','admin','edit_cues','edit_notes'):
        with pytest.raises(SecurityError, match='Permission'):
            signed(manager, reader, permission=permission)


def test_role_change_and_legacy_migration_preserve_identity(security, tmp_path):
    manager, now = security
    device = pair(manager)
    path = tmp_path/'security.json'
    record = json.loads(path.read_text()); record.pop('remote_armed')
    path.write_text(json.dumps(record))
    restored = RemoteSecurity(tmp_path, clock=lambda: now[0])
    assert restored.snapshot()['armed']  # Previous versions had no durable arming choice.
    assert restored.devices[device['device_id']]['key'] == record['devices'][device['device_id']]['key']
    restored.change_role(device['device_id'], 'reader')
    assert not restored.armed
    again = RemoteSecurity(tmp_path, clock=lambda: now[0])
    assert signed(again, device, permission='read')['role'] == 'reader'
    with pytest.raises(SecurityError): signed(again, device, permission='go')
    again.change_role(device['device_id'], 'admin')
    assert again.armed
    assert signed(again, device, nonce='upgraded123456789')['role'] == 'admin'


def test_unknown_and_pending_device_remain_blocked_in_show(security):
    manager, _ = security
    manager.set_mode('show')
    manager.request_pair(manager.new_code('operator'), 'pending iPhone')
    with pytest.raises(SecurityError, match='inconnu'):
        manager.authorize('unknown','','POST','/action',b'{}',str(manager.clock()),'unknownnonce1234','show')


def test_http_approval_role_override_and_toggle_preserve_local_admin_gate(tmp_path):
    app = Flask(__name__)
    manager = attach_security(app, directory=tmp_path)
    manager.set_password(PASSWORD)
    client = app.test_client()
    pending = manager.request_pair(manager.new_code('operator'), 'iPhone')
    assert client.post('/security/admin/arm', json={'armed':True}).status_code == 403
    client.post('/security/admin/unlock', json={'password':PASSWORD,'duration':'session'})
    assert client.post('/security/admin/approve', json={'request_id':pending['request_id'],
        'authorization_type':'permanent','role':'reader'}).status_code == 200
    device = manager.claim(pending['request_id'], pending['claim'])
    assert device['role'] == 'reader'
    for value in (True, False, True):
        assert client.post('/security/admin/arm', json={'armed':value}).status_code == 200
        assert client.get('/security/status').json['armed'] is value
    for operation in ('arm','role','approve','mode'):
        assert client.post('/security/admin/'+operation,json={},environ_base={'REMOTE_ADDR':'192.168.1.4'}).status_code == 403
    manager.set_armed(False)
    assert client.post('/security/admin/mode',json={'mode':'show'}).status_code == 200
    assert manager.armed
    assert client.post('/security/admin/arm',json={'armed':False}).status_code == 403 # show revokes unlock


def test_reader_showcue_read_is_available_when_disarmed(tmp_path):
    app = Flask(__name__)
    manager = attach_security(app, directory=tmp_path)
    manager.set_password(PASSWORD)
    reader = pair(manager, role='reader')
    manager.set_armed(False)
    app.add_url_rule('/show-info', endpoint='read_show', view_func=lambda: jsonify(read=True))
    app.add_url_rule('/show-info/cues', endpoint='read_cues', view_func=lambda: jsonify(cues=[]))
    app.add_url_rule('/action', endpoint='action', view_func=lambda: jsonify(ok=True), methods=['POST'])
    client = app.test_client()
    for path in ('/show-info','/show-info/cues'):
        assert client.get(path, environ_base={'REMOTE_ADDR':'192.168.1.4'}).status_code == 200
    assert signed(manager, reader, permission='read')['role'] == 'reader'
    assert client.post('/action',json={'action':'stop'},environ_base={'REMOTE_ADDR':'192.168.1.4'}).status_code == 403


def test_admin_settings_accept_session_unlock_and_keep_existing_gates(tmp_path):
    import hashlib
    import hmac
    from remote_security import canonical_request
    app = Flask(__name__)
    manager = attach_security(app, directory=tmp_path)
    manager.set_password(PASSWORD)
    device = pair(manager, role='admin')
    manager.unlock(PASSWORD, duration='session')
    manager.set_mode('development')
    app.add_url_rule('/network-config', endpoint='settings', methods=['POST'], view_func=lambda: jsonify(ok=True))
    body = b'{}'; stamp = str(manager.clock()); nonce = 'adminsettings1234'
    signature = hmac.new(hashlib.sha256(device['token'].encode()).digest(),
        canonical_request('POST','/network-config',body,stamp,nonce),hashlib.sha256).hexdigest()
    headers = {'Content-Type':'application/json','X-CL-Device':device['device_id'],
        'X-CL-Signature':signature,'X-CL-Timestamp':stamp,'X-CL-Nonce':nonce}
    response = app.test_client().post('/network-config',data=body,headers=headers,
        base_url='https://server.local',environ_base={'REMOTE_ADDR':'192.168.1.4'})
    assert response.status_code == 200
    manager.set_mode('show')
    assert app.test_client().post('/network-config',data=body,headers=headers,
        base_url='https://server.local',environ_base={'REMOTE_ADDR':'192.168.1.4'}).status_code == 403


@pytest.mark.parametrize('role', ['unknown', [], {}])
def test_invalid_approval_role_preserves_pending_request(security, role):
    manager, _ = security
    pending = manager.request_pair(manager.new_code('operator'), 'iPhone')
    with pytest.raises(SecurityError, match='Rôle inconnu'):
        manager.approve(pending['request_id'], role=role)
    assert not manager.devices and not manager.pending[pending['request_id']]['approved']
