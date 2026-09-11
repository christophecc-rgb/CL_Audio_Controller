import time


class PrintEngineError(RuntimeError):
    pass


def _last(response):
    values = list(response or [])
    return values[-1] if values else None


def capture_clean(
    *,
    query,
    send,
    fire_scene,
    generation,
    scene_index,
    slot_index,
    duration_seconds,
    sleep=time.sleep,
):
    if scene_index < 0 or slot_index < 0:
        raise PrintEngineError("index négatif")
    if not (0 < float(duration_seconds) <= 3600):
        raise PrintEngineError("durée invalide")

    names = list(query(
        "/live/song/get/track_names",
        expected_generation=generation,
        apply_response=False,
    ) or [])

    matches = [i for i, name in enumerate(names) if str(name).strip() == "RESAMPLE"]
    if len(matches) != 1:
        raise PrintEngineError("piste RESAMPLE absente ou ambiguë")

    track_index = matches[0]

    can_arm = bool(_last(query(
        "/live/track/get/can_be_armed", track_index,
        expected_generation=generation, apply_response=False,
    )))
    initial_arm = bool(_last(query(
        "/live/track/get/arm", track_index,
        expected_generation=generation, apply_response=False,
    )))
    routing = str(_last(query(
        "/live/track/get/input_routing_type", track_index,
        expected_generation=generation, apply_response=False,
    )) or "")
    has_clip = bool(_last(query(
        "/live/clip_slot/get/has_clip", track_index, slot_index,
        expected_generation=generation, apply_response=False,
    )))

    if not can_arm:
        raise PrintEngineError("RESAMPLE non armable")
    if routing != "Resampling":
        raise PrintEngineError(f"routing attendu Resampling, reçu {routing!r}")
    if has_clip:
        raise PrintEngineError("slot RESAMPLE déjà occupé")

    recording_started = False

    try:
        if not initial_arm:
            send("/live/track/set/arm", track_index, True)
            sleep(0.15)

        send("/live/clip_slot/fire", track_index, slot_index)
        recording_started = True
        sleep(0.25)

        fire_scene(scene_index)

        sleep(float(duration_seconds))

        send("/live/clip/stop", track_index, slot_index)
        recording_started = False
        sleep(0.25)

        file_path = _last(query(
            "/live/clip/get/file_path", track_index, slot_index,
            expected_generation=generation, apply_response=False,
        ))
        length = _last(query(
            "/live/clip/get/length", track_index, slot_index,
            expected_generation=generation, apply_response=False,
        ))
        is_recording = bool(_last(query(
            "/live/clip/get/is_recording", track_index, slot_index,
            expected_generation=generation, apply_response=False,
        )))

        if not file_path:
            raise PrintEngineError("WAV enregistré sans file_path")
        if is_recording:
            raise PrintEngineError("clip encore en enregistrement après stop")

        return {
            "track_index": track_index,
            "slot_index": slot_index,
            "scene_index": scene_index,
            "file_path": str(file_path),
            "clip_length_beats": length,
            "is_recording": False,
        }

    finally:
        if recording_started:
            try:
                send("/live/clip/stop", track_index, slot_index)
            except Exception:
                pass

        if not initial_arm:
            try:
                send("/live/track/set/arm", track_index, False)
            except Exception:
                pass
