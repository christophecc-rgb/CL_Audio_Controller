import json
import unittest
from pathlib import Path

from scripts.create_ltc_remote_device import parse_port_text


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MAX_SOURCE = PROJECT_ROOT / "M4L" / "LTC Display v2.0 Remote Config.maxpat"
MAX_DEVICE = PROJECT_ROOT / "M4L" / "LTC Display v2.0 Remote Config.amxd"


def walk_boxes(patcher):
    for item in patcher.get("boxes", []):
        candidate = item["box"]
        yield candidate
        if "patcher" in candidate:
            yield from walk_boxes(candidate["patcher"])


def load_max_payload(path):
    raw = path.read_bytes()
    start = raw.find(b"{")
    if start < 0:
        raise AssertionError(f"aucun patcher JSON dans {path}")
    payload, _ = json.JSONDecoder().raw_decode(
        raw[start:].decode("utf-8", errors="ignore")
    )
    return payload


def patchline_pairs(patcher):
    return {
        (
            tuple(item["patchline"]["source"]),
            tuple(item["patchline"]["destination"]),
        )
        for item in patcher.get("lines", [])
    }


class LTCMaxDeviceTests(unittest.TestCase):
    def test_v2_source_has_visible_persistent_destination_controls(self):
        payload = load_max_payload(MAX_SOURCE)
        boxes = list(walk_boxes(payload["patcher"]))
        by_id = {item.get("id"): item for item in boxes}
        self.assertEqual(
            sum(item.get("text") == "udpsend 127.0.0.1 63123" for item in boxes),
            1,
        )
        self.assertEqual(by_id["obj-ltc-host"]["text"], "127.0.0.1")
        self.assertTrue(by_id["obj-ltc-host"]["presentation"])
        self.assertEqual(by_id["obj-ltc-host"]["parameter_enable"], 0)
        self.assertEqual(by_id["obj-ltc-port"]["parameter_enable"], 0)
        self.assertEqual(by_id["obj-ltc-port"]["maxclass"], "textedit")
        self.assertEqual(by_id["obj-ltc-port"]["text"], "63123")
        self.assertEqual(by_id["obj-ltc-port"]["varname"], "ltc_port_input")
        for identifier in (
            "obj-ltc-destination-label",
            "obj-ltc-host",
            "obj-ltc-port",
        ):
            _, y, _, height = by_id[identifier]["presentation_rect"]
            self.assertGreaterEqual(y, 0)
            self.assertLessEqual(y + height, 169)
        self.assertNotIn("deviceheight", payload["patcher"])

        self.assertEqual(by_id["obj-ltc-route-text"]["text"], "route text")
        self.assertEqual(by_id["obj-ltc-host-message"]["text"], "prepend host")
        host_pattr = by_id["obj-ltc-host-pattr"]
        self.assertEqual(
            host_pattr["saved_object_attributes"]["parameter_enable"], 1
        )
        self.assertIn("@initial 127.0.0.1", host_pattr["text"])
        self.assertIn("@type symbol", host_pattr["text"])
        self.assertIn("@parameter_enable 1", host_pattr["text"])
        host_parameter = host_pattr["saved_attribute_attributes"]["valueof"]
        self.assertEqual(host_parameter["parameter_invisible"], 1)
        self.assertEqual(host_parameter["parameter_type"], 3)
        self.assertEqual(by_id["obj-ltc-port-split"]["text"], "split 1 65535")
        self.assertEqual(
            by_id["obj-ltc-port-restore-split"]["text"], "split 1 65535"
        )
        self.assertEqual(by_id["obj-ltc-port-message"]["text"], "prepend port")
        self.assertEqual(by_id["obj-ltc-port-route-text"]["text"], "route text")
        self.assertEqual(
            by_id["obj-ltc-port-fromsymbol"]["text"], "fromsymbol"
        )
        self.assertEqual(by_id["obj-ltc-port-int"]["text"], "route int")
        self.assertEqual(by_id["obj-ltc-port-restore-int"]["text"], "i")
        port_pattr = by_id["obj-ltc-port-pattr"]
        self.assertEqual(
            port_pattr["saved_object_attributes"]["parameter_enable"], 1
        )
        self.assertIn("@initial 63123.", port_pattr["text"])
        self.assertIn("@type float", port_pattr["text"])
        self.assertIn("@parameter_enable 1", port_pattr["text"])
        port_parameter = port_pattr["saved_attribute_attributes"]["valueof"]
        self.assertEqual(port_parameter["parameter_invisible"], 1)
        self.assertEqual(port_parameter["parameter_type"], 0)
        self.assertEqual(port_parameter["parameter_unitstyle"], 0)
        self.assertEqual(port_parameter["parameter_mmin"], 1.0)
        self.assertEqual(port_parameter["parameter_mmax"], 65535.0)
        self.assertNotIn("port 0", str(payload))
        self.assertNotIn("port 127", str(payload))
        self.assertNotIn("host text", str(payload))
        # 63124 doit traverser une saisie texte et une conversion décimale sans
        # dépendre d'un glissement ou d'une plage MIDI 0..127.
        self.assertEqual(parse_port_text("63124"), 63124)
        self.assertLessEqual(63124, port_parameter["parameter_mmax"])
        self.assertNotIn("atoi", [item.get("text") for item in boxes])

    def test_configuration_paths_are_explicit_and_validated(self):
        payload = load_max_payload(MAX_SOURCE)
        lines = patchline_pairs(payload["patcher"])
        expected = {
            (("obj-ltc-host", 0), ("obj-ltc-route-text", 0)),
            (("obj-ltc-route-text", 0), ("obj-ltc-tosymbol", 0)),
            (("obj-ltc-tosymbol", 0), ("obj-ltc-host-pattr", 0)),
            (("obj-ltc-host-message", 0), ("obj-51", 3)),
            (("obj-ltc-port", 0), ("obj-ltc-port-route-text", 0)),
            (("obj-ltc-port-route-text", 0), ("obj-ltc-port-fromsymbol", 0)),
            (("obj-ltc-port-fromsymbol", 0), ("obj-ltc-port-int", 0)),
            (("obj-ltc-port-int", 0), ("obj-ltc-port-split", 0)),
            (("obj-ltc-port-split", 0), ("obj-ltc-port-pattr", 0)),
            (("obj-ltc-port-pattr", 0), ("obj-ltc-port-restore-int", 0)),
            (("obj-ltc-port-restore-int", 0), ("obj-ltc-port-restore-split", 0)),
            (("obj-ltc-port-message", 0), ("obj-51", 3)),
        }
        self.assertTrue(expected.issubset(lines))

        # Les valeurs restaurées passent elles aussi par la validation 1..65535.
        self.assertIn(
            (("obj-ltc-port-pattr", 0), ("obj-ltc-port-restore-int", 0)),
            lines,
        )
        self.assertIn(
            (("obj-ltc-port-restore-int", 0), ("obj-ltc-port-restore-split", 0)),
            lines,
        )
        # Aucun chemin direct depuis le contrôle ou pattr ne peut produire port 0.
        self.assertNotIn(
            (("obj-ltc-port", 0), ("obj-ltc-port-message", 0)), lines
        )
        self.assertNotIn(
            (("obj-ltc-port-pattr", 0), ("obj-ltc-port-message", 0)), lines
        )
        self.assertIn(
            (("obj-ltc-port-split", 1), ("obj-ltc-port-invalid", 0)), lines
        )
        self.assertIn(
            (("obj-ltc-port-invalid", 0), ("obj-ltc-port-pattr", 0)), lines
        )
        self.assertIn(
            (("obj-ltc-port-int", 1), ("obj-ltc-port-invalid", 0)), lines
        )
        identifiers = {
            item.get("id") for item in walk_boxes(payload["patcher"])
        }
        self.assertNotIn("obj-ltc-loadbang", identifiers)
        self.assertNotIn("obj-ltc-deferlow", identifiers)
        self.assertNotIn("obj-ltc-load-trigger", identifiers)

    def test_compiled_device_is_distinct_and_contains_v2_controls(self):
        source = load_max_payload(MAX_SOURCE)
        compiled = load_max_payload(MAX_DEVICE)
        compiled_boxes = list(walk_boxes(compiled["patcher"]))
        by_varname = {
            item.get("varname"): item for item in compiled_boxes if item.get("varname")
        }
        self.assertEqual(by_varname["ltc_destination"]["text"], "127.0.0.1")
        self.assertEqual(by_varname["ltc_port_input"]["text"], "63123")
        texts = [item.get("text") for item in compiled_boxes]
        self.assertIn("route text", texts)
        self.assertIn("fromsymbol", texts)
        self.assertNotIn("atoi", texts)
        self.assertIn("split 1 65535", texts)
        self.assertIn("prepend port", texts)
        port_store = next(
            item for item in compiled_boxes
            if item.get("text", "").startswith("pattr ltc_port_state ")
        )
        parameter = port_store["saved_attribute_attributes"]["valueof"]
        self.assertEqual(
            port_store["saved_object_attributes"]["parameter_enable"], 1
        )
        self.assertEqual(parameter["parameter_type"], 0)
        self.assertEqual(parameter["parameter_unitstyle"], 0)
        self.assertEqual(parameter["parameter_mmin"], 1.0)
        self.assertEqual(parameter["parameter_mmax"], 65535.0)

    def test_port_text_validation_matches_the_max_graph(self):
        self.assertEqual(parse_port_text("1"), 1)
        self.assertEqual(parse_port_text("63123"), 63123)
        self.assertEqual(parse_port_text("63124"), 63124)
        self.assertEqual(parse_port_text("65535"), 65535)
        for invalid in ("", "abc", "63124 63123", "0", "-1", "65536", "1.5"):
            self.assertIsNone(parse_port_text(invalid), invalid)
        self.assertNotEqual(parse_port_text("63124"), 54)


if __name__ == "__main__":
    unittest.main()
