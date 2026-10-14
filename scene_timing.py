"""Common timing boundary, without changing FULL's legacy algorithms.

Declared durations, clip estimates and observed positions are different sources.
The adapter deliberately performs no queries or service startup on construction.
"""
from dataclasses import dataclass
from enum import Enum
from typing import Callable


class TimingSource(str, Enum):
    DECLARED = 'declared'
    CLIP_ESTIMATED = 'clip_estimated'
    OBSERVED = 'observed'


@dataclass(frozen=True)
class SceneTimingAPI:
    declared_duration: Callable
    resolve_current: Callable
    prepare_duration: Callable
    refresh_remaining: Callable
