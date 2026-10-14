from light_timing import reference_candidates, timing_from_clip


def test_tableaux_has_priority_over_saison8():
    layout = [
        dict(index=0, name="1 LTC VIDEO / LIGHT",
             foldable=False, grouped=False),
        dict(index=14, name="15 SAISON 8",
             foldable=True, grouped=False),
        dict(index=15, name="16 JMD",
             foldable=True, grouped=True),
        dict(index=16, name="JOHANNA/MIKA/DIR",
             foldable=False, grouped=True),
        dict(index=23, name="24 TABLEAUX",
             foldable=False, grouped=False),
    ]

    result = reference_candidates(layout)

    assert result[0]["track"] == 23
    assert result[0]["kind"] == "tableaux"


def test_saison8_leaf_remembers_parent_branch():
    layout = [
        dict(index=14, name="15 SAISON 8",
             foldable=True, grouped=False),
        dict(index=15, name="16 JMD",
             foldable=True, grouped=True),
        dict(index=16, name="JOHANNA/MIKA/DIR",
             foldable=False, grouped=True),
        dict(index=17, name="18 JCD",
             foldable=True, grouped=True),
        dict(index=18, name="JOHANNA/CYRYL/DIR",
             foldable=False, grouped=True),
        dict(index=23, name="24 TABLEAUX",
             foldable=False, grouped=False),
    ]

    result = reference_candidates(layout)

    saison = [x for x in result if x["kind"] == "saison8"]

    assert saison == [
        {
            "track": 16,
            "required_unmuted": (14, 15),
            "kind": "saison8",
        },
        {
            "track": 18,
            "required_unmuted": (14, 17),
            "kind": "saison8",
        },
    ]


def test_technical_tracks_are_not_reference_candidates():
    layout = [
        dict(index=14, name="15 SAISON 8",
             foldable=True, grouped=False),
        dict(index=15, name="16 JMD",
             foldable=True, grouped=True),
        dict(index=16, name="PGM CHANGE CL5",
             foldable=False, grouped=True),
        dict(index=17, name="JOHANNA/MIKA/DIR",
             foldable=False, grouped=True),
    ]

    result = reference_candidates(layout)

    assert [x["track"] for x in result] == [17]


def test_nonwarped_audio_uses_markers_as_seconds():
    result = timing_from_clip(
        is_audio_clip=True,
        warping=False,
        looping=False,
        start_marker=0.0,
        end_marker=112.078125,
        playing_position=15.614583015441895,
    )

    duration, position, remaining = result

    assert duration == 112.078125
    assert abs(position - 15.614583015441895) < 0.000001
    assert abs(remaining - 96.4635419845581) < 0.000001


def test_warped_or_looped_clip_is_rejected():
    assert timing_from_clip(
        is_audio_clip=True,
        warping=True,
        looping=False,
        start_marker=0,
        end_marker=100,
        playing_position=10,
    ) is None

    assert timing_from_clip(
        is_audio_clip=True,
        warping=False,
        looping=True,
        start_marker=0,
        end_marker=100,
        playing_position=10,
    ) is None
