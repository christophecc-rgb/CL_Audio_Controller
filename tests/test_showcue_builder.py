import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

from show_cues import (SHOW_SECTIONS, active_session_paths, create_show_cue,
                       initialize_show_cue_sessions, load_show_document,
                       save_show_document, update_show_cue)
from showcue_builder import (
    export_csv, export_xlsx, import_csv, import_xlsx, load_builder_document,
    builder_import_values, normalize_builder_document, resolve_builder_cue, save_builder_document,
    validate_builder_document, _sheet_xml,
)


def sample_document():
    return {"cues": [
        {"id": "builder_roxy", "number": "1", "timecode": "", "source": "Final",
         "type": "TEST EAR / IEM", "section": "IEM", "role": "ROXY", "artist": "",
         "text": "ROXY — TEST EAR", "microphone": "HF3", "iem": "IEM2",
         "equipment": "Accessoire Étoile", "foh": True, "ret": True, "plt": True,
         "lum": False, "origin": "BUILDER", "notes": "À confirmer"},
    ], "distribution": [
        {"role": "ROXY", "artist": "Élodie", "microphone": "HF3", "iem": "IEM2",
         "equipment": "Accessoire Étoile", "active": True, "notes": "Distribution du jour"},
        {"role": "ROXY", "artist": "Zoé", "microphone": "HF5", "iem": "IEM3",
         "equipment": "Accessoire Étoile", "active": False, "notes": "Remplaçante"},
    ]}


def slotted_document():
    document = sample_document()
    document["distribution"] = [
        {"role": "DIRECTRICE", "artist": "VENUS", "active": True,
         "equipment_slots": [
             {"type": "MICRO", "value": "M3 / C3"},
             {"type": "MICRO", "value": "M7 / C7"},
             {"type": "IEM", "value": "IEM 3"},
         ], "notes": ""},
        {"role": "DIRECTRICE", "artist": "AUTRE", "active": False,
         "equipment_slots": [], "notes": ""},
    ]
    document["cues"][0]["role"] = "DIRECTRICE"
    document["cues"][0].update({"microphone": "", "iem": "", "equipment": ""})
    return document


def legacy_xlsx_payload():
    source = io.BytesIO(export_xlsx(sample_document()))
    output = io.BytesIO()
    with zipfile.ZipFile(source) as archive:
        files = {name: archive.read(name) for name in archive.namelist()}
    files["xl/worksheets/sheet2.xml"] = _sheet_xml([
        ["RÔLE", "ARTISTE", "MICRO", "IEM", "ÉQUIPEMENT", "ACTIF", "NOTES"],
        ["DIRECTRICE", "VENUS", "M3 / C3", "IEM 3", "TABLE HF", True, ""],
    ]).encode()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, payload in files.items():
            archive.writestr(name, payload)
    return output.getvalue()


