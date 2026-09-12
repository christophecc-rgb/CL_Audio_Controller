import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from show_cues import (
    activate_show_cue_session, active_session_paths, create_show_cue,
    create_show_cue_session, delete_show_cue, delete_show_cue_session,
    duplicate_show_cue_session, initialize_show_cue_sessions, initialize_show_cue_storage,
    load_session_registry, load_show_document, persistent_show_cue_directory,
    rename_show_cue_session, save_show_document, select_manual_cue, select_show_cues,
    select_timed_cues, show_cues_for_conduite, show_cues_for_post, timecode_to_units,
    update_show_cue,
)


class ShowCueTests(unittest.TestCase):
    def setUp(self):
        self.cues = [
            {"id": "cue_a", "mode": "timed", "timecode": "00:00:10:00", "text": "FOH 1", "posts": ["FOH"], "status": "official", "_position": 1000},
            {"id": "cue_b", "mode": "timed", "timecode": "00:00:12:00", "text": "Multi", "posts": ["FOH", "PLATEAU"], "status": "draft", "_position": 1200},
            {"id": "cue_c", "mode": "timed", "timecode": "00:00:14:00", "text": "Retours", "posts": ["RETOURS"], "status": "official", "_position": 1400},
            {"id": "cue_d", "mode": "timed", "timecode": "00:00:16:00", "text": "Lumière", "posts": ["LUMIERE"], "status": "official", "_position": 1600},
            {"id": "cue_e", "mode": "timed", "timecode": "00:00:20:00", "text": "FOH 2", "posts": ["FOH"], "status": "official", "_position": 2000},
            {"id": "cue_m1", "mode": "manual", "section": "PARLÉ", "order": 1, "text": "Manuel 1", "posts": ["FOH"], "status": "official"},
            {"id": "cue_m2", "mode": "manual", "section": "PARLÉ", "order": 2, "text": "Manuel 2", "posts": ["FOH"], "status": "draft"},
            {"id": "cue_lib", "mode": "library", "text": "Incident", "posts": ["FOH"], "status": "official"},
        ]
        self.document = {"version": 1, "cues": self.cues}

    def test_timecode_conversion_comparison_and_invalid_values(self):
        self.assertEqual(timecode_to_units("01:02:03:04"), 372304)
        self.assertLess(timecode_to_units("00:59:59:24"), timecode_to_units("01:00:00:00"))
        for invalid in ("1:02:03:04", "00:60:00:00", "00:00:00:100"):
            with self.assertRaises(ValueError):
                timecode_to_units(invalid)

    def test_existing_prototype_cues_gain_compatible_unique_ids(self):
        payload = {"cues": [
            {"timecode": "00:00:02:00", "text": "Deux", "posts": ["FOH"]},
            {"timecode": "00:00:01:00", "text": "Un", "posts": ["FOH"]},
        ]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "show_cues.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            cues = load_show_document(path)["cues"]
        self.assertEqual([cue["id"] for cue in cues], ["cue_0001", "cue_0002"])
        self.assertTrue(all(cue["mode"] == "timed" and cue["status"] == "official" for cue in cues))

    def test_duplicate_ids_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "show_cues.json"
            cue = {"id": "cue_same", "mode": "library", "text": "A", "posts": ["FOH"], "status": "draft"}
            path.write_text(json.dumps({"cues": [cue, cue]}), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "dupliqué"):
                load_show_document(path)

    def test_current_next_missed_frame_forward_and_backward(self):
        reached = select_show_cues(self.cues, "00:00:12:09", "FOH")
        self.assertEqual((reached["current"]["id"], reached["next"]["id"]), ("cue_b", "cue_e"))
        self.assertEqual(select_show_cues(self.cues, "00:00:25:00", "FOH")["current"]["id"], "cue_e")
        backward = select_show_cues(self.cues, "00:00:11:00", "FOH")
        self.assertEqual((backward["current"]["id"], backward["next"]["id"]), ("cue_a", "cue_b"))

    def test_five_cue_window_is_timeline_derived_filtered_and_handles_edges(self):
        extra = [
            {"id": "cue_f", "mode": "timed", "timecode": "00:00:22:00", "text": "FOH 3", "posts": ["FOH"], "status": "official", "_position": 2200},
            {"id": "cue_g", "mode": "timed", "timecode": "00:00:24:00", "text": "FOH 4", "posts": ["FOH"], "status": "official", "_position": 2400},
        ]
        cues = self.cues + extra
        middle = select_show_cues(cues, "00:00:20:50", "FOH")
        self.assertEqual(
            [middle[key]["id"] if middle[key] else None for key in
             ("previous_second", "previous", "current", "next", "following")],
            ["cue_a", "cue_b", "cue_e", "cue_f", "cue_g"],
        )
        self.assertNotIn("cue_c", [item["id"] for item in middle.values() if item])
        beginning = select_show_cues(cues, "00:00:01:00", "FOH")
        self.assertEqual((beginning["previous"], beginning["current"]), (None, None))
        self.assertEqual((beginning["next"]["id"], beginning["following"]["id"]), ("cue_a", "cue_b"))
        end = select_show_cues(cues, "00:00:30:00", "FOH")
        self.assertEqual((end["current"]["id"], end["next"], end["following"]), ("cue_g", None, None))

    def test_global_timed_selection_uses_same_crossing_rule_for_jump_and_rewind(self):
        forward = select_timed_cues(self.cues, "00:00:18:99")
        self.assertEqual(forward["current"]["id"], "cue_d")
        crossed = select_timed_cues(self.cues, "00:00:20:01")
        self.assertEqual(crossed["current"]["id"], "cue_e")
        rewind = select_timed_cues(self.cues, "00:00:12:01")
        self.assertEqual(rewind["current"]["id"], "cue_b")
        self.assertIsNone(select_timed_cues(self.cues, "00:00:01:00")["current"])

    def test_four_posts_multi_post_and_statuses(self):
        expected = {"FOH": "cue_b", "RETOURS": "cue_c", "PLATEAU": "cue_b", "LUMIERE": "cue_d"}
        for post, cue_id in expected.items():
            with self.subTest(post=post):
                self.assertEqual(select_show_cues(self.cues, "00:00:18:00", post)["current"]["id"], cue_id)
        self.assertEqual(select_show_cues(self.cues, "00:00:18:00", "FOH")["current"]["status"], "draft")

    def test_manual_previous_next_and_library_exclusion(self):
        selected = select_manual_cue(self.cues, "FOH", "PARLÉ", 0)
        self.assertEqual(selected["current"]["id"], "cue_m1")
        self.assertIsNone(selected["previous"])
        self.assertEqual(selected["next"]["id"], "cue_m2")
        self.assertNotIn("cue_lib", [cue["id"] for cue in show_cues_for_post(self.cues, "FOH", "manual")])
        self.assertNotIn("cue_lib", [cue["id"] for cue in select_show_cues(self.cues, "00:00:30:00", "FOH").values() if cue])

    def test_create_timed_preserves_captured_ltc_and_defaults_to_draft(self):
        document, cue = create_show_cue(self.document, {"mode": "timed", "timecode": "01:14:27:12", "text": "Capturé", "posts": ["FOH"]})
        self.assertEqual(cue["timecode"], "01:14:27:12")
        self.assertEqual(cue["status"], "draft")
        self.assertEqual(len({item["id"] for item in document["cues"]}), len(document["cues"]))

    def test_create_manual_without_ltc_assigns_section_order(self):
        document, cue = create_show_cue(self.document, {"mode": "manual", "section": "PARLÉ", "text": "Manuel 3", "posts": ["FOH"]})
        self.assertEqual((cue["order"], cue["status"]), (3, "draft"))
        self.assertNotIn("timecode", cue)

    def test_manual_anchor_is_optional_validated_and_round_trips(self):
        document, cue = create_show_cue(self.document, {"mode": "manual", "section": "PARLÉ", "text": "Ancré", "posts": ["FOH"], "anchor_after": "cue_a"})
        self.assertEqual(cue["anchor_after"], "cue_a")
        self.assertEqual(show_cues_for_conduite(document["cues"], "manual")[-1]["anchor_after"], "cue_a")
        with self.assertRaisesRegex(ValueError, "ancre invalide"):
            create_show_cue(self.document, {"mode": "manual", "section": "X", "text": "X", "posts": ["FOH"], "anchor_after": "index-3"})

    def test_missing_manual_anchor_target_remains_readable(self):
        document, cue = create_show_cue(self.document, {"mode": "manual", "section": "PARLÉ", "text": "Après cue supprimé", "posts": ["FOH"], "anchor_after": "cue_disparu"})
        exposed = show_cues_for_conduite(document["cues"], "manual")
        self.assertEqual(next(item for item in exposed if item["id"] == cue["id"])["anchor_after"], "cue_disparu")

    def test_missing_anchor_target_remains_readable(self):
        document, cue = create_show_cue(self.document, {"mode": "manual", "section": "ORPHELINE", "text": "Toujours visible", "posts": ["PLATEAU"], "anchor_after": "cue_disparu"})
        visible = show_cues_for_conduite(document["cues"], "manual")
        self.assertIn(cue["id"], [item["id"] for item in visible])

    def test_create_and_filter_library(self):
        document, cue = create_show_cue(self.document, {"mode": "library", "text": "Stand-by", "posts": ["PLATEAU"]})
        self.assertEqual(cue["status"], "draft")
        self.assertIn(cue["id"], [item["id"] for item in show_cues_for_post(document["cues"], "PLATEAU", "library")])

    def test_update_text_posts_timecode_and_draft_to_official(self):
        document, cue = update_show_cue(self.document, "cue_b", {"text": "Corrigé", "posts": ["RETOURS", "PLATEAU"], "timecode": "00:00:13:00", "status": "official"})
        self.assertEqual((cue["text"], cue["timecode"], cue["status"]), ("Corrigé", "00:00:13:00", "official"))
        self.assertEqual(cue["posts"], ["RETOURS", "PLATEAU"])
        self.assertEqual(len(document["cues"]), len(self.document["cues"]))

    def test_classification_changes_mode_without_changing_stable_identity_or_content(self):
        original = next(cue for cue in self.cues if cue["id"] == "cue_b")
        document, library = update_show_cue(self.document, "cue_b", {"mode": "library", "status": "official"})
        self.assertEqual((library["id"], library["text"], library["posts"]),
                         (original["id"], original["text"], original["posts"]))
        self.assertEqual((library["mode"], library["status"]), ("library", "official"))
        self.assertNotIn("timecode", library)
        document, manual = update_show_cue(document, "cue_b", {
            "mode": "manual", "section": "PARLÉ", "order": 3,
        })
        self.assertEqual((manual["id"], manual["mode"], manual["section"], manual["order"]),
                         ("cue_b", "manual", "PARLÉ", 3))
        document, timed = update_show_cue(document, "cue_b", {
            "mode": "timed", "timecode": "00:01:02:03",
        })
        self.assertEqual((timed["id"], timed["mode"], timed["timecode"]),
                         ("cue_b", "timed", "00:01:02:03"))

    def test_write_read_round_trip_and_atomic_replace(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "show_cues.json"
            with mock.patch("show_cues.os.replace", wraps=__import__("os").replace) as replace:
                save_show_document(path, self.document)
            loaded = load_show_document(path)
            replace.assert_called_once()
            self.assertEqual(len(loaded["cues"]), len(self.cues))
            self.assertFalse(list(Path(directory).glob("*.tmp")))

    def test_optional_audio_round_trip_and_delete(self):
        document, cue = create_show_cue(self.document, {"mode": "manual", "section": "CAPTURES AUDIO", "text": "À compléter", "posts": ["FOH"]})
        filename = f"{cue['id']}.webm"
        document, cue = update_show_cue(document, cue["id"], {"audio": {"filename": filename, "mime_type": "audio/webm"}})
        self.assertEqual(cue["audio"]["filename"], filename)
        document, removed = delete_show_cue(document, cue["id"])
        self.assertEqual(removed["audio"]["filename"], filename)
        self.assertNotIn(cue["id"], [item["id"] for item in document["cues"]])

    def test_audio_filename_must_match_stable_cue_id(self):
        cue = {"id": "cue_audio", "mode": "library", "text": "Audio", "posts": ["FOH"], "status": "draft", "audio": {"filename": "cue_other.webm", "mime_type": "audio/webm"}}
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "fichier audio"):
                save_show_document(Path(directory) / "show_cues.json", {"cues": [cue]})


class ShowCuePersistenceTests(unittest.TestCase):
    def cue(self, text="Historique"):
        return {
            "id": "cue_persistent", "mode": "manual", "section": "PARLÉ", "order": 2,
            "anchor_after": "cue_anchor", "text": text, "posts": ["FOH", "LUMIERE"],
            "status": "official",
            "audio": {"filename": "cue_persistent.webm", "mime_type": "audio/webm"},
        }

    def test_persistent_path_is_independent_from_cwd_bundle_and_private_tmp(self):
        home = Path("/Users/tester")
        expected = home / "Library/Application Support/CL Audio Show Control/ShowCue"
        self.assertEqual(persistent_show_cue_directory(home), expected)
        with mock.patch("pathlib.Path.cwd", return_value=Path("/private/tmp/CL_ShowCue_Test_2.2.0")):
            self.assertEqual(persistent_show_cue_directory(home), expected)

    def test_first_start_creates_directory_and_empty_valid_database(self):
        with tempfile.TemporaryDirectory() as directory:
            data = Path(directory) / "user-data"
            path, audio = initialize_show_cue_storage(data)
            self.assertEqual(path, data / "show_cues.json")
            self.assertEqual(audio, data / "show_cues_audio")
            self.assertEqual(load_show_document(path), {"version": 1, "cues": []})

    def test_valid_historical_database_and_referenced_audio_are_migrated(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            historical, persistent = root / "bundle-a", root / "user-data"
            save_show_document(historical / "show_cues.json", {"cues": [self.cue()]})
            audio = historical / "show_cues_audio/cue_persistent.webm"
            audio.parent.mkdir()
            audio.write_bytes(b"historical-audio")
            path, audio_directory = initialize_show_cue_storage(persistent, [historical])
            migrated = load_show_document(path)["cues"][0]
            self.assertEqual(migrated["id"], "cue_persistent")
            self.assertEqual((migrated["section"], migrated["order"], migrated["anchor_after"]),
                             ("PARLÉ", 2, "cue_anchor"))
            self.assertEqual(migrated["posts"], ["FOH", "LUMIERE"])
            self.assertEqual((audio_directory / migrated["audio"]["filename"]).read_bytes(),
                             b"historical-audio")

    def test_existing_persistent_database_wins_on_restart_and_other_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            persistent, build_a, build_b = root / "user-data", root / "build-a", root / "build-b"
            save_show_document(build_a / "show_cues.json", {"cues": [self.cue("Build A")]})
            initialize_show_cue_storage(persistent, [build_a])
            document = load_show_document(persistent / "show_cues.json")
            document["cues"][0]["text"] = "Modifié par le serveur"
            save_show_document(persistent / "show_cues.json", document)
            save_show_document(build_b / "show_cues.json", {"cues": [self.cue("Ancien Build B")]})
            initialize_show_cue_storage(persistent, [build_b])
            self.assertEqual(load_show_document(persistent / "show_cues.json")["cues"][0]["text"],
                             "Modifié par le serveur")

    def test_invalid_or_empty_historical_candidate_cannot_overwrite_persistent_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            persistent, historical = root / "user-data", root / "bundle"
            save_show_document(persistent / "show_cues.json", {"cues": [self.cue("À garder")]})
            historical.mkdir()
            (historical / "show_cues.json").write_text('{"cues": "invalide"}', encoding="utf-8")
            initialize_show_cue_storage(persistent, [historical])
            self.assertEqual(load_show_document(persistent / "show_cues.json")["cues"][0]["text"],
                             "À garder")


class ShowCueSessionStorageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.data = Path(self.temporary.name) / "ShowCue"
        save_show_document(self.data / "show_cues.json", {"cues": [
            {"id": "cue_original", "mode": "manual", "section": "PARLÉ", "order": 1,
             "anchor_after": "cue_anchor", "text": "Original", "posts": ["FOH"],
             "status": "official", "audio": {
                 "filename": "cue_original.webm", "mime_type": "audio/webm"}},
        ]})
        audio = self.data / "show_cues_audio/cue_original.webm"
        audio.parent.mkdir()
        audio.write_bytes(b"audio-original")

    def tearDown(self):
        self.temporary.cleanup()

    def test_mono_session_migration_preserves_cues_audio_and_active_restart(self):
        registry = initialize_show_cue_sessions(self.data)
        path, audio = active_session_paths(self.data, registry)
        cue = load_show_document(path)["cues"][0]
        self.assertEqual((cue["id"], cue["section"], cue["anchor_after"]),
                         ("cue_original", "PARLÉ", "cue_anchor"))
        self.assertEqual((audio / cue["audio"]["filename"]).read_bytes(), b"audio-original")
        restarted = initialize_show_cue_sessions(self.data)
        self.assertEqual(restarted["active_session_id"], registry["active_session_id"])

    def test_create_activate_rename_and_empty_session(self):
        registry = initialize_show_cue_sessions(self.data)
        original_id = registry["active_session_id"]
        registry = create_show_cue_session(self.data, registry, "Deuxième show")
        created_id = registry["active_session_id"]
        self.assertNotEqual(created_id, original_id)
        self.assertEqual(load_show_document(active_session_paths(self.data, registry)[0])["cues"], [])
        registry = rename_show_cue_session(self.data, registry, created_id, "Show renommé")
        self.assertEqual(next(item["name"] for item in registry["sessions"]
                              if item["id"] == created_id), "Show renommé")
        registry = activate_show_cue_session(self.data, registry, original_id)
        self.assertEqual(registry["active_session_id"], original_id)
        self.assertEqual(load_session_registry(self.data / "sessions.json"), registry)

    def test_duplicate_keeps_scoped_cue_ids_but_copies_audio_independently(self):
        registry = initialize_show_cue_sessions(self.data)
        original_id = registry["active_session_id"]
        registry = duplicate_show_cue_session(self.data, registry, original_id, "Variante")
        duplicate_id = registry["active_session_id"]
        original_path = active_session_paths(
            self.data, {**registry, "active_session_id": original_id})
        duplicate_path = active_session_paths(self.data, registry)
        self.assertEqual(load_show_document(original_path[0])["cues"][0]["id"],
                         load_show_document(duplicate_path[0])["cues"][0]["id"])
        self.assertNotEqual(original_path[1], duplicate_path[1])
        (duplicate_path[1] / "cue_original.webm").write_bytes(b"variante")
        self.assertEqual((original_path[1] / "cue_original.webm").read_bytes(), b"audio-original")

    def test_delete_is_protected_against_last_session_and_selects_survivor(self):
        registry = initialize_show_cue_sessions(self.data)
        with self.assertRaisesRegex(ValueError, "unique session"):
            delete_show_cue_session(self.data, registry, registry["active_session_id"])
        original_id = registry["active_session_id"]
        registry = create_show_cue_session(self.data, registry, "Jetable")
        deleted_id = registry["active_session_id"]
        registry = delete_show_cue_session(self.data, registry, deleted_id)
        self.assertEqual(registry["active_session_id"], original_id)
        self.assertFalse((self.data / "Sessions" / deleted_id).exists())


class ShowCueRouteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import app
        cls.app_module = app

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.data_directory = Path(self.temporary.name) / "ShowCue"
        legacy_path = self.data_directory / "show_cues.json"
        save_show_document(legacy_path, {"cues": [{"id": "cue_base", "mode": "timed", "timecode": "00:00:05:00", "text": "Base", "posts": ["FOH"], "status": "official"}]})
        registry = initialize_show_cue_sessions(self.data_directory)
        self.session_id = registry["active_session_id"]
        self.path, self.audio_path = active_session_paths(self.data_directory, registry)
        self.data_path_patch = mock.patch.object(
            self.app_module, "SHOW_CUES_DATA_DIRECTORY", self.data_directory)
        self.data_path_patch.start()
        with self.app_module.SHOW_CALLS_LOCK:
            self.app_module.SHOW_CALLS.clear()
        self.client = self.app_module.app.test_client()

    def tearDown(self):
        self.data_path_patch.stop()
        self.temporary.cleanup()

    def set_ltc(self, value, connected):
        with self.app_module.lock:
            self.app_module.state.update({"ltc_timecode": value, "ltc_connected": connected, "is_playing": connected})

    def test_existing_page_status_and_invalid_post_routes(self):
        self.set_ltc("00:00:06:00", True)
        page = self.client.get("/show-info")
        self.assertEqual(page.status_code, 200)
        source = page.get_data(as_text=True)
        self.assertIn('/assets/paradis%20latin.jpg', source)
        self.assertIn('alt="Paradis Latin Cabaret"', source)
        self.assertNotIn("BROUILLON", source)
        self.assertIn('type="button" id="editor-cancel"', source)
        self.assertIn("clearTimeout(editorFocusTimer)", source)
        self.assertIn("editor.close()", source)
        self.assertNotIn("addEventListener('keydown'", source)
        self.assertIn(".line-time.true-time{color:var(--ltc)}", source)
        self.assertIn("function isTimecode(value)", source)
        self.assertIn('id="live-edit"', source)
        self.assertIn('id="quick-editor"', source)
        self.assertIn('id="form-smpte"', source)
        self.assertIn('id="quick-smpte"', source)
        self.assertIn("limits=[99,59,59,99]", source)
        self.assertIn("event.key==='ArrowUp'", source)
        self.assertIn("event.key==='ArrowDown'", source)
        self.assertIn("$('quick-cancel').onclick=()=>{quickEditor.close()", source)
        self.assertIn("showCueVisualLtc", source)
        self.assertIn("performance.now", source)
        self.assertNotIn("requestAnimationFrame", source)
        self.assertNotIn("Date.now", source)
        self.assertIn(".ableton-value", source)
        self.assertIn("--ltc:#62df91", source)
        self.assertIn('id="call-button"', source)
        self.assertIn('id="call-panel"', source)
        self.assertIn('id="past-second"', source)
        self.assertIn('id="past"', source)
        self.assertIn("grid-template-columns:minmax(0,2fr) minmax(260px,1fr)", source)
        self.assertIn("grid-template-columns:96px minmax(160px,1fr) auto 28px", source)
        self.assertIn("cue-line.current-timed", source)
        self.assertIn("row.scrollIntoView({behavior:'smooth',block:'center'})", source)
        self.assertIn("id===lastConduiteActiveId", source)
        self.assertIn('id="form-anchor"', source)
        self.assertNotIn("label.textContent='Position : après'", source)
        self.assertIn("Promise.all(cues.map", source)
        self.assertIn('id="editor-delete"', source)
        self.assertIn('id="quick-delete"', source)
        self.assertIn("Supprimer définitivement ce cue ?", source)
        self.assertIn("PLACER AU TC", source)
        self.assertIn("PLACER SANS LTC", source)
        self.assertIn("METTRE EN RÉSERVE", source)
        self.assertIn("À PLACER", source)
        self.assertNotIn("<h3>Lecture manuelle</h3>", source)
        self.assertIn("manual-section-nav", source)
        self.assertIn("manual-current", source)
        self.assertIn("function interactionActive()", source)
        self.assertIn("/^(INPUT|TEXTAREA|SELECT)$/", source)
        self.assertIn("if(interactionActive()){renderCalls(data.calls);return}", source)
        self.assertEqual(source.count('id="ltc"'), 1)
        self.assertNotIn('id="live-ltc"', source)
        self.assertNotIn("$('live-ltc')", source)
        self.assertIn('id="current-meta"', source)
        self.assertIn('id="next-time"', source)
        self.assertIn('id="following-time"', source)
        self.assertIn('id="session"', source)
        self.assertIn('id="session-new"', source)
        self.assertIn('id="session-rename"', source)
        self.assertIn('id="session-duplicate"', source)
        self.assertIn('id="session-delete"', source)
        self.assertIn("editor.dataset.sessionId=snapshot.active_session_id", source)
        self.assertIn("quickEditor.dataset.sessionId=snapshot.active_session_id", source)
        self.assertIn("session_id:sessionId", source)
        self.assertIn("snapshot.active_session_id+'-'+postEl.value+'-'+section", source)
        self.assertIn("function setManualAnchor(cues,anchorAfter)", source)
        self.assertIn("details.draggable=true", source)
        self.assertIn("function manualDropTarget", source)
        self.assertIn("Déplacer le bloc plus haut", source)
        self.assertIn("Déplacer le bloc plus bas", source)
        self.assertIn("let sectionFilter='TOUT'", source)
        self.assertIn("setInterval(refresh,2000)", source)
        self.assertNotIn("setInterval(refresh,500)", source)
        self.assertNotIn("setInterval(refresh,1000)", source)
        self.assertIn("showCueVisualLtc.sync", source)
        self.assertIn("captureTimecodeInto", source)
        self.assertNotIn("[['timecode-field',formSmpte", source)
        self.assertEqual(source.count("button.textContent='CAPTURER TC'"), 2)
        self.assertIn("block.append(lines)", source)
        self.assertIn("manual-inline-nav", source)
        self.assertIn("setManualAnchor(cues,anchors[anchorIndex-1])", source)
        self.assertIn("event.dataTransfer.setData('text/plain',section)", source)
        self.assertIn('id="conduite-ableton-title"', source)
        self.assertEqual(source.count('id="conduite-ableton-title"'), 1)
        self.assertIn("data.elapsed_seconds", source)
        self.assertIn("data.scene_duration_seconds", source)
        self.assertIn("data.remaining_seconds", source)
        self.assertIn("finally{refreshInFlight=false}", source)
        self.assertEqual(source.count('id="add-cue"'), 1)
        self.assertEqual(source.count('id="capture-audio"'), 1)
        self.assertEqual(source.count('id="add-library"'), 1)
        self.assertIn("input.checked=cue?cue.posts.includes(input.value):true", source)
        self.assertIn("posts:Object.keys(destinationLabels)", source)
        self.assertIn("library-line", source)
        self.assertIn('grid-template-areas:"text edit" "meta meta"', source)
        self.assertIn("(data.timed||[]).filter(cue=>cue.status==='official')", source)
        self.assertIn("(data.manual||[]).filter(cue=>cue.status==='official')", source)
        response = self.client.get("/show-info/status?post=FOH")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["current"]["id"], "cue_base")
        self.assertEqual(self.client.get("/show-info/status?post=INCONNU").status_code, 400)

    def test_status_exposes_ableton_duration_remaining_and_server_elapsed(self):
        keys = ("playing_scene_name", "scene_duration_seconds", "scene_duration_is_clip", "remaining_seconds", "playback_deadline", "is_playing", "is_paused")
        with self.app_module.lock:
            previous = {key: self.app_module.state.get(key) for key in keys}
            self.app_module.state.update({
                "playing_scene_name": "SCENE TEST",
                "scene_duration_seconds": 222,
                "scene_duration_is_clip": True,
                "remaining_seconds": 88,
                "playback_deadline": None,
                "is_playing": False,
                "is_paused": False,
            })
        try:
            payload = self.client.get("/show-info/status?post=FOH").get_json()
            self.assertEqual(payload["title"], "SCENE TEST")
            self.assertEqual(payload["scene_duration_seconds"], 222)
            self.assertEqual(payload["remaining_seconds"], 88)
            self.assertEqual(payload["elapsed_seconds"], 134)
        finally:
            with self.app_module.lock:
                self.app_module.state.update(previous)

    def test_status_keeps_elapsed_absent_when_ableton_timing_is_unavailable(self):
        keys = ("scene_duration_seconds", "scene_duration_is_clip", "remaining_seconds", "playback_deadline")
        with self.app_module.lock:
            previous = {key: self.app_module.state.get(key) for key in keys}
            self.app_module.state.update({"scene_duration_seconds": None, "scene_duration_is_clip": False, "remaining_seconds": None, "playback_deadline": None})
        try:
            payload = self.client.get("/show-info/status?post=FOH").get_json()
            self.assertIsNone(payload["elapsed_seconds"])
        finally:
            with self.app_module.lock:
                self.app_module.state.update(previous)

    def test_showcue_filters_title_without_mutating_raw_ableton_state(self):
        keys = ("playing_scene_name", "scene_duration_seconds", "scene_duration_is_clip", "remaining_seconds", "playback_deadline")
        raw_title = "40. Gigi; BPM ; KEY ; 1:51"
        with self.app_module.lock:
            previous = {key: self.app_module.state.get(key) for key in keys}
            self.app_module.state.update({
                "playing_scene_name": raw_title,
                "scene_duration_seconds": 111,
                "scene_duration_is_clip": False,
                "remaining_seconds": 80,
                "playback_deadline": None,
            })
        try:
            payload = self.client.get("/show-info/status?post=FOH").get_json()
            self.assertEqual(payload["title"], "40. Gigi")
            self.assertEqual(payload["scene_duration_seconds"], 111)
            self.assertEqual(payload["remaining_seconds"], 80)
            self.assertEqual(payload["elapsed_seconds"], 31)
            with self.app_module.lock:
                self.assertEqual(self.app_module.state["playing_scene_name"], raw_title)
                self.assertEqual(self.app_module.state["scene_duration_seconds"], 111)
        finally:
            with self.app_module.lock:
                self.app_module.state.update(previous)

    def test_true_zero_clip_duration_is_not_treated_as_unknown(self):
        keys = ("scene_duration_seconds", "scene_duration_is_clip", "remaining_seconds", "playback_deadline")
        with self.app_module.lock:
            previous = {key: self.app_module.state.get(key) for key in keys}
            self.app_module.state.update({
                "scene_duration_seconds": 0,
                "scene_duration_is_clip": True,
                "remaining_seconds": 0,
                "playback_deadline": None,
            })
        try:
            payload = self.client.get("/show-info/status?post=FOH").get_json()
            self.assertEqual(payload["scene_duration_seconds"], 0)
            self.assertEqual(payload["elapsed_seconds"], 0)
            self.assertEqual(payload["remaining_seconds"], 0)
        finally:
            with self.app_module.lock:
                self.app_module.state.update(previous)

    def test_showcue_uses_shared_server_deadline_while_playing_without_osc_query(self):
        keys = ("scene_duration_seconds", "remaining_seconds", "playback_deadline", "is_playing", "is_paused")
        with self.app_module.lock:
            previous = {key: self.app_module.state.get(key) for key in keys}
            self.app_module.state.update({
                "scene_duration_seconds": 220,
                "remaining_seconds": 220,
                "playback_deadline": 237,
                "is_playing": True,
                "is_paused": False,
            })
        try:
            with mock.patch.object(self.app_module.time, "time", return_value=100), mock.patch.object(self.app_module, "query") as query:
                payload = self.client.get("/show-info/status?post=FOH").get_json()
            self.assertEqual(payload["scene_duration_seconds"], 220)
            self.assertEqual(payload["remaining_seconds"], 137)
            self.assertEqual(payload["elapsed_seconds"], 83)
            query.assert_not_called()
        finally:
            with self.app_module.lock:
                self.app_module.state.update(previous)

    def test_showcue_countdown_freezes_on_stop_and_accepts_new_scene_values(self):
        keys = ("playing_scene_name", "scene_duration_seconds", "remaining_seconds", "playback_deadline", "is_playing", "is_paused")
        with self.app_module.lock:
            previous = {key: self.app_module.state.get(key) for key in keys}
            self.app_module.state.update({
                "playing_scene_name": "SCÈNE A",
                "scene_duration_seconds": 180,
                "remaining_seconds": 70,
                "playback_deadline": 999,
                "is_playing": False,
                "is_paused": False,
            })
        try:
            with mock.patch.object(self.app_module.time, "time", return_value=500):
                stopped = self.client.get("/show-info/status?post=FOH").get_json()
            self.assertEqual((stopped["remaining_seconds"], stopped["elapsed_seconds"]), (70, 110))
            with self.app_module.lock:
                self.app_module.state.update({
                    "playing_scene_name": "SCÈNE B",
                    "scene_duration_seconds": 240,
                    "remaining_seconds": 240,
                    "playback_deadline": None,
                })
            changed = self.client.get("/show-info/status?post=FOH").get_json()
            self.assertEqual(changed["title"], "SCÈNE B")
            self.assertEqual((changed["scene_duration_seconds"], changed["remaining_seconds"], changed["elapsed_seconds"]), (240, 240, 0))
        finally:
            with self.app_module.lock:
                self.app_module.state.update(previous)

    def test_call_round_trip_ack_visibility_and_no_cue_write(self):
        before = self.path.read_bytes()
        created = self.client.post("/show-info/call", json={"source": "FOH", "destination": "RETOURS"})
        self.assertEqual(created.status_code, 201)
        call = created.get_json()["call"]
        self.assertEqual(call["state"], "calling")
        self.assertEqual(self.client.get("/show-info/status?post=PLATEAU").get_json()["calls"]["incoming"], [])
        incoming = self.client.get("/show-info/status?post=RETOURS").get_json()["calls"]["incoming"]
        self.assertEqual([item["id"] for item in incoming], [call["id"]])
        acknowledged = self.client.post(f"/show-info/call/{call['id']}/ack", json={"post": "RETOURS"})
        self.assertEqual(acknowledged.status_code, 200)
        outgoing = self.client.get("/show-info/status?post=FOH").get_json()["calls"]["outgoing"]
        self.assertEqual(outgoing[0]["state"], "acknowledged")
        self.assertEqual(self.path.read_bytes(), before)

    def test_call_validates_posts_self_call_and_ack_identity(self):
        self.assertEqual(self.client.post("/show-info/call", json={"source": "FOH", "destination": "FOH"}).status_code, 400)
        self.assertEqual(self.client.post("/show-info/call", json={"source": "INCONNU", "destination": "RETOURS"}).status_code, 400)
        call = self.client.post("/show-info/call", json={"source": "FOH", "destination": "RETOURS"}).get_json()["call"]
        self.assertEqual(self.client.post(f"/show-info/call/{call['id']}/ack", json={"post": "PLATEAU"}).status_code, 403)

    def test_independent_calls_coexist_and_sender_can_cancel(self):
        first = self.client.post("/show-info/call", json={"source": "FOH", "destination": "RETOURS"}).get_json()["call"]
        second = self.client.post("/show-info/call", json={"source": "LUMIERE", "destination": "PLATEAU"}).get_json()["call"]
        with self.app_module.SHOW_CALLS_LOCK:
            self.assertEqual(set(self.app_module.SHOW_CALLS), {first["id"], second["id"]})
        self.assertEqual(self.client.post(f"/show-info/call/{first['id']}/cancel", json={"post": "RETOURS"}).status_code, 403)
        self.assertEqual(self.client.post(f"/show-info/call/{first['id']}/cancel", json={"post": "FOH"}).status_code, 200)
        with self.app_module.SHOW_CALLS_LOCK:
            self.assertEqual(set(self.app_module.SHOW_CALLS), {second["id"]})

    def test_call_timeout_and_call_failure_are_isolated_from_showcue_status(self):
        self.set_ltc("00:00:06:00", True)
        call = self.client.post("/show-info/call", json={"source": "FOH", "destination": "RETOURS"}).get_json()["call"]
        with self.app_module.SHOW_CALLS_LOCK:
            self.app_module.SHOW_CALLS[call["id"]]["created_at"] -= self.app_module.SHOW_CALL_TIMEOUT_SECONDS + 1
        self.assertEqual(self.client.get("/show-info/status?post=RETOURS").get_json()["calls"]["incoming"], [])
        with mock.patch.object(self.app_module, "show_call_snapshot", side_effect=RuntimeError("CALL indisponible")):
            payload = self.client.get("/show-info/status?post=FOH").get_json()
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["current"]["id"], "cue_base")
        self.assertEqual(payload["calls"], {"incoming": [], "outgoing": []})

    def test_acknowledgement_expires_after_confirmation_window(self):
        call = self.client.post("/show-info/call", json={"source": "FOH", "destination": "RETOURS"}).get_json()["call"]
        self.client.post(f"/show-info/call/{call['id']}/ack", json={"post": "RETOURS"})
        with self.app_module.SHOW_CALLS_LOCK:
            self.app_module.SHOW_CALLS[call["id"]]["acknowledged_at"] -= self.app_module.SHOW_CALL_ACK_SECONDS + 1
        outgoing = self.client.get("/show-info/status?post=FOH").get_json()["calls"]["outgoing"]
        self.assertEqual(outgoing, [])

    def test_status_publishes_post_drafts_for_the_client_view(self):
        document = load_show_document(self.path)
        document, draft = create_show_cue(document, {"mode": "manual", "section": "RÉPÉTITION", "text": "À valider", "posts": ["FOH"]})
        save_show_document(self.path, document)
        payload = self.client.get("/show-info/status?post=FOH").get_json()
        self.assertEqual([cue["id"] for cue in payload["drafts"]], [draft["id"]])
        self.assertNotIn("_position", payload["drafts"][0])

    def test_unclassified_timed_cue_stays_out_of_live_until_classified(self):
        document = load_show_document(self.path)
        document, capture = create_show_cue(document, {
            "mode": "timed", "timecode": "00:00:10:00", "text": "À décider", "posts": ["FOH"],
        })
        save_show_document(self.path, document)
        self.set_ltc("00:00:11:00", True)
        pending = self.client.get("/show-info/status?post=FOH").get_json()
        self.assertEqual(pending["current"]["id"], "cue_base")
        self.assertIn(capture["id"], [cue["id"] for cue in pending["drafts"]])
        self.client.put(f"/show-info/cues/{capture['id']}", json={"session_id": self.session_id, "status": "official"})
        classified = self.client.get("/show-info/status?post=FOH").get_json()
        self.assertEqual(classified["current"]["id"], capture["id"])
        self.assertNotIn(capture["id"], [cue["id"] for cue in classified["drafts"]])

    def test_capture_classification_to_timed_preserves_id_audio_text_and_posts(self):
        import io
        self.set_ltc("--:--:--:--", False)
        uploaded = self.client.post("/show-info/audio", data={
            "context": json.dumps({"session_id": self.session_id, "mode": "manual", "timecode": None, "posts": ["RETOURS"]}),
            "audio": (io.BytesIO(b"classified-audio"), "capture.webm", "audio/webm"),
        }).get_json()["cue"]
        response = self.client.put(f"/show-info/cues/{uploaded['id']}", json={
            "session_id": self.session_id,
            "mode": "timed", "timecode": "01:02:03:04", "status": "official",
        })
        self.assertEqual(response.status_code, 200)
        classified = response.get_json()["cue"]
        self.assertEqual((classified["id"], classified["text"], classified["posts"]),
                         (uploaded["id"], uploaded["text"], uploaded["posts"]))
        self.assertEqual((classified["mode"], classified["timecode"], classified["status"]),
                         ("timed", "01:02:03:04", "official"))
        self.assertEqual(classified["audio"], uploaded["audio"])
        self.assertTrue((self.audio_path / classified["audio"]["filename"]).exists())
        status = self.client.get("/show-info/status?post=RETOURS").get_json()
        self.assertNotIn(classified["id"], [cue["id"] for cue in status["drafts"]])
        self.assertIn(classified["id"], [cue["id"] for cue in status["conduite"]["timed"]])

    def test_capture_classification_to_manual_or_library_leaves_capture_queue(self):
        document = load_show_document(self.path)
        document, manual_candidate = create_show_cue(document, {
            "mode": "library", "text": "Sans LTC", "posts": ["FOH"],
        })
        document, library_candidate = create_show_cue(document, {
            "mode": "manual", "section": "À TRAITER", "text": "Réserve future", "posts": ["PLATEAU"],
        })
        save_show_document(self.path, document)
        manual = self.client.put(f"/show-info/cues/{manual_candidate['id']}", json={
            "session_id": self.session_id,
            "mode": "manual", "section": "INTERVENTION", "order": 1, "status": "official",
        }).get_json()["cue"]
        library = self.client.put(f"/show-info/cues/{library_candidate['id']}", json={
            "session_id": self.session_id,
            "mode": "library", "status": "official",
        }).get_json()["cue"]
        self.assertEqual((manual["id"], manual["mode"], manual["section"]),
                         (manual_candidate["id"], "manual", "INTERVENTION"))
        self.assertNotIn("timecode", manual)
        self.assertEqual((library["id"], library["mode"]), (library_candidate["id"], "library"))
        status = self.client.get("/show-info/status?post=FOH").get_json()
        self.assertNotIn(manual["id"], [cue["id"] for cue in status["drafts"]])
        self.assertNotIn(library["id"], [cue["id"] for cue in status["drafts"]])

    def test_delete_timed_manual_and_library_preserves_other_cues_and_section_order(self):
        document = load_show_document(self.path)
        document, manual_one = create_show_cue(document, {"mode": "manual", "section": "SECTION", "text": "Un", "posts": ["FOH"]})
        document, manual_two = create_show_cue(document, {"mode": "manual", "section": "SECTION", "text": "Deux", "posts": ["FOH"]})
        document, library = create_show_cue(document, {"mode": "library", "text": "Bibliothèque", "posts": ["FOH"]})
        document, timed = create_show_cue(document, {"mode": "timed", "timecode": "00:00:08:00", "text": "Timed", "posts": ["FOH"]})
        save_show_document(self.path, document)
        for cue in (timed, library, manual_one):
            self.assertEqual(self.client.delete(f"/show-info/cues/{cue['id']}?session_id={self.session_id}").status_code, 200)
        loaded = load_show_document(self.path)["cues"]
        self.assertEqual([cue["id"] for cue in loaded], ["cue_base", manual_two["id"]])
        self.assertEqual((loaded[1]["section"], loaded[1]["order"], loaded[1]["text"]),
                         ("SECTION", 2, "Deux"))
        self.assertEqual(self.client.delete(f"/show-info/cues/{manual_two['id']}?session_id={self.session_id}").status_code, 200)
        self.assertEqual([cue["id"] for cue in load_show_document(self.path)["cues"]], ["cue_base"])

    def test_individual_destination_update_does_not_change_other_cues(self):
        document = load_show_document(self.path)
        document, second = create_show_cue(document, {"mode": "library", "text": "Réserve", "posts": ["PLATEAU"]})
        save_show_document(self.path, document)
        response = self.client.put("/show-info/cues/cue_base", json={"session_id": self.session_id, "posts": ["FOH", "LUMIERE"]})
        self.assertEqual(response.status_code, 200)
        loaded = load_show_document(self.path)["cues"]
        self.assertEqual(next(cue for cue in loaded if cue["id"] == "cue_base")["posts"], ["FOH", "LUMIERE"])
        self.assertEqual(next(cue for cue in loaded if cue["id"] == second["id"])["posts"], ["PLATEAU"])

    def test_quick_text_update_preserves_timecode_posts_and_status(self):
        response = self.client.put("/show-info/cues/cue_base", json={"session_id": self.session_id, "text": "Texte corrigé"})
        self.assertEqual(response.status_code, 200)
        cue = response.get_json()["cue"]
        self.assertEqual(cue["text"], "Texte corrigé")
        self.assertEqual(cue["timecode"], "00:00:05:00")
        self.assertEqual(cue["posts"], ["FOH"])
        self.assertEqual(cue["status"], "official")

    def test_status_publishes_complete_conduite_without_changing_local_post(self):
        payload = self.client.get("/show-info/status?post=RETOURS").get_json()
        self.assertEqual(payload["post"], "RETOURS")
        self.assertEqual(payload["conduite"]["timed"][0]["id"], "cue_base")
        self.assertEqual(payload["conduite"]["timed"][0]["posts"], ["FOH"])

    def test_session_api_create_activate_rename_duplicate_and_protected_delete(self):
        created = self.client.post("/show-info/sessions", json={"name": "Show B"})
        self.assertEqual(created.status_code, 201)
        registry = created.get_json()
        show_b = registry["active_session_id"]
        self.assertNotEqual(show_b, self.session_id)
        renamed = self.client.put(f"/show-info/sessions/{show_b}", json={"name": "Show B soir"})
        self.assertEqual(renamed.status_code, 200)
        duplicated = self.client.post(
            f"/show-info/sessions/{show_b}/duplicate", json={"name": "Show B copie"})
        copy_id = duplicated.get_json()["active_session_id"]
        self.assertNotEqual(copy_id, show_b)
        self.assertEqual(self.client.delete(
            f"/show-info/sessions/{copy_id}", json={"confirmation_name": "incorrect"}).status_code, 400)
        self.assertEqual(self.client.delete(
            f"/show-info/sessions/{copy_id}", json={"confirmation_name": "Show B copie"}).status_code, 200)
        self.assertEqual(self.client.post(
            f"/show-info/sessions/{self.session_id}/activate", json={}).status_code, 200)

    def test_active_session_is_global_isolated_and_recalculates_live_from_current_ltc(self):
        other = self.app_module.app.test_client()
        self.set_ltc("00:00:06:00", True)
        original = other.get("/show-info/status?post=PLATEAU").get_json()
        self.assertEqual(original["active_session_id"], self.session_id)
        created = self.client.post("/show-info/sessions", json={"name": "Session vide"}).get_json()
        empty_id = created["active_session_id"]
        empty = other.get("/show-info/status?post=PLATEAU").get_json()
        self.assertEqual(empty["active_session_id"], empty_id)
        self.assertEqual((empty["current"], empty["conduite"]["timed"], empty["drafts"],
                          empty["library"]), (None, [], [], []))
        self.client.post("/show-info/cues", json={
            "session_id": empty_id, "mode": "timed", "timecode": "00:00:04:00",
            "text": "Session B", "posts": ["PLATEAU"], "status": "official",
        })
        recalculated = other.get("/show-info/status?post=PLATEAU").get_json()
        self.assertEqual(recalculated["current"]["text"], "Session B")
        self.client.post(f"/show-info/sessions/{self.session_id}/activate", json={})
        back = other.get("/show-info/status?post=FOH").get_json()
        self.assertEqual(back["current"]["id"], "cue_base")
        self.assertNotIn("Session B", [cue["text"] for cue in back["conduite"]["timed"]])

    def test_mutation_from_editor_opened_in_previous_session_is_rejected(self):
        old_session = self.session_id
        new_session = self.client.post(
            "/show-info/sessions", json={"name": "Nouvelle active"}).get_json()["active_session_id"]
        response = self.client.put("/show-info/cues/cue_base", json={
            "session_id": old_session, "text": "Ne doit pas être écrit",
        })
        self.assertEqual(response.status_code, 409)
        self.assertIn("session active a changé", response.get_json()["message"])
        active_path, _ = active_session_paths(
            self.data_directory, {"active_session_id": new_session})
        self.assertEqual(load_show_document(active_path)["cues"], [])

    def test_second_polling_client_observes_create_update_classify_destination_anchor_and_delete(self):
        other_client = self.app_module.app.test_client()
        created = self.client.post("/show-info/cues", json={
            "session_id": self.session_id,
            "mode": "manual", "section": "MULTI CLIENT", "text": "Créé par A",
            "posts": ["FOH"],
        }).get_json()["cue"]
        first_poll = other_client.get("/show-info/status?post=FOH").get_json()
        self.assertIn(created["id"], [cue["id"] for cue in first_poll["drafts"]])

        updated = self.client.put(f"/show-info/cues/{created['id']}", json={
            "session_id": self.session_id,
            "text": "Mis à jour par A", "posts": ["FOH", "RETOURS"],
            "status": "official", "anchor_after": "cue_base",
        })
        self.assertEqual(updated.status_code, 200)
        second_poll = other_client.get("/show-info/status?post=RETOURS").get_json()
        observed = next(cue for cue in second_poll["conduite"]["manual"]
                        if cue["id"] == created["id"])
        self.assertEqual((observed["text"], observed["posts"], observed["status"],
                          observed["anchor_after"]),
                         ("Mis à jour par A", ["FOH", "RETOURS"], "official", "cue_base"))
        self.assertNotIn(created["id"], [cue["id"] for cue in second_poll["drafts"]])

        self.assertEqual(self.client.delete(f"/show-info/cues/{created['id']}?session_id={self.session_id}").status_code, 200)
        final_poll = other_client.get("/show-info/status?post=FOH").get_json()
        self.assertNotIn(created["id"], [cue["id"] for cue in final_poll["conduite"]["manual"]])

    def test_conduite_current_is_global_while_live_window_remains_post_filtered(self):
        document = load_show_document(self.path)
        document, other_post = create_show_cue(document, {
            "mode": "timed", "timecode": "00:00:10:00", "text": "Plateau",
            "posts": ["PLATEAU"], "status": "official",
        })
        save_show_document(self.path, document)
        self.set_ltc("00:00:11:00", True)
        payload = self.client.get("/show-info/status?post=FOH").get_json()
        self.assertEqual(payload["current"]["id"], "cue_base")
        self.assertEqual(payload["conduite_current_id"], other_post["id"])

    def test_repositioning_manual_section_changes_only_anchor_fields(self):
        document = load_show_document(self.path)
        document, first = create_show_cue(document, {"mode": "manual", "section": "PARLÉ", "text": "Un", "posts": ["FOH"]})
        document, second = create_show_cue(document, {"mode": "manual", "section": "PARLÉ", "text": "Deux", "posts": ["RETOURS"]})
        save_show_document(self.path, document)
        originals = {cue["id"]: cue for cue in (first, second)}
        for cue in (first, second):
            response = self.client.put(f"/show-info/cues/{cue['id']}", json={"session_id": self.session_id, "anchor_after": "cue_base"})
            self.assertEqual(response.status_code, 200)
        loaded = {cue["id"]: cue for cue in load_show_document(self.path)["cues"]}
        for cue_id, original in originals.items():
            self.assertEqual(loaded[cue_id]["anchor_after"], "cue_base")
            self.assertEqual(loaded[cue_id]["id"], original["id"])
            self.assertEqual(loaded[cue_id]["text"], original["text"])
            self.assertEqual(loaded[cue_id]["posts"], original["posts"])
            self.assertNotIn("timecode", loaded[cue_id])

    def test_capture_is_frozen_by_client_payload_while_ltc_advances(self):
        self.set_ltc("01:14:27:12", True)
        captured = self.client.post("/show-info/capture", json={}).get_json()
        self.set_ltc("01:14:37:12", True)
        response = self.client.post("/show-info/cues", json={"session_id": self.session_id, "mode": "timed", "timecode": captured["timecode"], "text": "Nouveau", "posts": ["FOH"]})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.get_json()["cue"]["timecode"], "01:14:27:12")

    def test_absent_ltc_captures_manual_and_server_create_update(self):
        self.set_ltc("--:--:--:--", False)
        self.assertEqual(self.client.post("/show-info/capture", json={}).get_json()["mode"], "manual")
        created = self.client.post("/show-info/cues", json={"session_id": self.session_id, "mode": "manual", "section": "FINAL", "text": "Préparer", "posts": ["PLATEAU"]})
        self.assertEqual(created.status_code, 201)
        cue = created.get_json()["cue"]
        updated = self.client.put(f"/show-info/cues/{cue['id']}", json={"session_id": self.session_id, "text": "Prêt", "posts": ["FOH", "PLATEAU"], "status": "official"})
        self.assertEqual(updated.status_code, 200)
        self.assertEqual(updated.get_json()["cue"]["status"], "official")

    def test_stopped_transport_does_not_capture_stale_ltc(self):
        self.set_ltc("01:00:00:00", True)
        with self.app_module.lock:
            self.app_module.state["is_playing"] = False
        captured = self.client.post("/show-info/capture", json={}).get_json()
        self.assertEqual((captured["mode"], captured["timecode"]), ("manual", None))

    def test_connected_but_stale_ltc_is_not_captured(self):
        self.set_ltc("01:00:00:00", True)
        with self.app_module.lock:
            self.app_module.state["ltc_last_received_at"] = __import__("time").time() - 3
        captured = self.client.post("/show-info/capture", json={}).get_json()
        self.assertEqual((captured["mode"], captured["timecode"]), ("manual", None))
        with self.app_module.lock:
            self.app_module.state["ltc_last_received_at"] = None

    def test_audio_upload_creates_timed_draft_and_serves_audio(self):
        import io
        self.set_ltc("01:14:27:12", True)
        context = self.client.post("/show-info/capture", json={}).get_json()
        response = self.client.post("/show-info/audio", data={
            "context": json.dumps({**context, "session_id": self.session_id, "posts": ["RETOURS"]}),
            "audio": (io.BytesIO(b"webm-audio"), "capture.webm", "audio/webm"),
        })
        self.assertEqual(response.status_code, 201)
        cue = response.get_json()["cue"]
        self.assertEqual((cue["mode"], cue["timecode"], cue["status"]), ("timed", "01:14:27:12", "draft"))
        self.assertTrue((self.audio_path / cue["audio"]["filename"]).is_file())
        playback = self.client.get(f"/show-info/cues/{cue['id']}/audio")
        self.assertEqual((playback.status_code, playback.data), (200, b"webm-audio"))
        playback.close()

    def test_audio_upload_without_ltc_is_manual_and_cancel_removes_both(self):
        import io
        self.set_ltc("--:--:--:--", False)
        response = self.client.post("/show-info/audio", data={
            "context": json.dumps({"session_id": self.session_id, "mode": "manual", "timecode": None, "posts": ["FOH"]}),
            "audio": (io.BytesIO(b"audio"), "capture.webm", "audio/webm"),
        })
        cue = response.get_json()["cue"]
        self.assertEqual(cue["mode"], "manual")
        audio_path = self.audio_path / cue["audio"]["filename"]
        self.assertTrue(audio_path.exists())
        self.assertEqual(self.client.delete(f"/show-info/cues/{cue['id']}?session_id={self.session_id}").status_code, 200)
        self.assertFalse(audio_path.exists())
        self.assertNotIn(cue["id"], [item["id"] for item in load_show_document(self.path)["cues"]])

    def test_audio_rejects_unsupported_or_oversized_payload_without_cue(self):
        import io
        before = self.path.read_text(encoding="utf-8")
        unsupported = self.client.post("/show-info/audio", data={"context": "{}", "audio": (io.BytesIO(b"x"), "x.txt", "text/plain")})
        self.assertEqual(unsupported.status_code, 415)
        with mock.patch.object(self.app_module, "SHOW_CUE_AUDIO_MAX_BYTES", 3):
            oversized = self.client.post("/show-info/audio", data={"context": json.dumps({"mode": "manual"}), "audio": (io.BytesIO(b"1234"), "x.webm", "audio/webm")})
        self.assertEqual(oversized.status_code, 413)
        self.assertEqual(self.path.read_text(encoding="utf-8"), before)


if __name__ == "__main__":
    unittest.main()
