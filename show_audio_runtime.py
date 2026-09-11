"""Chemins de ressources pour le Terminal et l'application macOS."""
from pathlib import Path
import shutil
import sys


def configuration_path() -> Path:
    source = Path(__file__).resolve().with_name("show_audio.json")
    if not getattr(sys, "frozen", False):
        return source
    target = Path.home() / "Library/Application Support/CL Show Audio Builder/show_audio.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        shutil.copy2(source, target)
    return target


def bundled_ffmpeg() -> Path | None:
    if getattr(sys, "frozen", False):
        return Path(sys._MEIPASS) / "ffmpeg"
    return None
