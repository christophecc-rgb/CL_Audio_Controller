import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools" / "cl_midi_network"
NATIVE_TEST = ROOT / "tests" / "native" / "CLMIDIEventTests.m"


class MidiEventTests(unittest.TestCase):
    def test_typed_midi_events_compile_and_pass(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            executable = Path(temporary_directory) / "CLMIDIEventTests"
            command = [
                "clang",
                "-mmacosx-version-min=10.15",
                "-fobjc-arc",
                "-Wall",
                "-Wextra",
                "-Werror",
                "-framework",
                "Foundation",
                "-framework",
                "CoreMIDI",
                "-I",
                str(TOOLS),
                str(TOOLS / "CLMIDIPacket.m"),
                str(TOOLS / "CLMIDIEvent.m"),
                str(NATIVE_TEST),
                "-o",
                str(executable),
            ]
            subprocess.run(command, check=True, capture_output=True, text=True)
            subprocess.run([str(executable)], check=True, capture_output=True, text=True)


if __name__ == "__main__":
    unittest.main()
