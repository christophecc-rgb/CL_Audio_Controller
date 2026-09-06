import json
import tempfile
import unittest
from pathlib import Path

from console_title_library import (
    ConsoleLibraryStore, LibraryImportError, MAX_FILE_SIZE, parse_import,
)


class ConsoleTitleLibraryTests(unittest.TestCase):
    def parse(self, text, name, console="cl5"):
        return parse_import(text.encode("utf-8"), name, console, "2026-08-25T12:00:00+00:00")

    def clf(self, family=b"CL", title=b"OUVERTURE"):
        data = bytearray(0x90)
        data[0x0C:0x0E] = (1).to_bytes(2, "big")
        data[0x10:0x12] = family
        data[0x12:0x13] = b" "
        data[0x38:0x3A] = (1).to_bytes(2, "big")
        data[0x3C:0x40] = (0x50).to_bytes(4, "big")
        data[0x50:0x56] = b"MEMAPI"
        data[0x5C:0x5C + len(title)] = title
        return bytes(data)

    def test_csv_simple_utf8_and_windows_lines(self):
        parsed = self.parse("memory,title\r\n1,OUVERTURE\r\n2,ÉTÉ À PARIS\r\n", "show.csv")
        self.assertEqual(parsed.libraries["cl5"], {1: "OUVERTURE", 2: "ÉTÉ À PARIS"})

    def test_csv_multiconsole(self):
        parsed = self.parse("console,memory,title\nCL5,1,A\nQL1,1,B\n", "show.csv", None)
        self.assertEqual(parsed.libraries, {"cl5": {1: "A"}, "ql1": {1: "B"}})

    def test_tsv(self):
        parsed = self.parse("memory\ttitle\n3\tFINAL\n", "show.tsv")
        self.assertEqual(parsed.libraries["cl5"][3], "FINAL")

    def test_json_single_and_multiconsole(self):
        single = self.parse(json.dumps({"console": "CL5", "scenes": [{"memory": 4, "title": "A"}]}), "a.json", None)
        multi = self.parse(json.dumps({"consoles": {"CL5": [{"memory": 4, "title": "A"}], "QL1": [{"memory": 5, "title": "B"}]}}), "b.json", None)
        self.assertEqual(single.libraries["cl5"], multi.libraries["cl5"])
        self.assertEqual(multi.libraries["ql1"], {5: "B"})

    def test_structured_txt(self):
        parsed = self.parse("# memory tab title\n6\tGÉNÉRIQUE\n", "show.txt")
        self.assertEqual(parsed.libraries["cl5"], {6: "GÉNÉRIQUE"})

    def test_export_style_txt_header_bom_and_windows_lines_are_reimportable(self):
        parsed = self.parse(
            "\ufeffmemory\ttitle\r\n1\tOUVERTURE\r\n64\tENTRACTE\r\n128\tFINAL\r\n",
            "modele.txt",
            "generic_library",
        )
        self.assertEqual(
            parsed.libraries["generic_library"],
            {1: "OUVERTURE", 64: "ENTRACTE", 128: "FINAL"},
        )
        self.assertEqual(
            [entry["midi_program"] for entry in parsed.canonical_for("generic_library")["entries"]],
            [0, 63, 127],
        )

    def test_txt_with_only_a_header_is_rejected(self):
        with self.assertRaisesRegex(LibraryImportError, "aucune entrée valide"):
            self.parse("memory\ttitle\r\n", "vide.txt", "generic_library")

    def test_existing_clf_parser_and_console_assignment(self):
        parsed = parse_import(self.clf(), "CL5.CLF", "cl5")
        self.assertEqual(parsed.libraries["cl5"], {1: "OUVERTURE"})
        with self.assertRaisesRegex(LibraryImportError, "destiné à CL5"):
            parse_import(self.clf(), "wrong.CLF", "ql1")

    def test_dynamic_ql_library_id_keeps_ql_clf_family(self):
        parsed = parse_import(self.clf(family=b"QL"), "QL3.CLF", "ql3")
        self.assertEqual(parsed.libraries["ql3"], {1: "OUVERTURE"})
        canonical = parsed.canonical_for("ql3")
        self.assertEqual(canonical["console"], "QL3")

    def test_dynamic_text_library_id_is_supported(self):
        parsed = self.parse("memory,title\n1,SCENE QL3\n", "ql3.csv", "ql3")
        self.assertEqual(parsed.libraries["ql3"], {1: "SCENE QL3"})

    def test_clf_family_mismatch_still_rejected_for_dynamic_id(self):
        with self.assertRaisesRegex(LibraryImportError, "destiné à CL5"):
            parse_import(self.clf(family=b"CL"), "wrong.CLF", "ql3")

    def test_all_text_formats_are_canonically_equivalent(self):
        values = [
            self.parse("memory,title\n7,FINAL\n", "a.csv"),
            self.parse("memory\ttitle\n7\tFINAL\n", "a.tsv"),
            self.parse('{"console":"CL5","scenes":[{"memory":7,"title":"FINAL"}]}', "a.json"),
            self.parse("7\tFINAL\n", "a.txt"),
        ]
        self.assertTrue(all(value.libraries["cl5"] == {7: "FINAL"} for value in values))

    def test_duplicate_policy(self):
        exact = self.parse("memory,title\n1,A\n1,A\n", "a.csv")
        self.assertEqual(exact.libraries["cl5"], {1: "A"})
        self.assertTrue(exact.warnings)
        with self.assertRaisesRegex(LibraryImportError, "doublon ambigu"):
            self.parse("memory,title\n1,A\n1,B\n", "a.csv")

    def test_rejects_empty_unknown_oversize_dangerous_and_out_of_range(self):
        cases = [
            (b"", "a.csv", "fichier vide"),
            (b"x", "a.xlsx", "format inconnu"),
            (b"x" * (MAX_FILE_SIZE + 1), "a.csv", "trop volumineux"),
            (b"memory,title\n1,A\n", "../a.csv", "dangereux"),
            (b"memory,title\n129,A\n", "a.csv", "hors plage"),
        ]
        for data, name, message in cases:
            with self.subTest(name=name, message=message), self.assertRaisesRegex(LibraryImportError, message):
                parse_import(data, name, "cl5")

    def test_atomic_install_backup_and_failed_import_preserves_active(self):
        with tempfile.TemporaryDirectory() as temporary:
            store = ConsoleLibraryStore(Path(temporary) / "Console Files")
            first = self.parse("memory,title\n1,PREMIER\n", "one.csv")
            second = self.parse("memory,title\n1,SECOND\n", "two.csv")
            store.install(first, "cl5")
            active = store.canonical_path("cl5")
            store.install(second, "cl5")
            self.assertEqual(store.load("cl5")["library"], {1: "SECOND"})
            backup = active.with_suffix(active.suffix + ".backup")
            self.assertEqual(json.loads(backup.read_text(encoding="utf-8"))["entries"][0]["title"], "PREMIER")
            before = active.read_bytes()
            with self.assertRaises(LibraryImportError):
                parse_import(b"memory,title\n1,A\n1,B\n", "bad.csv", "cl5")
            self.assertEqual(active.read_bytes(), before)

    def test_migration_copies_valid_clf_without_deleting_original(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            desktop = root / "Desktop"
            desktop.mkdir()
            original = desktop / "CL5.CLF"
            original.write_bytes(self.clf())
            store = ConsoleLibraryStore(root / "Support" / "Console Files")
            self.assertEqual(store.migrate_legacy(desktop), {"cl5": str(original)})
            self.assertTrue(original.exists())
            loaded = store.load("cl5")
            self.assertEqual(loaded["library"], {1: "OUVERTURE"})
            self.assertEqual(loaded["migrated_from"], str(original))


if __name__ == "__main__":
    unittest.main()
