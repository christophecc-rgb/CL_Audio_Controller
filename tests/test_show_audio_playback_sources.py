from show_audio_playback_sources import (
    group_descendants,
    group_playback_leaf_tracks,
    resolve_playback_track_names,
)


HIERARCHY = [
    {
        "track_index": 39,
        "track_name": "40 LTC VIDEO",
        "is_foldable": False,
        "is_grouped": False,
    },
    {
        "track_index": 40,
        "track_name": "41 SAISON 7",
        "is_foldable": True,
        "is_grouped": False,
    },
    {
        "track_index": 41,
        "track_name": "42 JC/D/V",
        "is_foldable": True,
        "is_grouped": True,
    },
    {
        "track_index": 42,
        "track_name": "MARGAUX-KEY-DIR",
        "is_foldable": False,
        "is_grouped": True,
    },
    {
        "track_index": 43,
        "track_name": "44 JC/D/V",
        "is_foldable": True,
        "is_grouped": True,
    },
    {
        "track_index": 44,
        "track_name": "MARGAUX-TONY-DIR",
        "is_foldable": False,
        "is_grouped": True,
    },
    {
        "track_index": 65,
        "track_name": "66 TABLEAUX",
        "is_foldable": False,
        "is_grouped": False,
    },
]


def test_group_descendants_stop_at_first_ungrouped():
    result = group_descendants(
        HIERARCHY,
        "41 SAISON 7",
    )

    assert [
        row["track_index"]
        for row in result
    ] == [41, 42, 43, 44]


def test_group_playback_leaf_tracks_exclude_subgroups():
    result = group_playback_leaf_tracks(
        HIERARCHY,
        "41 SAISON 7",
    )

    assert [
        row["track_name"]
        for row in result
    ] == [
        "MARGAUX-KEY-DIR",
        "MARGAUX-TONY-DIR",
    ]


def test_resolve_merges_historical_tracks_and_group():
    document = {
        "playback_tracks": [
            "38 Mathilde",
        ],
        "playback_groups": [
            "41 SAISON 7",
        ],
    }

    result = resolve_playback_track_names(
        document,
        HIERARCHY,
    )

    assert result == [
        "38 Mathilde",
        "MARGAUX-KEY-DIR",
        "MARGAUX-TONY-DIR",
    ]


def test_missing_group_does_not_invent_tracks():
    result = resolve_playback_track_names(
        {
            "playback_groups": [
                "INEXISTANT",
            ]
        },
        HIERARCHY,
    )

    assert result == []


def test_discover_sources_requires_audio_evidence_and_keeps_muted_tracks():
    from show_audio_playback_sources import discover_playback_sources

    hierarchy = [
        {"track_index": 0, "track_name": "New group", "is_foldable": True, "is_grouped": False},
        {"track_index": 1, "track_name": "New artist", "is_foldable": False, "is_grouped": True, "track_on": False},
        {"track_index": 2, "track_name": "Another artist", "is_foldable": False, "is_grouped": True},
        {"track_index": 3, "track_name": "LTC", "is_foldable": False, "is_grouped": False},
        {"track_index": 4, "track_name": "MIDI instrument", "is_foldable": False, "is_grouped": False},
    ]
    infos = [
        {"track_index": i, "ok": True, "has_clip": True, "file_path": "sample.wav" if i < 4 else None}
        for i in range(1, 5)
    ]
    assert discover_playback_sources(hierarchy, infos) == {
        "playback_tracks": ["New artist", "Another artist"],
        "playback_groups": ["New group"],
    }
    infos[1]["file_path"] = None
    assert discover_playback_sources(hierarchy, infos)["playback_groups"] == []
