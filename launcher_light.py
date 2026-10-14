"""Standalone entry point: always select the common engine with the Light profile."""
import os

os.environ['CL_APP_MODE'] = 'LOCAL_LIGHT'
# Frozen releases never select the historical development fallback.
import sys
if getattr(sys, 'frozen', False):
    os.environ['CL_LIGHT_ENGINE'] = 'common'

from runtime_startup import run_light_entry

if __name__ == '__main__':
    run_light_entry('launcher')
