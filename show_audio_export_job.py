"""Planification pure d'un Export Job CL Show Audio, sans opération audio."""

from __future__ import annotations

import re
from collections import Counter
from typing import Any

from show_audio_export_settings import normalize_export_settings


def _selected_item(item: dict, settings: dict) -> bool:
    item_type = str(item.get("type") or "")
    if item_type in {"scene", "medley_part"}:
        return settings["export_scenes"]
    if item_type == "medley_full":
        return settings["export_medleys"]
    return False


def _format_label(specification: dict) -> str:
    if specification["format"] == "mp3":
        return f"mp3_{specification['bitrate_kbps']}k"
    return f"{specification['format']}_{specification['bit_depth']}"


def _output_title(item: dict) -> str:
    title = str(item.get("title") or item.get("filename_stem") or item.get("id") or "Export").strip()
    if item.get("type") == "medley_full":
        title = re.sub(r"^medd?ley\b[\s-]*(?:\d+-\d+\s*-\s*)?", "", title, flags=re.I)
        title = "Medley " + title
    elif not item.get("title"):
        title = re.sub(r"^\d+\s*-\s*", "", title)
    title = re.sub(r'[\\/:*?"<>|]+', " - ", title)
    return re.sub(r"\s+", " ", title).strip(" .") or "Export"


def build_export_job(plan: dict, settings: dict) -> dict:
    if not isinstance(plan, dict) or not isinstance(plan.get("items"), list):
        raise ValueError("plan d’export invalide")
    normalized = normalize_export_settings(settings)
    profile_state = {
        "clean": "ready",
        "mastered": "requires_master_bus_validation",
        "direct": "requires_item_compatibility_validation",
    }[normalized["audio_profile"]]
    selected = [dict(item) for item in plan["items"]
                if item.get("status") == "ready" and _selected_item(item, normalized)]

    job_items = []
    width = max(2, len(str(len(selected))))
    format_counts = Counter(spec["format"] for spec in normalized["formats"])
    for index, item in enumerate(selected, 1):
        stem = _output_title(item)
        if len(selected) > 1:
            stem = f"{index:0{width}d} - {stem}"
        outputs = []
        for specification in normalized["formats"]:
            label = _format_label(specification)
            # Distinguer uniquement les variantes partageant la même extension.
            suffix = f" [{label}]" if format_counts[specification["format"]] > 1 else ""
            outputs.append({"kind": "final", "format": specification["format"],
                            "settings": dict(specification),
                            "output_id": f"{item.get('id')}::{label}",
                            "filename": f"{stem}{suffix}.{specification['format']}"})
        job_items.append({
            "id": item.get("id"), "type": item.get("type"), "source_item": item,
            "audio_profile": normalized["audio_profile"],
            "audio_profile_state": profile_state,
            "capture": {"kind": "master_intermediate", "format": "wav",
                        "sample_rate": normalized["sample_rate"],
                        "retained": normalized["keep_master_wav"]},
            "outputs": outputs,
        })

    final_count = sum(len(item["outputs"]) for item in job_items)
    return {
        "version": 1, "status": "planned", "settings": normalized,
        "audio_profile_state": profile_state, "fallback_profile": None,
        "items": job_items,
        "metrics": {
            "selected_item_count": len(job_items),
            "capture_count": len(job_items),
            "final_output_count": final_count,
            "retained_master_count": len(job_items) if normalized["keep_master_wav"] else 0,
        },
    }
