#!/usr/bin/env python3
"""Install or restore the bounded Live-thread polling extension (Live closed)."""
import argparse
import ast
from pathlib import Path
import shutil


def install(target, restore=False):
    manager = target / 'manager.py'
    backup = target / 'manager.py.before-cl-fast-poll'
    if restore:
        if not backup.exists():
            raise ValueError('Original manager backup missing')
        shutil.copy2(backup, manager)
        return
    source = manager.read_text(encoding='utf-8')
    if 'from .cl_fast_poll import FastPoll' in source:
        shutil.copy2(Path(__file__).with_name('cl_fast_poll.py'), target / 'cl_fast_poll.py')
        return
    start = '            self.init_api()\n'
    stop = '    def disconnect(self):\n'
    if source.count(start) != 1 or source.count(stop) != 1:
        raise ValueError('Unrecognized Manager; no modification')
    updated = source.replace(start, start + '            from .cl_fast_poll import FastPoll\n            self._cl_fast_poll = FastPoll(self)\n')
    updated = updated.replace(stop, stop + '        fast_poll = getattr(self, "_cl_fast_poll", None)\n        if fast_poll is not None:\n            fast_poll.close()\n')
    ast.parse(updated)
    if backup.exists() and backup.read_text(encoding='utf-8') != source:
        raise ValueError('Existing backup differs; no modification')
    if not backup.exists():
        shutil.copy2(manager, backup)
    shutil.copy2(Path(__file__).with_name('cl_fast_poll.py'), target / 'cl_fast_poll.py')
    temp = manager.with_name('manager.py.cl-new')
    temp.write_text(updated, encoding='utf-8')
    temp.replace(manager)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--target', type=Path, required=True)
    parser.add_argument('--restore', action='store_true')
    args = parser.parse_args()
    install(args.target, args.restore)
