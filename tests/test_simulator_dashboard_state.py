"""Run actual dashboard state helpers without app startup or production MIDI."""
from pathlib import Path
import subprocess
import sys
import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.skipif(sys.platform != "darwin", reason="Native macOS dashboard")
@pytest.mark.parametrize("source", ["test_simulator_dashboard_state.m", "test_simulator_dashboard_control.m"])
def test_dashboard_simulator_ownership(tmp_path, source):
    binary = tmp_path / "dashboard-state"
    compiled = subprocess.run([
        "clang", "-fobjc-arc", "-fblocks", "-framework", "AppKit",
        "-framework", "Foundation", "-framework", "CoreMIDI", "-framework", "QuartzCore",
        str(ROOT / "tests/native" / source), "-o", str(binary),
    ], capture_output=True, text=True)
    assert compiled.returncode == 0, compiled.stderr
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    assert "PASS:" in result.stdout
