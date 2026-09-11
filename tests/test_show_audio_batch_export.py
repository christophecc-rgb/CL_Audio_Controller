from pathlib import Path
import shutil
import subprocess
import wave

import pytest

from show_audio_batch_export import (
    BatchExportError,
    encode_mp3,
    execute_batch,
    execute_batch_item,
)


def write_wav(
    path: Path,
    *,
    seconds: float = 0.25,
    rate: int = 48000,
) -> None:
    frames = int(
        seconds * rate
    )

    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    with wave.open(
        str(path),
        "wb",
    ) as handle:
        handle.setnchannels(2)
        handle.setsampwidth(3)
        handle.setframerate(rate)

        # Signal non nul simple en PCM 24 bits.
        sample = (
            b"\x00\x10\x00"
            b"\x00\x10\x00"
        )

        handle.writeframes(
            sample * frames
        )


def test_encode_mp3_real_ffmpeg(
    tmp_path,
):
    if not shutil.which("ffmpeg"):
        pytest.skip(
            "ffmpeg absent"
        )

    source = (
        tmp_path / "master.wav"
    )

    target = (
        tmp_path / "final.mp3"
    )

    write_wav(
        source,
        seconds=0.25,
    )

    result = encode_mp3(
        source,
        target,
        bitrate_kbps=320,
    )

    assert target.is_file()
    assert target.stat().st_size > 1024
    assert result["format"] == "mp3"
    assert result["bitrate_kbps"] == 320


def test_invalid_mp3_bitrate(
    tmp_path,
):
    source = (
        tmp_path / "master.wav"
    )

    write_wav(source)

    with pytest.raises(
        BatchExportError
    ):
        encode_mp3(
            source,
            tmp_path / "x.mp3",
            bitrate_kbps=128,
        )


def test_batch_item_uses_one_master_for_mp3_and_wav(
    tmp_path,
    monkeypatch,
):
    calls = []

    def fake_offline(
        *,
        zone,
        settings,
        output_path,
        tempo,
        automation,
        timeout,
    ):
        calls.append(
            dict(zone)
        )

        write_wav(
            Path(output_path),
            seconds=1.0,
        )

        return {
            "status": "success",
            "mode": "OFFLINE_ABLETON",
            "file": {
                "path": str(output_path),
            },
        }

    monkeypatch.setattr(
        "show_audio_batch_export.execute_offline_wav",
        fake_offline,
    )

    def fake_mp3(
        master_wav,
        output_path,
        *,
        bitrate_kbps,
    ):
        Path(output_path).write_bytes(
            b"x" * 2048
        )

        return {
            "path": str(output_path),
            "size": 2048,
            "format": "mp3",
            "bitrate_kbps": bitrate_kbps,
        }

    monkeypatch.setattr(
        "show_audio_batch_export.encode_mp3",
        fake_mp3,
    )

    item = {
        "id": "scene_029",
        "zone": {
            "start_beats": 100.0,
            "duration_beats": 8.0,
            "expected_duration_seconds": 1.0,
        },
        "settings": {
            "sample_rate": 48000,
            "normalize": False,
        },
        "outputs": [
            {
                "format": "mp3",
                "bitrate_kbps": 320,
                "filename": "Annonce.mp3",
            },
            {
                "format": "wav",
                "bit_depth": 24,
                "filename": "Annonce.wav",
            },
        ],
    }

    result = execute_batch_item(
        item,
        output_directory=tmp_path,
        tempo=120.0,
        automation=lambda script: None,
        timeout=2.0,
    )

    assert result["status"] == "completed"
    assert len(calls) == 1
    assert len(result["outputs"]) == 2
    assert (
        tmp_path / "Annonce.mp3"
    ).is_file()
    assert (
        tmp_path / "Annonce.wav"
    ).is_file()


def test_batch_stops_after_offline_fallback(
    tmp_path,
    monkeypatch,
):
    calls = []

    def fake_offline(**kwargs):
        calls.append(
            kwargs["zone"]["name"]
        )

        return {
            "status": "OFFLINE_FAILED",
            "error": "boom",
            "fallback": "realtime",
        }

    monkeypatch.setattr(
        "show_audio_batch_export.execute_offline_wav",
        fake_offline,
    )

    def item(name):
        return {
            "id": name,
            "zone": {
                "name": name,
                "start_beats": 0,
                "duration_beats": 4,
            },
            "settings": {
                "sample_rate": 48000,
                "normalize": False,
            },
            "outputs": [
                {
                    "format": "mp3",
                    "bitrate_kbps": 320,
                    "filename": f"{name}.mp3",
                }
            ],
        }

    result = execute_batch(
        [
            item("one"),
            item("two"),
        ],
        output_directory=tmp_path,
        tempo=120.0,
        automation=lambda script: None,
        timeout_per_item=1.0,
    )

    assert result["status"] == "failed"
    assert calls == ["one"]
    assert result["metrics"]["processed"] == 1


def test_batch_default_automation_is_resolved_by_offline_engine(monkeypatch, tmp_path):
    import show_audio_batch_export as batch
    seen = []

    def offline(**kwargs):
        seen.append(kwargs)
        return {'status': 'OFFLINE_FAILED', 'error': 'configure_export_jxa: délai dépassé'}

    monkeypatch.setattr(batch, 'execute_offline_wav', offline)
    result = batch.execute_batch_item(
        {'id': 'annonce', 'zone': {'start_beats': 19390.220703125, 'duration_beats': 64,
                                 'expected_duration_seconds': 32},
         'settings': {'sample_rate': 48000},
         'outputs': [{'format': 'wav', 'bit_depth': 24, 'filename': 'annonce.wav'}]},
        output_directory=tmp_path, tempo=120, timeout=7)
    assert seen[0]['automation'] is None
    assert seen[0]['timeout'] == 7
    assert seen[0]['zone']['expected_duration_seconds'] == 32
    assert result['status'] == 'failed'
    assert result['error'] == 'configure_export_jxa: délai dépassé'
