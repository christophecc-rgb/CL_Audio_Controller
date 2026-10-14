"""Packaging boundaries, without starting any runtime or building an app."""
import ast
import os
from pathlib import Path
import runpy
import sys
import types

ROOT = Path(__file__).resolve().parents[1]


def test_light_entry_forces_mode_before_runtime_import(monkeypatch):
    calls = []
    module = types.ModuleType('runtime_startup')
    module.run_light_entry = lambda entry: calls.append((entry, os.environ['CL_APP_MODE']))
    monkeypatch.setitem(sys.modules, 'runtime_startup', module)
    monkeypatch.setenv('CL_APP_MODE', 'FULL')
    runpy.run_path(str(ROOT / 'launcher_light.py'), run_name='__main__')
    assert calls == [('launcher', 'LOCAL_LIGHT')]


def test_light_bundle_has_separate_identity_and_only_light_resources():
    captured = {}

    def record(name):
        def factory(*args, **kwargs):
            captured[name] = kwargs
            return types.SimpleNamespace(pure=[], scripts=[], binaries=[], datas=[])
        return factory

    env = {name: record(name) for name in ('Analysis', 'PYZ', 'EXE', 'COLLECT', 'BUNDLE')}
    env['SPECPATH'] = str(ROOT)
    exec(compile((ROOT / 'CL Show Control Light.spec').read_text(), '<spec>', 'exec'), env)
    assert captured['BUNDLE']['bundle_identifier'] == 'com.claudio.showcontrollight'
    assert captured['BUNDLE']['name'] == 'CL Show Control Light.app'
    assert captured['EXE']['name'] == 'CL Show Control Light'
    assert captured['Analysis']['binaries'] == []
    assert captured['Analysis']['datas'][:4] == [
        ('templates/light.html', 'templates'), ('static/light.css', 'static'),
        ('static/light.js', 'static'), ('static/remote-auth.js', 'static')]
    assert 'app' in captured['Analysis']['hiddenimports']
    assert not {'app', 'remote_tls', 'remote_security', 'security_http'} & set(captured['Analysis']['excludes'])
    ast.parse((ROOT / 'launcher_light.py').read_text())


def test_frozen_light_forces_common_engine(monkeypatch):
    calls = []
    module = types.ModuleType('runtime_startup')
    module.run_light_entry = lambda entry: calls.append(os.environ['CL_LIGHT_ENGINE'])
    monkeypatch.setitem(sys.modules, 'runtime_startup', module)
    monkeypatch.setenv('CL_LIGHT_ENGINE', 'legacy')
    monkeypatch.setattr(sys, 'frozen', True, raising=False)
    runpy.run_path(str(ROOT / 'launcher_light.py'), run_name='__main__')
    assert calls == ['common']


def test_light_excludes_historical_engine():
    captured = {}
    def record(name):
        def factory(*args, **kwargs):
            captured[name] = kwargs
            return types.SimpleNamespace(pure=[], scripts=[], binaries=[], datas=[])
        return factory
    env = {name: record(name) for name in ('Analysis', 'PYZ', 'EXE', 'COLLECT', 'BUNDLE')}
    env['SPECPATH'] = str(ROOT)
    exec(compile((ROOT / 'CL Show Control Light.spec').read_text(), '<spec>', 'exec'), env)
    assert {'light_runtime', 'light_timing'} <= set(captured['Analysis']['excludes'])
    assert captured['BUNDLE']['info_plist']['CFBundleShortVersionString'] == '2.3.0'
