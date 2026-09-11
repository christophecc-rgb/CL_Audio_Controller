from show_audio_export_plan import (
    build_export_plan,
    build_scene_export_items,
    scene_title,
)


def config():
    return {
        "medleys": [
            {
                "id": "medley_40_43",
                "title": "GIGI / NEVER / LOVE / DANCING QUEEN",
                "scene_numbers": [
                    40,
                    41,
                    42,
                    43,
                ],
                "export_parts": True,
                "export_full": True,
                "play_mode": "follow",
            }
        ]
    }


def snapshot():
    scenes = []

    durations = {
        40: 112.078125,
        41: 99.671875,
        42: 99.453125,
        43: 134.875,
    }

    names = {
        40: "GIGI; BPM ; KEY ; 1:51",
        41: "NEVER ; BPM ; KEY ; 1:39",
        42: "LOVE; BPM ; KEY ; 1:39",
        43: "DANCING QUEEN; BPM ; KEY ; 2:14",
    }

    for number in (
        40,
        41,
        42,
        43,
    ):
        scenes.append({
            "scene_index": (
                number - 1
            ),
            "scene_name": (
                names[number]
            ),
            "reference": {
                "track_name": (
                    "JADE-GUI/CYR-DIR"
                ),
                "duration_seconds": (
                    durations[number]
                ),
            },
        })

    scenes.append({
        "scene_index": 9,
        "scene_name": (
            "SIMPLE TITLE ; 120 ; C ; 2:00"
        ),
        "reference": {
            "track_name": (
                "38 Mathilde"
            ),
            "duration_seconds": 120.0,
        },
    })

    scenes.append({
        "scene_index": 10,
        "scene_name": "TECH",
        "reference": {},
    })

    return {
        "scenes": scenes
    }


def test_scene_title_strips_semicolon_metadata():
    assert scene_title(
        "GIGI; BPM ; KEY ; 1:51"
    ) == "GIGI"


def test_medley_members_are_medley_parts():
    items = build_scene_export_items(
        config(),
        snapshot(),
    )

    by_number = {
        item["scene_number"]: item
        for item in items
    }

    assert by_number[40]["type"] == (
        "medley_part"
    )
    assert by_number[43]["type"] == (
        "medley_part"
    )
    assert by_number[10]["type"] == (
        "scene"
    )


def test_scene_without_playback_is_not_exported():
    items = build_scene_export_items(
        config(),
        snapshot(),
    )

    numbers = {
        item["scene_number"]
        for item in items
    }

    assert 11 not in numbers


def test_export_plan_contains_parts_and_full_medley():
    plan = build_export_plan(
        config(),
        snapshot(),
    )

    metrics = plan["metrics"]

    assert metrics[
        "scene_export_count"
    ] == 5

    assert metrics[
        "medley_part_count"
    ] == 4

    assert metrics[
        "simple_scene_count"
    ] == 1

    assert metrics[
        "medley_full_count"
    ] == 1

    assert metrics[
        "item_count"
    ] == 6


def test_full_medley_duration_is_sum_of_parts():
    plan = build_export_plan(
        config(),
        snapshot(),
    )

    full = next(
        item
        for item in plan["items"]
        if item["type"] == (
            "medley_full"
        )
    )

    assert abs(
        full["duration_seconds"]
        - 446.078125
    ) < 0.000001


def test_full_medley_keeps_follow_mode():
    plan = build_export_plan(
        config(),
        snapshot(),
    )

    full = next(
        item
        for item in plan["items"]
        if item["type"] == (
            "medley_full"
        )
    )

    assert full["play_mode"] == (
        "follow"
    )


def test_tableaux_audio_scene_is_exportable_without_playback():
    from show_audio_export_plan import build_scene_export_items

    config = {"medleys": []}

    snapshot = {
        "scenes": [
            {
                "scene_index": 33,
                "scene_name": "Jingle AVA Le lustre",
                "reference": None,
                "audio_reference": {
                    "track_index": 65,
                    "track_name": "66 TABLEAUX",
                    "clip_name": "Jingle AVA 28sec",
                    "duration_seconds": 32.0,
                },
            }
        ]
    }

    items = build_scene_export_items(config, snapshot)

    assert len(items) == 1
    assert items[0]["scene_number"] == 34
    assert items[0]["duration_seconds"] == 32.0
    assert items[0]["playback_track"] == ""
    assert items[0]["source_track"] == "66 TABLEAUX"
    assert items[0]["source_clip"] == "Jingle AVA 28sec"



def test_scene_export_prefers_real_playback_duration_over_audio_fallback():
    from show_audio_export_plan import build_scene_export_items

    snapshot = {
        "scenes": [
            {
                "scene_index": 40,
                "scene_name": "GIGI; BPM ; KEY ; 1:51",
                "reference": {
                    "track_name": "JADE-GUI/CYR-DIR",
                    "clip_name": "GIGI (A)",
                    "duration_seconds": 112.078125,
                },
                "audio_reference": {
                    "track_name": "AUTRE AUDIO",
                    "clip_name": "AUTRE",
                    "duration_seconds": 999.0,
                },
            }
        ]
    }

    items = build_scene_export_items(
        {},
        snapshot,
    )

    assert len(items) == 1
    assert items[0]["scene_index"] == 40
    assert items[0]["duration_seconds"] == 112.078125
    assert items[0]["source_track"] == "JADE-GUI/CYR-DIR"
    assert items[0]["source_clip"] == "GIGI (A)"


def test_scene_export_uses_audio_reference_as_fallback():
    from show_audio_export_plan import build_scene_export_items

    snapshot = {
        "scenes": [
            {
                "scene_index": 29,
                "scene_name": "ANNONCE",
                "reference": None,
                "audio_reference": {
                    "track_name": "66 TABLEAUX",
                    "clip_name": "ANNONCE",
                    "duration_seconds": 32.0,
                },
            }
        ]
    }

    items = build_scene_export_items(
        {},
        snapshot,
    )

    assert len(items) == 1
    assert items[0]["scene_index"] == 29
    assert items[0]["duration_seconds"] == 32.0
    assert items[0]["source_track"] == "66 TABLEAUX"
    assert items[0]["source_clip"] == "ANNONCE"


def test_scene_export_skips_technical_scene_without_audio():
    from show_audio_export_plan import build_scene_export_items

    snapshot = {
        "scenes": [
            {
                "scene_index": 26,
                "scene_name": "entree directrice",
                "reference": None,
                "audio_reference": None,
            },
            {
                "scene_index": 28,
                "scene_name": "prepa SHOW",
                "reference": None,
                "audio_reference": None,
            },
        ]
    }

    assert build_scene_export_items({}, snapshot) == []
