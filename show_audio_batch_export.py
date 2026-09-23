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
import json
import urllib.request
import unicodedata

from show_audio_playback_sources import group_playback_leaf_tracks

from show_audio_ableton_offline import (
    OFFLINE_SUCCESS,
    execute_offline_wav,
)


class BatchExportError(RuntimeError):
    pass


_CL_AUDIO_HTTP = "http://127.0.0.1:5050"


def _http_json(url: str, *, method: str = "GET", payload=None):
    data = None
    headers = {}

    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(
        url,
        data=data,
        headers=headers,
        method=method,
    )

    with urllib.request.urlopen(request, timeout=3.0) as response:
        return json.loads(response.read().decode("utf-8"))


def _track_state_snapshot(indices):
    unique = sorted({int(value) for value in indices})

    if not unique:
        return {}

    query = ",".join(str(value) for value in unique)

    result = _http_json(
        f"{_CL_AUDIO_HTTP}/show-audio/tracks-bulk"
        f"?track_indices={query}"
    )

    if not result.get("ok"):
        raise BatchExportError(
            result.get("error") or "lecture états pistes impossible"
        )

    return {
        int(track["track_index"]): bool(track["track_mute"])
        for track in result.get("tracks") or []
        if track.get("track_mute") is not None
    }


def _set_track_mutes(states):
    if not states:
        return

    result = _http_json(
        f"{_CL_AUDIO_HTTP}/show-audio/tracks-mute",
        method="POST",
        payload={
            "tracks": [
                {
                    "track_index": int(index),
                    "mute": bool(mute),
                }
                for index, mute in states.items()
            ]
        },
    )

    if not result.get("ok"):
        raise BatchExportError(
            result.get("error") or "écriture états pistes impossible"
        )


def _text(value):
    return str(value or "").strip()


def _normalized_match_text(value):
    text = _text(value).casefold()
    text = unicodedata.normalize("NFKD", text)
    return "".join(
        char
        for char in text
        if not unicodedata.combining(char)
    )


def _token_matches(token, track_name):
    token = _normalized_match_text(token)
    track_name = _normalized_match_text(track_name)

    return bool(token and token in track_name)


def _automatic_playback_states(item):
    """
    Retourne {track_index: mute}.

    Aucun rôle/artiste configuré => {} => mode manuel historique inchangé.
    """
    source = item.get("source_item") or {}

    variants = [
        value
        for value in source.get("variants") or []
        if isinstance(value, dict)
        and _text(value.get("role"))
        and _text(value.get("artist"))
    ]

    if not variants:
        return {}

    artists = {
        _text(value.get("artist"))
        for value in variants
        if _text(value.get("artist"))
    }

    # Tokens utilisés pour retrouver les playbacks musicaux sous SAISON...
    #
    # Cas particulier métier actuel :
    #   rôle Directrice -> groupes/pistes musicaux nommés "DIR"
    #
    # La piste voix sous PLAYBACK... reste, elle, résolue avec le prénom
    # de l'artiste (par ex. Directrice -> Vénus -> PB VENUS).
    season_tokens = set()

    for value in variants:
        role = _text(value.get("role"))
        artist = _text(value.get("artist"))
        playback = _text(value.get("playback"))

        if role.casefold() == "directrice":
            season_tokens.add("DIR")
            continue

        token = playback or artist

        if token:
            season_tokens.add(token)

    # La clé reste disponible pour les futures variantes.
    keys = {
        _text(value.get("key"))
        for value in variants
        if _text(value.get("key"))
    }

    tracks = [
        dict(value)
        for value in item.get("track_inventory") or []
        if isinstance(value, dict)
    ]

    if not tracks:
        # Sécurité : ne rien modifier si l'inventaire n'est pas disponible.
        return {}

    playback_groups = [
        track
        for track in tracks
        if track.get("is_foldable") is True
        and _text(track.get("track_name")).casefold().startswith("playback")
    ]

    season_groups = [
        track
        for track in tracks
        if track.get("is_foldable") is True
        and _text(track.get("track_name")).casefold().startswith("saison")
    ]

    changes = {}

    # --------------------------------------------------------
    # VOIX : groupes PLAYBACK...
    # --------------------------------------------------------
    for group in playback_groups:
        group_name = _text(group.get("track_name"))

        for track in group_playback_leaf_tracks(tracks, group_name):
            try:
                index = int(track.get("track_index"))
            except (TypeError, ValueError):
                continue

            name = _text(track.get("track_name"))

            selected = any(
                _token_matches(artist, name)
                for artist in artists
            )

            # On ne pilote que les pistes ressemblant effectivement à
            # des playbacks artistes. Les autres pistes du groupe ne sont
            # pas modifiées arbitrairement.
            candidate = (
                "pb " in (" " + name.casefold())
                or any(
                    _token_matches(artist, name)
                    for artist in artists
                )
            )

            if candidate:
                changes[index] = not selected  # mute = not ON

    # --------------------------------------------------------
    # MUSIQUE : groupes SAISON...
    # --------------------------------------------------------
    for group in season_groups:
        group_name = _text(group.get("track_name"))

        for track in group_playback_leaf_tracks(tracks, group_name):
            try:
                index = int(track.get("track_index"))
            except (TypeError, ValueError):
                continue

            name = _text(track.get("track_name"))

            selected = any(
                _token_matches(token, name)
                for token in season_tokens
            )

            # Si une clé est renseignée et apparaît dans le nom,
            # elle participe naturellement au choix.
            if selected and keys:
                matching_keys = [
                    key for key in keys
                    if _token_matches(key, name)
                ]

                # Pas de clé dans le nom = on garde la version unique.
                # Clé présente = elle doit appartenir aux clés sélectionnées.
                name_has_any_key_marker = any(
                    _token_matches(key, name)
                    for key in keys
                )

                if name_has_any_key_marker and not matching_keys:
                    selected = False

            # Ici, on ne mute que les pistes qui correspondent à au moins
            # une identité de playback connue pour cette scène.
            candidate = any(
                _token_matches(token, name)
                for token in season_tokens
            )

            if candidate:
                changes[index] = not selected

    return changes


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

    playback_restore = {}

    try:
        result["status"] = "rendering"

        requested_states = _automatic_playback_states(item)

        if requested_states:
            playback_restore = _track_state_snapshot(
                requested_states.keys()
            )

            print(
                "[AUTO_PLAYBACK] apply "
                + json.dumps({
                    str(index): ("OFF" if mute else "ON")
                    for index, mute in requested_states.items()
                }, sort_keys=True),
                flush=True,
            )

            _set_track_mutes(requested_states)
            time.sleep(0.20)

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
        if playback_restore:
            try:
                print(
                    "[AUTO_PLAYBACK] restore "
                    + json.dumps({
                        str(index): ("OFF" if mute else "ON")
                        for index, mute in playback_restore.items()
                    }, sort_keys=True),
                    flush=True,
                )
                _set_track_mutes(playback_restore)
            except Exception as restore_exc:
                print(
                    f"[AUTO_PLAYBACK] restauration impossible: {restore_exc}",
                    flush=True,
                )

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
