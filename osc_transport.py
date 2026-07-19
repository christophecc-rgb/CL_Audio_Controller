"""Transport OSC local d'AbletonOSC, sans logique métier."""

from __future__ import annotations

import threading
import time
from contextlib import contextmanager
from typing import Any, Callable, Dict, Optional, Tuple

from pythonosc import dispatcher, osc_server, udp_client


LOCAL_ABLETON_HOST = "127.0.0.1"
LOCAL_ABLETON_SEND_PORT = 11000
LOCAL_ABLETON_REPLY_PORT = 11001


ResponseMatcher = Callable[[str, Tuple[Any, ...], Tuple[Any, ...]], bool]
UnsolicitedHandler = Callable[..., None]


class OSCTransport:
    """Émet, reçoit et corrèle les échanges OSC d'une cible unique."""

    def __init__(
        self,
        host: str = LOCAL_ABLETON_HOST,
        send_port: int = LOCAL_ABLETON_SEND_PORT,
        reply_port: int = LOCAL_ABLETON_REPLY_PORT,
        response_matcher: Optional[ResponseMatcher] = None,
        unsolicited_handler: Optional[UnsolicitedHandler] = None,
    ) -> None:
        self.host = host
        self.send_port = int(send_port)
        self.reply_port = int(reply_port)
        self._client = udp_client.SimpleUDPClient(self.host, self.send_port)
        self._response_matcher = response_matcher or self._default_response_matcher
        self._unsolicited_handler = unsolicited_handler
        self._state_lock = threading.RLock()
        self._query_lock = threading.Lock()
        self._active_request: Optional[Dict[str, Any]] = None
        self._reply_server = None
        self.connected = False
        self.last_response_at: Optional[float] = None
        self.last_latency_ms: Optional[float] = None
        self.timeout_count = 0

    @staticmethod
    def _default_response_matcher(
        address: str,
        request_args: Tuple[Any, ...],
        response_args: Tuple[Any, ...],
    ) -> bool:
        if not request_args:
            return True
        if address.startswith("/live/scene/") or address.startswith("/live/track/"):
            if not response_args:
                return False
            try:
                return int(response_args[0]) == int(request_args[0])
            except (TypeError, ValueError):
                return response_args[0] == request_args[0]
        return True

    def set_unsolicited_handler(self, handler: Optional[UnsolicitedHandler]) -> None:
        self._unsolicited_handler = handler

    def send(self, address: str, *args: Any) -> None:
        self._client.send_message(address, list(args))

    def _receive(self, address: str, *args: Any) -> None:
        now = time.time()
        with self._state_lock:
            self.connected = True
            self.last_response_at = now
            request = self._active_request
            if (
                request is not None
                and request.get("address") == address
                and self._response_matcher(address, request.get("args", ()), tuple(args))
            ):
                request["response"] = tuple(args)
                request["received_at"] = now
                self.last_latency_ms = max(0.0, (now - request["sent_at"]) * 1000.0)
                return
        handler = self._unsolicited_handler
        if handler is not None:
            handler(address, *args)

    def serve_forever(self, bind_host: str = "0.0.0.0") -> None:
        osc_dispatcher = dispatcher.Dispatcher()
        osc_dispatcher.set_default_handler(self._receive)
        server = osc_server.ThreadingOSCUDPServer((bind_host, self.reply_port), osc_dispatcher)
        with self._state_lock:
            self._reply_server = server
        server.serve_forever()

    @contextmanager
    def serialized_queries(self):
        with self._query_lock:
            yield

    def query(
        self,
        address: str,
        *args: Any,
        timeout: float,
        context: Optional[Dict[str, Any]] = None,
    ) -> Optional[Tuple[Any, ...]]:
        with self.serialized_queries():
            return self.query_locked(address, *args, timeout=timeout, context=context)

    def query_locked(
        self,
        address: str,
        *args: Any,
        timeout: float,
        context: Optional[Dict[str, Any]] = None,
    ) -> Optional[Tuple[Any, ...]]:
        request = {
            "address": address,
            "args": tuple(args),
            "sent_at": time.time(),
            "context": dict(context or {}),
            "response": None,
        }
        with self._state_lock:
            self._active_request = request
        self.send(address, *args)

        started = time.time()
        while time.time() - started < timeout:
            with self._state_lock:
                if self._active_request is not request:
                    return None
                response = request.get("response")
                if response is not None:
                    self._active_request = None
                    return tuple(response)
            time.sleep(0.006)

        with self._state_lock:
            if self._active_request is request:
                self._active_request = None
            self.connected = False
            self.timeout_count += 1
        return None

    def cancel_pending(self) -> None:
        with self._state_lock:
            self._active_request = None

    def pending_request(self) -> Optional[Dict[str, Any]]:
        with self._state_lock:
            if self._active_request is None:
                return None
            return dict(self._active_request)

    def diagnostics(self) -> Dict[str, Any]:
        with self._state_lock:
            return {
                "connected": bool(self.connected),
                "last_response_at": self.last_response_at,
                "last_latency_ms": self.last_latency_ms,
                "timeout_count": int(self.timeout_count),
            }
