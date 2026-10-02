"""Exercise real passive callbacks/PC validation without importing the server."""
import ast
from pathlib import Path
import threading
import types
import unittest
from typing import Any, Optional, Dict
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]


class PassiveFeedbackTests(unittest.TestCase):
    def test_direct_live_then_observed_pc_matches_without_live_commands(self):
        tree = ast.parse((ROOT / 'app.py').read_text())
        names = {'receive_playing_slot_event', 'record_ableton_midi_output',
                 'record_go_midi_expectations',
                 'expected_console_scene_for_index',
                 'build_device_state', 'console_visual_state'}
        functions = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in names]
        state = {'set_generation': 1, 'set_ready': True, 'scenes': {0: 'Intro', 1: 'Falling'},
                 'playing_scene': 0, 'play_mode': 'session'}
        transport = Mock(resolved_host='192.168.1.138')
        def profile(name):
            return types.SimpleNamespace(id=name, legacy_key=name, to_dict=lambda: {'id': name})
        scope = dict(Any=Any, Optional=Optional, Dict=Dict, state=state, lock=threading.RLock(),
                     time=types.SimpleNamespace(time=lambda: 100),
                     _playing_listener_generation=1, _playing_listener_token='token',
                     _playing_listener_tracks={0: 0}, ableton_transport=transport,
                     parse_scene_duration_seconds=lambda name: None,
                     send_midi_monitor_scene_context=Mock(), schedule_selected_scene_duration_refresh=Mock(),
                     resolve_device_profile=profile, MIDI_RETURN_VISUAL_TIMEOUT_SECONDS=5)
        exec(compile(ast.Module(body=functions, type_ignores=[]), '<passive feedback>', 'exec'), scope)
        scope['receive_playing_slot_event']((0, 'token', 1), '192.168.1.138')
        self.assertEqual(state['playing_scene_name'], 'Falling')
        self.assertEqual(state['expected_scene_signature'], (1, 'session', 1))
        transport.send.assert_not_called()
        for console in ('cl5', 'ql1'):
            # Incoming observed PC, not a command emitted to fix the display.
            scope['record_ableton_midi_output'](console, 12, 100)
            expected = state['ableton_midi_output'][console]
            for returned, status in ((12, 'confirmed'), (24, 'mismatch')):
                result = scope['build_device_state'](profile(console), expected,
                    {'returned_midi_program': returned, 'returned_received_at': 101}, now=101)
                self.assertEqual(result['validation_status'], status)
                self.assertEqual(result['expected_scene_memory'], 13)
        transport.send.assert_not_called()
        scan = next(n for n in tree.body if isinstance(n, ast.Assign)
                    and any(isinstance(t, ast.Name) and t.id == 'SCAN_PLAYING_SCENE_FROM_TRACKS' for t in n.targets))
        self.assertFalse(ast.literal_eval(scan.value))


if __name__ == '__main__':
    unittest.main()
