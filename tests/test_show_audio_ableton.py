from show_audio_ableton import (
    ShowAudioAbletonAdapter,
    beats_to_seconds,
    normalize_names,
)


class FakeAbleton:
    def __init__(self):
        self.calls = []

    def query(self, address, *args, **kwargs):
        self.calls.append(
            (address, args, kwargs)
        )

        if address == "/live/song/get/scenes/name":
            return [
                "01 INTRO",
                "02 JADE ROXY",
                "03 FINAL",
            ]

        if address == "/live/song/get/track_names":
            return [
                "TABLEAUX",
                "LTC",
                "CLICK",
            ]

        if address == "/live/song/get/tempo":
            return [120]

        if address == "/live/clip/get/length":
            if args == (0, 1):
                return [64]
            return []

        return []


def test_normalize_names():
    assert normalize_names(
        [" INTRO ", "JADE"]
    ) == [
        "INTRO",
        "JADE",
    ]


def test_beats_to_seconds():
    assert beats_to_seconds(
        64,
        120,
    ) == 32.0

    assert beats_to_seconds(
        64,
        0,
    ) is None


def test_list_scenes():
    fake = FakeAbleton()
    adapter = ShowAudioAbletonAdapter(
        fake.query
    )

    assert adapter.list_scenes()[1] == {
        "scene_index": 1,
        "scene_number": 2,
        "scene_name": "02 JADE ROXY",
    }


def test_list_tracks():
    fake = FakeAbleton()
    adapter = ShowAudioAbletonAdapter(
        fake.query
    )

    assert adapter.list_tracks()[0] == {
        "track_index": 0,
        "track_number": 1,
        "track_name": "TABLEAUX",
    }


def test_clip_duration_seconds():
    fake = FakeAbleton()
    adapter = ShowAudioAbletonAdapter(
        fake.query
    )

    assert (
        adapter.get_clip_duration_seconds(
            0,
            1,
        )
        == 32.0
    )


def test_match_variant_by_index():
    fake = FakeAbleton()
    adapter = ShowAudioAbletonAdapter(
        fake.query
    )

    result = adapter.match_variant({
        "scene_index": 1,
        "scene_name": "02 JADE ROXY",
    })

    assert result["status"] == "matched"
    assert (
        result["scene"]["scene_name"]
        == "02 JADE ROXY"
    )


def test_detect_name_mismatch():
    fake = FakeAbleton()
    adapter = ShowAudioAbletonAdapter(
        fake.query
    )

    result = adapter.match_variant({
        "scene_index": 1,
        "scene_name": "02 JADE LEO",
    })

    assert result["status"] == "mismatch"
    assert (
        result["scene"]["scene_name"]
        == "02 JADE ROXY"
    )


def test_match_by_name_without_index():
    fake = FakeAbleton()
    adapter = ShowAudioAbletonAdapter(
        fake.query
    )

    result = adapter.match_variant({
        "scene_index": None,
        "scene_name": "03 FINAL",
    })

    assert result["status"] == "matched"
    assert (
        result["scene"]["scene_index"]
        == 2
    )


def test_missing_scene():
    fake = FakeAbleton()
    adapter = ShowAudioAbletonAdapter(
        fake.query
    )

    result = adapter.match_variant({
        "scene_index": None,
        "scene_name": "99 ABSENT",
    })

    assert result["status"] == "missing"
    assert result["scene"] is None


def test_adapter_only_uses_get_addresses():
    fake = FakeAbleton()
    adapter = ShowAudioAbletonAdapter(
        fake.query
    )

    adapter.list_scenes()
    adapter.list_tracks()
    adapter.get_tempo()
    adapter.get_clip_length_beats(
        0,
        1,
    )

    addresses = [
        call[0]
        for call in fake.calls
    ]

    assert addresses
    assert all(
        "/get/" in address
        for address in addresses
    )
