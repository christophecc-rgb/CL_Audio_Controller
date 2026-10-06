"""Native Live-thread OSC polling; the original Manager.tick remains the fallback."""
import logging
import threading
from pathlib import Path

log = logging.getLogger('abletonosc')


class FastPoll:
    def __init__(self, manager, timer_factory=None):
        self.manager = manager
        self.thread = threading.get_ident()
        self.timer = None
        self.closed = False
        try:
            if Path(__file__).with_name('.cl-fast-poll-disabled').exists():
                return
            if timer_factory is None:
                import Live
                timer_factory = Live.Base.Timer
            self.timer = timer_factory(self.poll, 20, True, False)
            self.timer.start()
            log.info('CL fast OSC polling enabled: 20 ms')
        except Exception:
            self.close()
            log.exception('CL fast OSC polling unavailable; original polling retained')

    def poll(self):
        if self.closed:
            return
        if threading.get_ident() != self.thread:
            self.close()
            log.error('CL fast OSC polling stopped: unexpected callback thread')
            return
        try:
            self.manager.osc_server.process()
        except Exception:
            self.close()
            log.exception('CL fast OSC polling stopped; original polling retained')

    def close(self):
        self.closed = True
        timer, self.timer = self.timer, None
        if timer is not None:
            try:
                timer.stop()
            except Exception:
                log.exception('CL timer stop failed')
