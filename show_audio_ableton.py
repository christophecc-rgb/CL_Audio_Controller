"""Adaptateur AbletonOSC en lecture seule pour CL Show Audio Builder."""

from __future__ import annotations

from typing import Any, Callable


QueryFunction = Callable[..., Any]


def _text(value: Any) -> str:
    return str(value or "").strip()


def _positive_float(value: Any) -> float | None:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None

    if result < 0:
        return None

    return result


def normalize_names(response: Any) -> list[str]:
    if response is None:
        return []

    if isinstance(response, str):
        return [_text(response)]

    try:
        values = list(response)
    except TypeError:
        return []

    return [_text(value) for value in values]


def beats_to_seconds(
    length_beats: Any,
    tempo: Any,
) -> float | None:
    beats = _positive_float(length_beats)
    bpm = _positive_float(tempo)

    if beats is None or bpm is None or bpm <= 0:
        return None

    return beats * 60.0 / bpm


class ShowAudioAbletonAdapter:
    """Vue read-only du Live Set courant."""

    def __init__(self, query: QueryFunction):
        if not callable(query):
            raise TypeError("query doit être callable")

        self.query = query

    def get_scene_names(self) -> list[str]:
        response = self.query(
            "/live/song/get/scenes/name",
            apply_response=False,
        )
        return normalize_names(response)

    def get_track_names(self) -> list[str]:
        response = self.query(
            "/live/song/get/track_names",
            apply_response=False,
        )
        return normalize_names(response)

    def get_tempo(self) -> float | None:
        response = self.query(
            "/live/song/get/tempo",
            apply_response=False,
        )

        if not response:
            return None

        try:
            value = list(response)[-1]
        except (TypeError, IndexError):
            return None

        tempo = _positive_float(value)

        if tempo is None or tempo <= 0:
            return None

        return tempo

    def get_clip_length_beats(
        self,
        track_index: int,
        scene_index: int,
    ) -> float | None:
        response = self.query(
            "/live/clip/get/length",
            int(track_index),
            int(scene_index),
            apply_response=False,
        )

        if not response:
            return None

        try:
            value = list(response)[-1]
        except (TypeError, IndexError):
            return None

        return _positive_float(value)

    def get_clip_duration_seconds(
        self,
        track_index: int,
        scene_index: int,
        *,
        tempo: float | None = None,
    ) -> float | None:
        beats = self.get_clip_length_beats(
            track_index,
            scene_index,
        )

        if beats is None:
            return None

        if tempo is None:
            tempo = self.get_tempo()

        return beats_to_seconds(beats, tempo)

    def list_scenes(self) -> list[dict]:
        return [
            {
                "scene_index": index,
                "scene_number": index + 1,
                "scene_name": name,
            }
            for index, name in enumerate(
                self.get_scene_names()
            )
        ]

    def list_tracks(self) -> list[dict]:
        return [
            {
                "track_index": index,
                "track_number": index + 1,
                "track_name": name,
            }
            for index, name in enumerate(
                self.get_track_names()
            )
        ]

    def find_scene_by_index(
        self,
        scene_index: int,
    ) -> dict | None:
        wanted = int(scene_index)

        for scene in self.list_scenes():
            if scene["scene_index"] == wanted:
                return dict(scene)

        return None

    def find_scene_by_name(
        self,
        scene_name: str,
    ) -> dict | None:
        wanted = _text(scene_name).casefold()

        if not wanted:
            return None

        matches = [
            scene
            for scene in self.list_scenes()
            if scene["scene_name"].casefold() == wanted
        ]

        if len(matches) != 1:
            return None

        return dict(matches[0])

    def match_variant(self, variant: dict) -> dict:
        requested_index = variant.get("scene_index")
        requested_name = _text(
            variant.get("scene_name")
        )

        if requested_index is not None:
            scene = self.find_scene_by_index(
                int(requested_index)
            )

            if scene is None:
                return {
                    "status": "missing",
                    "matched_by": "scene_index",
                    "scene": None,
                }

            if (
                requested_name
                and scene["scene_name"].casefold()
                != requested_name.casefold()
            ):
                return {
                    "status": "mismatch",
                    "matched_by": "scene_index",
                    "scene": scene,
                    "expected_scene_name": requested_name,
                }

            return {
                "status": "matched",
                "matched_by": "scene_index",
                "scene": scene,
            }

        if requested_name:
            scene = self.find_scene_by_name(
                requested_name
            )

            if scene is not None:
                return {
                    "status": "matched",
                    "matched_by": "scene_name",
                    "scene": scene,
                }

        return {
            "status": "missing",
            "matched_by": (
                "scene_name"
                if requested_name
                else None
            ),
            "scene": None,
        }
