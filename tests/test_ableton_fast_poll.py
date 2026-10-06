import importlib.util
from pathlib import Path
from unittest.mock import Mock, patch
import pytest

ROOT = Path(__file__).resolve().parents[1]
def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'INSTALLER_AbletonOSC' / (name+'.py'))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def test_poll_uses_live_timer_and_stops_on_error():
    module = load('cl_fast_poll'); manager = Mock(); factory = Mock()
    poll = module.FastPoll(manager, factory)
    factory.assert_called_once_with(poll.poll, 20, True, False)
    factory.return_value.start.assert_called_once()
    poll.poll(); manager.osc_server.process.assert_called_once()
    manager.osc_server.process.side_effect = RuntimeError('Live unavailable')
    poll.poll(); poll.poll()
    assert manager.osc_server.process.call_count == 2
    factory.return_value.stop.assert_called_once()


def test_other_thread_never_touches_live():
    module = load('cl_fast_poll'); manager = Mock(); factory = Mock()
    poll = module.FastPoll(manager, factory)
    poll.thread = -1
    poll.poll()
    manager.osc_server.process.assert_not_called()
    factory.return_value.stop.assert_called_once()


def test_install_preserves_original_and_restores(tmp_path):
    module = load('install_fast_poll')
    source = 'class Manager:\n    def start(self):\n            self.init_api()\n    def disconnect(self):\n        pass\n'
    (tmp_path/'manager.py').write_text(source)
    module.install(tmp_path)
    assert (tmp_path/'manager.py.before-cl-fast-poll').read_text() == source
    assert 'FastPoll(self)' in (tmp_path/'manager.py').read_text()
    module.install(tmp_path)
    module.install(tmp_path, restore=True)
    assert (tmp_path/'manager.py').read_text() == source


def test_unrecognized_source_is_unchanged(tmp_path):
    module = load('install_fast_poll'); (tmp_path/'manager.py').write_text('pass\n')
    with pytest.raises(ValueError): module.install(tmp_path)
    assert (tmp_path/'manager.py').read_text() == 'pass\n'
    assert not (tmp_path/'manager.py.before-cl-fast-poll').exists()
