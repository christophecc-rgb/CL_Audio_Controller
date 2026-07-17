import importlib.util
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def load_app_module():
    spec = importlib.util.spec_from_file_location("cl_audio_controller_app_test", PROJECT_ROOT / "app.py")
    module = importlib.util.module_from_spec(spec)
    with mock.patch.object(subprocess, "run") as mocked_run:
        mocked_run.return_value.stdout = ""
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
    return module


class LiveSetGenerationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = load_app_module()

    def setUp(self):
        with self.app.lock:
            self.app.completed_go_requests.clear()
            self.app.state["set_generation"] = 3
            self.app.state["set_ready"] = True
            self.app.state["current_set_id"] = "/Sets/ancien.als"
            self.app.state["current_set_name"] = "ancien"
            self.app.state["selected_scene"] = 8
            self.app.state["selected_scene_name"] = "Ancienne prochaine"
            self.app.state["playing_scene"] = 7
            self.app.state["playing_scene_name"] = "Ancienne en cours"
            self.app.state["last_fired_scene"] = 7
            self.app.state["last_fired_scene_name"] = "Ancienne en cours"
            self.app.state["current_scene"] = 7
            self.app.state["next_scene"] = 8
            self.app.state["has_show_started"] = True
            self.app.state["scenes"] = {7: "Ancienne en cours", 8: "Ancienne prochaine"}

    def run_confirmed_go(self, request_id, generation, scene_number, sent):
        def confirm_selected(address, *args, **kwargs):
            self.assertEqual(address, "/live/view/get/selected_scene")
            return (scene_number - 1,)

        with (
            mock.patch.object(self.app, "show_session_view"),
            mock.patch.object(self.app, "send", side_effect=lambda address, *args: sent.append((address, args))),
            mock.patch.object(self.app, "_query_with_query_lock_held", side_effect=confirm_selected),
        ):
            return self.app.execute_go_transaction(request_id, generation, scene_number)

    def test_startup_reset_is_atomic_and_clears_previous_titles(self):
        with self.app.lock:
            generation = self.app.reset_live_set_state_locked(None, "startup")
            snapshot = self.app.state_snapshot_locked()

        self.assertEqual(generation, 4)
        self.assertEqual(snapshot["set_generation"], 4)
        self.assertEqual(snapshot["current_set_id"], "pending:4")
        self.assertIsNone(snapshot["current_scene"])
        self.assertIsNone(snapshot["next_scene"])
        self.assertFalse(snapshot["has_show_started"])
        self.assertFalse(snapshot["set_ready"])
        self.assertEqual(snapshot["playing_scene_name"], "—")
        self.assertEqual(snapshot["selected_scene_name"], "—")
        self.assertEqual(snapshot["scenes"], {})

    def test_not_ready_snapshot_never_publishes_titles(self):
        with self.app.lock:
            self.app.state.update({
                "set_ready": False,
                "selected_scene_name": "Ancienne prochaine",
                "playing_scene_name": "Ancienne en cours",
                "scenes": {4: "Ancienne scène"},
                "arrangement_markers": [{"name": "Ancien repère", "time": 0}],
            })
            snapshot = self.app.state_snapshot_locked()

        self.assertEqual(snapshot["scenes"], {})
        self.assertEqual(snapshot["selected_scene_name"], "—")
        self.assertEqual(snapshot["playing_scene_name"], "—")
        self.assertEqual(snapshot["arrangement_markers"], [])
        self.assertFalse(snapshot["has_show_started"])

    def test_file_path_change_creates_a_new_generation_without_startup(self):
        replies = {
            "/live/song/get/file_path": ("/Sets/nouveau.als",),
            "/live/song/get/name": ("nouveau",),
        }
        with mock.patch.object(self.app, "query", side_effect=lambda address, *args, **kwargs: replies[address]):
            generation = self.app.refresh_live_set_identity(expected_generation=3)

        with self.app.lock:
            snapshot = self.app.state_snapshot_locked()
        self.assertEqual(generation, 4)
        self.assertEqual(snapshot["current_set_id"], "/Sets/nouveau.als")
        self.assertEqual(snapshot["current_set_name"], "nouveau")
        self.assertFalse(snapshot["has_show_started"])
        self.assertEqual(snapshot["playing_scene_name"], "—")

    def test_same_path_does_not_create_a_generation(self):
        replies = {
            "/live/song/get/file_path": ("/Sets/ancien.als",),
            "/live/song/get/name": ("ancien",),
        }
        with mock.patch.object(self.app, "query", side_effect=lambda address, *args, **kwargs: replies[address]):
            generation = self.app.refresh_live_set_identity(expected_generation=3)
        self.assertEqual(generation, 3)

    def test_same_name_in_another_folder_creates_a_generation(self):
        replies = {
            "/live/song/get/file_path": ("/Autre dossier/ancien.als",),
            "/live/song/get/name": ("ancien",),
        }
        with mock.patch.object(self.app, "query", side_effect=lambda address, *args, **kwargs: replies[address]):
            generation = self.app.refresh_live_set_identity(expected_generation=3)
        self.assertEqual(generation, 4)
        self.assertEqual(self.app.state["current_set_id"], "/Autre dossier/ancien.als")

    def test_unsaved_set_gets_a_generation_scoped_identity(self):
        with self.app.lock:
            self.app.state["current_set_id"] = None
        replies = {
            "/live/song/get/file_path": ("",),
            "/live/song/get/name": ("",),
        }
        with mock.patch.object(self.app, "query", side_effect=lambda address, *args, **kwargs: replies[address]):
            generation = self.app.refresh_live_set_identity(expected_generation=3)
        self.assertEqual(generation, 4)
        self.assertEqual(self.app.state["current_set_id"], "unsaved:4")

    def test_saved_to_unsaved_transition_creates_a_generation(self):
        replies = {
            "/live/song/get/file_path": ("",),
            "/live/song/get/name": ("",),
        }
        with mock.patch.object(self.app, "query", side_effect=lambda address, *args, **kwargs: replies[address]):
            generation = self.app.refresh_live_set_identity(expected_generation=3)
        self.assertEqual(generation, 4)
        self.assertEqual(self.app.state["current_set_id"], "unsaved:4")

    def test_missing_file_path_reply_does_not_simulate_an_unsaved_set(self):
        replies = {
            "/live/song/get/file_path": None,
            "/live/song/get/name": None,
        }
        with mock.patch.object(self.app, "query", side_effect=lambda address, *args, **kwargs: replies[address]):
            generation = self.app.refresh_live_set_identity(expected_generation=3)
        self.assertIsNone(generation)
        self.assertEqual(self.app.state["current_set_id"], "/Sets/ancien.als")

    def test_stale_osc_payload_is_not_applied(self):
        with self.app.lock:
            self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")
            self.app.apply_osc_response_locked(
                "/live/scene/get/name",
                (7, "Ancienne en cours"),
                expected_generation=3,
            )
            snapshot = self.app.state_snapshot_locked()
        self.assertNotIn(7, snapshot["scenes"])
        self.assertEqual(snapshot["selected_scene_name"], "—")

    def test_late_osc_reply_from_previous_set_is_ignored(self):
        with self.app.lock:
            self.app.active_query = {
                "address": "/live/scene/get/name",
                "args": (7,),
                "generation": 3,
                "allow_during_bootstrap": False,
                "response": None,
            }
            self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")

        self.app.osc_reply("/live/scene/get/name", 7, "Ancienne en cours")

        with self.app.lock:
            snapshot = self.app.state_snapshot_locked()
            active_query = self.app.active_query
        self.assertIsNone(active_query)
        self.assertEqual(snapshot["scenes"], {})
        self.assertEqual(snapshot["playing_scene_name"], "—")

    def test_bootstrap_atomically_replaces_scenes_and_resolves_selection(self):
        with self.app.lock:
            old_scenes = self.app.state["scenes"]
            generation = self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")
            before = self.app.state_snapshot_locked()
            applied = self.app.apply_live_set_bootstrap_locked(
                generation,
                "/Sets/nouveau.als",
                "nouveau",
                1,
                ("Nouvelle ouverture", "Nouveau final"),
            )
            after = self.app.state_snapshot_locked()

        self.assertFalse(before["set_ready"])
        self.assertFalse(before["has_show_started"])
        self.assertEqual(before["playing_scene_name"], "—")
        self.assertTrue(applied)
        self.assertTrue(after["set_ready"])
        self.assertIsNot(self.app.state["scenes"], old_scenes)
        self.assertEqual(after["scenes"], {0: "Nouvelle ouverture", 1: "Nouveau final"})
        self.assertNotIn("Ancienne", " ".join(after["scenes"].values()))
        self.assertEqual(after["selected_scene"], 1)
        self.assertEqual(after["selected_scene_name"], "Nouveau final")
        self.assertFalse(after["has_show_started"])
        self.assertIsNone(after["current_scene"])
        self.assertEqual(after["playing_scene_name"], "—")

    def test_set_ready_requires_a_complete_matching_bootstrap(self):
        with self.app.lock:
            generation = self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")
            rejected = self.app.apply_live_set_bootstrap_locked(
                generation - 1,
                "/Sets/nouveau.als",
                "nouveau",
                0,
                ("Nouvelle scène",),
            )
            still_not_ready = self.app.state_snapshot_locked()

        self.assertFalse(rejected)
        self.assertFalse(still_not_ready["set_ready"])

    def test_incomplete_bootstrap_never_sets_ready(self):
        with self.app.lock:
            generation = self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")
            self.app._bootstrap_generation = generation

        replies = {
            "/live/song/get/name": ("nouveau",),
            "/live/view/get/selected_scene": (0,),
            "/live/song/get/scenes/name": None,
        }
        with (
            mock.patch.object(self.app.time, "sleep"),
            mock.patch.object(self.app, "_bootstrap_file_path", side_effect=["/Sets/nouveau.als", "/Sets/nouveau.als"]),
            mock.patch.object(self.app, "query", side_effect=lambda address, *args, **kwargs: replies[address]),
        ):
            self.app.bootstrap_live_set(generation)

        with self.app.lock:
            snapshot = self.app.state_snapshot_locked()
        self.assertFalse(snapshot["set_ready"])
        self.assertEqual(snapshot["scenes"], {})
        self.assertEqual(snapshot["playing_scene_name"], "—")

    def test_complete_bootstrap_uses_grouped_scene_snapshot(self):
        with self.app.lock:
            generation = self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")
            self.app._bootstrap_generation = generation

        replies = {
            "/live/song/get/file_path": ("/Sets/nouveau.als",),
            "/live/song/get/name": ("nouveau",),
            "/live/view/get/selected_scene": (1,),
            "/live/song/get/scenes/name": ("Ouverture", "Final"),
        }

        def reply_immediately(address, *args):
            self.app.osc_reply(address, *replies[address])

        with (
            mock.patch.object(self.app.time, "sleep"),
            mock.patch.object(self.app, "send", side_effect=reply_immediately),
        ):
            self.app.bootstrap_live_set(generation)

        with self.app.lock:
            snapshot = self.app.state_snapshot_locked()
        self.assertTrue(snapshot["set_ready"])
        self.assertEqual(snapshot["scenes"], {0: "Ouverture", 1: "Final"})
        self.assertEqual(snapshot["selected_scene_name"], "Final")
        self.assertEqual(snapshot["playing_scene_name"], "—")

    def test_late_arrangement_response_cannot_update_cache(self):
        with self.app.lock:
            self.app._cue_points_cache = (0.0, [], "JSON")

        def delayed_query(*args, **kwargs):
            with self.app.lock:
                self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")
            return ("Ancien repère", 64.0)

        with mock.patch.object(self.app, "query", side_effect=delayed_query):
            markers, source = self.app.get_live_cue_points(force=True, expected_generation=3)

        self.assertEqual(markers, [])
        self.assertEqual(source, "STALE")
        self.assertEqual(self.app._cue_points_cache, (0.0, [], "JSON"))

    def test_cycle_stops_immediately_when_identity_changes(self):
        def change_generation(_generation):
            with self.app.lock:
                return self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")

        with (
            mock.patch.object(self.app, "refresh_live_set_identity", side_effect=change_generation),
            mock.patch.object(self.app, "start_live_set_bootstrap") as start_bootstrap,
            mock.patch.object(self.app, "query") as query,
        ):
            ready = self.app.refresh_names_and_transport()

        self.assertFalse(ready)
        start_bootstrap.assert_called_once_with(4)
        query.assert_not_called()

    def test_all_web_interfaces_reject_older_generations(self):
        reset_helpers = {
            "templates/index.html": "resetSessionUiForGeneration",
            "templates/ab.html": "resetAbUiForGeneration",
            "templates/arrangement.html": "resetArrangementUiForGeneration",
        }
        for relative_path, reset_helper in reset_helpers.items():
            source = (PROJECT_ROOT / relative_path).read_text(encoding="utf-8")
            self.assertIn("generation < lastAcceptedGeneration", source)
            self.assertIn("if (!acceptStateGeneration(state)) return;", source)
            self.assertIn(f"function {reset_helper}()", source)
            self.assertIn(f"{reset_helper}();", source)

    def test_scene_selects_are_cleared_at_generation_boundary(self):
        session_source = (PROJECT_ROOT / "templates/index.html").read_text(encoding="utf-8")
        ab_source = (PROJECT_ROOT / "templates/ab.html").read_text(encoding="utf-8")
        self.assertIn("gotoInput.innerHTML = '<option", session_source)
        self.assertIn("abSceneSelectEl.innerHTML = '<option", ab_source)

    def test_multiple_rapid_go_commands_launch_their_explicit_scenes(self):
        sent = []
        first = self.run_confirmed_go("go-1", 3, 8, sent)
        second = self.run_confirmed_go("go-2", 3, 9, sent)

        self.assertTrue(first[0])
        self.assertTrue(second[0])
        fired = [args[0] for address, args in sent if address == "/live/scene/fire_as_selected"]
        self.assertEqual(fired, [7, 8])

    def test_selection_change_during_go_does_not_change_requested_scene(self):
        sent = []

        def confirm_after_concurrent_selection(address, *args, **kwargs):
            with self.app.lock:
                self.app.state["selected_scene"] = 8
            return (7,)

        with (
            mock.patch.object(self.app, "show_session_view"),
            mock.patch.object(self.app, "send", side_effect=lambda address, *args: sent.append((address, args))),
            mock.patch.object(
                self.app,
                "_query_with_query_lock_held",
                side_effect=confirm_after_concurrent_selection,
            ),
        ):
            ok, _ = self.app.execute_go_transaction("go-selection-race", 3, 8)

        self.assertTrue(ok)
        self.assertIn(("/live/scene/fire_as_selected", (7,)), sent)

    def test_live_set_change_during_go_aborts_before_fire(self):
        sent = []

        def change_set_before_confirmation(address, *args, **kwargs):
            with self.app.lock:
                self.app.reset_live_set_state_locked("/Sets/nouveau.als", "test")
            return (7,)

        with (
            mock.patch.object(self.app, "show_session_view"),
            mock.patch.object(self.app, "send", side_effect=lambda address, *args: sent.append((address, args))),
            mock.patch.object(
                self.app,
                "_query_with_query_lock_held",
                side_effect=change_set_before_confirmation,
            ),
        ):
            ok, message = self.app.execute_go_transaction("go-set-change", 3, 8)

        self.assertFalse(ok)
        self.assertIn("modifié", message)
        self.assertFalse(any(address == "/live/scene/fire_as_selected" for address, _ in sent))

    def test_out_of_order_confirmation_is_ignored_until_requested_scene_is_seen(self):
        sent = []
        replies = iter([(8,), (7,)])
        with (
            mock.patch.object(self.app, "show_session_view"),
            mock.patch.object(self.app, "send", side_effect=lambda address, *args: sent.append((address, args))),
            mock.patch.object(
                self.app,
                "_query_with_query_lock_held",
                side_effect=lambda *args, **kwargs: next(replies),
            ) as confirmation,
        ):
            ok, _ = self.app.execute_go_transaction("go-reordered", 3, 8)

        self.assertTrue(ok)
        self.assertEqual(confirmation.call_count, 2)
        self.assertIn(("/live/scene/fire_as_selected", (7,)), sent)

    def test_duplicate_request_id_fires_only_once(self):
        sent = []
        first = self.run_confirmed_go("same-request", 3, 8, sent)
        second = self.run_confirmed_go("same-request", 3, 8, sent)

        self.assertTrue(first[0])
        self.assertTrue(second[0])
        fired = [item for item in sent if item[0] == "/live/scene/fire_as_selected"]
        self.assertEqual(len(fired), 1)

    def test_go_is_rejected_while_set_is_not_ready(self):
        with self.app.lock:
            self.app.state["set_ready"] = False
        with mock.patch.object(self.app, "send") as send:
            ok, message = self.app.execute_go_transaction("go-not-ready", 3, 8)

        self.assertFalse(ok)
        self.assertIn("chargement", message)
        send.assert_not_called()

    def test_web_go_payloads_are_transactional_and_ab_has_no_fixed_wait(self):
        session_source = (PROJECT_ROOT / "templates/index.html").read_text(encoding="utf-8")
        ab_source = (PROJECT_ROOT / "templates/ab.html").read_text(encoding="utf-8")

        for source in (session_source, ab_source):
            self.assertIn("request_id", source)
            self.assertIn("set_generation", source)
            self.assertIn("scene:", source)
        self.assertNotIn("await wait(350)", ab_source)

    def test_keyboard_shortcuts_share_button_handlers_on_all_interfaces(self):
        sources = {
            "session": (PROJECT_ROOT / "templates/index.html").read_text(encoding="utf-8"),
            "ab": (PROJECT_ROOT / "templates/ab.html").read_text(encoding="utf-8"),
            "arrangement": (PROJECT_ROOT / "templates/arrangement.html").read_text(encoding="utf-8"),
        }

        expected_handlers = {
            "session": ("act('go');", "act('pause');"),
            "ab": ("confirmSelectedScene();", "togglePlayPauseFromKeyboard();"),
            "arrangement": ("runArrangementGo();", "runArrangementPlayPause();"),
        }
        for interface, source in sources.items():
            go_handler, play_pause_handler = expected_handlers[interface]
            self.assertIn("document.addEventListener('keydown'", source)
            self.assertIn("event.key === 'Enter'", source)
            self.assertIn("event.code === 'Space' || event.key === ' '", source)
            self.assertIn(go_handler, source)
            self.assertIn(play_pause_handler, source)

    def test_keyboard_shortcuts_protect_editable_focus_and_key_repeat(self):
        for relative_path in (
            "templates/index.html",
            "templates/ab.html",
            "templates/arrangement.html",
        ):
            source = (PROJECT_ROOT / relative_path).read_text(encoding="utf-8")
            self.assertIn("event.repeat", source)
            self.assertIn("input, textarea, select", source)
            self.assertIn("[contenteditable]", source)
            self.assertIn("keyboardShortcutBlockReason(event)", source)
            self.assertIn("[KEYBOARD]", source)

    def test_space_shortcut_prevents_page_scrolling(self):
        for relative_path in (
            "templates/index.html",
            "templates/ab.html",
            "templates/arrangement.html",
        ):
            source = (PROJECT_ROOT / relative_path).read_text(encoding="utf-8")
            space_branch = source.rsplit("if (event.code === 'Space' || event.key === ' ')", 1)[1]
            self.assertIn("event.preventDefault();", space_branch.split("}", 1)[0])


if __name__ == "__main__":
    unittest.main()
