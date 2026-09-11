from show_audio_scene_parser import (
    parse_duration_label,
    parse_scene_inventory,
    parse_scene_name,
)


def test_duration_standard():
    assert parse_duration_label(
        "TOXIC ; BPM ; KEY ; 4:25"
    ) == 265.0


def test_duration_single_digit_seconds():
    assert parse_duration_label(
        "VIOLONS QUEEN ; BPM ; KEY ; 2:8"
    ) == 128.0


def test_duration_invalid_seconds():
    assert parse_duration_label(
        "TEST ; 2:99"
    ) is None


def test_plain_scene():
    parsed = parse_scene_name(
        25,
        "entree directrice",
    )

    assert parsed["scene_index"] == 25
    assert parsed["scene_number"] == 26
    assert parsed["title"] == "entree directrice"
    assert parsed["show_number"] is None
    assert (
        parsed["declared_duration_seconds"]
        is None
    )


def test_placeholder_metadata():
    parsed = parse_scene_name(
        2,
        "TOXIC ; BPM ; KEY ; 4:25",
    )

    assert parsed["title"] == "TOXIC"
    assert parsed["show_number"] is None
    assert parsed["has_bpm_placeholder"] is True
    assert parsed["has_key_placeholder"] is True
    assert (
        parsed["declared_duration_seconds"]
        == 265.0
    )


def test_compact_metadata_spacing():
    parsed = parse_scene_name(
        37,
        'AVA "FAKIR"; BPM;KEY;5:17',
    )

    assert parsed["title"] == 'AVA "FAKIR"'
    assert parsed["has_bpm_placeholder"] is True
    assert parsed["has_key_placeholder"] is True
    assert (
        parsed["declared_duration_seconds"]
        == 317.0
    )


def test_show_number_prefix():
    parsed = parse_scene_name(
        30,
        "2 - TABLEAU VIS A VIS ; BPM ; KEY ; 6:15",
    )

    assert parsed["show_number"] == 2
    assert parsed["title"] == "TABLEAU VIS A VIS"
    assert (
        parsed["declared_duration_seconds"]
        == 375.0
    )


def test_number_without_metadata():
    parsed = parse_scene_name(
        47,
        "14 - ORAGE",
    )

    assert parsed["show_number"] == 14
    assert parsed["title"] == "ORAGE"
    assert (
        parsed["declared_duration_seconds"]
        is None
    )


def test_number_with_internal_hyphens():
    parsed = parse_scene_name(
        46,
        "13 - H2O - VIDEO - ; BPM ; KEY ; 3:20",
    )

    assert parsed["show_number"] == 13
    assert parsed["title"] == "H2O - VIDEO -"
    assert (
        parsed["declared_duration_seconds"]
        == 200.0
    )


def test_empty_scene():
    parsed = parse_scene_name(
        92,
        "",
    )

    assert parsed["empty"] is True
    assert parsed["title"] == ""


def test_inventory():
    result = parse_scene_inventory([
        {
            "scene_index": 0,
            "scene_name": "Reset",
        },
        {
            "scene_index": 1,
            "scene_name": (
                "1 - INTRO ; BPM ; KEY ; 1:14"
            ),
        },
    ])

    assert len(result) == 2
    assert result[0]["title"] == "Reset"
    assert result[1]["show_number"] == 1
    assert (
        result[1]["declared_duration_seconds"]
        == 74.0
    )
