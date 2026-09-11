#!/usr/bin/env python3

"""Résolution des sources playback CL Show Audio.

Supporte :
- pistes playback explicitement déclarées ;
- groupes Ableton déclarés comme zones playback ;
- descendants imbriqués ;
- exclusion des pistes groupe elles-mêmes.

Aucune communication Ableton dans ce module.
"""

from __future__ import annotations

from typing import Any, Dict, Iterable, List, Set


def _text(value: Any) -> str:
    return str(value or "").strip()


def normalize_names(values: Iterable[Any]) -> List[str]:
    result = []
    seen = set()

    for value in values or []:
        name = _text(value)

        if not name:
            continue

        key = name.casefold()

        if key in seen:
            continue

        seen.add(key)
        result.append(name)

    return result


def configured_playback_tracks(
    document: Dict[str, Any],
) -> List[str]:
    return normalize_names(
        document.get("playback_tracks") or []
    )


def configured_playback_groups(
    document: Dict[str, Any],
) -> List[str]:
    return normalize_names(
        document.get("playback_groups") or []
    )


def find_track_exact(
    hierarchy: Iterable[Dict[str, Any]],
    name: str,
) -> Dict[str, Any] | None:
    wanted = _text(name).casefold()

    matches = [
        dict(track)
        for track in hierarchy or []
        if _text(
            track.get("track_name")
        ).casefold() == wanted
    ]

    if len(matches) != 1:
        return None

    return matches[0]


def group_descendants(
    hierarchy: Iterable[Dict[str, Any]],
    group_name: str,
) -> List[Dict[str, Any]]:
    """Retourne les descendants contigus d'un groupe Ableton.

    Dans la liste Live :
    - le groupe parent est foldable=True ;
    - les descendants qui suivent ont is_grouped=True ;
    - le premier track is_grouped=False ferme la zone du groupe.

    Les groupes imbriqués sont conservés dans la liste brute.
    """

    tracks = sorted(
        (
            dict(track)
            for track in hierarchy or []
            if track.get("track_index") is not None
        ),
        key=lambda track: int(
            track["track_index"]
        ),
    )

    parent = find_track_exact(
        tracks,
        group_name,
    )

    if parent is None:
        return []

    if parent.get("is_foldable") is not True:
        return []

    parent_index = int(
        parent["track_index"]
    )

    descendants = []

    for track in tracks:
        index = int(
            track["track_index"]
        )

        if index <= parent_index:
            continue

        if track.get("is_grouped") is not True:
            break

        descendants.append(track)

    return descendants


def group_playback_leaf_tracks(
    hierarchy: Iterable[Dict[str, Any]],
    group_name: str,
) -> List[Dict[str, Any]]:
    """Descendants réellement candidats au playback.

    Une piste foldable est un groupe/sous-groupe, pas le fichier audio.
    On ne conserve donc que les descendants non foldable.
    """

    return [
        track
        for track in group_descendants(
            hierarchy,
            group_name,
        )
        if track.get("is_foldable") is not True
    ]


def resolve_playback_track_names(
    document: Dict[str, Any],
    hierarchy: Iterable[Dict[str, Any]],
) -> List[str]:
    names: List[str] = []
    seen: Set[str] = set()

    def add(name: Any) -> None:
        value = _text(name)

        if not value:
            return

        key = value.casefold()

        if key in seen:
            return

        seen.add(key)
        names.append(value)

    for name in configured_playback_tracks(
        document
    ):
        add(name)

    for group_name in configured_playback_groups(
        document
    ):
        for track in group_playback_leaf_tracks(
            hierarchy,
            group_name,
        ):
            add(
                track.get("track_name")
            )

    return names


def discover_playback_sources(hierarchy: Iterable[Dict[str, Any]],
                              clip_infos: Iterable[Dict[str, Any]]) -> Dict[str, Any]:
    """Sources du Set réel, confirmées par un fichier audio via HTTP.

    Aucun nom d'artiste/groupe n'est imposé. L'état mute n'intervient pas
    dans l'inventaire des variantes disponibles, seulement dans la référence.
    """
    from show_audio_plan import is_technical_track

    tracks = list(hierarchy)
    audio_indices = {
        int(info['track_index']) for info in clip_infos
        if info.get('ok') and info.get('has_clip') and info.get('file_path')
    }
    names = normalize_names(
        track.get('track_name') for track in tracks
        if track.get('is_foldable') is False
        and int(track['track_index']) in audio_indices
        and not is_technical_track(track.get('track_name'))
    )
    allowed = {name.casefold() for name in names}
    groups = []
    for track in tracks:
        if track.get('is_foldable') is not True or track.get('is_grouped') is not False:
            continue
        leaves = group_playback_leaf_tracks(tracks, track.get('track_name'))
        # Ne pas autoriser implicitement les feuilles MIDI d'un groupe mixte.
        if leaves and all(_text(leaf.get('track_name')).casefold() in allowed for leaf in leaves):
            groups.append(track['track_name'])
    config = {'playback_tracks': names, 'playback_groups': groups}
    config['playback_tracks'] = resolve_playback_track_names(config, tracks)
    return config
