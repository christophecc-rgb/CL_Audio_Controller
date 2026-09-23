import app


class FakeLive:
    def __init__(self, playing, jump_works=True):
        self.playing = playing
        self.position = 64.0
        self.jump_works = jump_works
        self.commands = []

    def send(self, address, *args):
        self.commands.append((address, args))
        if address == "/live/song/continue_playing":
            self.playing = True
        elif address == "/live/song/set/current_song_time" and self.jump_works:
            self.position = float(args[0])
        return True

    def query(self, address):
        if address == "/live/song/get/is_playing":
            return (int(self.playing),)
        if address == "/live/song/get/current_song_time":
            return (self.position,)
        raise AssertionError(address)


def setup_live(monkeypatch, playing, jump_works=True):
    live = FakeLive(playing, jump_works)
    monkeypatch.setattr(app.ableton_transport, "send", live.send)
    monkeypatch.setattr(app, "query", lambda address, **kwargs: live.query(address))
    monkeypatch.setattr(app, "generation_is_current", lambda generation: True)
    monkeypatch.setattr(app, "send_midi_monitor_scene_context", lambda *args: None)
    return live


def addresses(live):
    return [address for address, _ in live.commands]


def test_go_while_live_is_playing_does_not_continue(monkeypatch):
    live = setup_live(monkeypatch, playing=True)

    ok, _ = app.execute_arrangement_marker_go(128.0, "B", 1, 7)

    assert ok
    assert addresses(live) == [
        "/live/song/set/back_to_arranger",
        "/live/song/set/current_song_time",
    ]


def test_go_after_pause_continues_before_setting_time(monkeypatch):
    live = setup_live(monkeypatch, playing=False)

    ok, _ = app.execute_arrangement_marker_go(128.0, "B", 1, 7)

    assert ok
    assert addresses(live) == [
        "/live/song/set/back_to_arranger",
        "/live/song/continue_playing",
        "/live/song/set/current_song_time",
    ]


def test_resume_without_target_jump_returns_409(monkeypatch):
    live = setup_live(monkeypatch, playing=False, jump_works=False)
    monkeypatch.setattr(app, "show_arrangement_view", lambda: None)
    monkeypatch.setattr(app, "write_keyboard_diagnostic", lambda record: None)
    monkeypatch.setattr(app, "state", {**app.state, "set_ready": True, "set_generation": 7})

    response = app.app.test_client().post("/action", json={
        "action": "arrangement_play_marker", "name": "B", "time": 128.0,
        "cue_index": 1,
    })

    assert response.status_code == 409
    assert response.json["go_confirmed"] is False
    assert "locator demandé" in response.json["message"]
    assert "/live/song/continue_playing" in addresses(live)


def test_target_reached_while_playing_returns_confirmed_go(monkeypatch):
    live = setup_live(monkeypatch, playing=False)
    monkeypatch.setattr(app, "show_arrangement_view", lambda: None)
    monkeypatch.setattr(app, "write_keyboard_diagnostic", lambda record: None)
    monkeypatch.setattr(app, "state", {**app.state, "set_ready": True, "set_generation": 7})

    response = app.app.test_client().post("/action", json={
        "action": "arrangement_play_marker", "name": "B", "time": 128.0,
        "cue_index": 1,
    })

    assert response.status_code == 200
    assert response.json["go_confirmed"] is True
    assert addresses(live).index("/live/song/continue_playing") < addresses(live).index(
        "/live/song/set/current_song_time"
    )
