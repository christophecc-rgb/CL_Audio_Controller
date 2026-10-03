import json
import plistlib
import socket
import ssl
from pathlib import Path

import pytest
from flask import Flask, jsonify

import remote_tls
import security_http
from remote_security import RemoteSecurity

PASSWORD = 'Local iPhone setup password safe'


@pytest.fixture
def setup(tmp_path, monkeypatch):
    identity = {'bonjour_name': 'test-mac.local', 'interfaces': [{'name': 'en0', 'address': '127.0.0.1', 'primary': True}], 'suggested_url': 'https://test-mac.local:8443'}
    monkeypatch.setattr(remote_tls, 'network_identity', lambda: identity)
    monkeypatch.setattr(security_http, 'network_identity', lambda: identity)
    for variable in ('CL_REMOTE_TLS_CERT', 'CL_REMOTE_TLS_KEY', 'CL_REMOTE_TLS_PORT', 'CL_REMOTE_PUBLIC_URL'):
        monkeypatch.delenv(variable, raising=False)
    app = Flask(__name__)
    manager = security_http.attach_security(app, directory=tmp_path / 'Security')
    @app.route('/status')
    def status(): return jsonify(ok=True)
    @app.route('/action', methods=['POST'])
    def action(): return jsonify(ok=True)
    client = app.test_client()
    manager.set_password(PASSWORD, initial=True)
    client.post('/security/admin/unlock', json={'password': PASSWORD})
    client.post('/security/admin/mode', json={'mode': 'development'})
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]
    url = 'https://test-mac.local:' + str(port)
    yield app, client, manager, url
    app.extensions['cl_remote_tls'].stop()


def configure(setup):
    app, client, manager, url = setup
    result = client.post('/security/admin/tls-setup', json={'server_url': url})
    assert result.status_code == 200, result.json
    return result.json


def verify_phone(client, url):
    return client.post('/remote/verify', base_url=url, environ_base={'REMOTE_ADDR': '192.0.2.50'}, headers={'Origin': url})


def test_first_setup_real_tls_certificates_and_no_auto_arm(setup):
    app, client, manager, url = setup
    assert security_http.start_remote_tls(app) is None
    assert not client.get('/security/diagnostics').json['https']['ready']
    payload = configure(setup)
    tls = app.extensions['cl_remote_tls']
    assert tls.probe(url)
    assert payload['https']['ready'] and not payload['https']['phone_verified']
    assert not manager.armed
    for field in ('private_key', 'ca_certificate', 'certificate'):
        assert Path(tls.settings[field]).is_file()
    assert Path(tls.settings['private_key']).stat().st_mode & 0o777 == 0o600
    assert (manager.directory / 'https/ca-key.pem').stat().st_mode & 0o777 == 0o600
    assert (manager.directory / 'remote-tls.json').stat().st_mode & 0o777 == 0o600
    assert payload['https']['network']['bonjour_name'] == 'test-mac.local'
    assert client.get('/status', environ_base={'REMOTE_ADDR': '192.0.2.50'}).status_code == 200
    assert client.post('/action', json={'action': 'go'}).status_code == 200
    assert client.post('/action', json={'action': 'go'}, environ_base={'REMOTE_ADDR': '192.0.2.50'}).status_code == 403


def test_qr_requires_listener_and_remote_https_confirmation(setup):
    app, client, manager, url = setup
    qr = lambda address=url: client.post('/security/admin/qr', json={'server_url': address, 'role': 'operator'})
    assert qr().status_code == 403
    assert not manager.codes
    configure(setup)
    assert qr().status_code == 403
    assert client.post('/remote/verify', base_url=url).status_code == 403  # Loopback is not an iPhone.
    assert verify_phone(client, url.replace('https:', 'http:')).status_code == 403
    assert verify_phone(client, url).status_code == 200
    result = qr()
    assert result.status_code == 200 and '<svg' in result.json['svg']
    assert result.json['url'].startswith(url + '/remote/pair#code=')
    assert qr(url.replace('test-mac.local', 'other.local')).status_code == 403
    app.extensions['cl_remote_tls'].stop()
    assert qr().status_code == 403


