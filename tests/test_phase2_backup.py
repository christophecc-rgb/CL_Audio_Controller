import json
import socket
import sys
import time
import pytest
from scene_backup_protocol import SceneBackupReceiver,sign,unicast_ipv4
from scene_backup_receiver import SceneBackupUDPReceiver
from scene_backup_udp import SceneBackupUDP

SECRET='a'*64
LOOPBACK='lo0' if sys.platform=='darwin' else 'lo'

def packet(now=1790000000):
    return sign(dict(v=1,show='TEST',session='session1',seq=1,scene=31,ts=now),SECRET)


def test_hmac_accept_duplicate_bad_secret_stale_session_source():
    receiver=SceneBackupReceiver('TEST','session1',SECRET,allowed_source='192.0.2.1',clock=lambda:1790000000)
    for mutate,source in [(lambda p:p.update(auth='0'*64),'192.0.2.1'),(lambda p:p.update(ts=1789999998),'192.0.2.1'),(lambda p:p.update(session='other'),'192.0.2.1'),(lambda p:None,'192.0.2.2')]:
        value=packet();mutate(value)
        with pytest.raises(ValueError): receiver.accept(value,source)
    assert receiver.accept(packet(),'192.0.2.1')==31
    with pytest.raises(ValueError): receiver.accept(packet(),'192.0.2.1')
    receiver.rotate('session2','b'*64)
    with pytest.raises(ValueError): receiver.accept(packet(),'192.0.2.1')


@pytest.mark.parametrize('host',['255.255.255.255','224.0.0.1','0.0.0.0','hostname.local'])
def test_explicit_unicast_only(host):
    with pytest.raises(ValueError): unicast_ipv4(host)


def test_real_loopback_signed_link_scene_and_cable_loss_no_replay():
    probe=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);probe.bind(('127.0.0.1',0));port=probe.getsockname()[1];probe.close()
    scenes=[]
    rx=SceneBackupUDPReceiver(source_ip='127.0.0.1',show='TEST',session='session1',secret=SECRET,allowed_source='127.0.0.1',on_scene=scenes.append,port=port,source_interface=LOOPBACK)
    tx=SceneBackupUDP(port=port)
    rx.start();tx.configure(enabled=True,show_id='TEST',destinations=['127.0.0.1'],source_ip='127.0.0.1',source_interface=LOOPBACK,authentication='hmac_v1',shared_secret=SECRET,session='session1')
    try:
        deadline=time.monotonic()+3
        while tx.snapshot()['link_state']!='BACKUP LINK OK':
            assert time.monotonic()<deadline;time.sleep(.02)
        tx.scene_launched(31)
        deadline=time.monotonic()+2
        while scenes!=[31]: assert time.monotonic()<deadline;time.sleep(.01)
        assert rx.rejected>=0
        rx.close();tx.scene_launched(32);time.sleep(3.1)
        assert tx.snapshot()['link_state']=='BACKUP LINK DOWN'
        rx=SceneBackupUDPReceiver(source_ip='127.0.0.1',show='TEST',session='session1',secret=SECRET,allowed_source='127.0.0.1',on_scene=scenes.append,port=port,source_interface=LOOPBACK)
        rx.start()
        deadline=time.monotonic()+3
        while tx.snapshot()['link_state']!='BACKUP LINK OK':
            assert time.monotonic()<deadline;time.sleep(.02)
        assert scenes==[31]
        tx.scene_launched(33)
        deadline=time.monotonic()+2
        while scenes!=[31,33]:assert time.monotonic()<deadline;time.sleep(.01)
        assert scenes==[31,33] and 'shared_secret' not in tx.snapshot() and SECRET not in json.dumps(tx.snapshot())
    finally: tx.close();rx.close()


