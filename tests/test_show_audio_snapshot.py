from show_audio_snapshot import (
    ShowAudioSnapshotBuilder,
    _track_indices,
    format_duration,
    _resolve_snapshot_tempo,
)


def test_snapshot_tempo_prefers_status_when_available():
    tempo = _resolve_snapshot_tempo(
        {"tempo": 128.0},
        [
            {"tempo": 120.0},
            {"tempo": 120.0},
        ],
    )

    assert tempo == 128.0


def test_snapshot_tempo_uses_bulk_scene_when_status_has_no_tempo():
    tempo = _resolve_snapshot_tempo(
        {},
        [
            {"scene_index": 28, "tempo": 120.0},
            {"scene_index": 29, "tempo": 120.0},
        ],
    )

    assert tempo == 120.0


def test_snapshot_tempo_ignores_invalid_scene_values():
    tempo = _resolve_snapshot_tempo(
        {"tempo": None},
        [
            {"tempo": None},
            {"tempo": ""},
            {"tempo": 0},
            {"tempo": 120.0},
        ],
    )

    assert tempo == 120.0


def test_snapshot_tempo_rejects_contradictory_live_values():
    import pytest

    with pytest.raises(
        RuntimeError,
        match="Tempos Live contradictoires",
    ):
        _resolve_snapshot_tempo(
            {},
            [
                {"tempo": 120.0},
                {"tempo": 121.0},
            ],
        )


def test_snapshot_tempo_can_remain_absent():
    assert _resolve_snapshot_tempo(
        {},
        [
            {"tempo": None},
            {"tempo": 0},
        ],
    ) is None


def test_track_indices_unique_and_sorted():
    clips = [
        {"track_index": 37},
        {"track_index": 21},
        {"track_index": 37},
    ]

    assert _track_indices(clips) == [21, 37]


def test_format_duration():
    assert format_duration(266.1) == "4:26.10"
    assert format_duration(None) == "—"
    assert format_duration(0) == "—"


def test_merge_clips_uses_track_cache_and_playback_policy(tmp_path):
    config = tmp_path / "show_audio.json"

    config.write_text(
        """{
          "playback_tracks": [
            "38 Mathilde"
          ]
        }"""
    )

    builder = ShowAudioSnapshotBuilder(
        config_path=config
    )

    builder.track_cache = {
        37: {
            "track_index": 37,
            "track_name": "38 Mathilde",
            "track_on": True,
            "track_mute": False,
        },
        65: {
            "track_index": 65,
            "track_name": "66 TABLEAUX",
            "track_on": True,
            "track_mute": False,
        },
    }

    clips = builder.merge_clips([
        {
            "track_index": 37,
            "track_name": "38 Mathilde",
            "duration_seconds": 266.1,
        },
        {
            "track_index": 65,
            "track_name": "66 TABLEAUX",
            "duration_seconds": 376.0,
        },
    ])

    assert clips[0]["track_on"] is True
    assert clips[0]["playback_track"] is True

    assert clips[1]["track_on"] is True
    assert clips[1]["playback_track"] is False


def test_build_scene_from_raw_uses_cached_track_state(tmp_path):
    config = tmp_path / "show_audio.json"

    config.write_text(
        """{
          "playback_tracks": ["38 Mathilde"]
        }"""
    )

    builder = ShowAudioSnapshotBuilder(
        config_path=config
    )

    builder.track_cache = {
        37: {
            "track_index": 37,
            "track_name": "38 Mathilde",
            "track_on": True,
            "track_mute": False,
        }
    }

    scene = builder.build_scene_from_raw({
        "scene_index": 2,
        "scene_name": "TOXIC",
        "tempo": 120.0,
        "clips": [
            {
                "track_index": 37,
                "track_name": "38 Mathilde",
                "clip_name": "TOXIC",
                "duration_seconds": 266.1,
            }
        ],
    })

    assert scene["scene_index"] == 2
    assert scene["playback_on_count"] == 1
    assert scene["unknown_track_state_count"] == 0
    assert scene["reference"]["track_name"] == "38 Mathilde"
    assert scene["reference"]["duration_seconds"] == 266.1


def test_snapshot_preserves_existing_arrangement_markers(tmp_path, monkeypatch):
    config = tmp_path / "show_audio.json"
    config.write_text('{"playback_tracks": ["PB"]}')
    builder = ShowAudioSnapshotBuilder(config_path=config)
    monkeypatch.setattr(builder, "resolve_playback_sources", lambda: ["PB"])
    monkeypatch.setattr(builder, "status", lambda: {
        "set_ready": True,
        "current_set_name": "TEST",
        "set_generation": 3,
        "tempo": 120.0,
        "arrangement_markers_source": "Ableton Set",
        "arrangement_markers": [{"name": "40 - GIGI", "time": 400.0}],
    })
    monkeypatch.setattr(builder, "scene_clips_bulk", lambda _: {
        "ok": True,
        "scenes": [{"scene_index": 39, "scene_name": "GIGI", "clips": []}],
    })
    snapshot = builder.build([39])
    assert snapshot["arrangement"]["markers"] == [
        {"name": "40 - GIGI", "time": 400.0}
    ]
    assert snapshot["arrangement"]["markers_source"] == "Ableton Set"
    assert snapshot["arrangement"]["tempo"] == 120.0