@pytest.mark.parametrize('url', ['http://mac.local:8443', 'https://user:secret@mac.local:8443', 'https://mac.local:5050', 'https://mac.local:8443/path', 'https://mac.local:8443?token=x', 'https://bad_host.local:8443', 'https://mac.local:bad'])
def test_bad_address_never_generates_certificates(setup, url):
    app, client, manager, _ = setup
    result = client.post('/security/admin/tls-setup', json={'server_url': url})
    assert result.status_code == 403
    assert not (manager.directory / 'https').exists()
    assert app.extensions['cl_remote_tls'].server is None


def test_missing_or_invalid_files_keep_http_available(setup):
    app, client, manager, url = setup
    remote_tls.save_settings(manager.directory, {'certificate': '/missing/cert', 'private_key': '/missing/key', 'server_url': url, 'port': remote_tls.server_address(url)[1]})
    assert security_http.start_remote_tls(app) is None
    assert client.get('/status').status_code == 200
    assert 'absent' in client.get('/security/diagnostics').json['https']['error']
    assert client.post('/security/admin/tls-start', json={}).status_code == 403
    cert, key = manager.directory / 'bad.pem', manager.directory / 'bad-key.pem'
    cert.write_text('bad cert'); key.write_text('bad key'); key.chmod(0o600)
    remote_tls.save_settings(manager.directory, {'certificate': str(cert), 'private_key': str(key), 'server_url': url, 'port': remote_tls.server_address(url)[1]})
    assert security_http.start_remote_tls(app) is None
    assert client.get('/status').status_code == 200


def test_root_profile_only_contains_public_ca_and_link_expires(setup):
    app, client, manager, url = setup
    result = configure(setup)
    link = result['enrollment']['url']
    path = '/' + link.split('/', 3)[3]
    response = client.get(path, base_url='http://test-mac.local:5050', environ_base={'REMOTE_ADDR': '192.0.2.50'})
    assert response.status_code == 200
    profile = plistlib.loads(response.data)
    assert profile['PayloadContent'][0]['PayloadType'] == 'com.apple.security.root'
    assert 'PRIVATE KEY' not in response.data.decode()
    assert not profile.get('PayloadRemovalDisallowed', False)
    tls = app.extensions['cl_remote_tls']
    tls.enrollment_expires = 0
    assert client.get(path).status_code == 403
    assert client.get('/remote/trust/ca-key.pem').status_code == 403
    assert client.post('/remote/pair/request', json={'code': 'x'}, base_url='http://test-mac.local').status_code == 403


def test_admin_boundaries_and_no_setup_from_lan(setup):
    app, client, manager, url = setup
    data = {'server_url': url}
    assert client.post('/security/admin/tls-setup', json=data, environ_base={'REMOTE_ADDR': '192.0.2.50'}).status_code == 403
    assert client.post('/security/admin/tls-setup', json=data, headers={'Origin': 'https://evil.example'}).status_code == 403
    client.post('/security/admin/mode', json={'mode': 'show'})
    assert client.post('/security/admin/tls-setup', json=data).status_code == 403
    client.post('/security/admin/lock', json={})
    assert client.post('/security/admin/tls-start', json={}).status_code == 403
    assert not (manager.directory / 'https').exists()


