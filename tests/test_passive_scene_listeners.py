"""Passive AbletonOSC notifications, with no Live/hardware writes in tests."""
import unittest
from unittest import mock

from tests.test_live_set_generation import load_app_module
from osc_transport import OSCTransport


class PassiveSceneListenerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = load_app_module()

    def setUp(self):
        self.a = self.app
        self.a._playing_listener_shutdown = False
        self.a._playing_listener_tracks.clear()
        self.a._playing_listener_generation = None
        self.a._playing_listener_token = None
        self.patches = [
            mock.patch.dict(self.a.state, {
                "set_generation": 10, "set_ready": True, "is_playing": False,
                "play_mode": "stopped", "playing_scene": -1, "current_scene": None,
                "has_show_started": False, "selected_scene": 0, "next_scene": 0,
                "scenes": {0: "Intro ; 1:00", 1: "Final ; 2:00"},
            }),
            mock.patch.object(self.a.ableton_transport, "send", return_value=True),
            mock.patch.object(self.a, "query", return_value=(2,)),
            mock.patch.object(self.a, "send_midi_monitor_scene_context"),
        ]
        _, self.send, self.query, self.context = [p.start() for p in self.patches]
        self.a.completed_go_requests.clear()

    def tearDown(self):
        self.a.stop_playing_scene_listeners()
        for patch in reversed(self.patches):
            patch.stop()

    def install(self):
        self.a.ensure_playing_scene_listeners()
        return self.a._playing_listener_token

    def event(self, track, slot, token=None):
        self.a.osc_reply("/live/track/get/playing_slot_index", track,
                         token or self.a._playing_listener_token, slot)

    def prime_stopped(self):
        self.install()
        self.event(0, -1)
        self.event(1, -1)
        self.send.reset_mock()

    def test_liobox_and_direct_live_starts_update_remote_without_selection(self):
        self.prime_stopped()
        for slot in (1, 0, 1, 0):
            with self.subTest(source="LioBox / Live", slot=slot):
                self.event(0, slot)
                with self.a.lock:
                    snapshot = self.a.state_snapshot_locked()
                self.assertEqual(snapshot["playing_scene"], slot)
                self.assertEqual(snapshot["current_scene"], slot)
                self.assertEqual(snapshot["playing_scene_name"], self.a.state["scenes"][slot])
                self.assertEqual(snapshot["play_mode"], "session")
                expected_next = slot + 1 if (slot + 1) in self.a.state["scenes"] else self.a.state["selected_scene"]
                self.assertEqual(self.a.state["selected_scene"], expected_next)
                self.assertEqual(self.a.state["next_scene"], expected_next)
        self.context.assert_called_with(10, 0, "Intro ; 1:00")
        self.send.assert_not_called()
        self.query.assert_any_call(
            "/live/song/get/num_tracks",
            expected_generation=10,
            apply_response=False,
        )

    def test_track_fanout_does_not_restart_countdown(self):
        self.prime_stopped()
        with mock.patch.object(self.a.time, "time", return_value=100):
            self.event(0, 1)
        with mock.patch.object(self.a.time, "time", return_value=110):
            self.event(1, 1)
            self.event(0, 1)
        self.assertEqual(self.a.state["scene_duration_seconds"], 120)
        self.assertEqual(self.a.state["playback_deadline"], 220)
        self.context.assert_called_once()

    def test_initial_playing_snapshot_has_no_invented_remaining_time(self):
        self.a.state["is_playing"] = True
        self.install()
        self.event(0, 1)
        self.assertEqual(self.a.state["playing_scene"], 1)
        self.assertIsNone(self.a.state["remaining_seconds"])
        self.assertIsNone(self.a.state["playback_deadline"])

    def test_initial_values_do_not_override_arrangement_but_new_start_does(self):
        self.a.state.update(is_playing=True, play_mode="arrangement")
        self.install()
        self.event(0, 1)
        self.assertEqual(self.a.state["play_mode"], "arrangement")
        self.event(0, 0)
        self.assertEqual(self.a.state["play_mode"], "session")
        self.assertEqual(self.a.state["playing_scene"], 0)

    def test_stop_values_do_not_select_an_old_still_playing_scene(self):
        self.prime_stopped()
        self.event(0, 0)
        self.event(1, 1)
        self.event(1, -1)
        self.assertEqual(self.a.state["playing_scene"], 1)
        self.event(0, -1)
        self.assertEqual(self.a.state["playing_scene"], -1)
        self.send.assert_not_called()

    def test_reset_removes_old_subscriptions_and_installs_new_once(self):
        old_token = self.install()
        self.a.ensure_playing_scene_listeners()
        self.assertEqual(self.send.call_count, 2)
        with self.a.lock:
            generation = self.a.reset_live_set_state_locked("new.als", "test")
        for track in (0, 1):
            self.send.assert_any_call("/live/track/stop_listen/playing_slot_index", track, old_token)
        self.event(0, 1, old_token)
        self.assertEqual(self.a.state["playing_scene"], -1)
        self.a.state.update(set_ready=True, scenes={0: "New", 1: "Final"})
        new_token = self.install()
        self.assertNotEqual(old_token, new_token)
        self.assertEqual(self.a._playing_listener_generation, generation)
        self.a.ensure_playing_scene_listeners()
        self.assertEqual(self.send.call_count, 6)
        self.event(0, -1)
        self.event(0, 1, old_token)
        self.assertEqual(self.a.state["playing_scene"], -1)
        self.event(0, 1)
        self.assertEqual(self.a.state["playing_scene"], 1)

    def test_generation_change_during_count_query_cancels_installation(self):
        def change_set(*args, **kwargs):
            with self.a.lock:
                self.a.reset_live_set_state_locked("new.als", "test")
            return (2,)
        self.query.side_effect = change_set
        self.install()
        self.send.assert_not_called()

    def test_shutdown_removes_subscriptions_and_prevents_reinstallation(self):
        token = self.install()
        self.send.reset_mock()
        self.a.stop_playing_scene_listeners()
        self.a.ensure_playing_scene_listeners()
        self.assertEqual(self.send.call_args_list, [
            mock.call("/live/track/stop_listen/playing_slot_index", track, token)
            for track in (0, 1)
        ])

    def test_failed_install_is_cleaned_before_retry(self):
        self.send.side_effect = [True, False, True, True]
        self.install()
        self.assertIsNone(self.a._playing_listener_token)
        self.assertEqual(self.a._playing_listener_tracks, {})
        self.send.side_effect = None
        self.send.reset_mock()
        self.install()
        self.assertEqual(self.send.call_count, 2)

    def test_reentrant_install_does_not_duplicate_subscriptions(self):
        def reenter(*args, **kwargs):
            self.a.ensure_playing_scene_listeners()
            return (2,)
        self.query.side_effect = reenter
        self.install()
        self.query.assert_called_once()
        self.assertEqual(self.send.call_count, 2)

    def test_initial_positive_snapshot_reports_existing_session_playback(self):
        self.install()
        self.event(0, 1)
        self.event(1, 1)
        self.assertEqual(self.a.state["playing_scene"], 1)
        self.assertTrue(self.a.state["is_playing"])
        self.assertEqual(self.a.state["play_mode"], "session")
        self.context.assert_called()

    def test_all_tracks_are_subscribed_without_historical_32_track_cap(self):
        self.query.return_value = (67,)
        self.install()
        self.assertEqual(self.send.call_count, 67)
        self.assertIn(66, self.a._playing_listener_tracks)

    def test_untagged_malformed_foreign_and_old_events_are_ignored(self):
        token = self.install()
        for args in ((0, 1), (0, "old", 1), (99, token, 1), (0, token, "1")):
            self.a.osc_reply("/live/track/get/playing_slot_index", *args)
        self.a.osc_reply("/live/track/get/playing_slot_index", 0, token, 1,
                         source_host="192.0.2.123")
        self.assertEqual(self.a.state["playing_scene"], -1)
        self.context.assert_not_called()

    def test_connected_idle_background_subscribes_once_without_global_polling(self):
        self.assertFalse(self.a.SCAN_PLAYING_SCENE_FROM_TRACKS)
        with (
            mock.patch.object(self.a, "refresh_names_and_transport", return_value=True),
            mock.patch.object(self.a, "refresh_arrangement_time"),
            mock.patch.object(self.a, "publish_current_midi_monitor_scene_context"),
            mock.patch.object(self.a, "FULL_REFRESH_SECONDS", 0),
            mock.patch.object(self.a.time, "sleep", side_effect=[None, None, RuntimeError("done")]),
        ):
            with self.assertRaisesRegex(RuntimeError, "done"):
                self.a.background_refresh()
        self.query.assert_called_once_with("/live/song/get/num_tracks",
                                           expected_generation=10, apply_response=False)
        self.assertEqual(self.send.call_count, 2)
        for call in self.send.call_args_list:
            self.assertEqual(call.args[0], "/live/track/start_listen/playing_slot_index")
        self.assertEqual(self.a.state["playing_scene"], -1)

    def test_go_keeps_explicit_selection_and_fire_only(self):
        self.prime_stopped()
        with (
            mock.patch.object(self.a, "_query_with_query_lock_held", return_value=(0,)),
            mock.patch.object(self.a, "record_go_midi_expectations"),
            mock.patch.object(self.a, "schedule_selected_scene_duration_refresh"),
        ):
            self.assertTrue(self.a.execute_go_transaction("phone", 10, 1)[0])
        self.assertEqual(self.send.call_args_list, [
            mock.call("/live/view/set/selected_scene", 0),
            mock.call("/live/scene/fire_as_selected", 0),
        ])
        self.assertEqual(self.a.state["next_scene"], 1)
        deadline = self.a.state["playback_deadline"]
        self.event(0, 0)
        self.assertEqual(self.a.state["playback_deadline"], deadline)

    def test_tagged_notification_cannot_satisfy_plain_get_query(self):
        handler = mock.Mock()
        transport = OSCTransport(unsolicited_handler=handler)
        request = {"address": "/live/track/get/playing_slot_index", "args": (0,),
                   "sent_at": 0, "response": None}
        transport._active_request = request
        transport._receive(request["address"], 0, "generation-token", 1)
        self.assertIsNone(request["response"])
        handler.assert_called_once_with(request["address"], 0, "generation-token", 1)
        transport._receive(request["address"], 0, 1)
        self.assertEqual(request["response"], (0, 1))
