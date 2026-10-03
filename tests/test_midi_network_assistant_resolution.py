from unittest import mock

import launcher_control


def test_transport_kit_network_manager_has_priority(tmp_path):
    kit_root = tmp_path / "CL Audio Controller 2.2.0-test"

    show_control_exe = (
        kit_root
        / "01 — Applications principales"
        / "CL Show Control.app"
        / "Contents"
        / "MacOS"
        / "CL Audio Controller"
    )
    show_control_exe.parent.mkdir(parents=True)
    show_control_exe.touch()

    bundled_manager = (
        kit_root
        / "03 — MIDI & Réseau"
        / "CL MIDI Network Manager.app"
    )
    bundled_manager.mkdir(parents=True)

    installed_manager = (
        tmp_path
        / "Applications"
        / "Analyse - Réseau - MIDI"
        / "CL MIDI Network Manager.app"
    )
    installed_manager.mkdir(parents=True)

    with (
        mock.patch.object(launcher_control.sys, "frozen", True, create=True),
        mock.patch.object(launcher_control.sys, "executable", str(show_control_exe)),
        mock.patch.object(launcher_control.Path, "home", return_value=tmp_path),
    ):
        result = launcher_control.find_midi_network_assistant()

    assert result == bundled_manager


def test_installed_network_manager_is_fallback(tmp_path):
    installed_manager = (
        tmp_path
        / "Applications"
        / "Analyse - Réseau - MIDI"
        / "CL MIDI Network Manager.app"
    )
    installed_manager.mkdir(parents=True)

    with (
        mock.patch.object(launcher_control.sys, "frozen", False, create=True),
        mock.patch.object(launcher_control.Path, "home", return_value=tmp_path),
    ):
        result = launcher_control.find_midi_network_assistant()

    assert result == installed_manager
