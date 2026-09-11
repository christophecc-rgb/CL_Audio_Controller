import pytest

from show_audio_print_engine import PrintEngineError, capture_clean


def make_query(*, occupied=False, routing="Resampling", can_arm=True):
    def query(address, *args, **kwargs):
        values = {
            "/live/song/get/track_names": ["RESAMPLE", "PLAYBACK"],
            "/live/track/get/can_be_armed": [0, can_arm],
            "/live/track/get/arm": [0, False],
            "/live/track/get/input_routing_type": [0, routing],
            "/live/clip_slot/get/has_clip": [0, 0, occupied],
            "/live/clip/get/file_path": [0, 0, "/tmp/test.wav"],
            "/live/clip/get/length": [0, 0, 10.0],
            "/live/clip/get/is_recording": [0, 0, False],
        }
        return values[address]
    return query


def test_capture_clean_success():
    sent = []
    fired = []

    result = capture_clean(
        query=make_query(),
        send=lambda a, *x: sent.append((a, x)),
        fire_scene=lambda i: fired.append(i),
        generation=1,
        scene_index=4,
        slot_index=0,
        duration_seconds=1,
        sleep=lambda _: None,
    )

    assert result["file_path"] == "/tmp/test.wav"
    assert fired == [4]
    assert ("/live/clip_slot/fire", (0, 0)) in sent
    assert ("/live/clip/stop", (0, 0)) in sent
    assert sent[-1] == ("/live/track/set/arm", (0, False))


@pytest.mark.parametrize("kwargs", [
    {"occupied": True},
    {"routing": "No Input"},
    {"can_arm": False},
])
def test_preflight_refuses_unsafe_state(kwargs):
    with pytest.raises(PrintEngineError):
        capture_clean(
            query=make_query(**kwargs),
            send=lambda *a: None,
            fire_scene=lambda i: None,
            generation=1,
            scene_index=1,
            slot_index=0,
            duration_seconds=1,
            sleep=lambda _: None,
        )


def test_restores_arm_if_scene_fire_fails():
    sent = []

    def boom(_):
        raise RuntimeError("boom")

    with pytest.raises(RuntimeError):
        capture_clean(
            query=make_query(),
            send=lambda a, *x: sent.append((a, x)),
            fire_scene=boom,
            generation=1,
            scene_index=1,
            slot_index=0,
            duration_seconds=1,
            sleep=lambda _: None,
        )

    assert ("/live/clip/stop", (0, 0)) in sent
    assert sent[-1] == ("/live/track/set/arm", (0, False))
