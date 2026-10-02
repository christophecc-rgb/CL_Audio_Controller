"""Permanent grants must persist without weakening temporary sessions or GO gates."""
import hashlib
import hmac
import json
from pathlib import Path
import pytest
from flask import Flask,jsonify
from remote_security import RemoteSecurity,SecurityError,canonical_request
from security_http import attach_security

PASSWORD='Permanent devices local test password'

@pytest.fixture
def security(tmp_path):
    now=[1790000000.0]
    manager=RemoteSecurity(tmp_path,clock=lambda:now[0]);manager.set_password(PASSWORD)
    return manager,now


def pair(manager,kind='permanent',role='operator',lifetime=43200):
    code=manager.new_code(role);pending=manager.request_pair(code,'iPhone Christophe','Christophe')
    manager.approve(pending['request_id'],lifetime,kind)
    return manager.claim(pending['request_id'],pending['claim'])


def signed(manager,device,nonce='0123456789abcdef',permission='show',critical=True,timestamp=None,path='/action'):
    stamp=str(manager.clock() if timestamp is None else timestamp);body=b'{"action":"go","scene":31}'
    signature=hmac.new(hashlib.sha256(device['token'].encode()).digest(),canonical_request('POST',path,body,stamp,nonce),hashlib.sha256).hexdigest()
    return manager.authorize(device['device_id'],signature,'POST',path,body,stamp,nonce,permission,critical)


def test_default_temporary_and_custom_duration(security):
    manager,now=security
    default=pair(manager,'temporary');custom=pair(manager,'temporary',lifetime=60)
    assert default['expires']==now[0]+43200 and default['authorization_type']=='temporary'
    assert custom['expires']==now[0]+60
    manager.set_armed(True);now[0]+=61
    with pytest.raises(SecurityError,match='expirée'):signed(manager,custom)
    assert signed(manager,default)['name']=='iPhone Christophe'


@pytest.mark.parametrize('lifetime',[None,59,86401,float('nan'),'invalid'])
def test_invalid_temporary_duration_stays_rejected(security,lifetime):
    manager,_=security
    with pytest.raises(SecurityError):pair(manager,'temporary',lifetime=lifetime)


def test_permanent_no_expiry_and_runtime_session_change(security):
    manager,now=security;device=pair(manager)
    assert device['expires'] is None and device['authorization_type']=='permanent'
    assert device['name']=='iPhone Christophe' and device['operator']=='Christophe'
    manager.set_armed(True);now[0]+=86400*365;manager.session='another-runtime'
    assert signed(manager,device)['role']=='operator'
    assert manager.snapshot()['devices'][0]['active']


def test_restart_recognizes_same_device_without_pairing_but_starts_disarmed(security,tmp_path):
    manager,now=security;device=pair(manager);manager.set_armed(True)
    signed(manager,device)
    restarted=RemoteSecurity(tmp_path,clock=lambda:now[0]);snapshot=restarted.snapshot()
    assert restarted.server==manager.server and restarted.session!=manager.session
    assert snapshot['devices'][0]['id']==device['device_id'] and snapshot['devices'][0]['active']
    assert not snapshot['devices'][0]['connected'] and snapshot['devices'][0]['last_seen']==now[0]
    with pytest.raises(SecurityError,match='désarmées'):signed(restarted,device,nonce='abcdefghijklmnop')
    assert signed(restarted,device,nonce='ponmlkjihgfedcba',permission='read',critical=False)['id']==device['device_id']
    restarted.set_armed(True);assert signed(restarted,device,nonce='abcdefgh12345678')['role']=='operator'


def test_nonce_survives_restart_and_stale_timestamp_stays_rejected(security,tmp_path):
    manager,now=security;device=pair(manager);manager.set_armed(True);signed(manager,device)
    restarted=RemoteSecurity(tmp_path,clock=lambda:now[0]);restarted.load();restarted.set_armed(True)
    with pytest.raises(SecurityError,match='déjà utilisée'):signed(restarted,device)
    with pytest.raises(SecurityError,match='ancienne'):signed(restarted,device,nonce='anothernonce1234',timestamp=now[0]-16)


@pytest.mark.parametrize('role',['reader','operator','admin'])
def test_permanent_role_and_arm_disarm_are_independent(security,role):
    manager,_=security;device=pair(manager,role=role)
    signed(manager,device,permission='read',critical=False)
    with pytest.raises(SecurityError):signed(manager,device,nonce='abcdefghijklmnop')
    manager.set_armed(True)
    if role=='reader':
        with pytest.raises(SecurityError,match='Permission'):signed(manager,device,nonce='abcdefgh12345678')
    else:assert signed(manager,device,nonce='abcdefgh12345678')['role']==role
    manager.set_armed(False)
    with pytest.raises(SecurityError):signed(manager,device,nonce='abcdefgh87654321')


