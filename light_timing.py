from __future__ import annotations

import re
import unicodedata


def _norm(value):
    text = unicodedata.normalize("NFKD", str(value or ""))
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    return re.sub(r"\s+", " ", text).strip().upper()


def _technical(name):
    """
    Pistes qui ne doivent jamais devenir une référence de durée Light.
    """
    n = _norm(name)
    forbidden = (
        "LTC",
        "VIDEO",
        "LIGHT",
        "PGM CHANGE",
        "PROGRAM CHANGE",
        "CC TO",
        "TOP INFOS",
        "TOP INFO",
        "SYNC MTC",
        "MTC STOP",
        "CL5",
        "QL1",
    )
    return any(token in n for token in forbidden)


def reference_candidates(layout):
    """
    Construit les références de timing possibles à partir de la structure
    statique des pistes.

    Priorité :
      1. piste TABLEAU / TABLEAUX
      2. pistes audio appartenant à une branche de SAISON 8

    Retour :
      [
        {
          "track": <index piste feuille>,
          "required_unmuted": (<index groupe>, ...),
          "kind": "tableaux" | "saison8",
        },
        ...
      ]
    """

    candidates = []

    # 1 — TABLEAU / TABLEAUX
    for row in layout:
        name = _norm(row.get("name"))
        if (
            "TABLEAU" in name
            and not row.get("foldable")
            and not _technical(row.get("name"))
        ):
            candidates.append(
                {
                    "track": int(row["index"]),
                    "required_unmuted": (),
                    "kind": "tableaux",
                }
            )

    # 2 — groupe racine SAISON 8
    root_pos = None
    root_index = None

    for pos, row in enumerate(layout):
        if (
            row.get("foldable")
            and "SAISON 8" in _norm(row.get("name"))
        ):
            root_pos = pos
            root_index = int(row["index"])
            break

    if root_pos is None:
        return candidates

    # La zone SAISON 8 se termine à la prochaine piste top-level.
    zone = []
    for row in layout[root_pos + 1:]:
        if not row.get("grouped"):
            break
        zone.append(row)

    # Dans SAISON 8, les sous-groupes comme JMD/JCD/... ouvrent
    # chacun une branche. Une piste feuille hérite du mute de sa branche.
    branch_group = None

    for row in zone:
        index = int(row["index"])

        if row.get("foldable"):
            branch_group = index
            continue

        if branch_group is None:
            continue

        if _technical(row.get("name")):
            continue

        candidates.append(
            {
                "track": index,
                "required_unmuted": (root_index, branch_group),
                "kind": "saison8",
            }
        )

    return candidates


def timing_from_clip(
    *,
    is_audio_clip,
    warping,
    looping,
    start_marker,
    end_marker,
    playing_position,
):
    """
    Timing fiable retenu pour LOCAL_LIGHT V1.

    Pour un clip audio NON WARP et NON LOOP :
      - start_marker / end_marker sont utilisés comme référence temporelle ;
      - playing_position donne la position courante correspondante.

    Les clips MIDI, warpés ou bouclés ne sont volontairement pas utilisés :
    mieux vaut afficher — qu'une durée trompeuse.
    """

    if not bool(is_audio_clip):
        return None

    if bool(warping) or bool(looping):
        return None

    try:
        start = float(start_marker)
        end = float(end_marker)
        playing = float(playing_position)
    except (TypeError, ValueError):
        return None

    duration = end - start
    if duration <= 0:
        return None

    position = max(0.0, min(duration, playing - start))
    remaining = max(0.0, duration - position)

    return duration, position, remaining
