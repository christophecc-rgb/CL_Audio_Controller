from types import SimpleNamespace
from threading import RLock
from remote_tls import shared_addresses


def listener(active=False, managed=True):
    return SimpleNamespace(lock=RLock(), server=SimpleNamespace(server_port=8443) if active else None,
                           settings={'server_url': 'https://macchris.local:8443', 'managed': managed},
                           identity={'bonjour_name': 'macchris.local'})


def test_http_ignores_pending_https_configuration():
    result = shared_addresses(listener())
    assert result['remote_url'] == 'http://macchris.local:5050/'
    assert result['showcue_url'] == 'http://macchris.local:5050/show-info'
    assert not result['tls_active']
    assert '127.0.0.1' not in result['remote_url']


def test_https_uses_actual_listener_and_certificate():
    result = shared_addresses(listener(True))
    assert result['remote_url'] == 'https://macchris.local:8443/'
    assert result['showcue_url'] == 'https://macchris.local:8443/show-info'
    assert result['tls_active'] and result['local_certificate']
    assert not shared_addresses(listener(True, False))['local_certificate']


def test_inconsistent_listener_is_not_advertised():
    tls = listener(True)
    tls.server.server_port = 9443
    assert shared_addresses(tls) == {}


def test_network_change_and_http_to_https():
    tls = listener()
    # An IP change leaves the OS Bonjour name stable, so the QR needs no stale IP.
    tls.identity['interfaces'] = [{'name': 'en0', 'address': '192.168.1.20'}]
    first = shared_addresses(tls)
    tls.identity['interfaces'][0]['address'] = '192.168.2.30'
    assert shared_addresses(tls) == first
    tls.identity['bonjour_name'] = 'new-mac.local'
    assert shared_addresses(tls)['remote_url'] == 'http://new-mac.local:5050/'
    tls.settings['server_url'] = 'https://new-mac.local:8443'
    tls.server = SimpleNamespace(server_port=8443)
    assert shared_addresses(tls)['remote_url'] == 'https://new-mac.local:8443/'
    tls.identity['bonjour_name'] = 'renamed.local'
    assert shared_addresses(tls)['remote_url'] == ''
    assert 'certificat' in shared_addresses(tls)['warning']


def test_network_refresh_is_not_frozen(monkeypatch, tmp_path):
    import remote_tls
    from threading import Event
    identity = {'bonjour_name': 'old.local'}
    monkeypatch.setattr(remote_tls, 'network_identity', lambda: dict(identity))
    tls = remote_tls.RemoteTLS(None, tmp_path)
    identity['bonjour_name'] = 'new.local'
    refreshed = Event()
    def current():
        refreshed.set()
        return dict(identity)
    monkeypatch.setattr(remote_tls, 'network_identity', current)
    tls.network_updated = 0
    tls.refresh_network()
    assert refreshed.wait(2)
    # Join the refresh indirectly through its lock/completion marker.
    import time
    deadline = time.monotonic() + 2
    while tls.network_refreshing and time.monotonic() < deadline:
        time.sleep(.01)
    assert shared_addresses(tls)['remote_url'] == 'http://new.local:5050/'


def test_qr_endpoint_encodes_exact_url_and_rejects_untrusted_interfaces(monkeypatch):
    import ast
    from pathlib import Path
    from flask import Flask, request
    import security_http
    source = Path(__file__).resolve().parents[1] / 'launcher_control.py'
    node = next(n for n in ast.parse(source.read_text()).body
                if isinstance(n, ast.FunctionDef) and n.name == 'shared_qr')
    app = Flask(__name__)
    exec(compile(ast.Module(body=[node], type_ignores=[]), str(source), 'exec'),
         {'app': app, 'request': request})
    encoded = []
    monkeypatch.setattr(security_http, 'qr_svg', lambda value: encoded.append(value) or '<svg/>')
    client = app.test_client()
    for scheme in ('http', 'https'):
        url = scheme + '://macchris.local:8443/'
        assert client.get('/shared-qr', query_string={'url': url}).status_code == 200
        assert encoded[-1] == url
    for host in ('localhost', '127.0.0.1', '10.8.0.1', '169.254.2.3', '192.168.1.20'):
        assert client.get('/shared-qr', query_string={'url': 'http://' + host + ':5050/'}).status_code == 400
