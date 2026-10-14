"""FULL release metadata is consistent before any build or installer runs."""
import os
from pathlib import Path
import re
import subprocess
import sys
from types import SimpleNamespace

import pytest

import release_version

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(autouse=True)
def clean_version_environment(monkeypatch):
    monkeypatch.delenv('CL_AUDIO_VERSION', raising=False)
    monkeypatch.delenv('CL_BUILD_NUMBER', raising=False)


def spec_metadata(path):
    captured = {}
    def factory(name):
        def record(*args, **kwargs):
            captured[name] = kwargs
            return SimpleNamespace(pure=[], scripts=[], binaries=[], datas=[])
        return record
    context = {name: factory(name) for name in ('Analysis', 'PYZ', 'EXE', 'COLLECT', 'BUNDLE')}
    context['SPECPATH'] = str(ROOT)
    exec(compile(path.read_text(), str(path), 'exec'), context)
    return captured['BUNDLE']['info_plist']


@pytest.mark.parametrize('version,build', [(None, None), ('2.2.7', '7')])
def test_full_spec_and_cli_use_same_identity_from_another_directory(monkeypatch, tmp_path, version, build):
    if version:
        monkeypatch.setenv('CL_AUDIO_VERSION', version)
        monkeypatch.setenv('CL_BUILD_NUMBER', build)
    monkeypatch.chdir(tmp_path)
    metadata = spec_metadata(ROOT / 'CL Audio Controller.spec')
    expected = (release_version.full_version(), release_version.full_build())
    assert (metadata['CFBundleShortVersionString'], metadata['CFBundleVersion']) == expected
    for arguments, value in [([], expected[0]), (['--build'], expected[1])]:
        output = subprocess.check_output([sys.executable, str(ROOT / 'release_version.py'), *arguments], text=True)
        assert output.strip() == value


@pytest.mark.parametrize('script', ['scripts/build_release.sh', 'scripts/export_transport_kit.command'])
@pytest.mark.parametrize('version,build', [(None, None), ('2.2.7', '7')])
def test_distribution_prefix_exports_identity_before_creating_build_directories(script, version, build):
    source = (ROOT / script).read_text()
    # Execute only setup before mktemp/build/install operations.
    prefix = source.split('BUILD_ROOT=', 1)[0]
    if 'PROJECT_ROOT=' in prefix:
        prefix = re.sub(r'PROJECT_ROOT=.*', 'PROJECT_ROOT="$CL_VERSION_TEST_ROOT"', prefix, count=1)
    else:
        prefix = re.sub(r'SCRIPT_PATH=.*', 'SCRIPT_PATH="$CL_VERSION_TEST_SCRIPT"', prefix, count=1)
    prefix += '\n"$CL_PYTHON" -c "import os; print(os.environ[\'CL_AUDIO_VERSION\']); print(os.environ[\'CL_BUILD_NUMBER\'])"\n'
    environment = dict(os.environ, CL_PYTHON=sys.executable, CL_VERSION_TEST_ROOT=str(ROOT),
                       CL_VERSION_TEST_SCRIPT=str(ROOT / script))
    if version:
        environment.update(CL_AUDIO_VERSION=version, CL_BUILD_NUMBER=build)
    result = subprocess.run(['bash', '-c', prefix], env=environment, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [version or release_version.FULL_VERSION, build or release_version.FULL_BUILD]
    assert '2.2.1' not in source
    assert '<key>CFBundleVersion</key><string>$CL_BUILD_NUMBER</string>' in source


@pytest.mark.parametrize('name,value', [('CL_AUDIO_VERSION','invalid'), ('CL_BUILD_NUMBER','bad')])
@pytest.mark.parametrize('script', ['scripts/build_release.sh', 'scripts/export_transport_kit.command'])
def test_invalid_identity_fails_before_release_build(name, value, script):
    prefix = (ROOT / script).read_text().split('BUILD_ROOT=', 1)[0]
    if 'PROJECT_ROOT=' in prefix:
        prefix = re.sub(r'PROJECT_ROOT=.*', 'PROJECT_ROOT="$CL_VERSION_TEST_ROOT"', prefix, count=1)
    else:
        prefix = re.sub(r'SCRIPT_PATH=.*', 'SCRIPT_PATH="$CL_VERSION_TEST_SCRIPT"', prefix, count=1)
    environment = dict(os.environ, CL_PYTHON=sys.executable, CL_VERSION_TEST_ROOT=str(ROOT),
                       CL_VERSION_TEST_SCRIPT=str(ROOT / script))
    environment[name] = value
    result = subprocess.run(['bash','-c',prefix], env=environment, capture_output=True, text=True)
    assert result.returncode != 0
    assert name in result.stderr


def test_readme_declares_source_identity_and_components_remain_independent(monkeypatch):
    readme = (ROOT / 'README.md').read_text()
    assert f'**{release_version.FULL_VERSION}** (build {release_version.FULL_BUILD})' in readme
    assert 'release_version.py' in readme
    monkeypatch.setenv('CL_AUDIO_VERSION', '2.2.7')
    monkeypatch.setenv('CL_BUILD_NUMBER', '7')
    monkeypatch.setattr(Path, 'is_file', lambda self: True)  # FFmpeg presence only; no build.
    for filename in ('CL ShowCue.spec', 'CL ShowCue Builder.spec', 'CL Show Audio Builder.spec'):
        metadata = spec_metadata(ROOT / filename)
        assert metadata['CFBundleShortVersionString'] == '1.0.0'
        assert metadata['CFBundleVersion'] == '1'
