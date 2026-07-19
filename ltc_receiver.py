"""Réception UDP sécurisée du LTC, indépendante du transport AbletonOSC."""

from __future__ import annotations

import ipaddress
import re
import socket
import threading
import time
from typing import Callable, Optional, Tuple


LTC_BIND_HOST = "0.0.0.0"
LTC_PORT = 63123
LTC_MAX_PACKET_SIZE = 8192
LTC_PATTERN = re.compile(r"tc,s?(\d{1,2}):(\d{2}):(\d{2}):(\d{2})")


class LTCReceiver:
    """Reçoit le LTC et filtre chaque datagramme selon la cible Ableton active."""

    def __init__(
        self,
        *,
        target_provider: Callable[[], object],
        publish: Callable[[str, str, float], None],
        diagnostics: Callable[[dict], None],
        bind_host: str = LTC_BIND_HOST,
        port: int = LTC_PORT,
        max_packet_size: int = LTC_MAX_PACKET_SIZE,
        connection_timeout: float = 2.0,
        socket_factory: Callable[..., socket.socket] = socket.socket,
    ) -> None:
        self._target_provider = target_provider
        self._publish = publish
        self._diagnostics = diagnostics
        self.bind_host = bind_host
        self.port = int(port)
        self.max_packet_size = int(max_packet_size)
        self.connection_timeout = float(connection_timeout)
        self._socket_factory = socket_factory
        self._socket: Optional[socket.socket] = None
        self._stop_event = threading.Event()
        self._rejected_count = 0
        self._last_received_at: Optional[float] = None

    def _reject(self, reason: str, source_ip: Optional[str] = None) -> None:
        self._rejected_count += 1
        self._diagnostics({
            "ltc_rejected_count": self._rejected_count,
            "ltc_last_rejection_reason": reason,
            "ltc_last_rejected_source": source_ip,
        })

    def _source_allowed(self, source_ip: str) -> bool:
        try:
            source = ipaddress.ip_address(source_ip)
            target = self._target_provider()
            mode = str(getattr(target, "mode", "local")).lower()
            if mode == "local":
                return source.is_loopback
            target_address = ipaddress.ip_address(str(getattr(target, "host", "")))
            return source == target_address
        except (TypeError, ValueError):
            return False

    @staticmethod
    def _valid_timecode(parts: Tuple[str, str, str, str]) -> bool:
        hours, minutes, seconds, frames = (int(value) for value in parts)
        return (
            0 <= hours <= 99
            and 0 <= minutes <= 59
            and 0 <= seconds <= 59
            and 0 <= frames <= 99
        )

    def process_datagram(self, data: bytes, address: Tuple[str, int]) -> int:
        """Valide et publie un datagramme. Retourne le nombre de TC publiés."""
        source_ip = str(address[0])
        if not self._source_allowed(source_ip):
            self._reject("source-not-allowed", source_ip)
            return 0
        if not data:
            self._reject("empty-packet", source_ip)
            return 0
        if len(data) > self.max_packet_size:
            self._reject("packet-too-large", source_ip)
            return 0
        try:
            text = data.decode("utf-8", errors="strict").replace("\x00", "").strip()
        except UnicodeDecodeError:
            self._reject("invalid-encoding", source_ip)
            return 0
        if not text.startswith("tc"):
            self._reject("invalid-prefix", source_ip)
            return 0

        matches = list(LTC_PATTERN.finditer(text))
        if not matches:
            self._reject("invalid-timecode", source_ip)
            return 0

        accepted = 0
        received_at = time.time()
        for match in matches:
            parts = match.groups()
            if not self._valid_timecode(parts):
                continue
            timecode = ":".join(parts)
            self._publish(timecode, source_ip, received_at)
            accepted += 1
        if accepted:
            self._last_received_at = received_at
            self._diagnostics({
                "ltc_connected": True,
                "ltc_last_received_at": received_at,
                "ltc_last_source": source_ip,
            })
        if not accepted:
            self._reject("invalid-timecode-values", source_ip)
        return accepted

    def refresh_connection_state(self, now: Optional[float] = None) -> bool:
        """Marque le flux absent après une période sans trame acceptée."""
        now = time.time() if now is None else float(now)
        connected = bool(
            self._last_received_at is not None
            and now - self._last_received_at <= self.connection_timeout
        )
        if not connected:
            self._diagnostics({"ltc_connected": False})
        return connected

    def serve_forever(self) -> bool:
        """Écoute jusqu'à :meth:`stop`; renvoie False si le bind échoue."""
        sock = self._socket_factory(socket.AF_INET, socket.SOCK_DGRAM)
        self._socket = sock
        try:
            sock.settimeout(0.25)
            sock.bind((self.bind_host, self.port))
        except OSError as exc:
            self._diagnostics({
                "ltc_listener_active": False,
                "ltc_last_rejection_reason": f"bind-error: {exc}",
            })
            try:
                sock.close()
            finally:
                self._socket = None
            return False

        self._diagnostics({"ltc_listener_active": True})
        try:
            while not self._stop_event.is_set():
                try:
                    data, address = sock.recvfrom(self.max_packet_size + 1)
                    self.process_datagram(data, address)
                except socket.timeout:
                    self.refresh_connection_state()
                    continue
                except OSError:
                    if not self._stop_event.is_set():
                        self._reject("socket-error")
                except Exception:
                    self._reject("unexpected-listener-error")
        finally:
            self._diagnostics({"ltc_listener_active": False})
            try:
                sock.close()
            finally:
                self._socket = None
        return True

    def stop(self) -> None:
        self._stop_event.set()
        sock = self._socket
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass
