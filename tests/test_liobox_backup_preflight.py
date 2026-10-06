"""Dry preflight: exercise real passive callbacks, without sending to either Live.

These tests document what an observer can distinguish BEFORE enabling mirroring.
They intentionally do not claim hardware timing or full-scene launch identity.
"""
import unittest
from unittest.mock import patch
from tests import test_passive_scene_listeners as fixtures


class LioboxBackupPreflight(unittest.TestCase):
    setUpClass = classmethod(fixtures.PassiveSceneListenerTests.setUpClass.__func__)
    setUp = fixtures.PassiveSceneListenerTests.setUp
    tearDown = fixtures.PassiveSceneListenerTests.tearDown
    install = fixtures.PassiveSceneListenerTests.install
    event = fixtures.PassiveSceneListenerTests.event
    prime_stopped = fixtures.PassiveSceneListenerTests.prime_stopped

    def test_scene_change_is_detected_once_without_primary_or_backup_write(self):
        self.prime_stopped()
        with patch.object(self.a.hot_backup, 'offer') as backup_send:
            self.event(0, 1)
            self.event(1, 1)
            self.event(0, 1)
            self.assertEqual(self.a.state['playing_scene'], 1)
            self.context.assert_called_once()
            self.send.assert_not_called()
            backup_send.assert_not_called()

    def test_same_scene_restart_cannot_be_inferred_from_same_slot(self):
        self.prime_stopped()
        self.event(0, 1)
        self.context.reset_mock()
        self.event(0, 1)
        self.context.assert_not_called()
        self.assertEqual(self.a.state['playing_scene'], 1)

    def test_live_selection_is_not_a_followed_navigation_after_show_start(self):
        self.prime_stopped()
        self.event(0, 0)
        self.a.state.update(selected_scene=0, next_scene=0, has_show_started=True)
        with self.a.lock:
            self.a.apply_osc_response_locked('/live/view/get/selected_scene', (1,), 10)
        self.assertEqual(self.a.state['selected_scene'], 0)
        self.send.assert_not_called()

    def test_unsolicited_play_stop_is_not_an_installed_transport_listener(self):
        self.prime_stopped()
        self.a.osc_reply('/live/song/get/is_playing', 1)
        self.assertFalse(self.a.state['is_playing'])
        self.send.assert_not_called()
