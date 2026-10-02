import hashlib
import hmac
import json
import pytest
from flask import Flask, jsonify
from remote_security import RemoteSecurity, SecurityError, canonical_request
from security_http import attach_security

PASSWORD='Correct horse battery staple phase2'

@pytest.fixture
def security(tmp_path):
    now=[1790000000.0]
    obj=RemoteSecurity(tmp_path,clock=lambda:now[0]); obj.set_password(PASSWORD,initial=True)
    return obj,now


def device(obj,role='operator'):
    code=obj.new_code(role); pending=obj.request_pair(code,'iPhone','Chris')
    obj.approve(pending['request_id']); result=obj.claim(pending['request_id'],pending['claim'])
    return result


def signed(obj,item,*,nonce='1234567890abcdef',timestamp=None,body=b'{"action":"go"}',permission='show',critical=True,path='/action'):
    stamp=str(timestamp if timestamp is not None else obj.clock())
    key=hashlib.sha256(item['token'].encode()).digest()
    sig=hmac.new(key,canonical_request('POST',path,body,stamp,nonce),hashlib.sha256).hexdigest()
    return obj.authorize(item['device_id'],sig,'POST',path,body,stamp,nonce,permission,critical)


def test_password_hash_salt_permissions_lock_and_development(security,tmp_path):
    obj,now=security
    raw=(tmp_path/'security.json').read_text()
    assert PASSWORD not in raw
    assert json.loads(raw)['password']['algorithm']=='scrypt'
    assert (tmp_path/'security.json').stat().st_mode & 0o777 == 0o600
    with pytest.raises(SecurityError): obj.unlock('wrong')
    token=obj.unlock(PASSWORD); obj.admin(token); obj.set_mode('development'); assert obj.mode=='development'
    obj.lock_admin(); assert obj.mode=='show'
    with pytest.raises(SecurityError): obj.admin(token)
    token=obj.unlock(PASSWORD); now[0]+=301
    with pytest.raises(SecurityError): obj.admin(token)


def test_qr_expiration_single_use_claim_and_server_session_binding(security):
    obj,now=security
    code=obj.new_code('reader'); now[0]+=121
    with pytest.raises(SecurityError): obj.request_pair(code,'x')
    code=obj.new_code('operator'); pending=obj.request_pair(code,'Phone')
    with pytest.raises(SecurityError): obj.request_pair(code,'Other')
    assert obj.claim(pending['request_id'],pending['claim'])=={'pending':True}
    with pytest.raises(SecurityError): obj.claim(pending['request_id'],'other')
    obj.approve(pending['request_id']); item=obj.claim(pending['request_id'],pending['claim']); assert item['token']
    with pytest.raises(SecurityError): obj.claim(pending['request_id'],pending['claim'])
    old=obj.new_code('reader'); obj.session='next-show'
    with pytest.raises(SecurityError): obj.request_pair(old,'x')


@pytest.mark.parametrize('role',['reader','operator','admin'])
def test_roles_arming_revocation_and_replay(security,role):
    obj,now=security; item=device(obj,role)
    signed(obj,item,permission='read',critical=False,path='/remote/heartbeat')
    with pytest.raises(SecurityError): signed(obj,item,nonce='abcdef1234567890')
    obj.set_armed(True)
    if role=='reader':
        with pytest.raises(SecurityError): signed(obj,item,nonce='abcdef1234567890')
    else:
        assert signed(obj,item,nonce='abcdef1234567890')['role']==role
        with pytest.raises(SecurityError): signed(obj,item,nonce='abcdef1234567890')
        with pytest.raises(SecurityError): signed(obj,item,nonce='zbcdef1234567890',timestamp=now[0]-16)
    obj.revoke(item['device_id'])
    with pytest.raises(SecurityError): signed(obj,item,nonce='newnonce12345678',permission='read',critical=False)


