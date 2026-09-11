"""Exécution batch des exports CL Show Audio.

Ce module ne résout aucune identité métier.
Il reçoit des items dont la zone Arrangement est déjà résolue.

Pipeline :
    zone résolue
    -> master WAV Ableton offline
    -> validation master
    -> encodages finaux
    -> publication atomique
"""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid
import wave
from typing import Any, Callable

from show_audio_ableton_offline import (
    OFFLINE_SUCCESS,
    execute_offline_wav,
)


class BatchExportError(RuntimeError):
    pass


def _ffmpeg_path() -> str:
    from show_audio_runtime import bundled_ffmpeg
    bundled = bundled_ffmpeg()
    path = str(bundled) if bundled is not None and bundled.is_file() else shutil.which("ffmpeg")

    if not path:
        raise BatchExportError("ffmpeg introuvable")

    return path


def _validate_mp3(
    path: Path,
) -> dict:
    target = Path(path)

    if not target.is_file():
        raise BatchExportError(
            f"MP3 introuvable : {target}"
        )

    size = target.stat().st_size

    if size <= 1024:
        raise BatchExportError(
            f"MP3 vide ou incomplet : {target}"
        )

    return {
        "path": str(target),
        "size": size,
        "format": "mp3",
    }


def encode_mp3(
    master_wav: Path,
    output_path: Path,
    *,
    bitrate_kbps: int,
) -> dict:
    """Encode un master WAV en MP3 puis publie atomiquement."""

    source = Path(master_wav).expanduser().resolve()
    target = Path(output_path).expanduser().resolve()

    if not source.is_file():
        raise BatchExportError(
            f"master WAV introuvable : {source}"
        )

    bitrate = int(bitrate_kbps)

    if bitrate not in (192, 256, 320):
        raise BatchExportError(
            f"bitrate MP3 non supporté : {bitrate}"
        )

    target.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    token = uuid.uuid4().hex[:12]

    partial = target.with_name(
        f".{target.name}.{token}.partial.mp3"
    )

    try:
        command = [
            _ffmpeg_path(),
            "-hide_banner",
            "-loglevel",
            "error",
            "-nostdin",
            "-y",
            "-i",
            str(source),
            "-vn",
            "-codec:a",
            "libmp3lame",
            "-b:a",
            f"{bitrate}k",
            str(partial),
        ]

        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )

        if completed.returncode != 0:
            raise BatchExportError(
                "encodage MP3 échoué : "
                + completed.stderr.strip()
            )

        validation = _validate_mp3(
            partial
        )

        os.replace(
            partial,
            target,
        )

        validation["path"] = str(target)
        validation["bitrate_kbps"] = bitrate

        return validation

    finally:
        try:
            if partial.exists():
                partial.unlink()
        except OSError:
            pass


def _copy_wav_atomic(
    source: Path,
    target: Path,
) -> dict:
    source = Path(source).resolve()
    target = Path(target).resolve()

    target.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    token = uuid.uuid4().hex[:12]

    partial = target.with_name(
        f".{target.name}.{token}.partial"
    )

    try:
        shutil.copy2(
            source,
            partial,
        )

        with wave.open(
            str(partial),
            "rb",
        ) as handle:
            result = {
                "path": str(target),
                "size": partial.stat().st_size,
                "format": "wav",
                "sample_rate": handle.getframerate(),
                "channels": handle.getnchannels(),
                "bit_depth": (
                    handle.getsampwidth() * 8
                ),
                "duration_seconds": (
                    handle.getnframes()
                    / float(handle.getframerate())
                ),
            }

        os.replace(
            partial,
            target,
        )

        return result

    finally:
        try:
            if partial.exists():
                partial.unlink()
        except OSError:
            pass


