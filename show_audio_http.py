"""Source HTTP read-only pour CL Show Audio Builder.

Réutilise l'état déjà publié par CL Audio Controller sur /status.
Aucun accès direct à AbletonOSC.
Aucun listener UDP supplémentaire.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from typing import Any


DEFAULT_STATUS_URL = "http://127.0.0.1:5050/status"
DEFAULT_TIMEOUT = 1.0


def _scene_names_from_status(status: dict) -> list[str]:
    raw = status.get("scenes") or {}

    if isinstance(raw, list):
        return [str(value or "") for value in raw]

    if not isinstance(raw, dict):
        return []

    indexed = []

    for key, value in raw.items():
        try:
            index = int(key)
        except (TypeError, ValueError):
            continue

        indexed.append((index, str(value or "")))

    if not indexed:
        return []

    max_index = max(index for index, _ in indexed)
    names = [""] * (max_index + 1)

    for index, name in indexed:
        if index >= 0:
            names[index] = name

    return names


class ShowAudioHTTPStatusSource:
    """Expose /status avec l'interface query attendue par l'adaptateur."""

    def __init__(
        self,
        url: str = DEFAULT_STATUS_URL,
        *,
        timeout: float = DEFAULT_TIMEOUT,
    ):
        self.url = str(url)
        self.timeout = float(timeout)
        self.last_status: dict = {}

    def fetch_status(self) -> dict:
        request = urllib.request.Request(
            self.url,
            method="GET",
            headers={"Accept": "application/json"},
        )

        try:
            with urllib.request.urlopen(
                request,
                timeout=self.timeout,
            ) as response:
                raw = response.read()

        except urllib.error.URLError as exc:
            raise RuntimeError(
                f"CL Audio Controller inaccessible : {exc}"
            ) from exc

        try:
            status = json.loads(
                raw.decode("utf-8")
            )
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise RuntimeError(
                "Réponse /status invalide"
            ) from exc

        if not isinstance(status, dict):
            raise RuntimeError(
                "Réponse /status inattendue"
            )

        self.last_status = status
        return status

    def query(
        self,
        address: str,
        *args: Any,
        apply_response: bool = False,
        **_ignored: Any,
    ):
        status = self.fetch_status()

        if address == "/live/song/get/scenes/name":
            return tuple(
                _scene_names_from_status(status)
            )

        if address == "/live/song/get/track_names":
            raw = status.get("track_names")

            if isinstance(raw, list):
                return tuple(
                    str(value or "")
                    for value in raw
                )

            return tuple()

        if address == "/live/song/get/tempo":
            value = status.get("tempo")

            if value is None:
                return tuple()

            return (value,)

        if address == "/live/clip/get/length":
            # /status ne publie pas encore de longueurs arbitraires
            # par piste/scène.
            return tuple()

        raise RuntimeError(
            f"requête non supportée par /status : {address}"
        )

    def identity(self) -> dict:
        status = self.last_status or self.fetch_status()

        return {
            "connected": bool(status.get("connected")),
            "set_ready": bool(status.get("set_ready")),
            "set_generation": status.get("set_generation"),
            "set_id": status.get("current_set_id"),
            "set_name": status.get("current_set_name"),
            "selected_scene": status.get("selected_scene"),
            "playing_scene": status.get("playing_scene"),
            "playing_scene_name": status.get("playing_scene_name"),
            "server_process_id": status.get("server_process_id"),
            "service": status.get("service"),
        }
