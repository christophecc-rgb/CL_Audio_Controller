"""Optional best-effort OSC copy. No primary transport, retries or chase here."""
from dataclasses import dataclass
import ipaddress
import math
import queue
import socket
import threading
import time

from pythonosc.osc_message_builder import OscMessageBuilder

ALLOWED = frozenset({
    '/live/song/continue_playing', '/live/song/start_playing',
    '/live/song/stop_playing', '/live/song/set/current_song_time',
    '/live/song/set/back_to_arranger', '/live/scene/fire',
})
READS = ('is_playing', 'name', 'tempo')
MAX_AGE = 0.250


@dataclass(frozen=True)
class Config:
    epoch: int = 0
    mode: str = 'mtc'
    host: str = ''
    expected_name: str = ''
    expected_tempo: float = 0


class HotBackup:
    def __init__(self, clock=time.monotonic, socket_factory=socket.socket):
        self.clock = clock
        self.socket_factory = socket_factory
        self.config = Config()
        self.events = queue.Queue(maxsize=64)
        self.replies = queue.Queue(maxsize=64)
        self.thread = None
        self.info = {'state': 'DISABLED', 'detail': 'MTC continu'}
        self.values = {}
        self.last_probe = 0
        self.dropped = 0
        self.sent = 0
        self.preflight = False
        self.last_command = None
        self.missed = False
        self.health_epoch = -1
        self.last_progress = self.clock()
        self.shutdown = threading.Event()

    def configure(self, mode, host='', expected_name='', expected_tempo=0):
        if mode not in ('mtc', 'hot_backup'):
            raise ValueError('Mode invalide')
        if mode == 'hot_backup':
            ip = ipaddress.IPv4Address(host)
            if ip.is_loopback or ip.is_unspecified or ip.is_multicast or ip.is_link_local or str(ip).endswith('.255'):
                raise ValueError('Adresse IPv4 BACKUP unicast requise')
            if not expected_name or not math.isfinite(expected_tempo) or expected_tempo <= 0:
                raise ValueError('Identité et tempo PRIMARY indisponibles')
        self.config = Config(self.config.epoch + 1, mode, host, expected_name, expected_tempo)
        # Worker owns socket and mutable health. An epoch change discards old work.
        if self.thread is None and mode == 'hot_backup':
            self.thread = threading.Thread(target=self._run, daemon=True, name='CL Hot Backup')
            self.thread.start()

    def offer(self, address, *args):
        """Bounded in-memory handoff only; never DNS, network, wait or callback."""
        try:
            cfg = self.config
            if cfg.mode != 'hot_backup' or address not in ALLOWED:
                return
            self.events.put_nowait((cfg.epoch, self.clock(), address, args))
        except Exception:
            self.dropped += 1
            self.missed = True

    def receive(self, host, address, args):
        try:
            cfg = self.config
            if cfg.mode == 'hot_backup' and host == cfg.host:
                self.replies.put_nowait((cfg.epoch, self.clock(), address, tuple(args)))
        except Exception:
            pass

    def snapshot(self):
        if self.config.mode == 'mtc':
            return {'mode': 'mtc', 'state': 'DISABLED', 'host': self.config.host}
        info = self.info
        if self.health_epoch != self.config.epoch:
            info = {'state': 'NOT READY', 'detail': 'Vérification BACKUP'}
        elif self.clock() - self.last_progress > 3:
            info = {'state': 'OFFLINE', 'detail': 'Worker BACKUP sans réponse'}
        return {**info, 'mode': 'hot_backup', 'host': self.config.host,
                'sent': self.sent, 'dropped': self.dropped,
                'detail_note': 'EXT OFF manuel ; commandes CL et scènes Session directes'}

    def _write(self, sock, cfg, address, args=()):
        builder = OscMessageBuilder(address=address)
        for arg in args:
            builder.add_arg(arg)
        sock.sendto(builder.build().dgram, (cfg.host, 11000))

    def _health(self, cfg):
        while True:
            try:
                epoch, at, address, args = self.replies.get_nowait()
            except queue.Empty:
                break
            if epoch != cfg.epoch:
                continue
            if address == '/live/error':
                self.missed = True
                self.info = {'state': 'ERROR', 'detail': 'Erreur AbletonOSC BACKUP'}
                continue
            if not address.startswith('/live/song/get/'):
                continue
            key = address.rsplit('/', 1)[-1]
            if key not in READS:
                continue
            if len(args) != 1:
                self.info = {'state': 'ERROR', 'detail': 'Réponse OSC invalide'}
                self.values.pop(key, None)
                continue
            value = args[0]
            valid = ((key == 'name' and isinstance(value, str) and bool(value)) or
                     (key == 'is_playing' and type(value) in (int, bool) and value in (0, 1)) or
                     (key == 'tempo' and type(value) in (int, float) and math.isfinite(value) and value > 0))
            if not valid:
                self.info = {'state': 'ERROR', 'detail': 'Réponse OSC invalide'}
                self.values.pop(key, None)
                continue
            self.values[key] = (value, at)
        now = self.clock()
        if not all(k in self.values and now - self.values[k][1] < 3 for k in READS):
            if self.info.get('state') != 'ERROR':
                self.info = {'state': 'OFFLINE', 'detail': 'Réponses BACKUP absentes ou expirées'}
            return False
        if self.values['name'][0] != cfg.expected_name:
            self.info = {'state': 'NOT READY', 'detail': 'Nom du set BACKUP différent'}
            return False
        # Initial readiness only. Tempo automation during playback is never corrected.
        if not self.preflight:
            if self.values['is_playing'][0] or abs(self.values['tempo'][0] - cfg.expected_tempo) > .01:
                self.info = {'state': 'NOT READY', 'detail': 'Arrêter BACKUP et vérifier son tempo initial'}
                return False
            self.preflight = True
        if self.missed:
            self.info = {'state': 'NOT READY', 'detail': "Événement perdu / erreur : réarmer à l'arrêt"}
            return False
        self.info = {'state': 'ONLINE', 'detail': 'Réponses reçues ; contenu du set à vérifier manuellement'}
        return True

    def _event(self, sock, cfg, ready, item):
        epoch, at, address, args = item
        if cfg != self.config or epoch != cfg.epoch:
            self.dropped += 1
            return
        if self.clock() - at > MAX_AGE:
            self.dropped += 1
            self.missed = True
            return
        # Stop is always attempted, including offline/not-ready. Never replay GO.
        if not ready and address != '/live/song/stop_playing':
            self.dropped += 1
            self.missed = True
            return
        try:
            self._write(sock, cfg, address, args)
        except Exception:
            self.missed = True
            raise
        self.sent += 1
        self.last_command = address

    def _run(self):
        sock = None
        epoch = -1
        while not self.shutdown.is_set():
            cfg = self.config
            self.last_progress = self.clock()
            try:
                if cfg.epoch != epoch:
                    epoch = cfg.epoch
                    self.health_epoch = epoch
                    self.missed = False
                    self.values = {}
                    self.preflight = False
                    self.last_probe = -10
                    self.info = {'state': 'NOT READY', 'detail': 'Vérification BACKUP'}
                    if sock is not None:
                        sock.close()
                    sock = None
                if cfg.mode == 'mtc':
                    self.shutdown.wait(.05)
                    continue
                if sock is None:
                    sock = self.socket_factory(socket.AF_INET, socket.SOCK_DGRAM)
                    sock.setblocking(False)
                # Read-only telemetry; no periodic transport or position command.
                if self.clock() - self.last_probe >= 1:
                    self.last_probe = self.clock()
                    for key in READS:
                        self._write(sock, cfg, '/live/song/get/' + key)
                ready = self._health(cfg)
                try:
                    item = self.events.get(timeout=.020)
                except queue.Empty:
                    continue
                self._event(sock, cfg, ready, item)
            except Exception as exc:
                self.info = {'state': 'ERROR', 'detail': str(exc)[:160]}
                # No retry of the command that failed. Cooldown affects only worker.
                self.shutdown.wait(.05)

        if sock is not None:
            sock.close()