def test_revocation_and_revoke_all_persist_for_both_types(security,tmp_path):
    manager,now=security;permanent=pair(manager);temporary=pair(manager,'temporary');manager.set_armed(True)
    manager.revoke(permanent['device_id'])
    with pytest.raises(SecurityError,match='révoqué'):signed(manager,permanent)
    assert signed(manager,temporary)['authorization_type']=='temporary'
    second=pair(manager);manager.revoke()
    for item in (permanent,temporary,second):
        with pytest.raises(SecurityError,match='révoqué'):signed(manager,item)
    restarted=RemoteSecurity(tmp_path,clock=lambda:now[0])
    with pytest.raises(SecurityError,match='révoqué'):signed(restarted,second,permission='read',critical=False)


def test_permanent_role_changes_survive_restart(security,tmp_path):
    manager,now=security;device=pair(manager)
    restarted=RemoteSecurity(tmp_path,clock=lambda:now[0]);restarted.change_role(device['device_id'],'reader');restarted.set_armed(True)
    with pytest.raises(SecurityError,match='Permission'):signed(restarted,device)
    again=RemoteSecurity(tmp_path,clock=lambda:now[0]);assert signed(again,device,permission='read',critical=False)['role']=='reader'


def test_old_schema_without_type_is_only_temporary(security,tmp_path):
    manager,now=security;device=pair(manager,'temporary')
    path=tmp_path/'security.json';data=json.loads(path.read_text());data['schema']=1
    del data['devices'][device['device_id']]['authorization_type']
    path.write_text(json.dumps(data));path.chmod(0o600)
    restarted=RemoteSecurity(tmp_path,clock=lambda:now[0]);snap=restarted.snapshot()
    assert snap['devices'][0]['authorization_type']=='temporary' and not snap['devices'][0]['active']
    assert json.loads(path.read_text())['devices'][device['device_id']]['name']=='iPhone Christophe'
    with pytest.raises(SecurityError):signed(restarted,device,permission='read',critical=False)


def test_temporary_still_expires_on_runtime_restart(security,tmp_path):
    manager,now=security;device=pair(manager,'temporary')
    restarted=RemoteSecurity(tmp_path,clock=lambda:now[0]);restarted.load();restarted.set_armed(True)
    with pytest.raises(SecurityError,match='expirée'):signed(restarted,device)


def test_password_reset_revokes_permanents_in_other_instance_and_after_restart(security,tmp_path):
    manager,now=security;device=pair(manager);other=RemoteSecurity(tmp_path,clock=lambda:now[0]);other.load()
    manager.set_password('New permanent devices reset password')
    with pytest.raises(SecurityError,match='révoqué'):signed(other,device,permission='read',critical=False)
    restarted=RemoteSecurity(tmp_path,clock=lambda:now[0])
    with pytest.raises(SecurityError,match='révoqué'):signed(restarted,device,permission='read',critical=False)


def test_private_files_hash_only_and_single_use_qr_claim(security,tmp_path):
    manager,_=security;code=manager.new_code('operator');pending=manager.request_pair(code,'iPhone Christophe','Christophe')
    with pytest.raises(SecurityError):manager.request_pair(code,'other')
    manager.approve(pending['request_id'],authorization_type='permanent');device=manager.claim(pending['request_id'],pending['claim'])
    with pytest.raises(SecurityError):manager.claim(pending['request_id'],pending['claim'])
    manager.set_armed(True);signed(manager,device)
    for path in tmp_path.iterdir():
        if path.is_file():
            raw=path.read_text();assert device['token'] not in raw and PASSWORD not in raw and pending['claim'] not in raw
            assert path.stat().st_mode&0o777==0o600
    assert tmp_path.stat().st_mode&0o777==0o700
    record=json.loads((tmp_path/'security.json').read_text())
    assert record['schema']==2 and record['devices'][device['device_id']]['key']==hashlib.sha256(device['token'].encode()).hexdigest()


def test_http_approve_claim_and_heartbeat_permanent_restart(tmp_path):
    app=Flask(__name__);manager=attach_security(app,directory=tmp_path);manager.set_password(PASSWORD)
    client=app.test_client();client.post('/security/admin/unlock',json={'password':PASSWORD})
    code=manager.new_code('operator')
    pending=client.post('/remote/pair/request',json={'code':code,'name':'iPhone Christophe','operator':'Christophe'},base_url='https://server.local').json
    response=client.post('/security/admin/approve',json={'request_id':pending['request_id'],'authorization_type':'permanent'})
    assert response.status_code==200
    device=client.post('/remote/pair/claim',json=pending,base_url='https://server.local').json
    assert device['authorization_type']=='permanent' and device['expires'] is None
    assert client.post('/remote/pair/claim',json=pending,base_url='https://server.local').status_code==403
    restarted_app=Flask('restart');restarted=attach_security(restarted_app,directory=tmp_path)
    stamp=str(restarted.clock());nonce='abcdefgh12345678';raw=b'{}'
    signature=hmac.new(hashlib.sha256(device['token'].encode()).digest(),canonical_request('POST','/remote/heartbeat',raw,stamp,nonce),hashlib.sha256).hexdigest()
    headers={'X-CL-Device':device['device_id'],'X-CL-Timestamp':stamp,'X-CL-Nonce':nonce,'X-CL-Signature':signature}
    result=restarted_app.test_client().post('/remote/heartbeat',data=raw,headers=headers,base_url='https://server.local')
    assert result.status_code==200 and result.json['role']=='operator' and not result.json['armed']
