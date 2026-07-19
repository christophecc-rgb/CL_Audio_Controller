import socket
import threading
import time
import unittest
from types import SimpleNamespace
from unittest import mock

from ltc_receiver import LTCReceiver


class FakeSocket:
    def __init__(self, bind_error=None):
        self.bind_error = bind_error
        self.bound = None
        self.closed = False
        self.timeout = None

    def settimeout(self, value):
        self.timeout = value

    def bind(self, address):
        if self.bind_error:
            raise self.bind_error
        self.bound = address

    def recvfrom(self, _size):
        raise socket.timeout

    def close(self):
        self.closed = True


class LTCReceiverTests(unittest.TestCase):
    def setUp(self):
        self.target = SimpleNamespace(mode="local", host="127.0.0.1")
        self.published = []
        self.diagnostics = {}
        self.receiver = LTCReceiver(
            target_provider=lambda: self.target,
            publish=lambda tc, source, at: self.published.append((tc, source, at)),
            diagnostics=self.diagnostics.update,
        )

    def send(self, payload, source="127.0.0.1"):
        return self.receiver.process_datagram(payload, (source, 50000))

    def test_local_loopback_packet_and_historical_format_are_accepted(self):
        self.assertEqual(self.send(b"tc,s13:05:13:24"), 1)
        self.assertEqual(self.published[0][:2], ("13:05:13:24", "127.0.0.1"))

    def test_nul_padded_historical_format_is_accepted(self):
        self.assertEqual(self.send(b"tc\x00\x00,s\x00\x0013:05:13:24\x00"), 1)
        self.assertEqual(self.published[0][0], "13:05:13:24")

    def test_network_packet_is_rejected_in_local_mode(self):
        self.assertEqual(self.send(b"tc,s01:02:03:04", "192.168.1.22"), 0)
        self.assertEqual(self.diagnostics["ltc_last_rejection_reason"], "source-not-allowed")

    def test_remote_active_target_is_accepted_and_other_source_rejected(self):
        self.target = SimpleNamespace(mode="remote", host="192.168.1.22")
        self.assertEqual(self.send(b"tc,s01:02:03:04", "192.168.1.22"), 1)
        self.assertEqual(self.send(b"tc,s05:06:07:08", "192.168.1.23"), 0)

    def test_target_change_and_return_to_local_take_effect_immediately(self):
        self.target = SimpleNamespace(mode="remote", host="192.168.1.22")
        self.assertEqual(self.send(b"tc,s01:02:03:04", "192.168.1.22"), 1)
        self.target = SimpleNamespace(mode="remote", host="192.168.1.23")
        self.assertEqual(self.send(b"tc,s01:02:03:05", "192.168.1.22"), 0)
        self.assertEqual(self.send(b"tc,s01:02:03:06", "192.168.1.23"), 1)
        self.target = SimpleNamespace(mode="local", host="127.0.0.1")
        self.assertEqual(self.send(b"tc,s01:02:03:07", "192.168.1.23"), 0)
        self.assertEqual(self.send(b"tc,s01:02:03:08", "127.0.0.1"), 1)

    def test_four_aliases_can_be_published_unchanged(self):
        state = {}

        def publish(tc, _source, _at):
            for key in ("ltc_timecode", "timecode", "ltc", "smpte"):
                state[key] = tc

        receiver = LTCReceiver(
            target_provider=lambda: self.target,
            publish=publish,
            diagnostics=self.diagnostics.update,
        )
        receiver.process_datagram(b"tc,s10:11:12:13", ("127.0.0.1", 1234))
        self.assertEqual(set(state.values()), {"10:11:12:13"})
        self.assertEqual(len(state), 4)

    def test_connection_diagnostic_tracks_loss_and_recovery(self):
        self.assertFalse(self.receiver.refresh_connection_state(now=100.0))
        with mock.patch("ltc_receiver.time.time", return_value=100.0):
            self.assertEqual(self.send(b"tc,s10:11:12:13"), 1)
        self.assertTrue(self.diagnostics["ltc_connected"])
        self.assertTrue(self.receiver.refresh_connection_state(now=101.0))
        self.assertFalse(self.receiver.refresh_connection_state(now=103.0))
        self.assertFalse(self.diagnostics["ltc_connected"])

    def test_invalid_packets_are_rejected_without_disabling_receiver(self):
        invalid = (
            b"",
            b"other,s01:02:03:04",
            b"tc,s01:02:03",
            b"tc,saa:02:03:04",
            b"tc,s01:99:03:04",
            b"\xff\xfe",
            b"tc,s01:02:03:04" + b"x" * 8192,
        )
        for payload in invalid:
            self.assertEqual(self.send(payload), 0)
        self.assertEqual(self.send(b"tc,s01:02:03:04"), 1)
        self.assertEqual(self.diagnostics["ltc_rejected_count"], len(invalid))

    def test_bind_error_is_reported_and_socket_closed(self):
        fake = FakeSocket(OSError("already in use"))
        receiver = LTCReceiver(
            target_provider=lambda: self.target,
            publish=lambda *_args: None,
            diagnostics=self.diagnostics.update,
            socket_factory=lambda *_args: fake,
        )
        self.assertFalse(receiver.serve_forever())
        self.assertFalse(self.diagnostics["ltc_listener_active"])
        self.assertIn("bind-error", self.diagnostics["ltc_last_rejection_reason"])
        self.assertTrue(fake.closed)

    def test_listener_stops_cleanly(self):
        receiver = LTCReceiver(
            target_provider=lambda: self.target,
            publish=lambda *_args: None,
            diagnostics=self.diagnostics.update,
            port=0,
        )
        worker = threading.Thread(target=receiver.serve_forever)
        worker.start()
        deadline = time.time() + 1
        while not self.diagnostics.get("ltc_listener_active") and time.time() < deadline:
            time.sleep(0.01)
        receiver.stop()
        worker.join(1)
        self.assertFalse(worker.is_alive())
        self.assertFalse(self.diagnostics["ltc_listener_active"])


if __name__ == "__main__":
    unittest.main()
