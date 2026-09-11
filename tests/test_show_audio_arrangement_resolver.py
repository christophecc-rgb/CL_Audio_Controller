import pytest

from show_audio_arrangement_resolver import (
    ArrangementResolveError,
    normalize_arrangement_title,
    resolve_scene_zone,
    resolve_scene_zones,
)


def markers():
    return [
        {
            "name": "29. Annonce",
            "time": 19390.220703125,
        },
        {
            "name": (
                "30. En route pour le paradis_napoleon "
                "; BPM ; KEY ; 1:14"
            ),
            # VOLONTAIREMENT très loin :
            # la durée ANNONCE ne doit PAS dépendre
            # de ce locator suivant.
            "time": 20000.0,
        },
        {
            "name": (
                "31. Tableau vis a vis "
                "; BPM ; KEY ; 6:15"
            ),
            "time": 25000.0,
        },
    ]


def test_normalization_session_and_locator():
    assert (
        normalize_arrangement_title(
            "1 - EN ROUTE POUR LE PARADIS_NAPOLEON ; BPM ; KEY ; 1:14"
        )
        ==
        normalize_arrangement_title(
            "30. En route pour le paradis_napoleon ; BPM ; KEY ; 1:14"
        )
    )


def test_annonce_uses_audio_duration_not_next_locator():
    zone = resolve_scene_zone(
        {
            "scene_index": 29,
            "scene_name": "ANNONCE",
        },
        markers(),
        expected_duration_seconds=31.1875,
        tempo=120.0,
    )

    assert zone["locator_name"] == (
        "29. Annonce"
    )

    assert zone["start_beats"] == pytest.approx(
        19390.220703125
    )

    # 31.1875 s à 120 BPM = 62.375 beats.
    assert zone["duration_beats"] == pytest.approx(
        62.375
    )

    assert zone["end_beats"] == pytest.approx(
        19452.595703125
    )

    # Le locator suivant du fixture est à 20000 :
    # il NE DOIT PAS être utilisé.
    assert zone["end_beats"] != pytest.approx(
        20000.0
    )

    assert zone["duration_source"] == (
        "audio_reference"
    )


def test_numbering_does_not_drive_identity():
    zone = resolve_scene_zone(
        {
            "scene_index": 30,
            "scene_name": (
                "1 - EN ROUTE POUR LE PARADIS_NAPOLEON "
                "; BPM ; KEY ; 1:14"
            ),
        },
        markers(),
        expected_duration_seconds=74.0,
        tempo=120.0,
    )

    assert zone["locator_name"].startswith(
        "30."
    )


def test_missing_scene_is_rejected():
    with pytest.raises(
        ArrangementResolveError,
        match="aucun locator",
    ):
        resolve_scene_zone(
            {
                "scene_index": 80,
                "scene_name": "V chute d'eau",
            },
            markers(),
            expected_duration_seconds=10.0,
            tempo=120.0,
        )


def test_missing_duration_is_rejected():
    result = resolve_scene_zones(
        [
            {
                "scene_index": 29,
                "scene_name": "ANNONCE",
            }
        ],
        markers(),
        tempo=120.0,
        duration_by_scene_index={},
    )

    assert result["resolved_count"] == 0
    assert result["rejected_count"] == 1

    assert (
        "durée audio de référence absente"
        in result["rejected"][0]["reason"]
    )


def test_ambiguous_title_is_rejected():
    duplicate = markers() + [
        {
            "name": "99. Annonce",
            "time": 30000.0,
        }
    ]

    with pytest.raises(
        ArrangementResolveError,
        match="ambigu",
    ):
        resolve_scene_zone(
            {
                "scene_index": 29,
                "scene_name": "ANNONCE",
            },
            duplicate,
            expected_duration_seconds=31.1875,
            tempo=120.0,
        )


def test_last_locator_also_uses_audio_duration():
    zone = resolve_scene_zone(
        {
            "scene_index": 31,
            "scene_name": (
                "2 - TABLEAU VIS A VIS ; BPM ; KEY ; 6:15"
            ),
        },
        markers(),
        expected_duration_seconds=10.0,
        tempo=120.0,
    )

    assert zone["start_beats"] == pytest.approx(
        25000.0
    )

    assert zone["duration_beats"] == pytest.approx(
        20.0
    )

    assert zone["end_beats"] == pytest.approx(
        25020.0
    )


