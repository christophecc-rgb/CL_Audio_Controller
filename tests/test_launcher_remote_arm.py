"""The launcher shortcuts retain backend authorization and local-only access."""
import ast
import json
import urllib.request
import urllib.error
from pathlib import Path
from unittest.mock import Mock
from flask import Flask, jsonify, request


def setup_proxy():
    source = Path(__file__).resolve().parents[1] / 'launcher_control.py'
    tree = ast.parse(source.read_text())
    function = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'remote_control_proxy')
    app = Flask(__name__)
    opener = Mock()
    scope = dict(app=app, jsonify=jsonify, request=request, json=json, urllib=__import__('urllib'),
                 local_request=lambda: request.remote_addr == '127.0.0.1', cl_server_is_remote=lambda: False)
    exec(compile(ast.Module(body=[function], type_ignores=[]), str(source), 'exec'), scope)
    return app, opener, scope


def test_lan_requests_cannot_use_arm_shortcut(monkeypatch):
    app, opener, _ = setup_proxy()
    monkeypatch.setattr(urllib.request, 'build_opener', Mock(return_value=opener))
    result = app.test_client().post('/security/remote-control/arm', json={'armed': True}, environ_base={'REMOTE_ADDR': '192.168.1.8'})
    assert result.status_code == 403
    opener.open.assert_not_called()


def test_backend_authentication_refusal_is_preserved(monkeypatch):
    import io
    app, opener, _ = setup_proxy()
    opener.open.side_effect = urllib.error.HTTPError('http://127.0.0.1:5050/', 403, 'Forbidden', {}, io.BytesIO(b'{"error":"locked"}'))
    monkeypatch.setattr(urllib.request, 'build_opener', Mock(return_value=opener))
    result = app.test_client().post('/security/remote-control/arm', json={'armed': True})
    assert result.status_code == 403
    forwarded = opener.open.call_args.args[0]
    assert forwarded.full_url == 'http://127.0.0.1:5050/security/admin/arm'
    assert json.loads(forwarded.data) == {'armed': True}
    assert forwarded.get_header('Cookie') is None


def test_only_backend_cookie_is_forwarded(monkeypatch):
    app, opener, _ = setup_proxy()
    upstream = Mock(status=200, headers={})
    upstream.read.return_value = b'{"armed":true,"devices":["private"]}'
    opener.open.return_value.__enter__ = Mock(return_value=upstream)
    opener.open.return_value.__exit__ = Mock(return_value=False)
    monkeypatch.setattr(urllib.request, 'build_opener', Mock(return_value=opener))
    client = app.test_client()
    client.set_cookie('cl_admin_backend', 'backend-token')
    client.set_cookie('cl_admin_launcher', 'launcher-token')
    result = client.get('/security/remote-control/status')
    assert result.json == {'armed': True}
    assert opener.open.call_args.args[0].get_header('Cookie') == 'cl_admin_backend=backend-token'
