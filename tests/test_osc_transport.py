import threading
import time
import unittest
from pathlib import Path
from unittest import mock

import osc_transport


class FakeClient:
    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.messages = []

    def send_message(self, address, arguments):
        self.messages.append((address, arguments))


class OSCTransportTests(unittest.TestCase):
    def make_transport(self, handler=None):
        with mock.patch.object(osc_transport.udp_client, "SimpleUDPClient", FakeClient):
            return osc_transport.OSCTransport(unsolicited_handler=handler)

    def test_local_defaults_are_unchanged(self):
        transport = self.make_transport()
        self.assertEqual(transport.host, "127.0.0.1")
        self.assertEqual(transport.send_port, 11000)
        self.assertEqual(transport.reply_port, 11001)

    def test_remote_transport_uses_configured_destination(self):
        with mock.patch.object(osc_transport.udp_client, "SimpleUDPClient", FakeClient):
            transport = osc_transport.OSCTransport(
                host="192.168.50.10",
                send_port=12000,
                reply_port=12001,
            )
        self.assertEqual(transport._client.host, "192.168.50.10")
        self.assertEqual(transport._client.port, 12000)
        self.assertEqual(transport.reply_port, 12001)

    def test_all_emission_is_delegated_to_internal_client(self):
        transport = self.make_transport()
        transport.send("/live/song/get/name")
        transport.send("/live/view/set/selected_scene", 4)
        self.assertEqual(
            transport._client.messages,
            [
                ("/live/song/get/name", []),
                ("/live/view/set/selected_scene", [4]),
            ],
        )

    def test_query_correlates_response_and_measures_latency(self):
        transport = self.make_transport()
        result = []
        worker = threading.Thread(
            target=lambda: result.append(
                transport.query("/live/scene/get/name", 7, timeout=0.2)
            )
        )
        worker.start()
        deadline = time.time() + 0.1
        while transport.pending_request() is None and time.time() < deadline:
            time.sleep(0.001)
        transport._receive("/live/scene/get/name", 7, "Final")
        worker.join(0.3)
        self.assertEqual(result, [(7, "Final")])
        self.assertTrue(transport.connected)
        self.assertIsNotNone(transport.last_response_at)
        self.assertIsNotNone(transport.last_latency_ms)
        self.assertEqual(transport.timeout_count, 0)

    def test_query_keeps_opaque_application_context_without_interpreting_it(self):
        transport = self.make_transport()
        worker = threading.Thread(
            target=lambda: transport.query(
                "/live/song/get/name",
                timeout=0.2,
                context={"generation": 12},
            )
        )
        worker.start()
        deadline = time.time() + 0.1
        while transport.pending_request() is None and time.time() < deadline:
            time.sleep(0.001)
        self.assertEqual(transport.pending_request()["context"], {"generation": 12})
        transport.cancel_pending()
        worker.join(0.3)

    def test_incompatible_response_does_not_complete_query(self):
        received = []
        transport = self.make_transport(lambda address, *args: received.append((address, args)))
        result = []
        worker = threading.Thread(
            target=lambda: result.append(
                transport.query("/live/scene/get/name", 7, timeout=0.04)
            )
        )
        worker.start()
        deadline = time.time() + 0.02
        while transport.pending_request() is None and time.time() < deadline:
            time.sleep(0.001)
        transport._receive("/live/scene/get/name", 8, "Autre")
        worker.join(0.2)
        self.assertEqual(result, [None])
        self.assertEqual(received, [("/live/scene/get/name", (8, "Autre"))])
        self.assertEqual(transport.timeout_count, 1)

    def test_timeout_updates_diagnostics(self):
        transport = self.make_transport()
        self.assertIsNone(transport.query("/live/song/get/name", timeout=0.01))
        self.assertFalse(transport.connected)
        self.assertEqual(transport.timeout_count, 1)

    def test_response_after_timeout_restores_transport_connection(self):
        transport = self.make_transport()
        self.assertIsNone(transport.query("/live/song/get/name", timeout=0.01))
        self.assertFalse(transport.connected)
        transport._receive("/live/startup")
        self.assertTrue(transport.connected)

    def test_cancellation_invalidates_pending_query(self):
        transport = self.make_transport()
        result = []
        worker = threading.Thread(
            target=lambda: result.append(
                transport.query("/live/song/get/name", timeout=0.2)
            )
        )
        worker.start()
        deadline = time.time() + 0.1
        while transport.pending_request() is None and time.time() < deadline:
            time.sleep(0.001)
        transport.cancel_pending()
        worker.join(0.3)
        self.assertEqual(result, [None])
        self.assertEqual(transport.timeout_count, 0)

    def test_unsolicited_startup_reaches_application_handler(self):
        received = []
        transport = self.make_transport(lambda address, *args: received.append((address, args)))
        transport._receive("/live/startup")
        self.assertEqual(received, [("/live/startup", ())])

    def test_abletonosc_client_is_not_constructed_in_business_code(self):
        source = (Path(__file__).resolve().parents[1] / "app.py").read_text(encoding="utf-8")
        direct_clients = [line for line in source.splitlines() if "SimpleUDPClient(" in line]
        self.assertEqual(direct_clients, ["m4l_client = udp_client.SimpleUDPClient(M4L_IP, M4L_PORT)"])


if __name__ == "__main__":
    unittest.main()
