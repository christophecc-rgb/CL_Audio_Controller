"""Passive scene trigger classification; called under the application's lock."""
import time


class BackupSceneFollow:
    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.reset()

    def reset(self, token=None, scenes=()):
        self.token = token
        self.values = {scene: None for scene in scenes}
        self.pending_cl = {}
        self.transport_playing = None
        self.forwarded = 0
        self.suppressed_cl = 0

    def note_cl_launch(self, scene):
        if self.token and scene in self.values:
            self.pending_cl[scene] = self.pending_cl.get(scene, []) + [self.clock() + 30]

    def receive(self, scene, token, triggered):
        if not self.token or token != self.token or scene not in self.values:
            return False
        if type(triggered) not in (bool, int) or triggered not in (0, 1):
            return False
        previous = self.values[scene]
        self.values[scene] = bool(triggered)
        # Quantized launches emit True then False; immediate launches in Live
        # can notify only False after the trigger has already completed.
        # A known False followed by a new False callback is that completion.
        # The initial snapshot and completion following True never launch.
        if previous or (previous is None and not triggered):
            return False
        pending = [expiry for expiry in self.pending_cl.get(scene, []) if expiry > self.clock()]
        if pending:
            self.pending_cl[scene] = pending[1:]
            self.suppressed_cl += 1
            return False
        self.pending_cl.pop(scene, None)
        if previous is None:
            return False
        self.forwarded += 1
        return True

    def receive_transport_stop(self, token, playing):
        if not self.token or token != self.token or type(playing) not in (bool, int) or playing not in (0, 1):
            return False
        previous = self.transport_playing
        self.transport_playing = bool(playing)
        return previous is True and not playing