def test_collection_uses_explicit_audio_durations():
    result = resolve_scene_zones(
        [
            {
                "scene_index": 29,
                "scene_name": "ANNONCE",
            },
            {
                "scene_index": 30,
                "scene_name": (
                    "1 - EN ROUTE POUR LE PARADIS_NAPOLEON "
                    "; BPM ; KEY ; 1:14"
                ),
            },
        ],
        markers(),
        tempo=120.0,
        duration_by_scene_index={
            29: 31.1875,
            30: 74.0,
        },
    )

    assert result["resolved_count"] == 2
    assert result["rejected_count"] == 0

    assert result["resolved"][0][
        "duration_source"
    ] == "audio_reference"

    assert result["resolved"][1][
        "duration_source"
    ] == "audio_reference"


@pytest.mark.parametrize("problem", ["missing_scene", "missing_audio", "missing_locator", "order", "reversed", "numbers"])
def test_medley_rejects_incomplete_or_non_contiguous(problem):
    from show_audio_arrangement_resolver import resolve_medley_zone
    scenes = [{"scene_index": i, "scene_name": name, "reference": {"duration_seconds": 1}}
              for i, name in enumerate(["A", "B"])]
    markers = [{"name": "A", "time": 0}, {"name": "B", "time": 2}]
    medley = {"scene_numbers": [1, 2]}
    if problem == "missing_scene": scenes.pop()
    if problem == "missing_audio": scenes[1]["reference"] = {}
    if problem == "missing_locator": markers.pop()
    if problem == "order": markers[0]["time"], markers[1]["time"] = 2, 0
    if problem == "reversed": markers[0]["time"], markers[1]["time"] = 3, 0
    if problem == "numbers": medley["scene_numbers"] = [1, 3]
    with pytest.raises(ArrangementResolveError):
        resolve_medley_zone(medley, scenes, markers, tempo=120)


@pytest.mark.parametrize("starts, expected_end", [
    ([10, 15, 20], 22),  # Espaces internes.
    ([10, 11, 12], 14),  # Chevauchements internes.
    ([10, 15, 16], 18),  # Un espace puis un chevauchement.
])
def test_medley_global_zone_includes_internal_gaps_and_overlaps(starts, expected_end):
    from show_audio_arrangement_resolver import resolve_medley_zone
    scenes = [{"scene_index": i + 40, "scene_name": name,
               "reference": {"duration_seconds": 1}}
              for i, name in enumerate(["A", "B", "C"])]
    markers = [{"name": scene["scene_name"], "time": start}
               for scene, start in zip(scenes, starts)]
    # Le locator suivant ne définit jamais la fin du medley.
    markers.append({"name": "NEXT", "time": 1000})
    zone = resolve_medley_zone({"scene_numbers": [41, 42, 43]}, scenes, markers, tempo=120)
    assert zone["start_beats"] == starts[0]
    assert zone["end_beats"] == expected_end == starts[-1] + 2
    assert zone["duration_beats"] == zone["end_beats"] - zone["start_beats"]
    assert zone["duration_beats"] != 6  # Pas la somme des trois durées audio.
    assert zone["expected_duration_seconds"] == zone["duration_beats"] / 2
    assert zone["scene_numbers"] == [41, 42, 43]


@pytest.mark.parametrize("field", ["start", "audio", "tempo"])
@pytest.mark.parametrize("value", [float("nan"), float("inf"), float("-inf")])
def test_medley_rejects_non_finite_values(field, value):
    from show_audio_arrangement_resolver import resolve_medley_zone
    scenes = [{"scene_index": i, "scene_name": name,
               "reference": {"duration_seconds": 1}}
              for i, name in enumerate(["A", "B"])]
    markers = [{"name": "A", "time": 0}, {"name": "B", "time": 2}]
    tempo = 120
    if field == "start": markers[1]["time"] = value
    if field == "audio": scenes[1]["reference"]["duration_seconds"] = value
    if field == "tempo": tempo = value
    with pytest.raises(ArrangementResolveError):
        resolve_medley_zone({"scene_numbers": [1, 2]}, scenes, markers, tempo=tempo)
