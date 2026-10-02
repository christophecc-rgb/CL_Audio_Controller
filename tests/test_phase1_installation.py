from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def test_uninstall_missing_jobs_tolerated_both_plists_removed(tmp_path):
    source = (ROOT / 'packaging/Desinstaller_La_Suite_CL.command').read_text()
    assert 'retire_launch_agent com.claudio.midi-network-monitor' in source
    assert 'retire_launch_agent com.claudio.midi-rtp-agent' in source
    function = source[source.index('retire_launch_agent()'):source.index('\nif [[ "$UNINSTALL_MIDI_CONSOLE" == "1" ||')]
    # Inject a failing launchctl and a test user home; never reach real launchd.
    fake = tmp_path / 'launchctl'
    fake.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$CALLS"\nexit 1\n')
    fake.chmod(0o700)
    function = function.replace('/bin/launchctl', '"$FAKE_LAUNCHCTL"').replace('"$HOME"', '"$TEST_USER_HOME"')
    agents = tmp_path / 'Library/LaunchAgents'
    agents.mkdir(parents=True)
    for label in ('midi-network-monitor', 'midi-rtp-agent'):
        (agents / f'com.claudio.{label}.plist').write_text('test')
    env = dict(os.environ, INSTALL_HOME=str(tmp_path), TEST_USER_HOME=str(tmp_path),
               FAKE_LAUNCHCTL=str(fake), CALLS=str(tmp_path / 'calls'), CL_SUITE_SKIP_POSTINSTALL='0')
    subprocess.run(['bash', '-c', 'set -euo pipefail\n' + function + '\n'
                    'retire_launch_agent com.claudio.midi-network-monitor\n'
                    'retire_launch_agent com.claudio.midi-rtp-agent\n'
                    'retire_launch_agent com.claudio.midi-rtp-agent\n'], env=env, check=True)
    assert not list(agents.iterdir())
    assert (tmp_path / 'calls').read_text().count('bootout') == 3


def test_installation_retires_old_monitor_without_starting_background_app():
    for name in ('Installer_Toute_La_Suite_CL.command', 'Installer_CL_MIDI_Console.command'):
        source = (ROOT / 'packaging' / name).read_text()
        assert 'com.claudio.midi-network-monitor' in source
        assert 'bootout' in source
        assert '--background-monitor' not in source


def test_manager_never_installs_service_and_child_modes_remain():
    source = (ROOT / 'tools/cl_midi_network/CLMIDINetworkDashboard.m').read_text()
    assert 'installBackgroundLaunchAgent' not in source
    assert 'Library/LaunchAgents' not in source
    assert '@"--show-control-monitor"' in source
    assert '@"--background-monitor"' in source
    assert 'ownsPassiveReturnMonitor' in source
