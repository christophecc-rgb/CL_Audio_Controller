"""Real HTTP gates and the launcher/backend split, without production transports."""
import hashlib
import hmac
import json
import secrets
from io import BytesIO
from urllib.parse import urlsplit
from unittest.mock import Mock
import pytest
from flask import Flask, jsonify
from security_http import attach_security
from remote_security import canonical_request
from tests.test_permanent_devices import pair, PASSWORD
from tests.test_launcher_remote_arm import setup_proxy


def backend(directory):
    app = Flask('boundary_backend'); manager = attach_security(app, directory=directory)
    manager.set_password(PASSWORD)
    executed = []
    @app.route('/action', methods=['POST'])
    def action():
        from flask import request
        executed.append(request.json['action']); return jsonify(ok=True)
    @app.route('/show-info')
    def read(): return jsonify(read=True)
    return app, manager, executed


def command(client, device=None, action='go', **extra):
    body = json.dumps({'action':action}).encode(); stamp = str(__import__('time').time()); nonce = secrets.token_hex(16)
    headers = {'Content-Type':'application/json', **extra}
    if device:
        sig=hmac.new(hashlib.sha256(device['token'].encode()).digest(),
            canonical_request('POST','/action',body,stamp,nonce),hashlib.sha256).hexdigest()
        headers.update({'X-CL-Device':device['device_id'],'X-CL-Timestamp':stamp,'X-CL-Nonce':nonce,'X-CL-Signature':sig})
    return client.post('/action', data=body, headers=headers, base_url='https://mac.local:8443',
                       environ_base={'REMOTE_ADDR':'192.168.1.20'})


def test_launcher_disarming_targets_the_actual_command_server(tmp_path, monkeypatch):
    app, manager, executed = backend(tmp_path)
    device = pair(manager, role='admin'); remote = app.test_client()
    launcher_app, _, _ = setup_proxy()
    launcher = attach_security(launcher_app, launcher=True, directory=tmp_path)
    local = launcher_app.test_client()
    local.post('/security/admin/unlock', json={'password':PASSWORD})
    backend_token = manager.unlock(PASSWORD)
    local.set_cookie('cl_admin_backend', backend_token)
    backend_client = app.test_client()
    def upstream(req, **kwargs):
        cookie=req.get_header('Cookie','')
        if cookie.startswith('cl_admin_backend='):
            backend_client.set_cookie('cl_admin_backend', cookie.split('=',1)[1])
        result=backend_client.open(urlsplit(req.full_url).path,method=req.method,data=req.data,headers={'Content-Type':'application/json'})
        response=BytesIO(result.data); response.status=result.status_code; response.headers=result.headers
        return response
    monkeypatch.setattr('urllib.request.build_opener', Mock(return_value=Mock(open=upstream)))
    assert command(remote, device).status_code == 200
    result = local.post('/security/admin/arm', json={'armed':False})
    assert result.status_code == 200
    assert not manager.armed  # Regression: used to modify only launcher-security.json.
    assert command(remote, device).status_code == 403
    assert executed == ['go']
    assert local.post('/security/admin/arm', json={'armed':True}).status_code == 200
    assert command(remote, device).status_code == 200


def test_locked_registry_never_claims_zero_devices(tmp_path):
    app, manager, _ = backend(tmp_path)
    pair(manager)
    state = app.test_client().get('/security/status').json
    assert not state['unlocked'] and 'devices' not in state
    assert state['device_count'] == 1 and not state['devices_visible']


@pytest.mark.parametrize('role',['admin','operator','reader'])
@pytest.mark.parametrize('action',['go','stop','next','prev','pause','arrangement_toggle','arrangement_start','arrangement_play_marker','arrangement_prev','arrangement_next','back_to_arrangement','goto','xfade','xfade_value'])
def test_all_remote_actions_obey_role_and_live_arming(tmp_path, role, action):
    app, manager, executed = backend(tmp_path); device = pair(manager, role=role); client = app.test_client()
    manager.set_armed(True)
    assert command(client, device, action).status_code == (403 if role=='reader' else 200)
    manager.set_armed(False)
    assert command(client, device, action).status_code == 403
    assert client.get('/show-info',base_url='https://mac.local:8443',environ_base={'REMOTE_ADDR':'192.168.1.20'}).status_code == 200
    manager.set_armed(True)
    assert command(client, device, action).status_code == (403 if role=='reader' else 200)
    assert executed == ([] if role=='reader' else [action,action])


