from show_audio_model import (
    build_show_audio_item,
    build_show_audio_model,
    clean_scene_identity,
)


def test_clean_scene_identity_show_number():
    assert clean_scene_identity(
        "2 - TABLEAU VIS A VIS ; BPM ; KEY ; 6:15"
    ) == (
        "2",
        "TABLEAU VIS A VIS",
    )


def test_clean_scene_identity_plain_title():
    assert clean_scene_identity(
        "TOXIC ; BPM ; KEY ; 4:25"
    ) == (
        "",
        "TOXIC",
    )


def test_scene_with_single_playback_is_ready():
    scene = {
        "scene_index": 2,
        "scene_name": "TOXIC ; BPM ; KEY ; 4:25",
        "playback_on_count": 1,
        "reference": {
            "track_name": "38 Mathilde",
            "clip_name": "TOXIC",
            "duration_seconds": 266.1,
        },
        "clips": [
            {
                "track_index": 37,
                "track_name": "38 Mathilde",
                "clip_name": "TOXIC",
                "duration_seconds": 266.1,
                "track_on": True,
                "playback_track": True,
            }
        ],
    }

    item = build_show_audio_item(scene)

    assert item["title"] == "TOXIC"
    assert item["status"] == "ready"
    assert item["exportable"] is True
    assert item["duration_seconds"] == 266.1
    assert item["playback_on_count"] == 1


def test_scene_without_playback_is_not_exportable():
    scene = {
        "scene_index": 30,
        "scene_name": (
            "2 - TABLEAU VIS A VIS ; "
            "BPM ; KEY ; 6:15"
        ),
        "playback_on_count": 0,
        "reference": None,
        "clips": [],
    }

    item = build_show_audio_item(scene)

    assert item["show_number"] == "2"
    assert item["title"] == "TABLEAU VIS A VIS"
    assert item["status"] == "no_playback"
    assert item["exportable"] is False
    assert item["duration_seconds"] is None


def test_multiple_playbacks_are_visible_not_hidden():
    scene = {
        "scene_index": 4,
        "scene_name": "Falling",
        "playback_on_count": 2,
        "reference": {
            "track_name": "Artist B",
            "clip_name": "Falling B",
            "duration_seconds": 230.0,
        },
        "clips": [
            {
                "track_index": 1,
                "track_name": "Artist A",
                "clip_name": "Falling A",
                "duration_seconds": 229.0,
                "track_on": True,
                "playback_track": True,
            },
            {
                "track_index": 2,
                "track_name": "Artist B",
                "clip_name": "Falling B",
                "duration_seconds": 230.0,
                "track_on": True,
                "playback_track": True,
            },
        ],
    }

    item = build_show_audio_item(scene)

    assert item["status"] == "multiple_playbacks"
    assert item["exportable"] is True
    assert len(item["active_playbacks"]) == 2
    assert item["duration_seconds"] == 230.0


def test_variant_role_artist_key_attached_to_scene():
    snapshot = {
        "version": 2,
        "set": {
            "name": "TEST",
            "generation": 1,
            "ready": True,
        },
        "scenes": [
            {
                "scene_index": 2,
                "scene_name": "TOXIC",
                "playback_on_count": 1,
                "reference": {
                    "track_name": "38 Mathilde",
                    "clip_name": "TOXIC",
                    "duration_seconds": 266.1,
                },
                "clips": [],
            }
        ],
    }

    config = {
        "version": 1,
        "variants": [
            {
                "id": "toxic_mathilde",
                "number": "TOXIC",
                "title": "TOXIC",
                "role": "ROXY",
                "artist": "Mathilde",
                "key": "Gm",
                "playback": "TOXIC_Gm.wav",
                "scene_index": 2,
                "scene_name": "TOXIC",
                "export": True,
            }
        ],
    }

    model = build_show_audio_model(
        snapshot,
        config,
    )

    item = model["items"][0]

    assert item["variant_status"] == "configured"
    assert len(item["variants"]) == 1
    assert item["variants"][0]["role"] == "ROXY"
    assert item["variants"][0]["artist"] == "Mathilde"
    assert item["variants"][0]["key"] == "Gm"
    assert item["variants"][0]["playback"] == "TOXIC_Gm.wav"