def test_persistence_restarts_disarmed_and_reuses_ca(setup):
    app, client, manager, url = setup
    configure(setup)
    tls = app.extensions['cl_remote_tls']
    ca = Path(tls.settings['ca_certificate']).read_bytes()
    code = manager.new_code('operator')
    pending = manager.request_pair(code, 'iPhone', 'Operator')
    manager.approve(pending['request_id'], authorization_type='permanent')
    device = manager.claim(pending['request_id'], pending['claim'])
    manager.set_armed(True)
    tls.stop()
    restored_app = Flask('restored')
    restored = security_http.attach_security(restored_app, directory=manager.directory)
    restored.load()
    assert not restored.armed and restored.mode == 'show'
    assert restored.snapshot()['devices'][0]['active']
    restored.unlock(PASSWORD)
    assert restored.devices[device['device_id']]['name'] == 'iPhone'
    server = security_http.start_remote_tls(restored_app)
    try:
        assert server is not None
        assert restored_app.extensions['cl_remote_tls'].probe(url)
        assert not restored_app.extensions['cl_remote_tls'].snapshot()['phone_verified']
    finally:
        restored_app.extensions['cl_remote_tls'].stop()
    configure(setup)
    assert Path(tls.settings['ca_certificate']).read_bytes() == ca


def test_port_busy_does_not_break_http(setup):
    app, client, manager, url = setup
    with socket.socket() as occupied:
        occupied.bind(('0.0.0.0', remote_tls.server_address(url)[1])); occupied.listen()
        result = client.post('/security/admin/tls-setup', json={'server_url': url})
    assert result.status_code == 403
    assert client.get('/status').status_code == 200
    assert app.extensions['cl_remote_tls'].server is None


def test_packaging_contains_onboarding_and_no_extra_python_crypto_dependency():
    root = Path(__file__).resolve().parents[1]
    spec = (root / 'CL Audio Controller.spec').read_text()
    assert "'remote_tls'" in spec and "'ssl'" in spec
    assert "('static', 'static')" in spec
    assert Path('/usr/bin/openssl').is_file()


def test_hot_reload_keeps_port_and_ca_and_requires_new_phone_test(setup):
    app, client, manager, url = setup
    configure(setup)
    tls = app.extensions['cl_remote_tls']
    server, context = tls.server, tls.context
    ca = Path(tls.settings['ca_certificate']).read_bytes()
    assert verify_phone(client, url).status_code == 200
    configure(setup)
    assert tls.server is server and tls.context is context
    assert Path(tls.settings['ca_certificate']).read_bytes() == ca
    assert tls.probe(url)
    assert not tls.snapshot()['phone_verified']


def test_hostname_mismatch_and_key_permissions_are_not_bypassed(setup):
    app, client, manager, url = setup
    configure(setup)
    tls = app.extensions['cl_remote_tls']
    changed = url.replace('test-mac.local', 'other.local')
    tls.settings['server_url'] = changed
    with pytest.raises(ssl.SSLCertVerificationError):
        tls.probe(changed)
    assert not tls.snapshot()['ready']
    tls.settings['server_url'] = url
    key = Path(tls.settings['private_key'])
    key.chmod(0o644)
    assert client.post('/security/admin/tls-start', json={}).status_code == 403
    key.chmod(0o600)
    assert tls.probe(url)


def test_phone_confirmation_cannot_be_forged_cross_origin_or_different_host(setup):
    app, client, manager, url = setup
    configure(setup)
    remote = {'REMOTE_ADDR': '192.0.2.50'}
    assert client.post('/remote/verify', base_url=url, environ_base=remote, headers={'Origin': 'https://evil.example'}).status_code == 403
    assert client.post('/remote/verify', base_url=url.replace('test-mac.local', 'other.local'), environ_base=remote).status_code == 403
    assert not app.extensions['cl_remote_tls'].snapshot()['phone_verified']


