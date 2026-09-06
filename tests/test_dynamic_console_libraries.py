import io
import tempfile
import unittest
from pathlib import Path
from dataclasses import replace
from types import SimpleNamespace
from unittest import mock

import app
from console_title_library import ConsoleLibraryStore
from device_profiles import DeviceConfiguration, default_device_configuration


class DynamicConsoleLibraryTests(unittest.TestCase):
    def setUp(self):
        defaults = default_device_configuration()
        ql1 = defaults.by_id("console_b")
        ql3 = replace(
            ql1,
            id="console_c",
            display_name="QL3",
            midi_channel=3,
            ableton_track_aliases=("PGM CHANGE QL3",),
            library="ql3",
            legacy_key=None,
        )
        self.configuration = DeviceConfiguration(
            devices=defaults.devices + (ql3,)
        )

    def configuration_patch(self):
        return mock.patch.object(
            app,
            "load_device_configuration_result",
            return_value=SimpleNamespace(configuration=self.configuration),
        )

    def test_configured_library_ids_follow_device_profiles(self):
        with self.configuration_patch():
            self.assertEqual(
                app.configured_console_library_ids(),
                ("cl5", "ql1", "ql3"),
            )

    def test_dynamic_library_lookup_route_accepts_ql3(self):
        with self.configuration_patch(), mock.patch.dict(
            app.state,
            {
                "console_scene_libraries": {"ql3": {42: "QL3 TEST"}},
                "console_title_offsets": {"ql3": 0},
                "console_title_mode": "imported_library",
                "console_scene_map": {},
                "playing_scene": -1,
                "playing_scene_name": "",
            },
            clear=False,
        ):
            response = app.app.test_client().get(
                "/console-scene-title?console=ql3&midi_program=41"
            )

        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertEqual(payload["console"], "ql3")
        self.assertEqual(payload["scene_memory"], 42)
        self.assertEqual(payload["title"], "QL3 TEST")
        self.assertEqual(payload["title_source"], "imported_library")

    def test_unconfigured_library_lookup_is_rejected(self):
        with self.configuration_patch():
            response = app.app.test_client().get(
                "/console-scene-title?console=unknown&midi_program=0"
            )

        self.assertEqual(response.status_code, 400)

    def test_dynamic_library_import_preview_accepts_ql3(self):
        with self.configuration_patch():
            response = app.app.test_client().post(
                "/console-library/import/ql3",
                data={
                    "preview": "1",
                    "file": (
                        io.BytesIO(b"memory,title\n1,QL3 OUVERTURE\n"),
                        "ql3.csv",
                    ),
                },
                content_type="multipart/form-data",
            )

        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["preview"]["console"], "QL3")
        self.assertEqual(payload["preview"]["entry_count"], 1)

    def test_dynamic_text_import_persists_and_reloads_from_canonical_store(self):
        with tempfile.TemporaryDirectory() as temporary:
            store = ConsoleLibraryStore(Path(temporary) / "Console Files")
            with self.configuration_patch(), mock.patch.object(app, "CONSOLE_LIBRARY_STORE", store):
                response = app.app.test_client().post(
                    "/console-library/import/ql3",
                    data={
                        "file": (
                            io.BytesIO(b"\xef\xbb\xbfmemory\ttitle\r\n1\tOUVERTURE\r\n64\tENTRACTE\r\n128\tFINAL\r\n"),
                            "modele.txt",
                        ),
                    },
                    content_type="multipart/form-data",
                )
                reloaded = store.load("ql3")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(reloaded["library"], {1: "OUVERTURE", 64: "ENTRACTE", 128: "FINAL"})
        self.assertEqual(response.get_json()["library"]["source_format"], "TXT")

    def test_control_change_and_note_profiles_do_not_create_libraries(self):
        defaults = default_device_configuration()
        base = defaults.by_id("console_b")
        configuration = DeviceConfiguration(devices=defaults.devices + (
            replace(base, id="control_x", signal_type="control_change", library="control_library"),
            replace(base, id="note_x", signal_type="note", library="note_library"),
        ))
        with mock.patch.object(
            app, "load_device_configuration_result",
            return_value=SimpleNamespace(configuration=configuration),
        ):
            self.assertEqual(app.configured_console_library_ids(), ("cl5", "ql1"))


if __name__ == "__main__":
    unittest.main()