def test_expiry_restart_and_body_tamper(security,tmp_path):
    obj,now=security; item=device(obj); obj.set_armed(True)
    stamp=str(now[0]); nonce='abcdefghijklmnop'; raw=b'{"action":"go"}'
    sig=hmac.new(hashlib.sha256(item['token'].encode()).digest(),canonical_request('POST','/action',raw,stamp,nonce),hashlib.sha256).hexdigest()
    with pytest.raises(SecurityError): obj.authorize(item['device_id'],sig,'POST','/action',b'{"action":"stop"}',stamp,nonce,'show')
    with pytest.raises(SecurityError): signed(obj,item,timestamp='nan')
    now[0]+=43201
    with pytest.raises(SecurityError): signed(obj,item)
    fresh=RemoteSecurity(tmp_path,clock=lambda:now[0]); fresh.load(); assert not fresh.armed
    with pytest.raises(SecurityError): signed(fresh,item)


def test_global_revoke_audit_has_no_credentials(security,tmp_path):
    obj,_=security; one=device(obj); two=device(obj,'admin'); obj.set_armed(True); obj.revoke()
    assert not obj.armed and all(d['revoked'] for d in obj.snapshot()['devices'])
    raw=(tmp_path/'commands.jsonl').read_text()
    assert PASSWORD not in raw and one['token'] not in raw and two['token'] not in raw


def test_http_boundary_qr_and_https_claim(tmp_path):
    app=Flask(__name__); obj=attach_security(app,directory=tmp_path)
    @app.route('/action',methods=['POST'])
    def action(): return jsonify(ok=True)
    @app.route('/rescan-scenes',methods=['GET','POST'])
    def rescan(): return jsonify(ok=True)
    @app.route('/status')
    def status(): return jsonify(ok=True)
    client=app.test_client(); local='http://localhost'
    assert client.post('/action',json={'action':'go'},environ_base={'REMOTE_ADDR':'192.0.2.1'}).status_code==403
    assert client.get('/status',environ_base={'REMOTE_ADDR':'192.0.2.1'}).status_code==200
    assert client.post('/action',json={'action':'go'},base_url=local).status_code==200
    assert client.post('/action',json={'action':'go'},base_url=local,headers={'Origin':'https://evil.example'}).status_code==403
    assert client.get('/rescan-scenes',environ_base={'REMOTE_ADDR':'192.0.2.1'}).status_code==403
    assert client.post('/security/admin/setup',json={'password':PASSWORD},base_url=local).status_code==200
    assert client.post('/security/admin/unlock',json={'password':PASSWORD},base_url=local).status_code==200
    assert client.post('/security/admin/qr',json={'role':'admin','server_url':'https://server.local:8443'},base_url=local).status_code==403
    assert client.post('/security/admin/mode',json={'mode':'development'},base_url=local).status_code==200
    qr=client.post('/security/admin/qr',json={'role':'operator','server_url':'https://server.local:8443'},base_url=local)
    assert qr.status_code==200 and '<svg' in qr.json['svg'] and PASSWORD not in qr.json['url']
    code=qr.json['url'].split('#code=')[1]
    assert client.post('/remote/pair/request',json={'code':code},base_url='http://server.local',environ_base={'REMOTE_ADDR':'192.0.2.1'}).status_code==403
    result=client.post('/remote/pair/request',json={'code':code,'name':'Phone'},base_url='https://server.local',environ_base={'REMOTE_ADDR':'192.0.2.1'})
    assert result.status_code==200
    assert client.post('/security/admin/approve',json=result.json,base_url=local).status_code==200
    claimed=client.post('/remote/pair/claim',json=result.json,base_url='https://server.local',environ_base={'REMOTE_ADDR':'192.0.2.1'})
    item=claimed.json; assert item['token']
    assert client.post('/security/admin/arm',json={'armed':True},base_url=local).status_code==200
    raw=b'{"action":"go","scene":31}';stamp=str(obj.clock());nonce='1234567890abcdef'
    sig=hmac.new(hashlib.sha256(item['token'].encode()).digest(),canonical_request('POST','/action',raw,stamp,nonce),hashlib.sha256).hexdigest()
    headers={'X-CL-Device':item['device_id'],'X-CL-Timestamp':stamp,'X-CL-Nonce':nonce,'X-CL-Signature':sig,'Content-Type':'application/json'}
    assert client.post('/action',data=raw,headers=headers,base_url='https://server.local',environ_base={'REMOTE_ADDR':'192.0.2.1'}).status_code==200
    assert client.post('/action',data=raw,headers=headers,base_url='https://server.local',environ_base={'REMOTE_ADDR':'192.0.2.1'}).status_code==403


