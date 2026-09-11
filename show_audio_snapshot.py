#!/usr/bin/env python3

"""Snapshot global read-only pour CL Show Audio.

Cette V1 :
- passe uniquement par le backend CL Audio Controller ;
- n'ouvre aucun port AbletonOSC ;
- n'envoie aucune commande à Live ;
- lit /status ;
- lit /show-audio/scene-clips ;
- mémorise l'état ON/OFF de chaque piste déjà interrogée ;
- classe les pistes playback via show_audio.json ;
- calcule localement la durée de référence.

Le format produit est volontairement indépendant de l'interface graphique.
"""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

from show_audio_plan import (
    is_playback_track,
    select_reference_clip,
    select_reference_playback_clip,
)
from show_audio_playback_sources import resolve_playback_track_names, discover_playback_sources
from show_audio_plan import is_technical_track



DEFAULT_BASE_URL = "http://127.0.0.1:5050"
DEFAULT_CONFIG_PATH = Path("show_audio.json")


def _get_json(
    base_url: str,
    path: str,
    timeout: float,
) -> Dict[str, Any]:
    url = base_url.rstrip("/") + path
    started = time.monotonic()

    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            raw = response.read()
            status = int(getattr(response, "status", 200) or 200)
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        raise RuntimeError(
            f"HTTP {exc.code} pour {path}: "
            f"{raw.decode('utf-8', errors='replace')}"
        ) from exc
    except Exception as exc:
        raise RuntimeError(
            f"Erreur HTTP pour {path}: {exc}"
        ) from exc

    elapsed = time.monotonic() - started

    try:
        payload = json.loads(raw.decode("utf-8"))
    except Exception as exc:
        raise RuntimeError(
            f"Réponse non JSON pour {path} "
            f"({len(raw)} octets, HTTP {status})"
        ) from exc

    if isinstance(payload, dict):
        payload["_http_seconds"] = elapsed

    return payload


def _track_indices(
    clips: Iterable[Dict[str, Any]],
) -> List[int]:
    result = set()

    for clip in clips:
        try:
            result.add(int(clip["track_index"]))
        except (KeyError, TypeError, ValueError):
            continue

    return sorted(result)


def _format_seconds(value: Any) -> Optional[float]:
    try:
        seconds = float(value)
    except (TypeError, ValueError):
        return None

    if seconds <= 0:
        return None

    return seconds


def _resolve_snapshot_tempo(
    status: Dict[str, Any],
    raw_scenes: Iterable[Dict[str, Any]],
) -> Optional[float]:
    """Résout le tempo Live sans rendre /status bloquant."""

    try:
        status_tempo = float(status.get("tempo"))
    except (TypeError, ValueError):
        status_tempo = None

    if status_tempo is not None and status_tempo > 0:
        return status_tempo

    tempos = set()

    for scene in raw_scenes:
        try:
            tempo = float(scene.get("tempo"))
        except (TypeError, ValueError):
            continue

        if tempo > 0:
            tempos.add(tempo)

    if not tempos:
        return None

    if len(tempos) != 1:
        raise RuntimeError(
            "Tempos Live contradictoires dans le snapshot : "
            + ", ".join(
                f"{tempo:g}"
                for tempo in sorted(tempos)
            )
        )

    return next(iter(tempos))


