import json
import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEVICE_DIR = ROOT / "M4L" / "Devices" / "XFADER OSC BRIDGE v8"
SOURCE = DEVICE_DIR / "XFADER OSC BRIDGE v8.maxpat"
DEVICE = DEVICE_DIR / "XFADER OSC BRIDGE v8.amxd"


def read_amxd(path: Path):
    raw = path.read_bytes()
    if raw[:4] != b"ampf" or raw[24:28] != b"ptch":
        raise AssertionError("AMXD invalide")
    length = struct.unpack("<I", raw[28:32])[0]
    return json.loads(raw[32 : 32 + length].rstrip(b"\0"))


def graph(payload):
    boxes = {
        item["box"]["id"]: item["box"].get("text", "")
        for item in payload["patcher"]["boxes"]
    }
    lines = {
        (
            item["patchline"]["source"][0],
            item["patchline"]["source"][1],
            item["patchline"]["destination"][0],
            item["patchline"]["destination"][1],
        )
        for item in payload["patcher"]["lines"]
    }
    return boxes, lines


class XfaderMaxDeviceTests(unittest.TestCase):
    def check_stable_remote_mapping(self, payload):
        boxes, lines = graph(payload)

        self.assertEqual(boxes["remote"], "live.remote~")
        self.assertEqual(boxes["lp"], "live.path live_set master_track mixer_device crossfader")
        self.assertIn(("lp", 0, "remote", 1), lines)
        self.assertIn(("clip", 0, "sig", 0), lines)
        self.assertIn(("sig", 0, "remote", 0), lines)

        self.assertNotIn("id 0", boxes.values())
        self.assertNotIn("delay 450", boxes.values())
        self.assertNotIn("t b b f", boxes.values())
        self.assertFalse(any(source == "clip" and destination == "lp" for source, _, destination, _ in lines))

    def test_editable_source_maps_once_on_load(self):
        self.check_stable_remote_mapping(json.loads(SOURCE.read_text(encoding="utf-8")))

    def test_installable_device_uses_same_stable_mapping(self):
        self.check_stable_remote_mapping(read_amxd(DEVICE))


if __name__ == "__main__":
    unittest.main()