def test_shared_password_reset_locks_both_processes(security,tmp_path):
    obj,_=security; other=RemoteSecurity(tmp_path,namespace='launcher');other.load()
    token=other.unlock(PASSWORD);other.set_mode('development');other.set_armed(True)
    assert other.password_record==obj.password_record
    obj.set_password('New local reset password phase2')
    with pytest.raises(SecurityError): other.admin(token)
    assert not other.armed and other.mode=='show'
    with pytest.raises(SecurityError): other.set_password(PASSWORD,initial=True)
    other.unlock('New local reset password phase2')


def test_admin_device_settings_need_local_unlock_and_show_mode_lock(tmp_path):
    app=Flask(__name__);obj=attach_security(app,directory=tmp_path)
    @app.route('/network-config',methods=['POST'])
    def config():return jsonify(ok=True)
    obj.set_password(PASSWORD);item=device(obj,'admin');obj.set_armed(True)
    client=app.test_client()
    def command(nonce):
        body=b'{}';stamp=str(obj.clock());signature=hmac.new(hashlib.sha256(item['token'].encode()).digest(),canonical_request('POST','/network-config',body,stamp,nonce),hashlib.sha256).hexdigest()
        return client.post('/network-config',data=body,content_type='application/json',headers={'X-CL-Device':item['device_id'],'X-CL-Timestamp':stamp,'X-CL-Nonce':nonce,'X-CL-Signature':signature},base_url='https://server.local',environ_base={'REMOTE_ADDR':'192.0.2.10'})
    assert command('1234567890abcdef').status_code==403
    obj.set_mode('development');assert command('abcdefghijklmnop').status_code==403
    obj.unlock(PASSWORD);assert command('1122334455667788').status_code==200
    obj.lock_admin();assert command('8877665544332211').status_code==403


def test_first_security_log_does_not_break_target_config_permissions(tmp_path):
    root=tmp_path/'Library/Application Support/CL Audio Controller'
    obj=RemoteSecurity(root/'Security')
    obj.audit('go','refused','missing-device')
    assert root.stat().st_mode & 0o777 == 0o700
    obj.set_password(PASSWORD)
    assert root.stat().st_mode & 0o777 == 0o700


def test_tls_configuration_requires_local_unlock_and_restart(tmp_path,monkeypatch):
    import ssl
    app=Flask(__name__);manager=attach_security(app,directory=tmp_path/'Security')
    client=app.test_client();cert=tmp_path/'cert.pem';key=tmp_path/'key.pem';cert.write_text('fixture');key.write_text('fixture');key.chmod(0o600)
    payload={'certificate':str(cert),'private_key':str(key),'port':8443,'server_url':'https://server.local:8443'}
    assert client.post('/security/admin/tls',json=payload).status_code==403
    manager.set_password(PASSWORD);client.post('/security/admin/unlock',json={'password':PASSWORD});client.post('/security/admin/mode',json={'mode':'development'})
    monkeypatch.setattr(ssl.SSLContext,'load_cert_chain',lambda *args:None)
    response=client.post('/security/admin/tls',json=payload)
    assert response.status_code==200 and response.json['restart_required']
    assert json.loads((manager.directory/'remote-tls.json').read_text())['port']==8443
    assert (manager.directory/'remote-tls.json').stat().st_mode&0o777==0o600
    payload['port']=5050
    assert client.post('/security/admin/tls',json=payload).status_code==403