def test_missing_sources_are_discovered_from_live_http_without_fixed_track_limit(tmp_path):
    builder = ShowAudioSnapshotBuilder(config_path=tmp_path / "missing.json")
    requests = []
    def request(path, *, timeout):
        requests.append(path)
        if path == "/status":
            return {"set_ready": True, "set_generation": 1}
        if path.startswith("/show-audio/scene-clips-bulk"):
            return {"ok": True, "set_generation": 1, "track_count": 101, "scenes": [
                {"scene_index": 90, "scene_name": "SONG", "clips": [
                    {"track_index": 100, "track_name": "New source", "duration_seconds": 12}
                ]}
            ]}
        if path == "/show-audio/track-hierarchy?start=0&end=100":
            return {"ok": True, "set_generation": 1, "tracks": [
                {"track_index": 100, "track_name": "New source", "is_foldable": False, "is_grouped": False}
            ]}
        if path == "/show-audio/print/clip-info?track_index=100&slot_index=90":
            return {"ok": True, "set_generation": 1, "track_index": 100, "has_clip": True, "file_path": "new.wav"}
        if path == "/show-audio/tracks-bulk?track_indices=100":
            return {"ok": True, "tracks": [{"track_index": 100, "track_on": True}]}
        raise AssertionError(path)
    builder._request = request
    snapshot = builder.build([90])
    assert snapshot["playback_tracks"] == ["New source"]
    assert snapshot["scenes"][0]["reference"]["duration_seconds"] == 12
    assert len(requests) == 5


def test_discover_sources_skips_http_409_empty_representative_and_tries_next(
    tmp_path,
):
    builder = ShowAudioSnapshotBuilder(
        config_path=tmp_path / "missing.json"
    )
    builder.track_count = 21

    raw_scenes = [
        {
            "scene_index": 40,
            "clips": [
                {
                    "track_index": 20,
                    "track_name": "Playback candidate",
                },
            ],
        },
        {
            "scene_index": 41,
            "clips": [
                {
                    "track_index": 20,
                    "track_name": "Playback candidate",
                },
            ],
        },
    ]

    requests = []

    def request(path, *, timeout):
        requests.append(path)

        if path == "/show-audio/track-hierarchy?start=0&end=20":
            return {
                "ok": True,
                "set_generation": 1,
                "tracks": [
                    {
                        "track_index": 20,
                        "track_name": "Playback candidate",
                        "is_foldable": False,
                        "is_grouped": False,
                    },
                ],
            }

        if path == (
            "/show-audio/print/clip-info?"
            "track_index=20&slot_index=40"
        ):
            raise RuntimeError(
                'HTTP 409 pour /show-audio/print/clip-info?'
                'track_index=20&slot_index=40: '
                '{"error":"aucun clip dans ce slot",'
                '"has_clip":false,"ok":false,'
                '"set_generation":1,'
                '"slot_index":40,"track_index":20}'
            )

        if path == (
            "/show-audio/print/clip-info?"
            "track_index=20&slot_index=41"
        ):
            return {
                "ok": True,
                "has_clip": True,
                "set_generation": 1,
                "track_index": 20,
                "track_name": "Playback candidate",
                "file_path": "candidate.wav",
            }

        raise AssertionError(path)

    builder._request = request

    tracks = builder.discover_sources(
        raw_scenes,
        generation=1,
    )

    assert requests == [
        "/show-audio/track-hierarchy?start=0&end=20",
        (
            "/show-audio/print/clip-info?"
            "track_index=20&slot_index=40"
        ),
        (
            "/show-audio/print/clip-info?"
            "track_index=20&slot_index=41"
        ),
    ]
    assert "Playback candidate" in tracks


def test_discover_sources_does_not_swallow_other_http_409(tmp_path):
    builder = ShowAudioSnapshotBuilder(
        config_path=tmp_path / "missing.json"
    )
    builder.track_count = 21

    raw_scenes = [
        {
            "scene_index": 40,
            "clips": [
                {
                    "track_index": 20,
                    "track_name": "Playback candidate",
                },
            ],
        },
    ]

    def request(path, *, timeout):
        if path == "/show-audio/track-hierarchy?start=0&end=20":
            return {
                "ok": True,
                "set_generation": 1,
                "tracks": [
                    {
                        "track_index": 20,
                        "track_name": "Playback candidate",
                        "is_foldable": False,
                        "is_grouped": False,
                    },
                ],
            }

        if path.startswith("/show-audio/print/clip-info?"):
            raise RuntimeError(
                'HTTP 409 pour '
                '/show-audio/print/clip-info: '
                '{"error":"Set changé",'
                '"ok":false,"set_generation":2}'
            )

        raise AssertionError(path)

    builder._request = request

    try:
        builder.discover_sources(
            raw_scenes,
            generation=1,
        )
    except RuntimeError as exc:
        assert "HTTP 409" in str(exc)
        assert "Set changé" in str(exc)
    else:
        raise AssertionError(
            "Le 409 non lié à has_clip=false devait rester fatal"
        )
