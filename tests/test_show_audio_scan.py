import pytest

from show_audio_scan import (
    ReadOnlyOSCQuery,
    format_duration,
    is_read_only_address,
)


class FakeTransport:
    def __init__(self):
        self.calls = []

    def query(
        self,
        address,
        *args,
        timeout,
        context=None,
    ):
        self.calls.append(
            (address, args, timeout)
        )
        return ("ok",)


def test_get_addresses_are_allowed():
    assert is_read_only_address(
        "/live/song/get/scenes/name"
    )
    assert is_read_only_address(
        "/live/song/get/tempo"
    )
    assert is_read_only_address(
        "/live/clip/get/length"
    )


def test_mutating_addresses_are_rejected():
    assert not is_read_only_address(
        "/live/scene/fire"
    )
    assert not is_read_only_address(
        "/live/scene/fire_as_selected"
    )
    assert not is_read_only_address(
        "/live/view/set/selected_scene"
    )
    assert not is_read_only_address(
        "/live/song/stop_playing"
    )
    assert not is_read_only_address(
        "/live/song/continue_playing"
    )


def test_non_live_address_is_rejected():
    assert not is_read_only_address(
        "/foo/get/bar"
    )


def test_query_wrapper_calls_transport():
    transport = FakeTransport()

    query = ReadOnlyOSCQuery(
        transport,
        timeout=0.42,
    )

    result = query(
        "/live/song/get/tempo",
        apply_response=False,
    )

    assert result == ("ok",)

    assert transport.calls == [
        (
            "/live/song/get/tempo",
            (),
            0.42,
        )
    ]


def test_query_wrapper_can_override_timeout():
    transport = FakeTransport()

    query = ReadOnlyOSCQuery(
        transport,
        timeout=0.42,
    )

    query(
        "/live/song/get/tempo",
        timeout=0.10,
    )

    assert transport.calls[0][2] == 0.10


def test_query_wrapper_blocks_mutation():
    transport = FakeTransport()
    query = ReadOnlyOSCQuery(transport)

    with pytest.raises(RuntimeError):
        query(
            "/live/scene/fire_as_selected",
            12,
        )

    assert transport.calls == []


def test_duration_format():
    assert format_duration(None) == "--:--"
    assert format_duration(0) == "00:00"
    assert format_duration(32) == "00:32"
    assert format_duration(207) == "03:27"
    assert format_duration(3723) == "01:02:03"
