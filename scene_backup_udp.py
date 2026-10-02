"""Volatile Scene Backup V1 configuration; bounded asynchronous UDP delivery."""
import json
import queue
import socket
import threading
import time
import uuid
import secrets
import sys
import hashlib
import hmac
from scene_backup_protocol import unicast_ipv4, sign, canonical


class SceneBackupUDP:
    def __init__(self, show_id="OP2026", port=12042, *, queue_size=64,
                 max_event_age=0.5, copy_interval=0.015, socket_factory=socket.socket):
        self.show_id = str(show_id)
        self.port = int(port)
        self.session = uuid.uuid4().hex[:8]
        self.seq = 0
        self.destinations = []
        self.enabled = False
        self.lock = threading.Lock()
        self.events = queue.Queue(maxsize=max(1, int(queue_size)))
        self.max_event_age = float(max_event_age)
        self.copy_interval = float(copy_interval)
        self.socket_factory = socket_factory
        self.stop_event = threading.Event()
        self.worker = None
        self.epoch = 0
        self.enqueued = self.sent_packets = self.send_errors = self.dropped = self.expired = 0
        self.last_scene_sent = None
        self.authentication = "legacy_v1"
        self.shared_secret = None
        self.source_ip = None
        self.source_interface = None
        self.last_ack = {}
        self.probes = {}


    def configure(self, *, enabled=None, show_id=None, port=None, destinations=None,
                  source_ip=None, source_interface=None, authentication=None, shared_secret=None, session=None):
        # Configuration remains in memory. A future persistence layer can call
        # configure() without changing the V1 packet or the GO handoff.
        if port is not None:
            port = int(port)
            if not 1 <= port <= 65535:
                raise ValueError("Port UDP invalide")
        clean = None
        if destinations is not None:
            clean = []
            for item in destinations:
                if isinstance(item, str):
                    host, name, active = item.strip(), item.strip(), True
                else:
                    host = str(item.get("host", "")).strip()
                    name = str(item.get("name", host)).strip() or host
                    active = bool(item.get("enabled", True))
                if host:
                    clean.append({"name": name, "host": unicast_ipv4(host), "enabled": active})
        with self.lock:
            if self.stop_event.is_set():
                raise RuntimeError("Scene Backup fermé")
            mode = authentication if authentication is not None else self.authentication
            source = unicast_ipv4(source_ip) if source_ip is not None else self.source_ip
            interface = source_interface if source_interface is not None else self.source_interface
            if interface is not None and (not isinstance(interface, str) or not interface or len(interface) > 64):
                raise ValueError("Interface source invalide")
            secret = shared_secret if shared_secret is not None else self.shared_secret
            if mode not in ("legacy_v1", "hmac_v1"):
                raise ValueError("Authentification inconnue")
            if mode == "hmac_v1":
                sign({}, secret)
                if not source or not interface:
                    raise ValueError("Adresse ET interface source dédiées requises pour HMAC")
            if shared_secret is not None and mode != "hmac_v1":
                raise ValueError("Secret réservé au mode HMAC")
            rotating = shared_secret is not None and shared_secret != self.shared_secret
            if rotating and self.shared_secret and (not session or session == self.session):
                raise ValueError("Rotation : nouvelle session obligatoire")
            if session is not None:
                if not isinstance(session, str) or not 8 <= len(session) <= 128:
                    raise ValueError("Session explicite invalide")
                if session != self.session:
                    self.seq = 0
                self.session = session
            self.authentication, self.shared_secret, self.source_ip = mode, secret, source
            self.source_interface = interface
            self.last_ack.clear()
            self.probes.clear()
            if enabled is not None:
                self.enabled = bool(enabled)
            if show_id is not None:
                self.show_id = str(show_id)
            if port is not None:
                self.port = port
            if clean is not None:
                self.destinations = clean
            self.epoch += 1
            if self.enabled and (self.worker is None or not self.worker.is_alive()):
                self.worker = threading.Thread(target=self._run, name="CL Scene Backup UDP", daemon=True)
                self.worker.start()

    def new_session(self):
        with self.lock:
            self.session = uuid.uuid4().hex[:8]
            self.seq = 0
            self.epoch += 1

    def snapshot(self):
        with self.lock:
            return {
                "enabled": self.enabled, "show": self.show_id, "port": self.port,
                "authentication": self.authentication, "source_ip": self.source_ip, "source_interface": self.source_interface,
                "authenticated": self.authentication == "hmac_v1",
                "link_state": ("DISABLED" if not self.enabled else
                    "LEGACY UNVERIFIED" if self.authentication == "legacy_v1" else
                    "BACKUP LINK OK" if self.destinations and all(
                        time.monotonic() - self.last_ack.get(item["host"], float("-inf")) < 3
                        for item in self.destinations if item["enabled"]
                    ) and any(item["enabled"] for item in self.destinations) else "BACKUP LINK DOWN"),
                "session": self.session, "seq": self.seq,
                "destinations": [dict(item) for item in self.destinations],
                "config_volatile": True, "queued": self.events.qsize(),
                "enqueued": self.enqueued, "sent_packets": self.sent_packets,
                "send_errors": self.send_errors, "dropped": self.dropped,
                "expired": self.expired, "last_scene_sent": self.last_scene_sent,
                "worker_running": bool(self.worker and self.worker.is_alive()),
                "closed": self.stop_event.is_set(),
            }

    def scene_launched(self, scene_number):
        """Only validate, snapshot and enqueue; no socket, DNS or sleep on GO."""
        try:
            scene_number = int(scene_number)
        except (TypeError, ValueError, OverflowError):
            return
        if scene_number < 1:
            return
        with self.lock:
            if not self.enabled or self.stop_event.is_set():
                return
            targets = tuple(item["host"] for item in self.destinations
                            if item.get("enabled") and item.get("host"))
            if not targets:
                return
            self.seq += 1
            packet = {"v": 1, "show": self.show_id, "session": self.session,
                      "seq": self.seq, "scene": scene_number}
            if self.authentication == "hmac_v1":
                packet["ts"] = time.time()
                packet = sign(packet, self.shared_secret)
            event = (time.monotonic(), self.epoch, packet, targets, self.port)
            try:
                self.events.put_nowait(event)
                self.enqueued += 1
            except queue.Full:
                self.dropped += 1

    def _event_current(self, created_at, epoch):
        with self.lock:
            stale = time.monotonic() - created_at > self.max_event_age
            if stale or epoch != self.epoch or self.stop_event.is_set():
                self.dropped += 1
                self.expired += int(stale)
                return False
            return True

    def _run(self):
        sock = None
        socket_epoch = None
        try:
            while not self.stop_event.is_set():
                try:
                    created_at, epoch, packet, targets, port = self.events.get(timeout=0.05)
                except queue.Empty:
                    try:
                        with self.lock:
                            current_epoch = self.epoch
                            secure = self.enabled and self.authentication == "hmac_v1"
                            source = self.source_ip
                        if socket_epoch != current_epoch and sock is not None:
                            sock.close(); sock = None
                        if secure:
                            if sock is None:
                                sock = self.socket_factory(socket.AF_INET, socket.SOCK_DGRAM)
                                sock.setblocking(False); self._bind_source(sock, source); socket_epoch = current_epoch
                            self._probe(sock)
                    except Exception:
                        with self.lock:
                            self.send_errors += 1
                        if sock is not None:
                            sock.close(); sock = None
                    continue
                try:
                    if not self._event_current(created_at, epoch):
                        continue
                    data = json.dumps(packet, separators=(",", ":")).encode("utf-8")
                    with self.lock:
                        source = self.source_ip
                    if socket_epoch != epoch and sock is not None:
                        sock.close(); sock = None
                    if sock is None:
                        sock = self.socket_factory(socket.AF_INET, socket.SOCK_DGRAM)
                        sock.setblocking(False)
                        if source:
                            self._bind_source(sock, source)
                        socket_epoch = epoch
                    # Interleave destinations: all receive copy 1 before copy 2.
                    valid = True
                    for copy in range(3):
                        for host in targets:
                            if not self._event_current(created_at, epoch):
                                valid = False
                                break
                            try:
                                sock.sendto(data, (host, port))
                                with self.lock:
                                    self.sent_packets += 1
                                    self.last_scene_sent = packet["scene"]
                            except Exception:
                                with self.lock:
                                    self.send_errors += 1
                        if not valid or (copy < 2 and self.stop_event.wait(self.copy_interval)):
                            break
                except Exception:
                    with self.lock:
                        self.send_errors += 1
                        self.dropped += 1
                finally:
                    self.events.task_done()
        finally:
            if sock is not None:
                try:
                    sock.close()
                except Exception:
                    pass
            while True:
                try:
                    self.events.get_nowait()
                except queue.Empty:
                    break
                with self.lock:
                    self.dropped += 1
                self.events.task_done()

    def _bind_source(self, sock, source):
        with self.lock:
            interface = self.source_interface
        if interface:
            index = socket.if_nametoindex(interface)  # Missing adapter fails; no route fallback.
            if sys.platform == "darwin":
                sock.setsockopt(socket.IPPROTO_IP, getattr(socket, "IP_BOUND_IF", 25), index)
            elif sys.platform.startswith("linux"):
                sock.setsockopt(socket.SOL_SOCKET, getattr(socket, "SO_BINDTODEVICE", 25), interface.encode() + b"\0")
            else:
                raise OSError("Liaison à l'interface non supportée sur cette plateforme")
        sock.bind((source, 0))

    def _probe(self, sock):
        with self.lock:
            if not self.enabled or self.authentication != "hmac_v1":
                return
            now = time.monotonic()
            self.probes = {key: item for key, item in self.probes.items() if now - item[1] < 2}
            for item in self.destinations:
                if not item["enabled"]:
                    continue
                host = item["host"]
                last = self.probes.get(host)
                if last and now - last[1] < 1:
                    continue
                nonce = secrets.token_hex(16)
                packet = sign({"v": 1, "type": "ping", "show": self.show_id,
                    "session": self.session, "nonce": nonce, "ts": time.time()}, self.shared_secret)
                sock.sendto(json.dumps(packet, separators=(",", ":")).encode(), (host, self.port))
                self.probes[host] = (nonce, now)
            for _ in range(32):
                try:
                    raw, source = sock.recvfrom(2048)
                except BlockingIOError:
                    break
                try:
                    packet = json.loads(raw)
                    pending = self.probes.get(source[0])
                    if (source[1] != self.port or not pending or
                        set(packet) != {"v", "type", "show", "session", "nonce", "ts", "auth"} or
                        packet["v"] != 1 or packet["type"] != "pong" or
                        packet["show"] != self.show_id or packet["session"] != self.session or
                        packet["nonce"] != pending[0] or abs(time.time() - float(packet["ts"])) > 2):
                        continue
                    expected = hmac.new(self.shared_secret.encode(), canonical(packet), hashlib.sha256).hexdigest()
                    if not hmac.compare_digest(expected, packet["auth"]):
                        continue
                    self.last_ack[source[0]] = now
                except (ValueError, TypeError, KeyError):
                    continue

    def close(self, timeout=1.0):
        """Interrupt repetition delays, discard pending work and reap the worker."""
        with self.lock:
            self.stop_event.set()
            worker = self.worker
        if worker is not None and worker is not threading.current_thread():
            worker.join(timeout=timeout)
        return worker is None or not worker.is_alive()

    stop = close
