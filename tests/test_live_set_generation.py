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
            self.app.state["set_generation"] = 3
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
        self.assertEqual(snapshot["playing_scene_name"], "—")
        self.assertEqual(snapshot["selected_scene_name"], "—")
        self.assertEqual(snapshot["scenes"], {})

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
        self.assertEqual(generation, 3)
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

    def test_all_web_interfaces_reject_older_generations(self):
        for relative_path in ("templates/index.html", "templates/ab.html", "templates/arrangement.html"):
            source = (PROJECT_ROOT / relative_path).read_text(encoding="utf-8")
            self.assertIn("generation < lastAcceptedGeneration", source)
            self.assertIn("if (!acceptStateGeneration(state)) return;", source)


if __name__ == "__main__":
    unittest.main()
