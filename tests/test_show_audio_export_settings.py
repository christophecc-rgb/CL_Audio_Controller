import json
from pathlib import Path

import pytest

from show_audio_export_job import build_export_job
from show_audio_export_settings import (
    default_export_settings, export_settings_json, load_export_settings_json,
    normalize_export_settings,
)


def settings(**changes):
    value = default_export_settings()
    value.update(changes)
    return value


def plan_35():
    items = [
        {"id": f"scene_{index:03d}", "type": "medley_part" if index <= 8 else "scene",
         "filename_stem": f"{index:03d} - SCÈNE", "status": "ready"}
        for index in range(1, 34)
    ]
    items.extend([
        {"id": "medley_a_full", "type": "medley_full", "filename_stem": "MEDLEY A", "status": "ready"},
        {"id": "medley_b_full", "type": "medley_full", "filename_stem": "MEDLEY B", "status": "ready"},
    ])
    return {"version": 1, "status": "ready", "items": items}


def test_defaults():
    value = normalize_export_settings(default_export_settings())
    assert value == {"audio_profile": "clean", "sample_rate": 48000,
                     "normalize": False, "export_scenes": True,
                     "export_medleys": True, "keep_master_wav": False,
                     "formats": [{"format": "mp3", "bitrate_kbps": 320}]}


@pytest.mark.parametrize("bitrate", [192, 256, 320])
def test_mp3_bitrates(bitrate):
    assert normalize_export_settings(settings(
        formats=[{"format": "mp3", "bitrate_kbps": bitrate}]))["formats"][0]["bitrate_kbps"] == bitrate


def test_invalid_mp3_bitrate():
    with pytest.raises(ValueError, match="bitrate MP3"):
        normalize_export_settings(settings(formats=[{"format": "mp3", "bitrate_kbps": 128}]))


@pytest.mark.parametrize("name", ["wav", "aiff"])
@pytest.mark.parametrize("depth", [16, 24, "float32"])
def test_pcm_depths(name, depth):
    value = normalize_export_settings(settings(formats=[{"format": name, "bit_depth": depth}]))
    assert value["formats"][0]["bit_depth"] == depth


@pytest.mark.parametrize("depth", [16, 24])
def test_flac_depths(depth):
    assert normalize_export_settings(settings(
        formats=[{"format": "flac", "bit_depth": depth}]))["formats"][0]["bit_depth"] == depth


def test_flac_float_is_rejected():
    with pytest.raises(ValueError, match="FLAC"):
        normalize_export_settings(settings(formats=[{"format": "flac", "bit_depth": "float32"}]))


@pytest.mark.parametrize("rate", [44100, 48000, 88200, 96000])
def test_sample_rates(rate):
    assert normalize_export_settings(settings(sample_rate=rate))["sample_rate"] == rate


def test_invalid_profile_rate_empty_formats_selection_and_duplicate():
    invalid = [
        (settings(audio_profile="fallback"), "profil audio"),
        (settings(sample_rate=32000), "sample rate"),
        (settings(formats=[]), "format"),
        (settings(export_scenes=False, export_medleys=False), "sélection vide"),
        (settings(formats=[{"format": "wav", "bit_depth": 24},
                           {"format": "wav", "bit_depth": 24}]), "dupliqué"),
    ]
    for value, message in invalid:
        with pytest.raises(ValueError, match=message):
            normalize_export_settings(value)


def test_contradictory_format_parameters_are_rejected():
    with pytest.raises(ValueError, match="profondeur PCM"):
        normalize_export_settings(settings(formats=[
            {"format": "mp3", "bitrate_kbps": 320, "bit_depth": 24}]))
    with pytest.raises(ValueError, match="bitrate MP3"):
        normalize_export_settings(settings(formats=[
            {"format": "wav", "bit_depth": 24, "bitrate_kbps": 320}]))


def test_json_round_trip():
    value = settings(audio_profile="mastered", formats=[{"format": "wav", "bit_depth": 24}])
    assert load_export_settings_json(export_settings_json(value)) == normalize_export_settings(value)
    assert json.loads(export_settings_json(value))["audio_profile"] == "mastered"


