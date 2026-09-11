from show_audio_ableton import ShowAudioAbletonAdapter
from show_audio_plan import (
    STATUS_DISABLED,
    STATUS_MISMATCH,
    STATUS_MISSING,
    STATUS_READY,
    build_export_plan,
    export_item_label,
)


class FakeAbleton:
    def query(self, address, *args, **kwargs):
        if address == "/live/song/get/scenes/name":
            return [
                "01 INTRO",
                "42 JADE ROXY",
                "43 JADE LEO",
                "99 FINAL",
            ]

        return []


def adapter():
    return ShowAudioAbletonAdapter(
        FakeAbleton().query
    )


def test_ready_variant():
    document = {
        "variants": [{
            "id": "jade_roxy",
            "number": "42",
            "title": "JADE",
            "role": "ROXY",
            "artist": "Alice",
            "key": "Gm",
            "playback": "JADE_ROXY_Gm.wav",
            "scene_index": 1,
            "scene_name": "42 JADE ROXY",
            "export": True,
        }]
    }

    plan = build_export_plan(
        document,
        adapter(),
    )

    item = plan["items"][0]

    assert item["status"] == STATUS_READY
    assert item["actual_scene_index"] == 1
    assert item["actual_scene_name"] == "42 JADE ROXY"
    assert item["filename"] == (
        "42 - JADE - ROXY - Alice - Gm.mp3"
    )

    assert plan["ready"] is True
    assert plan["counts"][STATUS_READY] == 1


def test_mismatch_variant():
    document = {
        "variants": [{
            "id": "jade_roxy",
            "number": "42",
            "title": "JADE",
            "role": "ROXY",
            "artist": "Alice",
            "playback": "A.wav",
            "scene_index": 1,
            "scene_name": "42 JADE LEO",
        }]
    }

    plan = build_export_plan(
        document,
        adapter(),
    )

    item = plan["items"][0]

    assert item["status"] == STATUS_MISMATCH
    assert item["actual_scene_name"] == "42 JADE ROXY"
    assert item["expected_scene_name"] == "42 JADE LEO"

    assert plan["ready"] is False


def test_missing_variant():
    document = {
        "variants": [{
            "id": "absent",
            "number": "88",
            "title": "ABSENT",
            "role": "ROXY",
            "artist": "Alice",
            "playback": "absent.wav",
            "scene_index": None,
            "scene_name": "88 ABSENT",
        }]
    }

    plan = build_export_plan(
        document,
        adapter(),
    )

    assert (
        plan["items"][0]["status"]
        == STATUS_MISSING
    )
    assert plan["ready"] is False


def test_disabled_variant_does_not_block_plan():
    document = {
        "variants": [{
            "id": "disabled",
            "number": "88",
            "title": "ABSENT",
            "role": "ROXY",
            "artist": "Alice",
            "playback": "absent.wav",
            "scene_index": None,
            "scene_name": "88 ABSENT",
            "export": False,
        }]
    }

    plan = build_export_plan(
        document,
        adapter(),
    )

    assert (
        plan["items"][0]["status"]
        == STATUS_DISABLED
    )
    assert plan["ready"] is True


def test_plan_counts_statuses():
    document = {
        "variants": [
            {
                "id": "ready",
                "number": "42",
                "title": "JADE",
                "role": "ROXY",
                "artist": "Alice",
                "playback": "A.wav",
                "scene_index": 1,
                "scene_name": "42 JADE ROXY",
            },
            {
                "id": "mismatch",
                "number": "43",
                "title": "JADE",
                "role": "LEO",
                "artist": "Bob",
                "playback": "B.wav",
                "scene_index": 2,
                "scene_name": "WRONG",
            },
            {
                "id": "missing",
                "number": "88",
                "title": "ABSENT",
                "role": "ROXY",
                "artist": "Alice",
                "playback": "C.wav",
                "scene_name": "88 ABSENT",
            },
            {
                "id": "disabled",
                "number": "89",
                "title": "TECH",
                "role": "ROXY",
                "artist": "Alice",
                "playback": "D.wav",
                "scene_name": "89 TECH",
                "export": False,
            },
        ]
    }

    plan = build_export_plan(
        document,
        adapter(),
    )

    assert plan["counts"] == {
        STATUS_READY: 1,
        STATUS_MISMATCH: 1,
        STATUS_MISSING: 1,
        STATUS_DISABLED: 1,
    }


def test_export_item_label():
    label = export_item_label({
        "number": "42",
        "title": "JADE",
        "role": "ROXY",
        "artist": "Alice",
        "key": "Gm",
    })

    assert label == (
        "42 · JADE · ROXY · Alice · Gm"
    )


def test_select_reference_clip_uses_longest_on_non_technical_clip():
    from show_audio_plan import select_reference_clip

    clips = [
        {
            "track_index": 1,
            "track_name": "CLICK",
            "track_on": True,
            "clip_name": "Click song",
            "duration_seconds": 300.0,
            "length_beats": 600.0,
        },
        {
            "track_index": 21,
            "track_name": "TONA BASSE (A)",
            "track_on": True,
            "clip_name": "Playback A",
            "duration_seconds": 266.1,
            "length_beats": 532.2,
        },
        {
            "track_index": 31,
            "track_name": "MANON",
            "track_on": True,
            "clip_name": "Playback B",
            "duration_seconds": 265.9,
            "length_beats": 531.8,
        },
    ]

    result = select_reference_clip(clips)

    assert result is not None
    assert result["track_index"] == 21
    assert result["track_name"] == "TONA BASSE (A)"
    assert result["duration_seconds"] == 266.1