def execute_batch_item(
    item: dict,
    *,
    output_directory: Path,
    tempo: float,
    automation: Callable[[str], Any] | None = None,
    timeout: float = 300.0,
) -> dict:
    """Exécute un item dont la zone Arrangement est déjà résolue."""

    started = time.monotonic()

    zone = item.get("zone")

    if not isinstance(zone, dict):
        raise BatchExportError(
            "zone Arrangement résolue absente"
        )

    outputs = item.get("outputs")

    if not isinstance(outputs, list) or not outputs:
        raise BatchExportError(
            "aucune sortie finale demandée"
        )

    output_directory = (
        Path(output_directory)
        .expanduser()
        .resolve()
    )

    output_directory.mkdir(
        parents=True,
        exist_ok=True,
    )

    master_directory = (
        output_directory
        / ".cl_show_audio_masters"
    )

    master_directory.mkdir(
        parents=True,
        exist_ok=True,
    )

    item_id = str(
        item.get("id")
        or "export"
    )

    token = uuid.uuid4().hex[:12]

    master_path = (
        master_directory
        / f"{item_id}.{token}.wav"
    )

    settings = item.get("settings") or {}

    sample_rate = int(
        settings.get(
            "sample_rate",
            48000,
        )
    )

    normalize = bool(
        settings.get(
            "normalize",
            False,
        )
    )

    # Le master de travail offline reste WAV 24 bits.
    # Les formats finaux sont dérivés ensuite de cette capture unique.
    offline_settings = {
        "sample_rate": sample_rate,
        "normalize": normalize,
        "formats": [
            {
                "format": "wav",
                "bit_depth": 24,
            }
        ],
    }

    result = {
        "id": item_id,
        "status": "preparing",
        "outputs": [],
    }

    try:
        result["status"] = "rendering"

        render = execute_offline_wav(
            zone=zone,
            settings=offline_settings,
            output_path=master_path,
            tempo=float(tempo),
            automation=automation,
            timeout=float(timeout),
        )

        result["render"] = render

        if render.get("status") != OFFLINE_SUCCESS:
            result["status"] = "failed"
            result["fallback"] = render.get(
                "fallback",
                "realtime",
            )
            result["error"] = render.get(
                "error",
                "rendu offline échoué",
            )
            return result

        if not master_path.is_file():
            raise BatchExportError(
                "master WAV absent après rendu"
            )

        result["status"] = "encoding"

        for specification in outputs:
            fmt = str(
                specification.get("format")
                or ""
            ).casefold()

            filename = str(
                specification.get("filename")
                or ""
            ).strip()

            if not filename:
                raise BatchExportError(
                    "nom de sortie final absent"
                )

            final_path = (
                output_directory
                / filename
            )

            if fmt == "mp3":
                encoded = encode_mp3(
                    master_path,
                    final_path,
                    bitrate_kbps=int(
                        specification[
                            "bitrate_kbps"
                        ]
                    ),
                )

            elif fmt == "wav":
                encoded = _copy_wav_atomic(
                    master_path,
                    final_path,
                )

            else:
                raise BatchExportError(
                    "format batch V1 non supporté : "
                    + fmt
                )

            result["outputs"].append(
                encoded
            )

        result["status"] = "completed"
        result["elapsed_seconds"] = (
            time.monotonic() - started
        )

        return result

    except Exception as exc:
        result["status"] = "failed"
        result["error"] = str(exc)

        return result

    finally:
        try:
            if master_path.exists():
                master_path.unlink()
        except OSError:
            pass

        try:
            master_directory.rmdir()
        except OSError:
            pass


def execute_batch(
    items: list[dict],
    *,
    output_directory: Path,
    tempo: float,
    automation: Callable[[str], Any] | None = None,
    timeout_per_item: float = 300.0,
) -> dict:
    """Exécute séquentiellement une liste de zones déjà résolues."""

    started = time.monotonic()

    results = []

    for item in items:
        result = execute_batch_item(
            item,
            output_directory=output_directory,
            tempo=tempo,
            automation=automation,
            timeout=timeout_per_item,
        )

        results.append(
            result
        )

        # Un échec de rendu Ableton arrête le batch :
        # ne pas continuer à manipuler Live dans un état inconnu.
        if (
            result.get("status") == "failed"
            and result.get("fallback") == "realtime"
        ):
            break

    completed = sum(
        result.get("status") == "completed"
        for result in results
    )

    failed = sum(
        result.get("status") == "failed"
        for result in results
    )

    return {
        "status": (
            "completed"
            if failed == 0
            else "failed"
        ),
        "items": results,
        "metrics": {
            "requested": len(items),
            "processed": len(results),
            "completed": completed,
            "failed": failed,
            "elapsed_seconds": (
                time.monotonic() - started
            ),
        },
    }