def test_stable_bonjour_name_survives_new_ip_without_regenerating_ca(setup, monkeypatch):
    app, client, manager, url = setup
    configure(setup)
    original = json.loads((manager.directory / 'remote-tls.json').read_text())
    ca = Path(original['ca_certificate']).read_bytes()
    app.extensions['cl_remote_tls'].stop()
    identity = {'bonjour_name': 'test-mac.local', 'interfaces': [{'name': 'en0', 'address': '192.0.2.99', 'primary': True}], 'suggested_url': 'https://test-mac.local:8443'}
    monkeypatch.setattr(remote_tls, 'network_identity', lambda: identity)
    restarted = Flask('new-ip')
    security_http.attach_security(restarted, directory=manager.directory)
    try:
        assert security_http.start_remote_tls(restarted) is not None
        tls = restarted.extensions['cl_remote_tls']
        assert tls.probe(url)
        assert tls.snapshot()['network']['interfaces'][0]['address'] == '192.0.2.99'
        assert Path(tls.settings['ca_certificate']).read_bytes() == ca
        assert tls.settings['server_url'] == url
    finally:
        restarted.extensions['cl_remote_tls'].stop()


def test_network_proposal_uses_os_identity_and_default_interface(monkeypatch):
    outputs = {
        ('/usr/sbin/scutil', '--get', 'LocalHostName'): 'Fresh-Mac',
        ('/sbin/route', '-n', 'get', 'default'): 'interface: en1',
        ('/sbin/ifconfig', '-l'): 'lo0 en0 en1 utun1',
        ('/usr/sbin/ipconfig', 'getifaddr', 'en0'): '192.168.1.20',
        ('/usr/sbin/ipconfig', 'getifaddr', 'en1'): '192.168.2.20',
    }
    monkeypatch.setattr(remote_tls, '_command', lambda arguments: outputs[tuple(arguments)])
    result = remote_tls.network_identity()
    assert result['suggested_url'] == 'https://Fresh-Mac.local:8443'
    assert result['interfaces'][0] == {'name': 'en1', 'address': '192.168.2.20', 'primary': True}
    assert len(result['interfaces']) == 2


def test_packaged_ui_gates_qr_and_explains_physical_trust_steps():
    root = Path(__file__).resolve().parents[1]
    html = (root / 'static/security-panel.html').read_text()
    js = (root / 'static/security-panel.js').read_text()
    assert 'Première configuration iPhone' in html and 'prepare-https' in html
    assert 'confiance totale' in html and 'clés privées restent sur le Mac' in html
    assert 'disabled data-qr="operator"' in html
    assert '!https.ready||!https.phone_verified' in js
    assert "act('tls-setup'" in js and "act('tls-start'" in js
    for filename in ('remote-check.html', 'remote-check.js', 'security-panel.html', 'security-panel.js'):
        assert (root / 'static' / filename).is_file()


def test_iphone_browser_normalizes_bonjour_hostname_case(setup):
    app, client, manager, url = setup
    mixed_url = url.replace('test-mac.local', 'Test-Mac.local')
    response = client.post('/security/admin/tls-setup', json={'server_url': mixed_url})
    assert response.status_code == 200
    assert response.json['https']['ready']
    assert not response.json['https']['phone_verified']
    remote = {'REMOTE_ADDR': '192.0.2.50'}
    assert client.get('/remote/check', base_url=url, environ_base=remote).status_code == 200
    assert client.post('/remote/verify', base_url=url.replace('https:', 'http:'), environ_base=remote, headers={'Origin': url}).status_code == 403
    result = client.post('/remote/verify', base_url=url, environ_base=remote, headers={'Origin': url, 'Sec-Fetch-Site': 'same-origin'})
    assert result.status_code == 200, result.json
    assert client.get('/security/diagnostics').json['https']['phone_verified']
    assert not manager.armed
    for origin in ('http://test-mac.local', url.replace('test-mac.local', 'evil.local'), url + '/remote/check', url + '@evil.local'):
        assert client.post('/remote/verify', base_url=url, environ_base=remote, headers={'Origin': origin}).status_code == 403
    assert client.post('/remote/verify', base_url=url, environ_base=remote, headers={'Origin': url, 'Sec-Fetch-Site': 'cross-site'}).status_code == 403