def test_select_reference_clip_ignores_off_tracks():
    from show_audio_plan import select_reference_clip

    clips = [
        {
            "track_index": 25,
            "track_name": "Jade Naomi",
            "track_on": False,
            "clip_name": "Jade toxic",
            "duration_seconds": 400.0,
        },
        {
            "track_index": 35,
            "track_name": "AMALIA",
            "track_on": True,
            "clip_name": "toxic Amalia",
            "duration_seconds": 266.1,
        },
    ]

    result = select_reference_clip(clips)

    assert result is not None
    assert result["track_index"] == 35
    assert result["duration_seconds"] == 266.1


def test_select_reference_clip_ignores_technical_tracks():
    from show_audio_plan import select_reference_clip

    clips = [
        {
            "track_index": 39,
            "track_name": "40 LTC VIDEO / LIGHT",
            "track_on": True,
            "clip_name": "LTC_01",
            "duration_seconds": 376.0,
        },
        {
            "track_index": 68,
            "track_name": "PGM CHANGE CL5",
            "track_on": True,
            "clip_name": "PGM CHANGE 42",
            "duration_seconds": 0.5,
        },
        {
            "track_index": 72,
            "track_name": "TOP infos",
            "track_on": True,
            "clip_name": "ENCHAINE",
            "duration_seconds": 2.0,
        },
        {
            "track_index": 65,
            "track_name": "66 TABLEAUX",
            "track_on": True,
            "clip_name": "TABLEAU VIS A VIS",
            "duration_seconds": 376.0,
        },
    ]

    result = select_reference_clip(clips)

    assert result is not None
    assert result["track_index"] == 65


def test_select_reference_clip_returns_none_without_eligible_clip():
    from show_audio_plan import select_reference_clip

    clips = [
        {
            "track_index": 39,
            "track_name": "LTC VIDEO / LIGHT",
            "track_on": True,
            "duration_seconds": 300.0,
        },
        {
            "track_index": 31,
            "track_name": "MANON",
            "track_on": False,
            "duration_seconds": 266.0,
        },
    ]

    assert select_reference_clip(clips) is None


def test_select_reference_clip_accepts_real_toxic_shape():
    from show_audio_plan import select_reference_clip

    clips = [
        {
            "track_index": 21,
            "track_name": "TONA BASSE (A)",
            "track_on": True,
            "clip_name": "TOXIC AVEC BVS OK(3)",
            "length_beats": 532.2007446289062,
            "duration_seconds": 266.1003723144531,
        },
        {
            "track_index": 25,
            "track_name": "26 Jade Naomi",
            "track_on": False,
            "clip_name": "Jade toxic",
            "length_beats": 498.9738464355469,
            "duration_seconds": 249.48692321777344,
        },
        {
            "track_index": 39,
            "track_name": "40 LTC VIDEO / LIGHT",
            "track_on": True,
            "clip_name": "LTC_18_01_BANDEAU",
            "length_beats": 508.0,
            "duration_seconds": 254.0,
        },
    ]

    result = select_reference_clip(clips)

    assert result is not None
    assert result["track_index"] == 21
    assert result["clip_name"] == "TOXIC AVEC BVS OK(3)"
    assert round(result["duration_seconds"], 2) == 266.10


def test_is_playback_track_requires_explicit_allowlist():
    from show_audio_plan import is_playback_track

    allowed = [
        "TONA BASSE (A)",
        "38 Mathilde",
    ]

    assert is_playback_track(
        "TONA BASSE (A)",
        allowed,
    )

    assert is_playback_track(
        "38 mathilde",
        allowed,
    )

    assert not is_playback_track(
        "66 TABLEAUX",
        allowed,
    )

    assert not is_playback_track(
        "CC TO PGM QL1",
        allowed,
    )


def test_select_reference_playback_clip_ignores_non_playback_tracks():
    from show_audio_plan import select_reference_playback_clip

    allowed = [
        "TONA BASSE (A)",
        "38 Mathilde",
    ]

    clips = [
        {
            "track_index": 65,
            "track_name": "66 TABLEAUX",
            "track_on": True,
            "duration_seconds": 376.0,
        },
        {
            "track_index": 69,
            "track_name": "CC TO PGM QL1",
            "track_on": True,
            "duration_seconds": 376.0,
        },
        {
            "track_index": 37,
            "track_name": "38 Mathilde",
            "track_on": True,
            "duration_seconds": 195.6,
        },
    ]

    selected = select_reference_playback_clip(
        clips,
        allowed,
    )

    assert selected is not None
    assert selected["track_name"] == "38 Mathilde"


def test_select_reference_playback_clip_returns_none_without_allowed_playback():
    from show_audio_plan import select_reference_playback_clip

    clips = [
        {
            "track_name": "66 TABLEAUX",
            "track_on": True,
            "duration_seconds": 376.0,
        },
        {
            "track_name": "CC TO PGM QL1",
            "track_on": True,
            "duration_seconds": 376.0,
        },
    ]

    assert (
        select_reference_playback_clip(
            clips,
            ["38 Mathilde"],
        )
        is None
    )
