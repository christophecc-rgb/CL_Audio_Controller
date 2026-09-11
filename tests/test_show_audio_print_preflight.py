import app as app_module


def _client():
    app_module.app.config["TESTING"] = True
    return app_module.app.test_client()


def _set_ready(monkeypatch):
    with app_module.lock:
        app_module.state["set_ready"] = True
        app_module.state["set_generation"] = 1
        app_module.state["current_set_name"] = "TEST SET"


def test_print_preflight_ready_empty_slot(monkeypatch):
    _set_ready(monkeypatch)

    def fake_query(address, *args, **kwargs):
        mapping = {
            "/live/song/get/track_names": ["RESAMPLE", "OTHER"],
            "/live/track/get/can_be_armed": [0, True],
            "/live/track/get/arm": [0, False],
            "/live/track/get/input_routing_type": [0, "Resampling"],
            "/live/track/get/available_input_routing_types": [
                0,
                "Ext. In",
                "Resampling",
            ],
            "/live/clip_slot/get/has_clip": [0, 0, False],
        }
        return mapping[address]

    monkeypatch.setattr(app_module, "query", fake_query)

    response = _client().get("/show-audio/print/preflight?slot_index=0")
    data = response.get_json()

    assert response.status_code == 200
    assert data["ok"] is True
    assert data["track_name"] == "RESAMPLE"
    assert data["track_index"] == 0
    assert data["can_be_armed"] is True
    assert data["armed"] is False
    assert data["input_routing_type"] == "Resampling"
    assert data["slot_has_clip"] is False
    assert data["safe_for_test"] is True
    assert data["reasons"] == []


def test_print_preflight_missing_track(monkeypatch):
    _set_ready(monkeypatch)

    monkeypatch.setattr(
        app_module,
        "query",
        lambda address, *args, **kwargs: ["OTHER"],
    )

    response = _client().get("/show-audio/print/preflight")
    data = response.get_json()

    assert response.status_code == 404
    assert data["ok"] is False
    assert "introuvable" in data["error"]


def test_print_preflight_duplicate_track(monkeypatch):
    _set_ready(monkeypatch)

    monkeypatch.setattr(
        app_module,
        "query",
        lambda address, *args, **kwargs: ["RESAMPLE", "RESAMPLE"],
    )

    response = _client().get("/show-audio/print/preflight")
    data = response.get_json()

    assert response.status_code == 409
    assert data["ok"] is False
    assert data["track_indices"] == [0, 1]


def test_print_preflight_cannot_arm(monkeypatch):
    _set_ready(monkeypatch)

    def fake_query(address, *args, **kwargs):
        mapping = {
            "/live/song/get/track_names": ["RESAMPLE"],
            "/live/track/get/can_be_armed": [0, False],
            "/live/track/get/arm": [0, False],
            "/live/track/get/input_routing_type": [0, "Resampling"],
            "/live/track/get/available_input_routing_types": [0, "Resampling"],
            "/live/clip_slot/get/has_clip": [0, 0, False],
        }
        return mapping[address]

    monkeypatch.setattr(app_module, "query", fake_query)

    response = _client().get("/show-audio/print/preflight")
    data = response.get_json()

    assert response.status_code == 200
    assert data["can_be_armed"] is False
    assert data["safe_for_test"] is False


def test_print_preflight_occupied_slot(monkeypatch):
    _set_ready(monkeypatch)

    def fake_query(address, *args, **kwargs):
        mapping = {
            "/live/song/get/track_names": ["RESAMPLE"],
            "/live/track/get/can_be_armed": [0, True],
            "/live/track/get/arm": [0, False],
            "/live/track/get/input_routing_type": [0, "Resampling"],
            "/live/track/get/available_input_routing_types": [0, "Resampling"],
            "/live/clip_slot/get/has_clip": [0, 0, True],
        }
        return mapping[address]

    monkeypatch.setattr(app_module, "query", fake_query)

    response = _client().get("/show-audio/print/preflight")
    data = response.get_json()

    assert response.status_code == 200
    assert data["slot_has_clip"] is True
    assert data["safe_for_test"] is False


def test_print_preflight_invalid_slot():
    response = _client().get("/show-audio/print/preflight?slot_index=abc")
    assert response.status_code == 400

    response = _client().get("/show-audio/print/preflight?slot_index=-1")
    assert response.status_code == 400


def test_print_preflight_osc_error(monkeypatch):
    _set_ready(monkeypatch)

    def fake_query(address, *args, **kwargs):
        if address == "/live/song/get/track_names":
            return ["RESAMPLE"]
        raise RuntimeError("boom")

    monkeypatch.setattr(app_module, "query", fake_query)

    response = _client().get("/show-audio/print/preflight")
    data = response.get_json()

    assert response.status_code == 502
    assert data["ok"] is False
    assert "AbletonOSC" in data["error"]
