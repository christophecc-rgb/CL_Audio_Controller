"""Optional Bonjour publication using macOS dns-sd, without ctypes or threads."""
import atexit
import logging
import socket
import subprocess

from . import manager as _manager_module
from .manager import Manager

log = logging.getLogger('abletonosc')
SERVICE_TYPE = '_cl-ableton._udp'


class Announcement:
    def __init__(self, port):
        self.port = int(port)
        if not 1 <= self.port <= 65535:
            raise ValueError('Invalid Bonjour port')
        # DNS-SD instance labels are limited to 63 UTF-8 bytes. The SRV hostname
        # itself is supplied by mDNSResponder, not synthesized from this label.
        hostname = socket.gethostname().split('.')[0] or 'Mac'
        name = (hostname + ' AbletonOSC').encode('utf-8')[:63].decode('utf-8', 'ignore')
        self.process = subprocess.Popen(
            ['/usr/bin/dns-sd', '-R', name, SERVICE_TYPE, 'local.', str(self.port),
             'role=ableton', 'protocol=abletonosc', 'version=1'],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, shell=False, close_fds=True)
        atexit.register(self.close)

    def poll(self):
        if self.process is None:
            raise OSError('Bonjour publisher closed')
        code = self.process.poll()  # Also reaps an unexpectedly exited child.
        if code is not None:
            raise OSError('dns-sd exited with status %s' % code)

    def close(self):
        proc = self.process
        if proc is None:
            return
        if proc.poll() is None:
            try:
                proc.terminate()
            except ProcessLookupError:
                pass  # Exited between poll and terminate; still needs wait.
        try:
            proc.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            try:
                proc.kill()
            except ProcessLookupError:
                pass
            proc.wait(timeout=0.5)
        # Keep ownership on any failure above: never spawn a duplicate while
        # the old process may still be alive. atexit provides a final retry.
        self.process = None
        atexit.unregister(self.close)


class BonjourManager(Manager):
    def __init__(self, c_instance):
        self._cl_announcement = None
        self._cl_disconnected = False
        super().__init__(c_instance)
        self._cl_bonjour_tick()

    def _cl_close_announcement(self):
        if self._cl_announcement is not None:
            self._cl_announcement.close()
            self._cl_announcement = None

    def _cl_claim_publisher(self):
        # Keep the owner on the existing manager module, including across a
        # reload of this extension. No changes to manager.py are needed.
        previous = getattr(_manager_module, '_cl_bonjour_owner', None)
        if previous is not None and previous is not self:
            previous._cl_disconnected = True
            previous._cl_close_announcement()
        _manager_module._cl_bonjour_owner = self

    def _cl_bonjour_tick(self):
        if self._cl_disconnected:
            return
        try:
            server = getattr(self, 'osc_server', None)
            sock = getattr(server, '_socket', None)
            address = sock.getsockname() if sock is not None and sock.fileno() >= 0 else None
            if address is None or address[0] != '0.0.0.0':
                self._cl_close_announcement()
            else:
                self._cl_claim_publisher()
                if self._cl_announcement is not None and self._cl_announcement.port != address[1]:
                    self._cl_close_announcement()
                if self._cl_announcement is None:
                    self._cl_announcement = Announcement(address[1])
                self._cl_announcement.poll()
        except Exception as exc:
            try:
                self._cl_close_announcement()
            except Exception as cleanup_error:
                log.warning('CL Bonjour cleanup pending: %s', cleanup_error)
            log.warning('CL Bonjour unavailable: %s', exc)
        # Existing Live scheduler; no threads, OSC traffic or Manager.tick change.
        self.schedule_message(50, self._cl_bonjour_tick)

    def disconnect(self):
        self._cl_disconnected = True
        try:
            self._cl_close_announcement()
        except Exception as exc:
            log.warning('CL Bonjour cleanup pending: %s', exc)
        finally:
            if (self._cl_announcement is None
                    and getattr(_manager_module, '_cl_bonjour_owner', None) is self):
                delattr(_manager_module, '_cl_bonjour_owner')
            super().disconnect()
