"""Chemins de ressources pour le Terminal et l'application macOS."""
from pathlib import Path
import shutil
import sys


def configuration_path() -> Path:
    # CL_AUDIO_EXPORT_CONFIG_PATH_V1
    source = Path(__file__).resolve().with_name("show_audio.json")

    if not getattr(sys, "frozen", False):
        return source

    support = Path.home() / "Library/Application Support"

    target = support / "CL Audio Export/show_audio.json"
    legacy = support / "CL Show Audio Builder/show_audio.json"

    target.parent.mkdir(parents=True, exist_ok=True)

    if not target.exists():
        if legacy.exists():
            shutil.copy2(legacy, target)
        else:
            shutil.copy2(source, target)

    return target


def bundled_ffmpeg() -> Path | None:
    if getattr(sys, "frozen", False):
        return Path(sys._MEIPASS) / "ffmpeg"
    return None