def test_multiformat_job_uses_one_capture_per_item():
    formats = [{"format": "mp3", "bitrate_kbps": 320},
               {"format": "wav", "bit_depth": 24},
               {"format": "flac", "bit_depth": 24}]
    job = build_export_job(plan_35(), settings(formats=formats))
    assert job["metrics"] == {"selected_item_count": 35, "capture_count": 35,
                              "final_output_count": 105, "retained_master_count": 0}
    assert job["items"][0]["capture"]["kind"] == "master_intermediate"
    assert {output["kind"] for output in job["items"][0]["outputs"]} == {"final"}


def test_scene_only_and_medley_only_selection():
    scenes = build_export_job(plan_35(), settings(export_medleys=False))
    medleys = build_export_job(plan_35(), settings(export_scenes=False))
    assert scenes["metrics"]["capture_count"] == 33
    assert medleys["metrics"]["capture_count"] == 2


@pytest.mark.parametrize("profile", ["direct", "mastered"])
def test_profile_is_preserved_without_fallback(profile):
    job = build_export_job(plan_35(), settings(audio_profile=profile))
    assert job["settings"]["audio_profile"] == profile
    assert {item["audio_profile"] for item in job["items"]} == {profile}
    assert job["fallback_profile"] is None
    expected = ("requires_item_compatibility_validation" if profile == "direct"
                else "requires_master_bus_validation")
    assert job["audio_profile_state"] == expected


def test_requested_wav_is_distinct_from_retained_master():
    job = build_export_job(plan_35(), settings(
        keep_master_wav=True, formats=[{"format": "wav", "bit_depth": 24}]))
    assert job["metrics"]["final_output_count"] == 35
    assert job["metrics"]["retained_master_count"] == 35
    assert job["items"][0]["capture"]["kind"] == "master_intermediate"
    assert job["items"][0]["outputs"][0]["kind"] == "final"


def test_desktop_exposes_compact_settings_without_audio_engine():
    source = (Path(__file__).resolve().parents[1] /
              "show_audio_builder_desktop.py").read_text(encoding="utf-8")
    for label in ("CLEAN", "MASTERED", "DIRECT", '"mp3"', '"wav"', '"aiff"', '"flac"',
                  "Scènes", "Medleys complets", "Normaliser", "Conserver WAV maître"):
        assert label in source
    for forbidden in ("ffmpeg", "sounddevice", "pyaudio", "scene.fire", "clip.fire",
                      "/live/song/start", "/live/song/stop"):
        assert forbidden not in source


def test_readable_export_names_and_sequential_order():
    plan = {"items": [
        {"id": "a", "type": "scene", "title": "ANNONCE", "status": "ready"},
        {"id": "skip", "type": "scene", "title": "Absent", "status": "blocked"},
        {"id": "b", "type": "medley_full", "title": "meddley SING SING", "status": "ready"},
        {"id": "c", "type": "scene", "title": "ANNONCE", "status": "ready"},
    ]}
    job = build_export_job(plan, settings())
    assert [x["outputs"][0]["filename"] for x in job["items"]] == [
        "01 - ANNONCE.mp3", "02 - Medley SING SING.mp3", "03 - ANNONCE.mp3"]
    single = build_export_job(plan, settings(export_scenes=False))
    assert single["items"][0]["outputs"][0]["filename"] == "Medley SING SING.mp3"
    assert single["items"][0]["outputs"][0]["settings"]["bitrate_kbps"] == 320


def test_output_quality_variants_do_not_collide():
    plan = {"items": [{"id": "x", "type": "scene", "title": "A/B", "status": "ready"}]}
    job = build_export_job(plan, settings(formats=[
        {"format": "mp3", "bitrate_kbps": 192},
        {"format": "mp3", "bitrate_kbps": 320},
        {"format": "wav", "bit_depth": 24},
    ]))
    assert [o["filename"] for o in job["items"][0]["outputs"]] == [
        "A - B [mp3_192k].mp3", "A - B [mp3_320k].mp3", "A - B.wav"]