def test_interface_failure_does_not_fallback_and_rotation():
    tx=SceneBackupUDP()
    with pytest.raises(ValueError): tx.configure(authentication='hmac_v1',shared_secret=SECRET)
    tx.configure(authentication='hmac_v1',shared_secret=SECRET,source_ip='192.0.2.12',source_interface=LOOPBACK,session='session1')
    with pytest.raises(ValueError): tx.configure(shared_secret='b'*64)
    tx.configure(shared_secret='b'*64,session='session2')
    assert tx.snapshot()['session']=='session2';tx.close()


def test_source_bind_failure_never_uses_default_route():
    class Socket:
        def __init__(self):self.sent=[];self.binds=[]
        def setblocking(self,value):pass
        def setsockopt(self,*args):pass
        def bind(self,address):self.binds.append(address);raise OSError('dedicated interface absent')
        def sendto(self,*args):self.sent.append(args)
        def close(self):pass
    sock=Socket();tx=SceneBackupUDP(socket_factory=lambda *args:sock)
    try:
        tx.configure(enabled=True,authentication='hmac_v1',shared_secret=SECRET,source_ip='192.0.2.12',source_interface=LOOPBACK,session='session1',destinations=['192.0.2.13'])
        tx.scene_launched(1);deadline=time.monotonic()+1
        while tx.snapshot()['send_errors']==0:assert time.monotonic()<deadline;time.sleep(.005)
        assert sock.binds and not sock.sent and tx.snapshot()['link_state']=='BACKUP LINK DOWN'
    finally:tx.close()


def test_backup_has_no_transport_fallback_and_bonjour_cannot_select_peer(monkeypatch):
    # Numeric peers remain authoritative even when host discovery is unavailable.
    monkeypatch.setattr(socket,'gethostbyname',lambda *args:(_ for _ in ()).throw(OSError('Bonjour/DNS unavailable')))
    tx=SceneBackupUDP();tx.configure(destinations=['192.0.2.12'],source_ip='192.0.2.11')
    assert tx.snapshot()['destinations'][0]['host']=='192.0.2.12';tx.close()
    import ast
    from pathlib import Path
    for name in ('scene_backup_udp.py','scene_backup_receiver.py','scene_backup_protocol.py'):
        tree=ast.parse((Path(__file__).resolve().parents[1]/name).read_text())
        modules={n.module for n in ast.walk(tree) if isinstance(n,ast.ImportFrom)}
        modules|={alias.name for n in ast.walk(tree) if isinstance(n,ast.Import) for alias in n.names}
        assert not any(module and any(word in module for word in ('rtp','osc','bonjour')) for module in modules)


def test_reconfiguring_same_session_never_resets_sequence():
    tx=SceneBackupUDP();tx.configure(authentication='hmac_v1',shared_secret=SECRET,source_ip='127.0.0.1',source_interface=LOOPBACK,session='session1')
    tx.seq=42
    tx.configure(session='session1',destinations=['127.0.0.1'])
    assert tx.seq==42
    tx.configure(session='session2');assert tx.seq==0;tx.close()


def test_legacy_activation_requires_explicit_api_migration_choice():
    import ast,ipaddress
    from pathlib import Path
    from flask import Flask,jsonify,request
    node=next(n for n in ast.parse((Path(__file__).resolve().parents[1]/'app.py').read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='scene_backup_settings')
    node.decorator_list=[]
    app=Flask(__name__);tx=SceneBackupUDP()
    scope={'request':request,'jsonify':jsonify,'ipaddress':ipaddress,'scene_backup_udp':tx}
    exec(compile(ast.Module(body=[node],type_ignores=[]),'<actual backup settings>','exec'),scope)
    app.add_url_rule('/api/scene-backup',view_func=scope['scene_backup_settings'],methods=['POST'])
    client=app.test_client()
    try:
        assert client.post('/api/scene-backup',json={'enabled':True}).status_code==400
        assert not tx.enabled
        result=client.post('/api/scene-backup',json={'enabled':True,'authentication':'legacy_v1'})
        assert result.status_code==200 and result.json['link_state']=='LEGACY UNVERIFIED'
    finally:tx.close()
