"""Executable state-machine and OS-lock regression tests; no production MIDI traffic."""
from pathlib import Path
import subprocess
import sys
import pytest

ROOT = Path(__file__).resolve().parents[1]

@pytest.mark.skipif(sys.platform != 'darwin', reason='Native macOS supervision')
def test_local_simulator_lifecycle(tmp_path):
    binary = tmp_path / 'lifecycle'
    subprocess.run(['clang', '-fobjc-arc', '-fblocks', '-framework', 'Foundation',
                    str(ROOT / 'tests/native/test_local_simulator_supervisor.m'),
                    '-o', str(binary)], check=True, capture_output=True)
    result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=10)
    assert 'PASS:' in result.stdout