class ShowCueBuilderTests(unittest.TestCase):
    def test_equipment_slots_accept_zero_one_and_three_but_reject_four(self):
        for count in (0, 1, 3):
            with self.subTest(count=count):
                document = slotted_document()
                document["distribution"][0]["equipment_slots"] = [
                    {"type": "AUTRE", "value": f"E{index}"} for index in range(count)]
                self.assertEqual(len(normalize_builder_document(document)
                                     ["distribution"][0]["equipment_slots"]), count)
        document = slotted_document()
        document["distribution"][0]["equipment_slots"].append(
            {"type": "ÉQUIPEMENT", "value": "QUATRIÈME"})
        with self.assertRaisesRegex(ValueError, "maximum 3 équipements"):
            normalize_builder_document(document)

    def test_legacy_distribution_fields_become_typed_slots_without_loss(self):
        normalized = normalize_builder_document(sample_document())
        self.assertEqual(normalized["distribution"][0]["equipment_slots"], [
            {"type": "MICRO", "value": "HF3"},
            {"type": "IEM", "value": "IEM2"},
            {"type": "ÉQUIPEMENT", "value": "Accessoire Étoile"},
        ])
        self.assertNotIn("microphone", normalized["distribution"][0])

    def test_two_microphones_are_complete_but_legacy_microphone_is_not_arbitrary(self):
        resolved = resolve_builder_cue({"role": "DIRECTRICE", "text": "Entrée"},
                                       slotted_document()["distribution"])
        self.assertEqual([slot["value"] for slot in resolved["equipment_slots"]],
                         ["M3 / C3", "M7 / C7", "IEM 3"])
        self.assertIsNone(resolved["microphone"])
        self.assertIsNone(resolved["resolved_microphone"])
        self.assertEqual(resolved["iem"], "IEM 3")

    def test_distribution_validation_reports_assignment_and_equipment_issues(self):
        document = slotted_document()
        duplicate = dict(document["distribution"][0])
        duplicate["active"] = False
        duplicate["equipment_slots"] = [
            {"type": "MICRO", "value": "M3 / C3"},
            {"type": "MICRO", "value": "M3 / C3"},
            {"type": "INCONNU", "value": "X"},
        ]
        document["distribution"].append(duplicate)
        validation = validate_builder_document(document)
        self.assertEqual(validation["duplicate_role_artists"], ["DIRECTRICE · VENUS"])
        self.assertTrue(validation["duplicate_equipment_slots"])
        self.assertTrue(validation["invalid_equipment_slots"])
        self.assertFalse(validation["ready"])
    def test_common_sections_custom_values_and_historical_case_are_preserved(self):
        self.assertEqual(SHOW_SECTIONS, __import__("showcue_builder").BUILDER_SECTIONS)
        self.assertIn("INTERMÈDE", SHOW_SECTIONS)
        document, custom = create_show_cue({"version": 1, "cues": []}, {
            "mode": "manual", "section": "  Nouvelle fiche  ", "text": "X", "posts": ["FOH"]})
        self.assertEqual(custom["section"], "Nouvelle fiche")
        document, canonical = create_show_cue(document, {
            "mode": "manual", "section": "show", "text": "Y", "posts": ["FOH"]})
        self.assertEqual(canonical["section"], "SHOW")
        historical = {"version": 1, "cues": [{"id": "cue_old", "mode": "manual",
            "section": "Show historique", "order": 1, "text": "Z", "posts": ["FOH"],
            "status": "official"}]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "show_cues.json"
            save_show_document(path, historical)
            self.assertEqual(load_show_document(path)["cues"][0]["section"], "Show historique")

    def test_builder_mapping_keeps_metadata_and_never_invents_timecode(self):
        values = builder_import_values(sample_document())
        self.assertEqual(values[0]["mode"], "manual")
        self.assertNotIn("timecode", values[0])
        self.assertEqual(values[0]["builder"]["role"], "ROXY")
        self.assertEqual(values[0]["builder"]["resolved_artist"], "Élodie")
        document, cue = create_show_cue({"version": 1, "cues": []}, values[0])
        self.assertEqual(cue["builder"]["resolved_artist"], "Élodie")
        self.assertEqual(cue["builder"]["resolved_microphone"], "HF3")
        document, cue = update_show_cue(document, cue["id"], {"text": "Modifié"})
        self.assertEqual(cue["builder"]["role"], "ROXY")
        timed_source = sample_document()
        timed_source["cues"][0]["timecode"] = "01:02:03:04"
        timed = builder_import_values(timed_source)[0]
        self.assertEqual((timed["mode"], timed["timecode"]), ("timed", "01:02:03:04"))
        self.assertEqual(timed["posts"], ["FOH", "RETOURS", "PLATEAU"])

    def test_role_alias_preshow_punk_resolves_plain_punk_without_rewriting_labels(self):
        distribution = [{
            "role": "Preshow Punk",
            "artist": "Mathilde",
            "active": True,
            "equipment_slots": [
                {"type": "MICRO", "value": "Main 4"},
                {"type": "IEM", "value": "IEM 4"},
            ],
            "notes": "",
        }]

        cue = {
            "role": "PUNK",
            "text": "Donner HF M Punk",
        }

        resolved = resolve_builder_cue(cue, distribution)

        self.assertEqual(resolved["role"], "PUNK")
        self.assertEqual(resolved["artist"], "Mathilde")
        self.assertEqual(resolved["microphone"], "Main 4")
        self.assertEqual(resolved["iem"], "IEM 4")
        self.assertEqual(resolved["distribution_status"], "active")

        validation = validate_builder_document({
            "cues": [{
                "id": "builder_punk",
                "role": "PUNK",
                "text": "Donner HF M Punk",
            }],
            "distribution": distribution,
        })

        self.assertNotIn("PUNK", validation["unknown_roles"])
        self.assertNotIn("PUNK", validation["roles_without_active_artist"])

    def test_distribution_resolution_and_all_explicit_overrides(self):
        distribution = sample_document()["distribution"]
        base = {"role": "ROXY", "text": "Entrée"}
        resolved = resolve_builder_cue(base, distribution)
        self.assertEqual((resolved["artist"], resolved["microphone"], resolved["iem"]),
                         ("Élodie", "HF3", "IEM2"))
        overridden = resolve_builder_cue({**base, "artist": "Invitée", "microphone": "HF9",
                                          "iem": "IEM9", "equipment": "Cape"}, distribution)
        self.assertEqual((overridden["artist"], overridden["microphone"], overridden["iem"],
                          overridden["equipment"]), ("Invitée", "HF9", "IEM9", "Cape"))
        self.assertTrue(all(overridden["overrides"].values()))

    def test_resolution_ignores_inactive_and_reports_missing_multiple_or_no_role(self):
        distribution = sample_document()["distribution"]
        self.assertNotEqual(resolve_builder_cue({"role": "ROXY", "text": "X"}, distribution)["artist"], "Zoé")
        self.assertEqual(resolve_builder_cue({"role": "ABSENT", "text": "X"}, distribution)["distribution_status"], "missing")
        self.assertEqual(resolve_builder_cue({"text": "Sans rôle"}, distribution)["distribution_status"], "missing")
        distribution[1]["active"] = True
        multiple = resolve_builder_cue({"role": "ROXY", "text": "X"}, distribution)
        self.assertEqual((multiple["distribution_status"], multiple["artist"]), ("multiple", ""))

    def test_storage_is_atomic_and_keeps_structured_role_artist_distribution(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "showcue_builder.json"
            with mock.patch("showcue_builder.os.replace", wraps=__import__("os").replace) as replace:
                saved = save_builder_document(path, sample_document())
            self.assertEqual(load_builder_document(path), saved)
            self.assertEqual(saved["cues"][0]["role"], "ROXY")
            self.assertEqual(saved["distribution"][0]["artist"], "Élodie")
            replace.assert_called_once()

    def test_legacy_cue_values_remain_explicit_overrides_after_reload(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "showcue_builder.json"
            saved = save_builder_document(path, sample_document())
            loaded = load_builder_document(path)
        self.assertEqual(loaded["cues"][0]["artist"], saved["cues"][0]["artist"])
        resolved = resolve_builder_cue(loaded["cues"][0], loaded["distribution"])
        self.assertTrue(resolved["overrides"]["microphone"])
        self.assertTrue(resolved["overrides"]["iem"])
        self.assertTrue(resolved["overrides"]["equipment"])

    def test_xlsx_round_trip_preserves_accents_empty_tc_posts_and_distribution(self):
        expected = normalize_builder_document(sample_document())
        loaded, unknown = import_xlsx(export_xlsx(expected))
        cue = loaded["cues"][0]
        self.assertEqual(unknown, [])
        self.assertEqual((cue["timecode"], cue["text"], cue["equipment"]),
                         ("", "ROXY — TEST EAR", "Accessoire Étoile"))
        self.assertEqual((cue["foh"], cue["ret"], cue["plt"], cue["lum"]),
                         (True, True, True, False))
        self.assertEqual([row["artist"] for row in loaded["distribution"]], ["Élodie", "Zoé"])
        self.assertEqual([row["active"] for row in loaded["distribution"]], [True, False])

    def test_xlsx_and_csv_round_trip_new_slots_and_import_legacy_distribution(self):
        expected = slotted_document()["distribution"][0]["equipment_slots"]
        xlsx, _ = import_xlsx(export_xlsx(slotted_document()))
        csv_document, _ = import_csv(export_csv(slotted_document()))
        self.assertEqual(xlsx["distribution"][0]["equipment_slots"], expected)
        self.assertEqual(csv_document["distribution"][0]["equipment_slots"], expected)
        legacy_loaded, _ = import_xlsx(legacy_xlsx_payload())
        self.assertEqual(legacy_loaded["distribution"][0]["equipment_slots"][0],
                         {"type": "MICRO", "value": "M3 / C3"})

    def test_reload_persists_slots_and_does_not_rewrite_on_read(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "showcue_builder.json"
            saved = save_builder_document(path, slotted_document())
            loaded = load_builder_document(path)
        self.assertEqual(loaded["distribution"], saved["distribution"])

    def test_legacy_load_normalizes_in_memory_without_rewriting_disk(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "showcue_builder.json"
            path.write_text(json.dumps(sample_document(), ensure_ascii=False), encoding="utf-8")
            before = path.read_bytes()
            loaded = load_builder_document(path)
            self.assertEqual(path.read_bytes(), before)
        self.assertEqual(loaded["distribution"][0]["equipment_slots"][0],
                         {"type": "MICRO", "value": "HF3"})

    def test_csv_accepts_semicolon_and_comma_and_reports_unknown_columns(self):
        loaded, unknown = import_csv(export_csv(sample_document()))
        self.assertEqual((loaded["cues"][0]["role"], loaded["cues"][0]["timecode"]),
                         ("ROXY", ""))
        comma = b'TC,TEXTE,INCONNUE\n,Annonce,conservee\n'
        loaded, unknown = import_csv(comma)
        self.assertEqual(loaded["cues"][0]["text"], "Annonce")
        self.assertEqual(unknown, ["INCONNUE"])

    def test_validation_flags_invalid_tc_empty_text_and_multiple_active_cast(self):
        document = sample_document()
        document["cues"].append({"timecode": "00:99:00:00", "text": "", "role": "INCONNU"})
        document["distribution"][1]["active"] = True
        validation = validate_builder_document(document)
        self.assertFalse(validation["ready"])
        self.assertEqual(len(validation["invalid_timecodes"]), 1)
        self.assertEqual(len(validation["empty_texts"]), 1)
        self.assertEqual(validation["roles_with_multiple_active_artists"], ["ROXY"])
        self.assertIn("INCONNU", validation["roles_without_active_artist"])


class ShowCueBuilderRouteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import app
        cls.app_module = app

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.data = Path(self.temporary.name) / "ShowCue"
        save_show_document(self.data / "show_cues.json", {"cues": [
            {"id": "cue_official", "mode": "timed", "timecode": "00:00:05:00",
             "text": "Officiel", "posts": ["FOH"], "status": "official"}]})
        registry = initialize_show_cue_sessions(self.data)
        self.session_id = registry["active_session_id"]
        self.cue_path, _ = active_session_paths(self.data, registry)
        self.patch = mock.patch.object(self.app_module, "SHOW_CUES_DATA_DIRECTORY", self.data)
        self.patch.start()
        self.client = self.app_module.app.test_client()

    def tearDown(self):
        self.patch.stop()
        self.temporary.cleanup()

    def test_builder_page_and_save_are_separate_from_official_showcue(self):
        original = self.cue_path.read_bytes()
        page = self.client.get("/show-info/builder")
        self.assertEqual(page.status_code, 200)
        self.assertIn("ADOPTER LA PRÉVISUALISATION", page.get_data(as_text=True))
        self.assertIn("captureBuilderTc", page.get_data(as_text=True))
        self.assertIn("setTimeout(()=>save(),750)", page.get_data(as_text=True))
        self.assertIn("MODIFICATIONS…", page.get_data(as_text=True))
        self.assertIn("ERREUR DE SAUVEGARDE", page.get_data(as_text=True))
        self.assertNotIn("setInterval", page.get_data(as_text=True))
        self.assertNotIn("AbletonOSC", page.get_data(as_text=True))
        response = self.client.put("/show-info/builder/document", json={
            "session_id": self.session_id, "document": sample_document()})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.cue_path.read_bytes(), original)
        self.assertTrue((self.cue_path.parent / "showcue_builder.json").is_file())

    def test_xlsx_import_is_preview_only_until_explicit_builder_save(self):
        payload = export_xlsx(sample_document())
        response = self.client.post("/show-info/builder/import", data={
            "file": (io.BytesIO(payload), "conduite.xlsx")})
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.get_json()["saved"])
        self.assertFalse((self.cue_path.parent / "showcue_builder.json").exists())

    def test_export_routes_round_trip_current_builder(self):
        self.client.put("/show-info/builder/document", json={
            "session_id": self.session_id, "document": sample_document()})
        xlsx = self.client.get("/show-info/builder/export.xlsx")
        self.assertEqual(xlsx.status_code, 200)
        loaded, _ = import_xlsx(xlsx.data)
        self.assertEqual(loaded["distribution"][0]["artist"], "Élodie")
        csv_response = self.client.get("/show-info/builder/export.csv")
        self.assertEqual(csv_response.status_code, 200)
        self.assertIn("ROXY — TEST EAR", csv_response.data.decode("utf-8-sig"))

    def test_stale_session_cannot_overwrite_builder(self):
        response = self.client.put("/show-info/builder/document", json={
            "session_id": "session_stale", "document": sample_document()})
        self.assertEqual(response.status_code, 409)

    def test_explicit_preview_then_import_adds_without_replacing_existing_cue(self):
        original = load_show_document(self.cue_path)["cues"][0]
        self.client.put("/show-info/builder/document", json={
            "session_id": self.session_id, "document": sample_document()})
        preview = self.client.post("/show-info/builder/showcue-preview", json={
            "session_id": self.session_id})
        self.assertEqual(preview.status_code, 200)
        payload = preview.get_json()
        self.assertTrue(payload["ready"])
        self.assertEqual((payload["will_add"], payload["will_replace"], payload["information_lost"]),
                         (1, 0, []))
        imported = self.client.post("/show-info/builder/showcue-import", json={
            "token": payload["token"], "confirm": True})
        self.assertEqual(imported.status_code, 201)
        cues = load_show_document(self.cue_path)["cues"]
        self.assertEqual(cues[0]["id"], original["id"])
        self.assertEqual(len(cues), 2)
        added = cues[1]
        self.assertTrue(added["id"].startswith("cue_"))
        self.assertEqual((added["mode"], added["section"]), ("manual", "IEM"))
        self.assertEqual(added["builder"]["resolved_artist"], "Élodie")

    def test_import_requires_confirmation_and_rejects_changed_builder(self):
        self.client.put("/show-info/builder/document", json={
            "session_id": self.session_id, "document": sample_document()})
        token = self.client.post("/show-info/builder/showcue-preview", json={
            "session_id": self.session_id}).get_json()["token"]
        self.assertEqual(self.client.post("/show-info/builder/showcue-import", json={
            "token": token}).status_code, 400)
        token = self.client.post("/show-info/builder/showcue-preview", json={
            "session_id": self.session_id}).get_json()["token"]
        changed = sample_document()
        changed["cues"][0]["text"] = "Autre"
        changed["revision"] = 1
        self.client.put("/show-info/builder/document", json={
            "session_id": self.session_id, "document": changed})
        self.assertEqual(self.client.post("/show-info/builder/showcue-import", json={
            "token": token, "confirm": True}).status_code, 409)

    def test_builder_is_local_only_but_showcue_and_distribution_are_network_visible(self):
        remote = {"REMOTE_ADDR": "192.168.10.24"}
        self.assertEqual(self.client.get("/show-info", environ_base=remote).status_code, 200)
        self.assertEqual(self.client.get("/show-info/status?post=FOH",
                                         environ_base=remote).status_code, 200)
        paths = [
            ("get", "/show-info/builder"),
            ("get", "/show-info/builder/document"),
            ("put", "/show-info/builder/document"),
            ("post", "/show-info/builder/import"),
            ("get", "/show-info/builder/export.xlsx"),
            ("post", "/show-info/builder/showcue-preview"),
            ("post", "/show-info/builder/showcue-import"),
        ]
        for method, path in paths:
            with self.subTest(path=path):
                response = getattr(self.client, method)(path, environ_base=remote)
                self.assertEqual(response.status_code, 403)

    def test_plateau_switches_distribution_persistently_without_touching_showcue(self):
        original = self.cue_path.read_bytes()
        saved = self.client.put("/show-info/builder/document", json={
            "session_id": self.session_id, "document": sample_document()}).get_json()["document"]
        response = self.client.put("/show-info/distribution/active", json={
            "session_id": self.session_id, "post": "PLATEAU", "role": "ROXY",
            "artist": "Zoé", "revision": saved["revision"]})
        self.assertEqual(response.status_code, 200)
        distribution = response.get_json()["distribution"]
        self.assertEqual(distribution["roles"][0]["active"]["artist"], "Zoé")
        reloaded = load_builder_document(self.cue_path.parent / "showcue_builder.json")
        self.assertEqual([row["active"] for row in reloaded["distribution"]], [False, True])
        self.assertEqual(self.cue_path.read_bytes(), original)
        self.assertEqual(self.client.get("/show-info/status?post=FOH").get_json()
                         ["distribution"]["roles"][0]["active"]["artist"], "Zoé")

    def test_distribution_rejects_non_plateau_and_stale_builder_save(self):
        saved = self.client.put("/show-info/builder/document", json={
            "session_id": self.session_id, "document": sample_document()}).get_json()["document"]
        forbidden = self.client.put("/show-info/distribution/active", json={
            "session_id": self.session_id, "post": "FOH", "role": "ROXY",
            "artist": "Zoé", "revision": saved["revision"]})
        self.assertEqual(forbidden.status_code, 403)
        self.assertEqual(self.client.put("/show-info/distribution/active", json={
            "session_id": self.session_id, "post": "PLATEAU", "role": "ROXY",
            "artist": "Zoé", "revision": saved["revision"]}).status_code, 200)
        stale = self.client.put("/show-info/builder/document", json={
            "session_id": self.session_id, "document": saved})
        self.assertEqual(stale.status_code, 409)
        document = load_builder_document(self.cue_path.parent / "showcue_builder.json")
        self.assertTrue(document["distribution"][1]["active"])

    def test_server_rejects_four_equipment_slots_and_multiple_active_artists(self):
        too_many = slotted_document()
        too_many["distribution"][0]["equipment_slots"].append(
            {"type": "AUTRE", "value": "QUATRIÈME"})
        response = self.client.put("/show-info/builder/document", json={
            "session_id": self.session_id, "document": too_many})
        self.assertEqual(response.status_code, 400)
        self.assertIn("maximum 3 équipements", response.get_json()["message"])
        multiple = slotted_document()
        multiple["distribution"][1]["active"] = True
        response = self.client.put("/show-info/builder/document", json={
            "session_id": self.session_id, "document": multiple})
        self.assertEqual(response.status_code, 400)
        self.assertIn("un seul artiste actif", response.get_json()["message"])

    def test_distribution_can_be_explicitly_unassigned(self):
        saved = self.client.put("/show-info/builder/document", json={
            "session_id": self.session_id, "document": sample_document()}).get_json()["document"]
        response = self.client.put("/show-info/distribution/active", json={
            "session_id": self.session_id, "post": "PLATEAU", "role": "ROXY",
            "artist": "", "revision": saved["revision"]})
        self.assertIsNone(response.get_json()["distribution"]["roles"][0]["active"])

    def test_showcue_resolves_imported_role_from_current_distribution(self):
        saved = self.client.put("/show-info/builder/document", json={
            "session_id": self.session_id, "document": slotted_document()}).get_json()["document"]
        preview = self.client.post("/show-info/builder/showcue-preview", json={
            "session_id": self.session_id}).get_json()
        self.client.post("/show-info/builder/showcue-import", json={
            "token": preview["token"], "confirm": True})
        before = self.client.get("/show-info/status?post=FOH").get_json()
        imported = next(cue for cue in before["conduite"]["manual"]
                        if cue.get("builder", {}).get("role") == "DIRECTRICE")
        self.assertEqual([slot["value"] for slot in imported["resolved"]["equipment_slots"]],
                         ["M3 / C3", "M7 / C7", "IEM 3"])
        self.assertIsNone(imported["resolved"]["microphone"])
        self.client.put("/show-info/distribution/active", json={
            "session_id": self.session_id, "post": "PLATEAU", "role": "DIRECTRICE",
            "artist": "AUTRE", "revision": saved["revision"]})
        status = self.client.get("/show-info/status?post=FOH").get_json()
        imported = next(cue for cue in status["conduite"]["manual"]
                        if cue.get("builder", {}).get("role") == "DIRECTRICE")
        self.assertEqual(imported["resolved"]["artist"], "AUTRE")
        self.assertEqual(imported["resolved"]["equipment_slots"], [])

    def test_builder_desktop_and_future_als_affordance_are_static_only(self):
        root = Path(__file__).resolve().parents[1]
        launcher = (root / "showcue_builder_desktop.py").read_text(encoding="utf-8")
        spec = (root / "CL ShowCue Builder.spec").read_text(encoding="utf-8")
        page = self.client.get("/show-info/builder").get_data(as_text=True)
        self.assertIn("127.0.0.1:5050/show-info/builder", launcher)
        self.assertIn("CL ShowCue Builder.app", spec)
        self.assertIn("IMPORT ALS — À VENIR", page)
        self.assertIn("+ ÉQUIPEMENT", page)
        self.assertIn("equipment_slots", page)
        self.assertIn("setTimeout(()=>save(),750)", page)
        self.assertNotIn("AbletonOSC", launcher)


if __name__ == "__main__":
    unittest.main()
