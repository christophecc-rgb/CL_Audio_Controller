import unittest
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[1]


class AppIconTests(unittest.TestCase):
    def test_panel_logo_and_macos_icon_source_are_identical(self):
        panel = Image.open(ROOT / "cl_audio_logo.png").convert("RGB")
        source = Image.open(
            ROOT / "assets" / "cl_audio_show_control_icon_1024.png"
        ).convert("RGB")
        self.assertEqual(panel.size, (1024, 1024))
        self.assertIsNone(ImageChops.difference(panel, source).getbbox())

    def test_spec_uses_the_canonical_icns_for_executable_and_bundle(self):
        source = (ROOT / "CL Audio Controller.spec").read_text()
        self.assertIn("icon=['CL_AUDIO.icns']", source)
        self.assertIn("icon='CL_AUDIO.icns'", source)
        self.assertIn("('cl_audio_logo.png', '.')", source)

    def test_icns_contains_every_required_macos_representation(self):
        with Image.open(ROOT / "CL_AUDIO.icns") as icon:
            self.assertEqual(icon.format, "ICNS")
            self.assertEqual(icon.size, (1024, 1024))
            sizes = set(icon.info["sizes"])
        self.assertTrue(
            {
                (512, 512, 2),
                (512, 512, 1),
                (256, 256, 2),
                (256, 256, 1),
                (128, 128, 2),
                (128, 128, 1),
                (32, 32, 2),
                (16, 16, 2),
            }.issubset(sizes)
        )

    def test_iconset_contains_the_expected_pixel_dimensions(self):
        expected = {
            "icon_16x16.png": (16, 16),
            "icon_16x16@2x.png": (32, 32),
            "icon_32x32.png": (32, 32),
            "icon_32x32@2x.png": (64, 64),
            "icon_128x128.png": (128, 128),
            "icon_128x128@2x.png": (256, 256),
            "icon_256x256.png": (256, 256),
            "icon_256x256@2x.png": (512, 512),
            "icon_512x512.png": (512, 512),
            "icon_512x512@2x.png": (1024, 1024),
        }
        for filename, dimensions in expected.items():
            with self.subTest(filename=filename):
                with Image.open(ROOT / "icon.iconset" / filename) as icon:
                    self.assertEqual(icon.size, dimensions)

    def test_midi_network_assistant_has_a_distinct_full_resolution_icon(self):
        source = Image.open(
            ROOT / "assets" / "cl_midi_network_assistant_icon_1024.png"
        )
        self.assertEqual(source.size, (1024, 1024))
        with Image.open(ROOT / "assets" / "CL_MIDI_Network_Assistant.icns") as icon:
            self.assertEqual(icon.format, "ICNS")
            self.assertEqual(icon.size, (1024, 1024))

        show_control = Image.open(
            ROOT / "assets" / "cl_audio_show_control_icon_1024.png"
        ).convert("RGB")
        self.assertIsNotNone(
            ImageChops.difference(source.convert("RGB"), show_control).getbbox()
        )


if __name__ == "__main__":
    unittest.main()
