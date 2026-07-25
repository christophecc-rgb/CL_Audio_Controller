import importlib.util
import re
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
            self.app._bootstrap_generation = None
            self.app._bootstrap_transaction = None
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
            mock.patch.object(self.app, "resolve_scene_clip_duration_async"),
        ):
            return self.app.execute_go_transaction(request_id, generation, scene_number)

    def post_action_with_playing_reply(self, action_name, playing, sent):
        with (
            mock.patch.object(
                self.app,
                "query",
                return_value=(1 if playing else 0,),
            ) as query_playing,
            mock.patch.object(
                self.app,
                "send",
                side_effect=lambda address, *args: sent.append((address, args)),
            ),
        ):
            response = self.app.app.test_client().post(
                "/action",
                json={"action": action_name},
            )
        return response, query_playing

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

    def test_pause_uses_confirmed_live_state_instead_of_stale_stopped_cache(self):
        sent = []
        with self.app.lock:
            self.app.state["is_playing"] = False
            self.app.state["is_paused"] = False
            self.app.state["play_mode"] = "session"

        response, query_playing = self.post_action_with_playing_reply("pause", True, sent)

        self.assertEqual(response.status_code, 200)
        query_playing.assert_called_once_with(
            "/live/song/get/is_playing",
            timeout=0.20,
            expected_generation=3,
        )
        self.assertIn(("/live/song/stop_playing", ()), sent)
        self.assertNotIn(("/live/song/continue_playing", ()), sent)

    def test_pause_uses_confirmed_live_state_instead_of_stale_playing_cache(self):
        sent = []
        with self.app.lock:
            self.app.state["is_playing"] = True
            self.app.state["is_paused"] = True
            self.app.state["play_mode"] = "session"

        response, _ = self.post_action_with_playing_reply("pause", False, sent)

        self.assertEqual(response.status_code, 200)
        self.assertIn(("/live/song/continue_playing", ()), sent)
        self.assertNotIn(("/live/song/stop_playing", ()), sent)

    def test_arrangement_toggle_uses_confirmed_live_state(self):
        sent = []
        with self.app.lock:
            self.app.state["is_playing"] = False
            self.app.state["is_paused"] = False
            self.app.state["play_mode"] = "arrangement"

        response, _ = self.post_action_with_playing_reply(
            "arrangement_toggle",
            True,
            sent,
        )

        self.assertEqual(response.status_code, 200)
        self.assertIn(("/live/song/stop_playing", ()), sent)
        self.assertNotIn(("/live/song/continue_playing", ()), sent)

    def test_toggle_refuses_if_generation_changes_during_confirmation(self):
        def change_generation(*args, **kwargs):
            with self.app.lock:
                self.app.state["set_generation"] = 4
                self.app.state["set_ready"] = False
            return (1,)

        with (
            mock.patch.object(self.app, "query", side_effect=change_generation),
            mock.patch.object(self.app, "send") as send,
        ):
            response = self.app.app.test_client().post(
                "/action",
                json={"action": "pause"},
            )

        self.assertEqual(response.status_code, 409)
        send.assert_not_called()

    def test_missing_name_refresh_does_not_erase_bootstrapped_name(self):
        with self.app.lock:
            self.app.state["current_set_name"] = "Saison 6 - 2025"

        replies = {
            "/live/song/get/file_path": ("/Sets/ancien.als",),
            "/live/song/get/name": None,
        }
        with mock.patch.object(self.app, "query", side_effect=lambda address, *args, **kwargs: replies[address]):
            generation = self.app.refresh_live_set_identity(expected_generation=3)

        with self.app.lock:
            current_set_name = self.app.state["current_set_name"]
        self.assertEqual(generation, 3)
        self.assertEqual(current_set_name, "Saison 6 - 2025")

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
        with mock.patch.object(self.app.ableton_transport, "cancel_pending") as cancel_pending:
            with self.app.lock:
                self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")
            cancel_pending.assert_called_once_with()

        self.app.osc_reply("/live/scene/get/name", 7, "Ancienne en cours")

        with self.app.lock:
            snapshot = self.app.state_snapshot_locked()
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
            "/live/song/get/file_path": ("/Sets/nouveau.als",),
            "/live/song/get/name": ("nouveau",),
            "/live/view/get/selected_scene": (0,),
            "/live/song/get/scenes/name": None,
        }
        with (
            mock.patch.object(self.app, "BOOTSTRAP_TRANSACTION_TIMEOUT", 0.03),
            mock.patch.object(self.app, "OSC_BOOTSTRAP_DRAIN_SECONDS", 0.0),
            mock.patch.object(self.app, "query", side_effect=lambda address, *args, **kwargs: replies[address]),
        ):
            self.app.bootstrap_live_set(generation)

        with self.app.lock:
            snapshot = self.app.state_snapshot_locked()
        self.assertFalse(snapshot["set_ready"])
        self.assertEqual(snapshot["scenes"], {})
        self.assertEqual(snapshot["playing_scene_name"], "—")

    def test_transaction_retries_an_individual_timeout_then_succeeds(self):
        with self.app.lock:
            generation = self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")
            self.app._bootstrap_generation = generation

        attempts = {"scene_names": 0}

        def delayed_scene_names(address, *args, **kwargs):
            if address == "/live/song/get/file_path":
                return ("/Sets/nouveau.als",)
            if address == "/live/song/get/name":
                return ("nouveau",)
            if address == "/live/view/get/selected_scene":
                return (1,)
            attempts["scene_names"] += 1
            return None if attempts["scene_names"] == 1 else ("Ouverture", "Final")

        with (
            mock.patch.object(self.app, "OSC_BOOTSTRAP_DRAIN_SECONDS", 0.0),
            mock.patch.object(self.app, "query", side_effect=delayed_scene_names),
        ):
            self.app.bootstrap_live_set(generation)

        self.assertEqual(attempts["scene_names"], 2)
        self.assertTrue(self.app.state["set_ready"])
        self.assertEqual(self.app.state["scenes"], {0: "Ouverture", 1: "Final"})

    def test_transaction_accepts_a_response_after_several_slow_retries(self):
        with self.app.lock:
            generation = self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")
            self.app._bootstrap_generation = generation

        song_attempts = 0

        def slow_song_name(address, *args, **kwargs):
            nonlocal song_attempts
            if address == "/live/song/get/file_path":
                return ("/Sets/nouveau.als",)
            if address == "/live/view/get/selected_scene":
                return (0,)
            if address == "/live/song/get/scenes/name":
                return ("Ouverture", "Final")
            song_attempts += 1
            if song_attempts < 8:
                self.app.time.sleep(0.10)
                return None
            return ("nouveau",)

        started_at = self.app.time.monotonic()
        with (
            mock.patch.object(self.app, "BOOTSTRAP_TRANSACTION_TIMEOUT", 1.5),
            mock.patch.object(self.app, "OSC_BOOTSTRAP_DRAIN_SECONDS", 0.0),
            mock.patch.object(self.app, "query", side_effect=slow_song_name),
        ):
            self.app.bootstrap_live_set(generation)

        self.assertGreaterEqual(self.app.time.monotonic() - started_at, 0.7)
        self.assertEqual(song_attempts, 8)
        self.assertTrue(self.app.state["set_ready"])

    def test_transaction_accepts_fields_in_a_different_order(self):
        transaction = self.app._new_bootstrap_transaction(3)
        responses = {
            "/live/song/get/scenes/name": ("Ouverture", "Final"),
            "/live/view/get/selected_scene": (1,),
            "/live/song/get/name": ("nouveau",),
            "/live/song/get/file_path": ("/Sets/nouveau.als",),
        }
        with mock.patch.object(self.app, "query", side_effect=lambda address, *args, **kwargs: responses[address]):
            self.assertTrue(self.app._bootstrap_query_field(transaction, "scene_names", "/live/song/get/scenes/name", 0.2))
            self.assertTrue(self.app._bootstrap_query_field(transaction, "selected_scene", "/live/view/get/selected_scene", 0.1))
            self.assertTrue(self.app._bootstrap_query_field(transaction, "song_name", "/live/song/get/name", 0.08))
            self.assertTrue(self.app._bootstrap_query_field(transaction, "file_path", "/live/song/get/file_path", 0.1))

        self.assertTrue(transaction.ready_to_confirm())
        self.assertEqual(transaction.scene_names, ("Ouverture", "Final"))
        self.assertEqual(transaction.selected_scene, 1)

    def test_empty_values_are_received_values_not_missing_fields(self):
        transaction = self.app._new_bootstrap_transaction(3)
        with mock.patch.object(self.app, "query", return_value=("",)):
            self.app._bootstrap_query_field(transaction, "file_path", "/live/song/get/file_path", 0.1)
            self.app._bootstrap_query_field(transaction, "song_name", "/live/song/get/name", 0.08)
        with mock.patch.object(self.app, "query", return_value=()):
            self.app._bootstrap_query_field(transaction, "scene_names", "/live/song/get/scenes/name", 0.2)

        self.assertTrue(transaction.received("file_path"))
        self.assertTrue(transaction.received("song_name"))
        self.assertTrue(transaction.received("scene_names"))

    def test_generation_change_cancels_transaction_without_publication(self):
        with self.app.lock:
            generation = self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")
            self.app._bootstrap_generation = generation

        def change_generation(address, *args, **kwargs):
            if address == "/live/song/get/name":
                with self.app.lock:
                    self.app.reset_live_set_state_locked("/Sets/autre.als", "test")
            return ("/Sets/nouveau.als",) if address == "/live/song/get/file_path" else ("nouveau",)

        with (
            mock.patch.object(self.app, "OSC_BOOTSTRAP_DRAIN_SECONDS", 0.0),
            mock.patch.object(self.app, "query", side_effect=change_generation),
            mock.patch.object(self.app, "apply_live_set_bootstrap_locked", wraps=self.app.apply_live_set_bootstrap_locked) as apply,
        ):
            self.app.bootstrap_live_set(generation)

        apply.assert_not_called()
        self.assertFalse(self.app.state["set_ready"])
        self.assertEqual(self.app.state["current_set_id"], "/Sets/autre.als")

    def test_file_path_change_during_transaction_cancels_publication(self):
        with self.app.lock:
            generation = self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")
            self.app._bootstrap_generation = generation

        paths = iter((("/Sets/nouveau.als",), ("/Sets/autre.als",)))
        replies = {
            "/live/song/get/name": ("nouveau",),
            "/live/view/get/selected_scene": (0,),
            "/live/song/get/scenes/name": ("Ouverture",),
        }

        def changed_path(address, *args, **kwargs):
            return next(paths) if address == "/live/song/get/file_path" else replies[address]

        with (
            mock.patch.object(self.app, "OSC_BOOTSTRAP_DRAIN_SECONDS", 0.0),
            mock.patch.object(self.app, "query", side_effect=changed_path),
        ):
            self.app.bootstrap_live_set(generation)

        self.assertFalse(self.app.state["set_ready"])
        self.assertEqual(self.app.state["scenes"], {})

    def test_set_ready_is_published_only_once(self):
        with self.app.lock:
            generation = self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")
            self.app._bootstrap_generation = generation
        replies = {
            "/live/song/get/file_path": ("/Sets/nouveau.als",),
            "/live/song/get/name": ("nouveau",),
            "/live/view/get/selected_scene": (0,),
            "/live/song/get/scenes/name": ("Ouverture",),
        }
        with (
            mock.patch.object(self.app, "OSC_BOOTSTRAP_DRAIN_SECONDS", 0.0),
            mock.patch.object(self.app, "query", side_effect=lambda address, *args, **kwargs: replies[address]),
            mock.patch.object(self.app, "apply_live_set_bootstrap_locked", wraps=self.app.apply_live_set_bootstrap_locked) as apply,
        ):
            self.app.bootstrap_live_set(generation)

        apply.assert_called_once()
        self.assertTrue(self.app.state["set_ready"])

    def test_expired_transaction_times_out_without_publication(self):
        with self.app.lock:
            generation = self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")
            self.app._bootstrap_generation = generation
            transaction = self.app._new_bootstrap_transaction(generation)
            transaction.deadline = self.app.time.monotonic() - 0.001
            self.app._bootstrap_transaction = transaction

        with (
            mock.patch.object(self.app, "OSC_BOOTSTRAP_DRAIN_SECONDS", 0.0),
            mock.patch.object(self.app, "query") as query,
        ):
            self.app.bootstrap_live_set(generation)

        query.assert_not_called()
        self.assertTrue(transaction.cancelled)
        self.assertEqual(transaction.cancel_reason, "timeout global du bootstrap")
        self.assertFalse(self.app.state["set_ready"])

    def test_target_change_during_bootstrap_cancels_transaction(self):
        with self.app.lock:
            generation = self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")
            self.app._bootstrap_generation = generation

        targets = iter([
            ("127.0.0.1", 11000, 11001),
            ("192.168.1.20", 11000, 11001),
        ])
        with (
            mock.patch.object(self.app, "OSC_BOOTSTRAP_DRAIN_SECONDS", 0.0),
            mock.patch.object(self.app, "_bootstrap_target_identity", side_effect=lambda: next(targets)),
            mock.patch.object(self.app, "query") as query,
        ):
            self.app.bootstrap_live_set(generation)

        query.assert_not_called()
        self.assertFalse(self.app.state["set_ready"])

    def test_received_field_is_not_requested_twice(self):
        with self.app.lock:
            generation = self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")
            self.app._bootstrap_generation = generation
        replies = {
            "/live/song/get/file_path": ("/Sets/nouveau.als",),
            "/live/song/get/name": ("nouveau",),
            "/live/view/get/selected_scene": (0,),
            "/live/song/get/scenes/name": ("Ouverture",),
        }
        with (
            mock.patch.object(self.app, "OSC_BOOTSTRAP_DRAIN_SECONDS", 0.0),
            mock.patch.object(
                self.app,
                "query",
                side_effect=lambda address, *args, **kwargs: replies[address],
            ) as query,
        ):
            self.app.bootstrap_live_set(generation)

        addresses = [call.args[0] for call in query.call_args_list]
        self.assertEqual(addresses.count("/live/song/get/name"), 1)
        self.assertEqual(addresses.count("/live/view/get/selected_scene"), 1)
        self.assertEqual(addresses.count("/live/song/get/scenes/name"), 1)
        self.assertEqual(addresses.count("/live/song/get/file_path"), 2)

    def test_active_transaction_prevents_concurrent_bootstrap_and_identity_queries(self):
        with self.app.lock:
            generation = self.app.reset_live_set_state_locked("/Sets/nouveau.als", "file_path")

        created_threads = []

        class DeferredThread:
            def __init__(self, *args, **kwargs):
                created_threads.append((args, kwargs))

            def start(self):
                return None

        with mock.patch.object(self.app.threading, "Thread", DeferredThread):
            self.app.start_live_set_bootstrap(generation)
            first_transaction = self.app._bootstrap_transaction
            self.app.start_live_set_bootstrap(generation)

        self.assertEqual(len(created_threads), 1)
        self.assertIs(self.app._bootstrap_transaction, first_transaction)
        with mock.patch.object(self.app, "query") as query:
            self.assertEqual(self.app.refresh_live_set_identity(generation), generation)
        query.assert_not_called()

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
            self.app.ableton_transport._receive(address, *replies[address])

        with (
            mock.patch.object(self.app.time, "sleep"),
            mock.patch.object(self.app.ableton_transport, "send", side_effect=reply_immediately),
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

    def test_initial_cycle_starts_bootstrap_directly_in_local_and_remote_modes(self):
        target_values = (
            self.app.ableton_target.__class__(mode="local", host="127.0.0.1"),
            self.app.ableton_target.__class__(mode="remote", host="192.168.1.20"),
        )
        for target in target_values:
            with self.subTest(mode=target.mode):
                with self.app.lock:
                    self.app._bootstrap_generation = None
                    self.app._bootstrap_transaction = None
                    self.app.state["set_generation"] = 3
                    self.app.state["set_ready"] = False
                    self.app.state["current_set_id"] = None
                with (
                    mock.patch.object(self.app, "ableton_target", target),
                    mock.patch.object(self.app, "refresh_live_set_identity") as refresh_identity,
                    mock.patch.object(self.app, "start_live_set_bootstrap") as start_bootstrap,
                ):
                    ready = self.app.refresh_names_and_transport()

                self.assertFalse(ready)
                self.assertEqual(self.app.state["set_generation"], 4)
                self.assertEqual(self.app.state["current_set_id"], "pending:4")
                start_bootstrap.assert_called_once_with(4)
                refresh_identity.assert_not_called()

    def test_background_cycles_never_launch_a_second_initial_bootstrap(self):
        with self.app.lock:
            self.app._bootstrap_generation = None
            self.app._bootstrap_transaction = None
            self.app.state["set_generation"] = 3
            self.app.state["set_ready"] = False
            self.app.state["current_set_id"] = None

        created_threads = []

        class DeferredThread:
            def __init__(self, *args, **kwargs):
                created_threads.append((args, kwargs))

            def start(self):
                return None

        with (
            mock.patch.object(self.app.threading, "Thread", DeferredThread),
            mock.patch.object(self.app, "query") as query,
            mock.patch.object(
                self.app,
                "start_live_set_bootstrap",
                wraps=self.app.start_live_set_bootstrap,
            ) as start_bootstrap,
        ):
            for _ in range(6):
                self.assertFalse(self.app.refresh_names_and_transport())

        self.assertEqual(self.app.state["set_generation"], 4)
        self.assertEqual(self.app.state["current_set_id"], "pending:4")
        self.assertEqual(self.app._bootstrap_generation, 4)
        self.assertEqual(self.app._bootstrap_transaction.generation, 4)
        self.assertEqual(len(created_threads), 1)
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
            mock.patch.object(self.app, "resolve_scene_clip_duration_async"),
            mock.patch.object(self.app, "schedule_selected_scene_duration_refresh"),
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
            mock.patch.object(self.app, "resolve_scene_clip_duration_async"),
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
            mock.patch.object(self.app, "resolve_scene_clip_duration_async"),
            mock.patch.object(self.app, "schedule_selected_scene_duration_refresh"),
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

    def test_shared_ltc_interfaces_allow_40ms_active_polling(self):
        scheduler_source = (PROJECT_ROOT / "static/remote-v2.js").read_text(encoding="utf-8")
        ab_source = (PROJECT_ROOT / "templates/ab.html").read_text(encoding="utf-8")
        session_source = (PROJECT_ROOT / "templates/index.html").read_text(encoding="utf-8")
        arrangement_source = (PROJECT_ROOT / "templates/arrangement.html").read_text(encoding="utf-8")

        self.assertIn(
            "const minActiveMs = Math.max(40, Number(options.minActiveMs) || 250);",
            scheduler_source,
        )
        self.assertIn(
            "const activeMs = Math.max(minActiveMs, Number(options.activeMs) || 900);",
            scheduler_source,
        )
        self.assertIn(
            "{ activeMs: 40, idleMs: 2000, hiddenMs: 15000, minActiveMs: 40 }",
            ab_source,
        )
        self.assertIn(
            "{ activeMs: 40, idleMs: 2500, hiddenMs: 15000, minActiveMs: 40 }",
            session_source,
        )
        self.assertIn(
            "{ activeMs: 40, idleMs: 2500, hiddenMs: 15000, minActiveMs: 40 }",
            arrangement_source,
        )

    def test_polling_remains_serialized_and_recovers_after_failures(self):
        scheduler_source = (PROJECT_ROOT / "static/remote-v2.js").read_text(encoding="utf-8")

        self.assertNotIn("setInterval", scheduler_source)
        self.assertIn("let running = false;", scheduler_source)
        self.assertIn("if (running) {", scheduler_source)
        self.assertIn("try { await task(); }", scheduler_source)
        self.assertIn("catch (_) {}", scheduler_source)
        self.assertIn("finally {", scheduler_source)
        self.assertIn("running = false;", scheduler_source)
        self.assertIn("schedule();", scheduler_source)

    def test_ab_generation_filter_and_controls_are_unchanged(self):
        ab_source = (PROJECT_ROOT / "templates/ab.html").read_text(encoding="utf-8")

        self.assertIn("generation < lastAcceptedGeneration", ab_source)
        self.assertIn("confirmSelectedScene();", ab_source)
        self.assertIn("togglePlayPauseFromKeyboard();", ab_source)
        self.assertIn("timeoutMs = 2500", ab_source)
        self.assertIn("fetchJSON('/status', {}, 1800)", ab_source)

    def test_shared_ltc_display_is_present_on_session_and_arrangement_only(self):
        for relative_path in (
            "templates/index.html",
            "templates/arrangement.html",
        ):
            source = (PROJECT_ROOT / relative_path).read_text(encoding="utf-8")
            self.assertIn('class="ltc-display ltc-display--disconnected"', source)
            self.assertIn('class="ltc-display__value" id="ltcTimecode"', source)
            self.assertIn("window.CLRemoteLTC.render(ltcTimecodeEl, state)", source)

        ab_source = (PROJECT_ROOT / "templates/ab.html").read_text(encoding="utf-8")
        self.assertNotIn('id="ltcTimecode"', ab_source)
        self.assertNotIn("window.CLRemoteLTC.render", ab_source)

    def test_session_places_ltc_between_next_scene_and_go_controls(self):
        source = (PROJECT_ROOT / "templates/index.html").read_text(encoding="utf-8")

        selected_position = source.index('class="card selected-card"')
        ltc_position = source.index('class="ltc-display ltc-display--disconnected"')
        go_position = source.index('class="grid" aria-label="Commandes Ableton"')
        self.assertLess(selected_position, ltc_position)
        self.assertLess(ltc_position, go_position)

    def test_ab_orders_scene_selection_transport_and_crossfader_below_titles(self):
        source = (PROJECT_ROOT / "templates/ab.html").read_text(encoding="utf-8")

        deck_position = source.index('class="card deck-screen"')
        select_position = source.index('class="scene-select-panel"')
        transport_position = source.index('class="transport-dock"')
        slider_position = source.index('class="crossfader-section" aria-live="polite"')
        ab_buttons_position = source.index('class="buttons-dock"')
        self.assertEqual(source.count('id="xfader"'), 1)
        self.assertLess(deck_position, select_position)
        self.assertLess(select_position, transport_position)
        self.assertLess(transport_position, slider_position)
        self.assertLess(slider_position, ab_buttons_position)

    def test_ab_hides_the_large_crossfader_position_without_removing_the_slider(self):
        source = (PROJECT_ROOT / "templates/ab.html").read_text(encoding="utf-8")

        self.assertIn('class="crossfader-position" id="position"', source)
        self.assertRegex(
            source,
            r"\.crossfader-position\s*\{\s*display:\s*none\s*!important;",
        )
        self.assertIn('id="xfader"', source)
        self.assertIn("<span>A</span><span>Centre</span><span>B</span>", source)
        self.assertIn("min-height: 0 !important;", source)
        self.assertIn("Crossfader de console", source)
        self.assertIn("height: 34px !important;", source)

    def test_arrangement_navigation_requires_explicit_confirmation(self):
        session_page = self.app.app.test_client().get("/").get_data(as_text=True)
        script = (PROJECT_ROOT / "static/remote-v2.js").read_text(encoding="utf-8")
        arrangement_source = (PROJECT_ROOT / "templates/arrangement.html").read_text(encoding="utf-8")

        self.assertIn('href="/arrangement" data-arrangement-link', session_page)
        self.assertIn("Attention : vous passez en mode Arrangement", script)
        self.assertIn("window.confirm(arrangementWarning)", script)
        self.assertIn("action: 'back_to_arrangement'", script)
        self.assertIn("Attention : vous êtes en mode Arrangement", arrangement_source)

    def test_opening_arrangement_page_does_not_switch_ableton_view(self):
        with (
            mock.patch.object(self.app, "show_arrangement_view") as show_arrangement,
            mock.patch.object(self.app, "load_arrangement_markers", return_value=[]),
        ):
            response = self.app.app.test_client().get("/arrangement")

        self.assertEqual(response.status_code, 200)
        show_arrangement.assert_not_called()

    def test_launcher_remote_window_still_opens_session_by_default(self):
        launcher_source = (PROJECT_ROOT / "launcher_control.py").read_text(encoding="utf-8")

        self.assertIn('REMOTE_ROOT_URL = f"http://127.0.0.1:{WEB_PORT}/"', launcher_source)
        self.assertIn('open_remote_app_window(REMOTE_ROOT_URL, "Télécommande Ableton")', launcher_source)
        self.assertIn('event("Télécommande ouverte sur Session")', launcher_source)

    def test_shared_ltc_renderer_uses_only_published_ltc_state(self):
        source = (PROJECT_ROOT / "static/remote-v2.js").read_text(encoding="utf-8")

        self.assertIn("const LTC_PLACEHOLDER = '--:--:--:--';", source)
        self.assertIn("const LTC_PATTERN = /^\\d{2}:\\d{2}:\\d{2}:\\d{2}$/;", source)
        self.assertIn("state.ltc_connected === true", source)
        self.assertIn("state.ltc_timecode", source)
        self.assertIn("element.textContent = active ? value : LTC_PLACEHOLDER;", source)
        self.assertIn("ltc-display--connected", source)
        self.assertIn("ltc-display--disconnected", source)
        for legacy_source in ("state.timecode", "state.smpte", "state.arrangement_timecode"):
            self.assertNotIn(legacy_source, source)
        self.assertIsNone(re.search(r"state\.ltc(?!_)", source))
        for interpolation_marker in ("requestAnimationFrame", "interpolate", "setInterval"):
            self.assertNotIn(interpolation_marker, source)

    def test_shared_ltc_style_is_stable_and_uses_system_fonts(self):
        source = (PROJECT_ROOT / "static/remote-v2.css").read_text(encoding="utf-8")

        self.assertIn(".ltc-display__value", source)
        self.assertIn('ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace', source)
        self.assertIn("font-variant-numeric: tabular-nums", source)
        self.assertIn("min-width: 11ch", source)
        self.assertNotIn("Ableton Sans", source)

    def test_ltc_display_does_not_change_polling_or_generation_guards(self):
        expected_polling = {
            "templates/index.html": "{ activeMs: 40, idleMs: 2500, hiddenMs: 15000, minActiveMs: 40 }",
            "templates/ab.html": "{ activeMs: 40, idleMs: 2000, hiddenMs: 15000, minActiveMs: 40 }",
            "templates/arrangement.html": "{ activeMs: 40, idleMs: 2500, hiddenMs: 15000, minActiveMs: 40 }",
        }
        for relative_path, polling in expected_polling.items():
            source = (PROJECT_ROOT / relative_path).read_text(encoding="utf-8")
            self.assertIn(polling, source)
            self.assertIn("generation < lastAcceptedGeneration", source)

        scheduler_source = (PROJECT_ROOT / "static/remote-v2.js").read_text(encoding="utf-8")
        self.assertIn("wake() { schedule(document.hidden ? hiddenMs : 0); }", scheduler_source)
        self.assertIn("controllers.add(controller);\n      schedule(0);", scheduler_source)
        self.assertIn("const hiddenMs = Math.max(idleMs, Number(options.hiddenMs) || 15000);", scheduler_source)

        self.assertIsNotNone(re.fullmatch(r"\d{2}:\d{2}:\d{2}:\d{2}", "14:27:53:24"))

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

    def test_session_arrow_keys_share_previous_and_next_handlers(self):
        source = (PROJECT_ROOT / "templates/index.html").read_text(encoding="utf-8")

        self.assertIn("event.key === 'ArrowLeft' || event.key === 'ArrowRight'", source)
        self.assertIn("event.key === 'ArrowLeft' ? 'prev' : 'next'", source)
        self.assertIn("act(action);", source)
        self.assertIn("keyboardShortcutBlockReason(event)", source)

    def test_session_countdown_uses_published_remaining_time(self):
        source = (PROJECT_ROOT / "templates/index.html").read_text(encoding="utf-8")

        self.assertIn(
            '<div class="scene-countdown" id="currentTimer">Temps restant · --:--</div>',
            source,
        )
        self.assertIn("currentTimerEl.textContent = 'Temps restant · --:--';", source)
        self.assertIn("Temps restant · ${formatted}", source)
        self.assertIn("state && state.remaining_seconds", source)
        self.assertIn("state && state.scene_duration_seconds", source)
        self.assertIn("Math.min(effectiveDuration, publishedRemaining)", source)
        self.assertIn("Number.isFinite(publishedDuration)", source)
        self.assertIn("parts[parts.length - 1]", source)
        self.assertNotIn("parts.length >= 3 ? parts[2]", source)

    def test_session_next_duration_uses_the_same_blue_as_ab(self):
        session_source = (PROJECT_ROOT / "templates/index.html").read_text(encoding="utf-8")
        ab_source = (PROJECT_ROOT / "templates/ab.html").read_text(encoding="utf-8")
        shared_styles = (PROJECT_ROOT / "static/remote-v2.css").read_text(encoding="utf-8")

        self.assertIn("color: #9dd7ff;", session_source)
        self.assertIn("color: #9dd7ff !important;", ab_source)
        self.assertIn(".selected-card .selected-duration", shared_styles)
        self.assertIn(".selected-card .selected-title", shared_styles)
        self.assertIn("color: #9dd7ff !important;", shared_styles)

    def test_ab_displays_published_remaining_time_in_current_title(self):
        source = (PROJECT_ROOT / "templates/ab.html").read_text(encoding="utf-8")

        current_position = source.index('id="abCurrentTitle"')
        remaining_position = source.index('id="abRemaining"')
        next_position = source.index('id="nextTitleCard"')
        self.assertLess(current_position, remaining_position)
        self.assertLess(remaining_position, next_position)
        self.assertIn("state && state.remaining_seconds", source)
        self.assertIn("Temps restant · ${formatRemainingSeconds(", source)
        self.assertIn("Temps restant · --:--", source)
        self.assertIn("display: block !important;", source)
        self.assertIn("color: #f4d58d !important;", source)

    def test_ab_displays_selected_scene_duration_under_next_title(self):
        source = (PROJECT_ROOT / "templates/ab.html").read_text(encoding="utf-8")

        next_title_position = source.index('id="abNextTitle"')
        next_duration_position = source.index('id="abNextDuration"')
        self.assertLess(next_title_position, next_duration_position)
        self.assertIn("function selectedSceneDuration(state, sceneNumber, rawName)", source)
        self.assertIn("state && state.selected_scene_duration_seconds", source)
        self.assertIn("state && state.selected_scene_duration_index", source)
        self.assertIn(r"\d{1,2}:\d{2}(?::\d{2})?", source)
        self.assertIn("color: #9dd7ff !important;", source)

    def test_session_displays_the_published_selected_scene_duration(self):
        source = (PROJECT_ROOT / "templates/index.html").read_text(encoding="utf-8")

        self.assertIn("state && state.selected_scene_duration_seconds", source)
        self.assertIn("state && state.selected_scene_duration_index", source)
        self.assertIn("const duration = publishedDuration || selectedInfo.durationText;", source)

    def test_session_and_ab_share_the_professional_current_title_animation(self):
        source = (PROJECT_ROOT / "static/remote-v2.css").read_text(encoding="utf-8")

        self.assertIn(".current-card .title,", source)
        self.assertIn(".title-box-current .now-title", source)
        self.assertIn("color: #f4d58d !important;", source)
        self.assertIn("@keyframes v2-live-console-sweep", source)
        self.assertIn(".current-card.session-playing::after,", source)
        self.assertIn(".title-box-current.is-playing::after,", source)
        self.assertIn("animation: v2-live-console-sweep 5.2s ease-in-out infinite !important;", source)
        self.assertIn("@media (prefers-reduced-motion: reduce)", source)

    def test_session_has_a_dedicated_single_screen_iphone_landscape_layout(self):
        source = (PROJECT_ROOT / "static/remote-v2.css").read_text(encoding="utf-8")
        landscape = source.split(
            "@media (orientation: landscape) and (max-height: 500px)",
            1,
        )[1]

        self.assertIn('.v2-app[data-module="session"]', landscape)
        self.assertIn("grid-template-rows: 58px minmax(0, 1fr) !important;", landscape)
        self.assertIn("grid-template-columns: 1fr 1fr !important;", landscape)
        self.assertIn("grid-column: 1 / 4 !important;", landscape)
        self.assertIn("grid-column: 4 / -1 !important;", landscape)
        self.assertIn("font-size: clamp(14px, 2.2vw, 20px) !important;", landscape)
        self.assertIn("letter-spacing: .01em !important;", landscape)
        self.assertIn("grid-template-columns: .82fr .82fr 1.35fr .9fr .9fr !important;", landscape)
        self.assertIn("grid-column: 1 / -1 !important;", landscape)
        self.assertIn("overflow: hidden !important;", landscape)

    def test_ab_has_a_dedicated_single_screen_iphone_landscape_layout(self):
        source = (PROJECT_ROOT / "static/remote-v2.css").read_text(encoding="utf-8")
        landscape = source.rsplit(
            "@media (orientation: landscape) and (max-height: 500px)",
            1,
        )[1]

        self.assertIn('.v2-app[data-module="ab"]', landscape)
        self.assertIn("grid-template-rows: 58px minmax(0, 1fr) !important;", landscape)
        self.assertIn("grid-template-columns: 1fr 1fr !important;", landscape)
        self.assertIn("grid-column: 1 / 6 !important;", landscape)
        self.assertIn("grid-column: 6 / 10 !important;", landscape)
        self.assertIn("grid-column: 10 / -1 !important;", landscape)
        self.assertIn("grid-row: 3 !important;", landscape)
        self.assertIn("color: #72b7f2 !important;", landscape)
        self.assertIn("overflow: hidden !important;", landscape)

    def test_ab_arrow_keys_keep_using_the_existing_scene_preview_handler(self):
        source = (PROJECT_ROOT / "templates/ab.html").read_text(encoding="utf-8")

        self.assertIn("if (event.key === 'ArrowLeft')", source)
        self.assertIn("movePreparedScene(-1);", source)
        self.assertIn("if (event.key === 'ArrowRight')", source)
        self.assertIn("movePreparedScene(1);", source)
        self.assertIn("previewSceneSelect(true);", source)

    def test_scene_selection_publishes_cached_title_immediately(self):
        with self.app.lock:
            self.app.state["scenes"] = {
                7: "Ancienne en cours",
                8: "Final ; 128 ; 03:45",
            }

        with (
            mock.patch.object(self.app, "send"),
            mock.patch.object(self.app.threading, "Thread") as thread_class,
        ):
            self.app.select_scene(8)

        with self.app.lock:
            self.assertEqual(
                self.app.state["selected_scene_name"],
                "Final ; 128 ; 03:45",
            )
        self.assertEqual(thread_class.call_count, 2)
        scheduled_targets = [call.kwargs.get("target") for call in thread_class.call_args_list]
        self.assertIn(self.app.refresh_scene_name_async, scheduled_targets)
        self.assertIn(self.app.refresh_selected_scene_duration_async, scheduled_targets)

    def test_selected_scene_duration_prefers_the_tableaux_clip(self):
        with self.app.lock:
            self.app.state["set_generation"] = 3
            self.app.state["set_ready"] = True
            self.app.state["scenes"] = {0: "A", 1: "B", 2: "C"}

        def query_duration(address, *args, **kwargs):
            if address == "/live/song/get/track_names":
                return ("TABLEAUX", "MUSIC")
            if address == "/live/song/get/track_data":
                return (None, 400.0, None, None, 800.0, None)
            if address == "/live/song/get/tempo":
                return (120.0,)
            return None

        with mock.patch.object(self.app, "query", side_effect=query_duration):
            duration = self.app.read_scene_clip_duration_seconds(1, 3)

        self.assertEqual(duration, 200.0)

    def test_missing_scene_duration_is_resolved_from_tableaux_clip(self):
        with self.app.lock:
            self.app.state["set_generation"] = 3
            self.app.state["set_ready"] = True
            self.app.state["playing_scene"] = 38
            self.app.state["scene_duration_seconds"] = None
            self.app.state["remaining_seconds"] = None
            self.app.state["playback_deadline"] = None

        def query_duration(address, *args, **kwargs):
            if address == "/live/song/get/track_names":
                return ("PIANO", "66 TABLEAUX", "TOP infos")
            if address == "/live/song/get/track_data":
                return (-1, "PIANO", 38, "66 TABLEAUX", 38, "TOP infos")
            if address == "/live/clip/get/length":
                track_index, scene_index = args
                self.assertEqual(scene_index, 38)
                return (track_index, scene_index, 360.0 if track_index == 1 else 120.0)
            if address == "/live/song/get/tempo":
                return (120.0,)
            self.fail(f"Requête inattendue : {address}")

        started_at = self.app.time.time()
        with mock.patch.object(self.app, "query", side_effect=query_duration):
            self.app.resolve_scene_clip_duration_async(38, 3, started_at)

        with self.app.lock:
            self.assertEqual(self.app.state["scene_duration_seconds"], 180.0)
            self.assertGreater(self.app.state["remaining_seconds"], 179.0)
            self.assertLessEqual(self.app.state["remaining_seconds"], 180.0)

    def test_scene_name_duration_remains_prioritary_over_clip_lookup(self):
        with self.app.lock:
            self.app.state["set_generation"] = 3
            self.app.state["set_ready"] = True
            self.app.state["playing_scene"] = 38
            self.app.state["scene_duration_seconds"] = 95.0

        with mock.patch.object(self.app, "query") as query_mock:
            self.app.resolve_scene_clip_duration_async(
                38,
                3,
                self.app.time.time(),
            )

        with self.app.lock:
            self.assertEqual(self.app.state["scene_duration_seconds"], 95.0)
        query_mock.assert_not_called()

    def test_direct_ableton_launch_uses_grouped_scan_across_all_tracks(self):
        with self.app.lock:
            self.app.state["set_generation"] = 3
            self.app.state["set_ready"] = True
            self.app.state["is_playing"] = True
            self.app.state["play_mode"] = "session"
            self.app.state["playing_scene"] = -1
            self.app.state["scenes"] = {
                38: "AVA j'ai encore ; BPM ; KEY ; 3:00",
            }

        grouped = []
        for track_index in range(67):
            grouped.extend((38 if track_index in (65, 66) else -1, f"Piste {track_index + 1}"))

        with (
            mock.patch.object(
                self.app,
                "query",
                return_value=tuple(grouped),
            ) as query_mock,
            mock.patch.object(self.app.threading, "Thread") as thread_class,
        ):
            self.app.scan_playing_scene_from_tracks()

        query_mock.assert_called_once_with(
            "/live/song/get/track_data",
            0,
            -1,
            "track.playing_slot_index",
            "track.name",
            timeout=0.25,
            expected_generation=3,
            apply_response=False,
        )
        with self.app.lock:
            self.assertEqual(self.app.state["playing_scene"], 38)
            self.assertEqual(
                self.app.state["playing_scene_name"],
                "AVA j'ai encore ; BPM ; KEY ; 3:00",
            )
            self.assertEqual(self.app.state["scene_duration_seconds"], 180.0)
        thread_class.assert_not_called()

    def test_direct_ableton_launch_keeps_sequential_scan_as_fallback(self):
        with self.app.lock:
            self.app.state["set_generation"] = 3
            self.app.state["set_ready"] = True
            self.app.state["is_playing"] = True
            self.app.state["play_mode"] = "session"
            self.app.state["playing_scene"] = -1
            self.app.state["scenes"] = {4: "Titre sans durée"}

        def fallback_query(address, *args, **kwargs):
            if address == "/live/song/get/track_data":
                return None
            if address == "/live/track/get/playing_slot_index":
                track_index = args[0]
                return (track_index, 4 if track_index == 2 else -1)
            self.fail(f"Requête inattendue : {address}")

        with (
            mock.patch.object(self.app, "query", side_effect=fallback_query),
            mock.patch.object(self.app, "get_track_count", return_value=3),
            mock.patch.object(self.app.threading, "Thread") as thread_class,
        ):
            self.app.scan_playing_scene_from_tracks()

        with self.app.lock:
            self.assertEqual(self.app.state["playing_scene"], 4)
            self.assertEqual(self.app.state["playing_scene_name"], "Titre sans durée")
        thread_class.assert_called_once()

    def test_space_shortcut_prevents_page_scrolling(self):
        for relative_path in (
            "templates/index.html",
            "templates/ab.html",
            "templates/arrangement.html",
        ):
            source = (PROJECT_ROOT / relative_path).read_text(encoding="utf-8")
            space_branch = source.rsplit("if (event.code === 'Space' || event.key === ' ')", 1)[1]
            self.assertIn("event.preventDefault();", space_branch.split("}", 1)[0])

    def test_session_buttons_are_reenabled_without_artificial_delay(self):
        source = (PROJECT_ROOT / "templates/index.html").read_text(encoding="utf-8")
        action_finally = source.split(
            "if (action === 'go' && selectedCard) selectedCard.classList.add('is-prepared');",
            1,
        )[1].split("async function update(", 1)[0]

        self.assertIn("buttons.forEach(button => { button.disabled = false; });", action_finally)
        self.assertIn("actionBusy = false;", action_finally)
        self.assertNotIn("setTimeout(() =>", action_finally)

    def test_session_portrait_layout_is_compact_and_places_go_below_ltc(self):
        source = (PROJECT_ROOT / "templates/index.html").read_text(encoding="utf-8")
        portrait_css = source.split(
            "@media (orientation: portrait) and (max-width: 430px)",
            1,
        )[1].split("@media (orientation: landscape)", 1)[0]

        self.assertIn(".topnav a", portrait_css)
        self.assertIn("min-height: 22px;", portrait_css)
        self.assertIn(".card", portrait_css)
        self.assertIn("padding: 8px 10px;", portrait_css)
        self.assertIn(".ltc-display", portrait_css)
        self.assertIn("padding: 4px 8px;", portrait_css)
        self.assertIn(".go-button", portrait_css)
        self.assertIn("order: -1;", portrait_css)
        self.assertIn("min-height: 62px;", portrait_css)

    def test_ab_portrait_layout_fits_without_scrolling(self):
        source = (PROJECT_ROOT / "templates/ab.html").read_text(encoding="utf-8")
        portrait_css = source.rsplit(
            "@media (max-width: 430px) and (orientation: portrait)",
            1,
        )[1].split("</style>", 1)[0]

        self.assertIn("overflow-y: hidden !important;", portrait_css)
        self.assertIn("height: 48px !important;", portrait_css)
        self.assertIn("min-height: 31px !important;", portrait_css)
        self.assertIn("flex: 0 0 clamp(235px, 31dvh, 275px) !important;", portrait_css)
        self.assertIn("font-size: clamp(30px, 9.3vw, 40px) !important;", portrait_css)
        self.assertIn("font-size: clamp(27px, 8vw, 36px) !important;", portrait_css)
        self.assertIn("color: #72b7f2 !important;", portrait_css)
        self.assertIn("color: #9dd7ff !important;", portrait_css)
        self.assertIn("width: 100% !important;", portrait_css)
        self.assertIn("max-width: none !important;", portrait_css)
        self.assertIn("margin-left: 0 !important;", portrait_css)
        self.assertIn("margin-right: 0 !important;", portrait_css)
        self.assertIn("min-height: 0 !important;", portrait_css)
        self.assertNotIn("min-height: 72px !important;", portrait_css)
        self.assertIn("height: 42px !important;", portrait_css)


if __name__ == "__main__":
    unittest.main()
