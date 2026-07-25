import hashlib
import json
import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEVICES = ROOT / "M4L" / "Devices"
INSTALL = ROOT / "M4L" / "Install"


def read_amxd(path: Path):
    data = path.read_bytes()
    if data[:4] != b"ampf" or data[24:28] != b"ptch":
        raise AssertionError(f"Conteneur AMXD inattendu : {path}")
    payload_size = struct.unpack("<I", data[28:32])[0]
    payload = data[32 : 32 + payload_size]
    if len(payload) != payload_size or len(data) != 32 + payload_size:
        raise AssertionError(f"Taille AMXD incohérente : {path}")
    return json.loads(payload.decode("utf-8"))


def sha256(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class MaxForLiveDistributionTests(unittest.TestCase):
    def test_each_device_has_source_and_installable_amxd(self):
        expected = {
            "Paradis Latin AutoScene": [
                "Paradis Latin AutoScene",
                "Paradis Latin AutoScene - Live 10",
            ],
            "XFADER OSC BRIDGE v8": ["XFADER OSC BRIDGE v8"],
            "LTC Display v2.0 Remote Config": [
                "LTC Display v2.0 Remote Config"
            ],
        }
        for directory, device_names in expected.items():
            with self.subTest(device=directory):
                device_dir = DEVICES / directory
                self.assertTrue(device_dir.is_dir())
                for name in device_names:
                    self.assertTrue((device_dir / f"{name}.maxpat").is_file())
                    self.assertTrue((device_dir / f"{name}.amxd").is_file())

    def test_autoscene_sources_and_amxd_use_relative_javascript_path(self):
        device_dir = DEVICES / "Paradis Latin AutoScene"
        for name in (
            "Paradis Latin AutoScene",
            "Paradis Latin AutoScene - Live 10",
        ):
            with self.subTest(device=name):
                source = json.loads(
                    (device_dir / f"{name}.maxpat").read_text(encoding="utf-8")
                )
                compiled = read_amxd(device_dir / f"{name}.amxd")
                self.assertEqual(source, compiled)
                texts = [
                    entry["box"].get("text", "")
                    for entry in source["patcher"]["boxes"]
                ]
                self.assertIn("js ParadisLatin_AutoScene.js", texts)
                self.assertNotIn("/Users/", json.dumps(source))

    def test_autoscene_dependencies_are_distributed(self):
        device_dir = DEVICES / "Paradis Latin AutoScene"
        for filename in (
            "ParadisLatin_AutoScene.js",
            "paradis_latin_logo.jpg",
        ):
            with self.subTest(filename=filename):
                source_file = device_dir / filename
                install_file = INSTALL / filename
                self.assertTrue(source_file.is_file())
                self.assertTrue(install_file.is_file())
                self.assertEqual(sha256(source_file), sha256(install_file))

    def test_installable_autoscene_matches_versioned_device(self):
        device_dir = DEVICES / "Paradis Latin AutoScene"
        for name in (
            "Paradis Latin AutoScene",
            "Paradis Latin AutoScene - Live 10",
        ):
            with self.subTest(device=name):
                self.assertEqual(
                    sha256(device_dir / f"{name}.amxd"),
                    sha256(INSTALL / f"{name}.amxd"),
                )

    def test_live_10_variant_keeps_explicit_compatibility_metadata(self):
        device = read_amxd(
            DEVICES
            / "Paradis Latin AutoScene"
            / "Paradis Latin AutoScene - Live 10.amxd"
        )
        patcher = device["patcher"]
        self.assertEqual(patcher["appversion"]["major"], 8)
        self.assertEqual(patcher["minimum_live_version"], "10.0.0")
        self.assertEqual(patcher["minimum_max_version"], "8.0.0")

    def test_ltc_cache_script_is_distributed(self):
        source = DEVICES / "LTC Display v2.0 Remote Config" / "cache.js"
        installed = INSTALL / "cache.js"
        self.assertTrue(source.is_file())
        self.assertTrue(installed.is_file())
        self.assertEqual(sha256(source), sha256(installed))


if __name__ == "__main__":
    unittest.main()