def test_legacy_cookies_tokens_and_removed_identity_cannot_command(tmp_path):
    app, manager, executed = backend(tmp_path); client = app.test_client()
    old = pair(manager,role='admin'); admin = manager.unlock(PASSWORD,duration='session')
    manager.devices.clear();manager.save();manager.set_armed(True)
    for name in ('session','token','cl_admin_backend','cl_admin_launcher','cl-paired-device-v1'):
        client.set_cookie(name,admin)
    assert command(client).status_code == 403
    assert command(client,old,Authorization='Bearer '+old['token'],**{'X-CL-Admin':admin}).status_code == 403
    manager.set_armed(False)
    assert command(client,old).status_code == 403
    assert not executed


def test_forwarded_headers_cannot_turn_lan_into_local(tmp_path):
    app, manager, executed = backend(tmp_path)
    assert command(app.test_client(),**{'X-Forwarded-For':'127.0.0.1','X-Forwarded-Host':'localhost','Host':'localhost'}).status_code == 403
    assert not executed


def test_launcher_panel_routes_to_backend_and_keeps_local_maintenance(tmp_path):
    app = Flask('launcher_pages'); attach_security(app, launcher=True, directory=tmp_path)
    client = app.test_client()
    response = client.get('/security/panel')
    assert response.status_code == 302
    assert response.headers['Location'] == 'http://127.0.0.1:5050/security/panel'
    assert client.get('/security/maintenance').status_code == 200
    assert client.get('/security/panel', environ_base={'REMOTE_ADDR':'192.168.1.20'}).status_code == 403


def test_launcher_without_backend_cannot_report_successful_disarming(tmp_path):
    app = Flask('launcher_missing_backend'); manager = attach_security(app, launcher=True, directory=tmp_path)
    manager.set_password(PASSWORD);manager.set_armed(True)
    client = app.test_client();client.post('/security/admin/unlock',json={'password':PASSWORD})
    assert client.post('/security/admin/arm',json={'armed':False}).status_code == 503
    assert manager.armed
    for operation in ('approve','role','permissions','revoke'):
        assert client.post('/security/admin/'+operation,json={}).status_code == 409


def test_local_launcher_unlock_is_not_backend_command_authority(tmp_path):
    app, manager, executed = backend(tmp_path); device = pair(manager)
    launcher_app = Flask('launcher_cookie');launcher = attach_security(launcher_app,launcher=True,directory=tmp_path)
    local_token = launcher.unlock(PASSWORD)
    client = app.test_client();client.set_cookie('cl_admin_launcher',local_token)
    manager.set_armed(False)
    assert command(client,device,**{'X-CL-Admin':local_token}).status_code == 403
    assert not executed


def test_live_role_change_and_revocation_invalidate_open_remote(tmp_path):
    app, manager, executed = backend(tmp_path);device = pair(manager,role='admin');client=app.test_client()
    assert command(client,device).status_code == 200
    manager.change_role(device['device_id'],'reader')
    manager.set_armed(True)
    assert command(client,device).status_code == 403
    manager.change_role(device['device_id'],'operator')
    assert command(client,device).status_code == 200
    manager.revoke(device['device_id'])
    assert command(client,device).status_code == 403
    assert executed == ['go','go']


def test_every_app_mutation_route_rejects_unpaired_remote_before_handler(tmp_path):
    """Build the route inventory from app.py, so a new command route cannot escape."""
    import ast
    from pathlib import Path
    app = Flask('app_route_inventory');manager=attach_security(app,directory=tmp_path)
    manager.set_password(PASSWORD);manager.set_armed(True)
    tree=ast.parse((Path(__file__).resolve().parents[1]/'app.py').read_text())
    executed=[];routes=[]
    def handler(**kwargs):
        executed.append(True);return jsonify(ok=True)
    for function in tree.body:
        if not isinstance(function,ast.FunctionDef):continue
        for decorator in function.decorator_list:
            if not (isinstance(decorator,ast.Call) and isinstance(decorator.func,ast.Attribute)
                    and isinstance(decorator.func.value,ast.Name) and decorator.func.value.id=='app'
                    and decorator.func.attr=='route'):continue
            path=ast.literal_eval(decorator.args[0])
            methods=next((ast.literal_eval(k.value) for k in decorator.keywords if k.arg=='methods'),['GET'])
            guarded=[m for m in methods if m not in ('GET','HEAD','OPTIONS') or path in ('/build-show','/rescan-scenes')]
            if not guarded:continue
            app.add_url_rule(path,endpoint='inventory_'+str(len(routes)),view_func=handler,methods=methods)
            routes.append((path,guarded))
    assert len(routes)>30
    client=app.test_client();client.set_cookie('cl_admin_backend',manager.unlock(PASSWORD))
    import re
    for route,methods in routes:
        concrete=re.sub(r'<[^>]+>','test',route)
        for method in methods:
            result=client.open(concrete,method=method,json={'action':'go'},base_url='https://mac.local:8443',
                environ_base={'REMOTE_ADDR':'192.168.1.20'})
            assert result.status_code==403,(method,route,result.status_code)
    assert not executed
