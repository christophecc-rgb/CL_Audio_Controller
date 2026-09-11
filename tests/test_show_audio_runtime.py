from pathlib import Path
import show_audio_runtime as runtime


def test_frozen_config_is_seeded_without_overwriting(monkeypatch, tmp_path):
    resources = tmp_path / 'resources'
    resources.mkdir()
    (resources / 'show_audio.json').write_text('{"revision": 1}')
    monkeypatch.setattr(runtime, '__file__', str(resources / 'show_audio_runtime.py'))
    monkeypatch.setattr(runtime.sys, 'frozen', True, raising=False)
    monkeypatch.setattr(Path, 'home', lambda: tmp_path / 'user')
    path = runtime.configuration_path()
    assert 'Application Support' in str(path)
    assert path.read_text() == '{"revision": 1}'
    path.write_text('{"revision": 2}')
    assert runtime.configuration_path().read_text() == '{"revision": 2}'


def test_ffmpeg_bundle_precedes_terminal_path(monkeypatch, tmp_path):
    import show_audio_batch_export as batch
    executable = tmp_path / 'ffmpeg'
    executable.touch()
    monkeypatch.setattr(runtime.sys, 'frozen', True, raising=False)
    monkeypatch.setattr(runtime.sys, '_MEIPASS', str(tmp_path), raising=False)
    monkeypatch.setattr(batch.shutil, 'which', lambda _: None)
    assert batch._ffmpeg_path() == str(executable)
