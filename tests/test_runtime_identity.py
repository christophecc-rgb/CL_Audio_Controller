import os
from pathlib import Path
from unittest.mock import patch
from runtime_identity import runtime_identity


def test_identity_reports_actual_source_and_process(tmp_path):
    source = tmp_path / 'app.py'
    source.write_text('test source')
    result = runtime_identity(source)
    assert result['pid'] == os.getpid()
    assert result['script_path'] == str(source)
    assert result['backend_path'] == str(source)
    assert len(result['source_sha256_short']) == 12
    assert result['source_mtime'] > 0
    assert result['origin'] == 'repo_dev'
    with patch('sys.frozen', True, create=True):
        assert runtime_identity(source)['origin'] == 'installed_bundle'


def test_missing_metadata_is_nonfatal(tmp_path):
    assert runtime_identity(tmp_path / 'absent')['source_sha256_short'] is None


def test_status_integration_is_additive():
    root = Path(__file__).resolve().parents[1]
    assert 'snapshot["runtime_identity"] = runtime_identity(__file__)' in (root / 'app.py').read_text()
    assert 'runtime_identity=runtime_identity(__file__, backend_path=APP)' in (root / 'launcher_control.py').read_text()
