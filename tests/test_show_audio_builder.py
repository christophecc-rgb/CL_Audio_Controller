import pytest

from show_audio_builder import (
    empty_show_audio_document,
    normalize_show_audio_document,
    resolve_variant,
    resolve_variant_for_builder_cue,
    validate_show_audio_document,
)


def test_empty_document():
    assert empty_show_audio_document() == {
        "version": 1,
        "revision": 0,
        "variants": [],
    }


def test_normalize_audio_variant():
    document = normalize_show_audio_document({
        "variants": [{
            "number": "42",
            "title": "JADE",
            "role": "ROXY",
            "artist": "Alice",
            "key": "Gm",
            "playback": "JADE_ROXY_Gm.wav",
            "scene_index": 41,
            "scene_name": "42 JADE ROXY",
        }]
    })

    variant = document["variants"][0]

    assert variant["number"] == "42"
    assert variant["title"] == "JADE"
    assert variant["role"] == "ROXY"
    assert variant["artist"] == "Alice"
    assert variant["key"] == "Gm"
    assert variant["playback"] == "JADE_ROXY_Gm.wav"
    assert variant["scene_index"] == 41
    assert variant["export"] is True


def test_resolve_variant_by_number_role_artist():
    document = {
        "variants": [
            {
                "number": "42",
                "title": "JADE",
                "role": "ROXY",
                "artist": "Alice",
                "key": "Gm",
                "playback": "JADE_ROXY_Gm.wav",
                "scene_index": 41,
            },
            {
                "number": "42",
                "title": "JADE",
                "role": "ROXY",
                "artist": "Sophie",
                "key": "F#m",
                "playback": "JADE_ROXY_Fs.wav",
                "scene_index": 42,
            },
        ]
    }

    resolved = resolve_variant(
        document,
        number="42",
        role="ROXY",
        artist="Sophie",
    )

    assert resolved is not None
    assert resolved["key"] == "F#m"
    assert resolved["playback"] == "JADE_ROXY_Fs.wav"
    assert resolved["scene_index"] == 42


def test_artist_is_required_when_role_has_multiple_variants():
    document = {
        "variants": [
            {
                "number": "42",
                "title": "JADE",
                "role": "ROXY",
                "artist": "Alice",
                "playback": "A.wav",
                "scene_index": 1,
            },
            {
                "number": "42",
                "title": "JADE",
                "role": "ROXY",
                "artist": "Sophie",
                "playback": "B.wav",
                "scene_index": 2,
            },
        ]
    }

    assert resolve_variant(
        document,
        number="42",
        role="ROXY",
    ) is None


def test_resolve_variant_from_showcue_distribution():
    document = {
        "variants": [{
            "number": "42",
            "title": "JADE",
            "role": "ROXY",
            "artist": "Alice",
            "key": "Gm",
            "playback": "JADE_ROXY_Gm.wav",
            "scene_index": 41,
        }]
    }

    cue = {
        "number": "42",
        "role": "ROXY",
    }

    resolved_distribution = {
        "resolved_artist": "Alice",
    }

    variant = resolve_variant_for_builder_cue(
        document,
        cue,
        resolved_distribution,
    )

    assert variant is not None
    assert variant["playback"] == "JADE_ROXY_Gm.wav"
    assert variant["key"] == "Gm"


def test_validation_detects_incomplete_variant():
    result = validate_show_audio_document({
        "variants": [{
            "number": "42",
            "title": "JADE",
            "role": "ROXY",
            "artist": "Alice",
        }]
    })

    assert result["ready"] is False
    assert result["incomplete_variants"][0]["missing"] == [
        "playback",
        "scene",
    ]


def test_negative_scene_index_is_rejected():
    with pytest.raises(ValueError):
        normalize_show_audio_document({
            "variants": [{
                "scene_index": -1,
            }]
        })


from show_audio_builder import (
    audio_filename_for_variant,
    load_show_audio_document,
    save_show_audio_document,
    variant_display_name,
)


def test_save_and_load_show_audio_document(tmp_path):
    path = tmp_path / "show_audio.json"

    original = {
        "revision": 3,
        "variants": [{
            "number": "42",
            "title": "JADE",
            "role": "ROXY",
            "artist": "Alice",
            "key": "Gm",
            "playback": "JADE_ROXY_Gm.wav",
            "scene_index": 41,
        }]
    }

    saved = save_show_audio_document(path, original)
    loaded = load_show_audio_document(path)

    assert path.exists()
    assert saved == loaded
    assert loaded["revision"] == 3
    assert loaded["variants"][0]["key"] == "Gm"


def test_missing_show_audio_file_returns_empty_document(tmp_path):
    document = load_show_audio_document(
        tmp_path / "missing.json"
    )

    assert document == empty_show_audio_document()


def test_variant_display_name():
    label = variant_display_name({
        "number": "42",
        "title": "JADE",
        "role": "ROXY",
        "artist": "Alice",
        "key": "Gm",
    })

    assert label == "42 · JADE · ROXY · Alice · Gm"


def test_audio_filename():
    filename = audio_filename_for_variant({
        "number": "42",
        "title": "JADE",
        "role": "ROXY",
        "artist": "Alice",
        "key": "Gm",
    })

    assert filename == "42 - JADE - ROXY - Alice - Gm.mp3"


def test_audio_filename_sanitizes_forbidden_characters():
    filename = audio_filename_for_variant({
        "number": "42",
        "title": 'JADE / FINAL',
        "role": "ROXY",
        "artist": 'Alice:Test',
        "key": "Gm",
    })

    assert "/" not in filename
    assert ":" not in filename
    assert filename.endswith(".mp3")


def test_variant_save_preserves_playback_medleys_and_other_settings(tmp_path):
    from copy import deepcopy
    from show_audio_builder_desktop import upsert_scene_variant

    config = {
        "variants": [], "revision": 7,
        "playback_tracks": ["A"], "playback_groups": ["GROUP"],
        "playback_source_mode": "live",
        "medleys": [{"id": "disco", "scene_numbers": [41, 42, 43, 44]}],
        "export_settings": {"sample_rate": 48000},
        "future_setting": {"nested": [1, 2]},
    }
    before = deepcopy(config)
    updated = upsert_scene_variant(
        config, scene_index=32, scene_name="3 - SUPREME", number="3",
        title="SUPREME", role="Meneuse", artist="Jade", key="", playback="C",
    )
    path = tmp_path / "show_audio.json"
    save_show_audio_document(path, updated)
    loaded = load_show_audio_document(path)
    for key in before.keys() - {"variants", "revision"}:
        assert loaded[key] == before[key]
    assert config == before
    updated["medleys"][0]["scene_numbers"].append(45)
    assert config == before
