from show_audio_medleys import (
    build_medley,
    normalize_medley,
    validate_medley,
)


def snapshot():
    return {
        "scenes": [
            {
                "scene_index": 39,
                "scene_name": "GIGI",
                "reference": {
                    "track_name": "PLAYBACK",
                    "duration_seconds": 112.078125,
                },
            },
            {
                "scene_index": 40,
                "scene_name": "NEVER",
                "reference": {
                    "track_name": "PLAYBACK",
                    "duration_seconds": 99.671875,
                },
            },
            {
                "scene_index": 41,
                "scene_name": "LOVE",
                "reference": {
                    "track_name": "PLAYBACK",
                    "duration_seconds": 99.453125,
                },
            },
            {
                "scene_index": 42,
                "scene_name": "DANCING QUEEN",
                "reference": {
                    "track_name": "PLAYBACK",
                    "duration_seconds": 134.875,
                },
            },
        ]
    }


def medley():
    return {
        "id": "medley_40_43",
        "title": "TEST",
        "scene_numbers": [40, 41, 42, 43],
        "export_parts": True,
        "export_full": True,
        "play_mode": "follow",
    }


def test_normalize_medley():
    result = normalize_medley(medley())

    assert result["scene_numbers"] == [
        40, 41, 42, 43
    ]
    assert result["play_mode"] == "follow"


def test_validate_contiguous_medley():
    assert validate_medley(
        normalize_medley(medley())
    ) == []


def test_reject_non_contiguous_medley():
    raw = medley()
    raw["scene_numbers"] = [40, 41, 43]

    assert "non_contiguous_scenes" in validate_medley(
        normalize_medley(raw)
    )


def test_build_medley_uses_real_playback_durations():
    result = build_medley(
        medley(),
        snapshot(),
    )

    assert result["status"] == "ready"
    assert result["part_count"] == 4
    assert result["ready_part_count"] == 4

    assert abs(
        result["duration_seconds"] - 446.078125
    ) < 0.000001


def test_missing_playback_makes_medley_incomplete():
    snap = snapshot()
    snap["scenes"][2]["reference"] = {}

    result = build_medley(
        medley(),
        snap,
    )

    assert result["status"] == "incomplete"
    assert result["duration_seconds"] is None