class ShowAudioSnapshotBuilder:
    def __init__(
        self,
        *,
        base_url: str = DEFAULT_BASE_URL,
        config_path: Path = DEFAULT_CONFIG_PATH,
        progress=None,
    ) -> None:
        self.progress = progress
        self.discovered_sources = None
        self.base_url = base_url.rstrip("/")
        self.config_path = Path(config_path)
        self.track_cache: Dict[int, Dict[str, Any]] = {}
        self.http_seconds = 0.0
        self.scene_clip_seconds = 0.0
        self.track_seconds = 0.0

        self.config = self._load_config()

        self.playback_track_names = list(
            self.config.get("playback_tracks") or []
        )

    def _load_config(self) -> Dict[str, Any]:
        if not self.config_path.exists():
            return {}

        with self.config_path.open(
            "r",
            encoding="utf-8",
        ) as handle:
            data = json.load(handle)

        return data if isinstance(data, dict) else {}

    def _request(
        self,
        path: str,
        *,
        timeout: float,
    ) -> Dict[str, Any]:
        if self.progress:
            self.progress(path)
        data = _get_json(
            self.base_url,
            path,
            timeout,
        )

        elapsed = float(
            data.get("_http_seconds") or 0.0
        )

        self.http_seconds += elapsed

        return data

    def status(self) -> Dict[str, Any]:
        # /status publie le cache Arrangement mais ne le rafraîchit pas.
        # La route /arrangement charge les vrais Cue Points depuis Ableton
        # dans ce cache. Sa réponse HTML n'est pas utilisée ici.
        try:
            with urllib.request.urlopen(
                f"{self.base_url}/arrangement",
                timeout=2.0,
            ) as response:
                response.read()
        except Exception:
            # Le snapshot reste utilisable même si l'Arrangement est
            # momentanément indisponible ; /status donnera alors son cache.
            pass

        return self._request(
            "/status",
            timeout=5.0,
        )

    def scene_clips(
        self,
        scene_index: int,
    ) -> Dict[str, Any]:
        """Lecture historique d'une scène, conservée pour diagnostic."""
        data = self._request(
            f"/show-audio/scene-clips?"
            f"scene_index={int(scene_index)}",
            timeout=10.0,
        )

        self.scene_clip_seconds += float(
            data.get("_http_seconds") or 0.0
        )

        return data

    def resolve_playback_sources(self) -> list[str]:
        """Résout pistes explicites + descendants des groupes playback."""

        groups = list(
            self.config.get("playback_groups") or []
        )

        if not groups:
            return list(self.playback_track_names)

        # Diagnostic hiérarchique actuellement nécessaire uniquement
        # pour résoudre les descendants de groupes.
        hierarchy = self._request(
            f"/show-audio/track-hierarchy?start=0&end={self.track_count - 1}",
            timeout=20.0,
        )

        if not hierarchy.get("ok"):
            raise RuntimeError(
                f"Hiérarchie playback invalide: {hierarchy}"
            )

        resolved = resolve_playback_track_names(
            self.config,
            hierarchy.get("tracks") or [],
        )

        if not resolved:
            raise RuntimeError(
                "Aucune piste playback résolue."
            )

        return resolved

    def discover_sources(self, raw_scenes, generation):
        hierarchy = self._request(
            f"/show-audio/track-hierarchy?start=0&end={self.track_count - 1}",
            timeout=max(20.0, self.track_count * 0.3 + 5.0),
        )
        if not hierarchy.get("ok") or hierarchy.get("set_generation") != generation:
            raise RuntimeError("Hiérarchie playback invalide ou Set changé pendant le scan")
        representatives = {}
        for scene in raw_scenes:
            for clip in scene.get("clips") or []:
                if is_technical_track(clip.get("track_name")):
                    continue

                index = int(clip["track_index"])
                scene_index = int(scene["scene_index"])
                candidates = representatives.setdefault(index, [])

                if scene_index not in candidates:
                    candidates.append(scene_index)

        infos = []
        for track in hierarchy.get("tracks") or []:
            index = int(track["track_index"])
            if track.get("is_foldable") is not False or index not in representatives:
                continue

            info = None

            for slot_index in representatives[index]:
                path = (
                    "/show-audio/print/clip-info?"
                    f"track_index={index}&slot_index={slot_index}"
                )

                try:
                    candidate = self._request(
                        path,
                        timeout=5.0,
                    )
                except RuntimeError as exc:
                    message = str(exc)

                    if (
                        "HTTP 409 " in message
                        and '"has_clip":false' in message.replace(" ", "")
                    ):
                        continue

                    raise

                if candidate.get("set_generation") != generation:
                    raise RuntimeError(
                        f"Clip playback invalide ou Set changé : piste {index}"
                    )

                if candidate.get("ok") and candidate.get("has_clip") is not False:
                    info = candidate
                    break

                if candidate.get("has_clip") is False:
                    continue

                raise RuntimeError(
                    f"Clip playback invalide ou Set changé : piste {index}"
                )

            if info is not None:
                infos.append(info)
        self.discovered_sources = discover_playback_sources(hierarchy.get("tracks") or [], infos)
        return self.discovered_sources['playback_tracks']

    def scene_clips_bulk(
        self,
        scene_indices: Iterable[int],
    ) -> Dict[str, Any]:
        indices = []

        for value in scene_indices:
            index = int(value)

            if index not in indices:
                indices.append(index)

        if indices:
            encoded = urllib.parse.quote(
                ",".join(str(index) for index in indices),
                safe=",",
            )

            path = (
                "/show-audio/scene-clips-bulk?"
                f"scene_indices={encoded}"
            )
        else:
            path = "/show-audio/scene-clips-bulk"

        data = self._request(
            path,
            timeout=15.0,
        )

        self.scene_clip_seconds += float(
            data.get("_http_seconds") or 0.0
        )

        return data

    def ensure_tracks(
        self,
        indices: Iterable[int],
    ) -> None:
        missing = sorted({
            int(index)
            for index in indices
            if int(index) not in self.track_cache
        })

        if not missing:
            return

        encoded = urllib.parse.quote(
            ",".join(str(index) for index in missing),
            safe=",",
        )

        data = self._request(
            "/show-audio/tracks-bulk?"
            f"track_indices={encoded}",
            timeout=8.0,
        )

        self.track_seconds += float(
            data.get("_http_seconds") or 0.0
        )

        if not data.get("ok"):
            raise RuntimeError(
                f"Snapshot tracks bulk invalide: {data}"
            )

        for track in data.get("tracks") or []:
            try:
                index = int(track["track_index"])
            except (KeyError, TypeError, ValueError):
                continue

            self.track_cache[index] = dict(track)

    def merge_clips(
        self,
        clips: Iterable[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        result = []

        for raw_clip in clips:
            clip = dict(raw_clip)

            try:
                index = int(clip["track_index"])
            except (KeyError, TypeError, ValueError):
                index = -1

            track = self.track_cache.get(index) or {}

            clip["track_on"] = track.get("track_on")
            clip["track_mute"] = track.get("track_mute")

            if not clip.get("track_name"):
                clip["track_name"] = (
                    track.get("track_name") or ""
                )

            clip["playback_track"] = is_playback_track(
                clip.get("track_name", ""),
                self.playback_track_names,
            )

            result.append(clip)

        return result

    def build_scene_from_raw(
        self,
        raw: Dict[str, Any],
    ) -> Dict[str, Any]:
        scene_index = int(raw.get("scene_index", -1))

        clips = list(raw.get("clips") or [])
        merged = self.merge_clips(clips)

        reference = select_reference_playback_clip(
            merged,
            self.playback_track_names,
        )

        audio_reference = select_reference_clip(
            merged,
        )

        playback_on = [
            clip
            for clip in merged
            if clip.get("track_on") is True
            and clip.get("playback_track") is True
            and _format_seconds(
                clip.get("duration_seconds")
            ) is not None
        ]

        unknown = [
            clip
            for clip in merged
            if clip.get("track_on") is None
        ]

        reference_data = None
        audio_reference_data = None

        if reference:
            reference_data = {
                "track_index": reference.get("track_index"),
                "track_name": reference.get("track_name"),
                "clip_name": reference.get("clip_name"),
                "duration_seconds": _format_seconds(
                    reference.get("duration_seconds")
                ),
            }

        if audio_reference:
            audio_reference_data = {
                "track_index": audio_reference.get("track_index"),
                "track_name": audio_reference.get("track_name"),
                "clip_name": audio_reference.get("clip_name"),
                "duration_seconds": _format_seconds(
                    audio_reference.get("duration_seconds")
                ),
            }

        return {
            "scene_index": scene_index,
            "scene_name": raw.get("scene_name") or "",
            "tempo": raw.get("tempo"),
            "ok": True,
            "clip_count": len(merged),
            "unknown_track_state_count": len(unknown),
            "playback_on_count": len(playback_on),
            "reference": reference_data,
            "audio_reference": audio_reference_data,
            "has_exportable_audio": audio_reference_data is not None,
            "clips": merged,
        }

    def build_scene(
        self,
        scene_index: int,
    ) -> Dict[str, Any]:
        """Compatibilité diagnostic : construit encore une scène seule."""
        raw = self.scene_clips(scene_index)

        if not raw.get("ok"):
            return {
                "scene_index": int(scene_index),
                "ok": False,
                "error": raw.get("error") or "scene invalide",
            }

        clips = list(raw.get("clips") or [])

        self.ensure_tracks(
            _track_indices(clips)
        )

        return self.build_scene_from_raw(raw)

    def build(
        self,
        scene_indices: Iterable[int],
    ) -> Dict[str, Any]:
        started = time.monotonic()

        requested_indices = []

        for value in scene_indices:
            index = int(value)

            if index not in requested_indices:
                requested_indices.append(index)

        status = self.status()

        if not status.get("set_ready"):
            raise RuntimeError(
                "Live Set non prêt"
            )

        bulk = self.scene_clips_bulk(
            requested_indices
        )

        if not bulk.get("ok"):
            raise RuntimeError(
                bulk.get("error")
                or "snapshot bulk invalide"
            )

        raw_scenes = list(
            bulk.get("scenes") or []
        )

        snapshot_tempo = _resolve_snapshot_tempo(
            status,
            raw_scenes,
        )

        if bulk.get("set_generation", status.get("set_generation")) != status.get("set_generation"):
            raise RuntimeError("Live Set changé pendant le snapshot")
        self.track_count = int(bulk.get("track_count") or 0)
        automatic = self.config.get("playback_source_mode") == "live" or not (
            self.config.get("playback_tracks") or self.config.get("playback_groups")
        )
        if automatic and raw_scenes:
            self.playback_track_names = self.discover_sources(raw_scenes, status.get("set_generation"))
        else:
            self.playback_track_names = self.resolve_playback_sources()

        all_clips = []

        for raw_scene in raw_scenes:
            all_clips.extend(
                raw_scene.get("clips") or []
            )

        # Un seul snapshot ON/OFF pour toutes les pistes
        # réellement présentes dans les scènes demandées.
        self.ensure_tracks(
            _track_indices(all_clips)
        )

        scenes = [
            self.build_scene_from_raw(raw_scene)
            for raw_scene in raw_scenes
        ]

        elapsed = time.monotonic() - started

        tracks = [
            self.track_cache[index]
            for index in sorted(self.track_cache)
        ]

        return {
            "version": 2,
            "source": "CL_Audio_Controller",
            "read_only": True,
            "acquisition": "bulk",
            "arrangement": {
                "markers": list(status.get("arrangement_markers") or []),
                "markers_source": status.get("arrangement_markers_source") or "",
                "tempo": snapshot_tempo,
                "signature_numerator": status.get("signature_numerator") or 4,
            },
            "set": {
                "name": status.get("current_set_name") or "",
                "generation": status.get("set_generation"),
                "id": status.get("current_set_id"),
                "server_instance_id": status.get("server_instance_id"),
                "ready": bool(status.get("set_ready")),
            },
            "playback_tracks": list(
                self.playback_track_names
            ),
            "discovered_sources": self.discovered_sources,
            "tracks": tracks,
            "scenes": scenes,
            "metrics": {
                "total_seconds": elapsed,
                "http_seconds": self.http_seconds,
                "scene_clip_seconds": self.scene_clip_seconds,
                "track_seconds": self.track_seconds,
                "track_cache_size": len(self.track_cache),
                "scene_count": len(scenes),
            },
        }


def format_duration(value: Any) -> str:
    seconds = _format_seconds(value)

    if seconds is None:
        return "—"

    minutes = int(seconds // 60)
    remainder = seconds - minutes * 60

    return f"{minutes}:{remainder:05.2f}"
