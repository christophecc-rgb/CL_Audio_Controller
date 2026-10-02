import json
from pathlib import Path
import subprocess
import sys
import tempfile
import pytest
from midi_endpoint_names import ALIASES, MTC_IAC, CLOCK_IAC, RETURN_RTP, resolve_endpoint, endpoint_matches

ROOT = Path(__file__).resolve().parents[1]

@pytest.mark.parametrize('canonical', ALIASES)
def test_priority_missing_and_unchanged_endpoints(canonical):
    assert resolve_endpoint([canonical], canonical) == canonical
    with pytest.raises(LookupError, match='Endpoint absent'):
        resolve_endpoint([], canonical)
    for alias in ALIASES[canonical]:
        assert resolve_endpoint([alias], canonical) == alias
        assert resolve_endpoint([alias, canonical], canonical) == canonical
        assert resolve_endpoint([alias, canonical], alias) == canonical
        assert endpoint_matches(alias, canonical)
        for other in ALIASES:
            assert endpoint_matches(alias, other) == (canonical == other)


def test_decorated_canonical_before_legacy_and_no_rtp_iac_confusion():
    assert resolve_endpoint(['Gestionnaire IAC MTC vers Logic', 'Gestionnaire IAC CL MTC IAC'], MTC_IAC) == 'Gestionnaire IAC CL MTC IAC'
    for available, requested in [('Réseau CL MTC', MTC_IAC), ('Réseau CL Ableton Clock', CLOCK_IAC)]:
        with pytest.raises(LookupError):
            resolve_endpoint([available], requested)
    assert endpoint_matches('Réseau Rtp MB Chris', RETURN_RTP)


@pytest.mark.skipif(sys.platform != 'darwin', reason='CoreMIDI requires macOS')
def test_native_resolver_and_identical_python_table():
    with tempfile.TemporaryDirectory() as tmp:
        binary = str(Path(tmp) / 'names')
        subprocess.run(['clang', '-fobjc-arc', '-fblocks', str(ROOT / 'tests/native/test_midi_endpoint_names.m'),
                        '-framework', 'Foundation', '-framework', 'CoreMIDI', '-o', binary], check=True)
        subprocess.run([binary], check=True, capture_output=True)
        table = json.loads(subprocess.check_output([binary, '--table']))
        assert table == {key: list(value) for key, value in ALIASES.items()}


def test_consumers_use_shared_resolution():
    for file in ['CLAbletonMTCBridge.m', 'CLSyncProbe.m', 'CLSyncMeter.m']:
        assert 'CLMIDIFindEndpoint(' in (ROOT / 'tools/ableton_mtc_bridge' / file).read_text()
    for file in ['CLMIDINetworkDashboard.m', 'CLConfigurationValidator.m']:
        assert 'CLMIDIResolveName(' in (ROOT / 'tools/cl_midi_network' / file).read_text()


def test_packaging_uses_explicit_rebuilt_bridge(monkeypatch):
    import runpy

    selected = {}

    class AnalysisReached(Exception):
        pass

    def capture_analysis(*args, **kwargs):
        selected.update(kwargs)
        raise AnalysisReached

    monkeypatch.setenv('CL_MTC_BRIDGE_BINARY', '/tmp/rebuilt/CLAbletonMTCBridge')
    with pytest.raises(AnalysisReached):
        runpy.run_path(str(ROOT / 'CL Audio Controller.spec'), init_globals={'Analysis': capture_analysis})
    assert selected['binaries'][0] == ('/tmp/rebuilt/CLAbletonMTCBridge', 'tools/ableton_mtc_bridge')
