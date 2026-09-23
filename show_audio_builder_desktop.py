#!/usr/bin/env python3

"""CL Audio Export Desktop V1.

Interface locale uniquement.

Fonctions V1 :
- snapshot bulk du Set Ableton via CL Audio Controller ;
- affichage des scènes et de leur durée playback réelle ;
- filtrage exportables / toutes les scènes ;
- affichage du playback actuellement ON ;
- édition d'une variante métier :
      rôle + artiste + tonalité + playback ;
- la variante reste attachée au couple rôle/artiste ;
- sauvegarde atomique dans show_audio.json ;
- aucune commande de transport envoyée à Ableton.
"""

from __future__ import annotations

import json
import queue
import threading
import time
import traceback
import uuid
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk
from typing import Any, Dict, List, Optional

from show_audio_builder import (
    load_show_audio_document,
    normalize_show_audio_document,
    save_show_audio_document,
)
from show_audio_model import build_show_audio_model
from show_audio_medleys import build_medleys, normalize_medley, validate_medley
from show_audio_export_job import build_export_job
from show_audio_arrangement_resolver import (
    normalize_arrangement_title,
    resolve_scene_zone,
    resolve_medley_zone,
)
from show_audio_batch_export import execute_batch_item
from show_audio_export_plan import build_export_plan
from show_audio_export_settings import normalize_export_settings
from show_audio_snapshot import ShowAudioSnapshotBuilder


from show_audio_runtime import configuration_path

CONFIG_PATH = configuration_path()


def export_identity(status):
    """L'identité inclut le serveur : une génération peut repartir de zéro."""
    values = (status.get("server_instance_id"), status.get("current_set_id"),
              status.get("set_generation"), status.get("current_set_name"))
    return values if status.get("set_ready") and all(v is not None and v != "" for v in values) else None


def scroll_units(event, windowing_system):
    if getattr(event, "num", None) in (4, 5):
        return -1 if event.num == 4 else 1
    delta = getattr(event, "delta", 0)
    if not delta:
        return 0
    magnitude = abs(delta) if windowing_system == "aqua" else abs(delta) / 120
    return (-1 if delta > 0 else 1) * min(3, max(1, round(magnitude)))


def format_duration(value: Any) -> str:
    try:
        seconds = float(value)
    except (TypeError, ValueError):
        return "—"

    if seconds <= 0:
        return "—"

    minutes = int(seconds // 60)
    remainder = seconds - minutes * 60

    return f"{minutes}:{remainder:05.2f}"


def status_label(item: Dict[str, Any]) -> str:
    status = str(item.get("status") or "")

    if status == "ready":
        return "PRÊT"
    if status == "multiple_playbacks":
        return "MULTIPLE"
    if status == "no_playback":
        return "SANS PLAYBACK"

    return status.upper() or "—"


def find_scene_variant(
    variants: List[Dict[str, Any]],
    scene_index: int,
) -> Optional[Dict[str, Any]]:
    matches = []

    for variant in variants:
        try:
            index = int(variant.get("scene_index"))
        except (TypeError, ValueError):
            continue

        if index == int(scene_index):
            matches.append(variant)

    if len(matches) == 1:
        return matches[0]

    return None


def medley_groups_for_builder(
    document: Dict[str, Any],
    snapshot: Dict[str, Any],
) -> Dict[int, Dict[str, Any]]:
    """Indexe l'affichage des medleys depuis le modèle métier existant."""
    result: Dict[int, Dict[str, Any]] = {}

    for medley in build_medleys(document, snapshot):
        parts = []

        for part in medley.get("parts") or []:
            try:
                scene_index = int(part.get("scene_index"))
                scene_number = int(part.get("scene_number"))
            except (TypeError, ValueError):
                continue

            title = str(part.get("scene_name") or "").split(";", 1)[0].strip()
            parts.append({
                "scene_index": scene_index,
                "scene_number": scene_number,
                "title": title,
            })

        group = {
            "id": str(medley.get("id") or "").strip(),
            "title": str(medley.get("title") or "MEDLEY").strip(),
            "parts": parts,
        }

        for part in parts:
            result[part["scene_index"]] = group

    return result


def upsert_medley_from_scenes(document, model, *, title, scene_indices, medley_id=None):
    """Enregistre des titres choisis, avec des numéros LIVE explicites.

    La numérotation SHOW n'est pas réinterprétée par le moteur d'export.
    Les anciens medleys sans marqueur conservent leur résolution UI.
    """
    title = str(title or "").strip()
    if not title:
        raise ValueError("Donne un nom au medley.")
    selected = sorted({int(index) for index in scene_indices})
    items = {int(item['scene_index']): item for item in model.get('items') or []}
    if any(index not in items for index in selected):
        raise ValueError("Une scène sélectionnée n'existe plus dans le Set. Recharge le Set.")
    updated = normalize_show_audio_document(document)
    medleys = updated.setdefault('medleys', [])
    existing = next((m for m in medleys if m.get('id') == medley_id), None)
    if medley_id and existing is None:
        raise ValueError("Ce medley n'existe plus. Rouvre l'éditeur.")
    candidate = {
        **(existing or {}),
        'id': medley_id or 'medley_' + uuid.uuid4().hex[:12],
        'title': title, 'scene_numbers': [index + 1 for index in selected],
        'numbering': 'live',
    }
    errors = validate_medley(normalize_medley(candidate))
    if 'not_enough_scenes' in errors:
        raise ValueError("Sélectionne au moins deux titres.")
    if 'non_contiguous_scenes' in errors:
        raise ValueError("Les titres doivent être consécutifs dans le Set pour un medley complet.")
    if errors:
        raise ValueError("Medley invalide : " + ', '.join(errors))
    numbers = set(candidate['scene_numbers'])
    for medley in medleys:
        if medley.get('id') != medley_id and numbers.intersection(int(n) for n in medley.get('scene_numbers') or []):
            raise ValueError(f"Un titre appartient déjà au medley « {medley.get('title')} ».")
    if existing is None:
        medleys.append(candidate)
    else:
        medleys[medleys.index(existing)] = candidate
    updated['revision'] += 1
    return updated


def upsert_scene_variant(
    document: Dict[str, Any],
    *,
    scene_index: int,
    scene_name: str,
    number: str,
    title: str,
    role: str,
    artist: str,
    key: str,
    playback: str,
) -> Dict[str, Any]:
    normalized = normalize_show_audio_document(document)

    variants = [
        dict(value)
        for value in normalized.get("variants") or []
    ]

    role = str(role or "").strip()
    artist = str(artist or "").strip()
    key = str(key or "").strip()
    playback = str(playback or "").strip()

    if not role:
        raise ValueError("Le rôle est obligatoire.")

    if not artist:
        raise ValueError("L'artiste / nom est obligatoire.")

    if not playback:
        raise ValueError("Le playback est obligatoire.")

    replacement = None

    # Règle métier :
    # une variante est identifiée dans la scène par rôle + artiste.
    for index, variant in enumerate(variants):
        try:
            same_scene = (
                int(variant.get("scene_index"))
                == int(scene_index)
            )
        except (TypeError, ValueError):
            same_scene = False

        if not same_scene:
            continue

        if (
            str(variant.get("role") or "").strip().casefold()
            == role.casefold()
            and
            str(variant.get("artist") or "").strip().casefold()
            == artist.casefold()
        ):
            replacement = index
            break

    variant_id = (
        f"scene_{int(scene_index):03d}_"
        f"{role.casefold().replace(' ', '_')}_"
        f"{artist.casefold().replace(' ', '_')}"
    )

    value = {
        "id": variant_id,
        "number": str(number or "").strip(),
        "title": str(title or "").strip(),
        "role": role,
        "artist": artist,
        "key": key,
        "playback": playback,
        "scene_index": int(scene_index),
        "scene_name": str(scene_name or "").strip(),
        "export": True,
        "notes": "",
    }

    if replacement is None:
        variants.append(value)
    else:
        variants[replacement] = value

    normalized["variants"] = variants
    normalized["revision"] = int(
        normalized.get("revision") or 0
    ) + 1

    return normalize_show_audio_document(normalized)


class ShowAudioBuilderDesktop(tk.Tk):
    def __init__(self) -> None:
        super().__init__()

        self.title("CL Audio Export")
        self.geometry("1180x780")
        self.minsize(980, 680)

        self.snapshot: Dict[str, Any] = {}
        self.model: Dict[str, Any] = {}
        self.document: Dict[str, Any] = (
            load_show_audio_document(CONFIG_PATH)
            if CONFIG_PATH.exists()
            else normalize_show_audio_document({})
        )

        self.current_item: Optional[Dict[str, Any]] = None

        # Sélection finale d'export, indépendante du filtre d'affichage.
        # Clé stable : scene_index Ableton.
        self.export_selected_scene_indices: set[int] = set()
        self.export_selected_medley_ids: set[str] = set()
        self.export_selection_initialized = False
        self.export_selection_summary_var = tk.StringVar(
            value="0 scène sélectionnée"
        )

        self.show_all_var = tk.BooleanVar(value=True)

        self.role_var = tk.StringVar()
        self.artist_var = tk.StringVar()
        self.key_var = tk.StringVar()
        self.playback_var = tk.StringVar()
        self.variant_summary_var = tk.StringVar(
            value="Aucune variante enregistrée pour cette scène."
        )

        self.role_combo = None
        self.artist_combo = None
        self.key_combo = None
        self.playback_combo = None

        self.scene_title_var = tk.StringVar(value="—")
        self.scene_status_var = tk.StringVar(value="—")
        self.scene_duration_var = tk.StringVar(value="—")
        self.scene_track_var = tk.StringVar(value="—")
        self.scene_clip_var = tk.StringVar(value="—")
        self.info_var = tk.StringVar(value="Prêt.")

        self.export_profile_var = tk.StringVar(value="clean")
        self.export_sample_rate_var = tk.StringVar(value="48000")
        self.export_normalize_var = tk.BooleanVar(value=False)
        self.export_scenes_var = tk.BooleanVar(value=True)
        self.export_medleys_var = tk.BooleanVar(value=True)
        self.export_keep_master_var = tk.BooleanVar(value=False)
        self.export_format_vars = {
            "mp3": tk.BooleanVar(value=True), "wav": tk.BooleanVar(value=False),
            "aiff": tk.BooleanVar(value=False), "flac": tk.BooleanVar(value=False),
        }
        self.export_quality_vars = {
            "mp3": tk.StringVar(value="320"), "wav": tk.StringVar(value="24"),
            "aiff": tk.StringVar(value="24"), "flac": tk.StringVar(value="24"),
        }

        self.export_workflow_state = "IDLE"
        self.prepared_export_job = None
        self.export_preparation_valid = False
        self.export_state_var = tk.StringVar(value="À préparer")
        self.export_counter_var = tk.StringVar(value="0 / 0")
        self.scene_export_summary_var = tk.StringVar(value="Aucune scène sélectionnée")
        self._loading = False
        self._load_results = queue.Queue()
        self._load_progress = queue.Queue()
        self._scene_export_results = queue.Queue()
        self._build_ui()
        self.after(150, self.refresh_from_live)

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=12)
        root.pack(fill="both", expand=True)

        toolbar = ttk.Frame(root)
        toolbar.pack(fill="x", pady=(0, 10))

        self.reload_button = ttk.Button(
            toolbar,
            text="RECHARGER LE SET",
            command=self.refresh_from_live,
        )
        self.reload_button.pack(side="left")

        ttk.Checkbutton(
            toolbar,
            text="Afficher aussi les scènes sans playback",
            variable=self.show_all_var,
            command=self.populate_tree,
        ).pack(side="left", padx=18)

        selection_bar = ttk.Frame(root)
        selection_bar.pack(fill="x", pady=(0, 6))
        ttk.Label(selection_bar, text="Sélection").pack(side="left", padx=(0, 8))

        ttk.Button(
            selection_bar,
            text="TOUT COCHER",
            command=self.select_all_exportable_scenes,
        ).pack(side="left", padx=(4, 0))

        ttk.Button(
            selection_bar,
            text="TOUT DÉCOCHER",
            command=self.clear_export_selection,
        ).pack(side="left", padx=(4, 0))

        ttk.Button(
            selection_bar,
            text="COCHER LES VISIBLES",
            command=self.select_visible_scenes,
        ).pack(side="left", padx=(4, 0))

        export_bar = ttk.Frame(root)
        export_bar.pack(fill="x", pady=(0, 6))
        ttk.Label(export_bar, text="Export").pack(side="left", padx=(0, 8))
        self.prepare_export_button = ttk.Button(
            export_bar, text="PRÉPARER", command=self.prepare_export_ui,
        )
        self.prepare_export_button.pack(side="left", padx=(12, 0))
        self.launch_export_button = ttk.Button(
            export_bar,
            text="EXPORTER LA SÉLECTION",
            state="disabled",
            command=self.request_export_selection_ui,
        )
        self.launch_export_button.pack(side="left", padx=(4, 0))

        ttk.Label(
            selection_bar,
            textvariable=self.export_selection_summary_var,
        ).pack(side="left", padx=(12, 0))

        # Ligne dédiée : la progression reste visible même lorsque la barre
        # de boutons occupe toute la largeur de la fenêtre.
        status_bar = ttk.Frame(root)
        status_bar.pack(fill="x", pady=(0, 8))
        ttk.Label(status_bar, textvariable=self.info_var, anchor="w").pack(side="left", fill="x", expand=True)
        self.medley_button = ttk.Button(status_bar, text="GÉRER LES MEDLEYS", command=self.open_medley_editor)
        self.medley_button.pack(side="right")

        pane = ttk.Panedwindow(
            root,
            orient="horizontal",
        )
        pane.pack(fill="both", expand=True)

        left = ttk.Frame(pane, padding=(0, 0, 8, 0))
        notebook = ttk.Notebook(pane)
        right = ttk.Frame(notebook, padding=8)
        export_tab = ttk.Frame(notebook, padding=8)
        notebook.add(right, text="Scène / variantes")
        notebook.add(export_tab, text="Réglages export")

        pane.add(left, weight=3)
        pane.add(notebook, weight=2)

        progress = ttk.Frame(left)
        progress.pack(fill="x", pady=(0, 8))
        ttk.Label(progress, textvariable=self.export_state_var).pack(anchor="w")
        self.export_progress = ttk.Progressbar(progress, mode="determinate", maximum=1, value=0)
        self.export_progress.pack(side="left", fill="x", expand=True)
        ttk.Label(progress, textvariable=self.export_counter_var).pack(side="left", padx=8)
        self.cancel_export_button = ttk.Button(
            progress, text="ANNULER", state="disabled", command=self.request_cancel_export_ui,
        )
        self.cancel_export_button.pack(side="right")

        columns = (
            "export",
            "idx",
            "show",
            "title",
            "duration",
            "playback",
            "status",
            "variants",
        )

        table = ttk.Frame(left)
        table.pack(fill="both", expand=True)
        table.rowconfigure(0, weight=1)
        table.columnconfigure(0, weight=1)
        self.tree = ttk.Treeview(
            table,
            columns=columns,
            show="headings",
            selectmode="extended",
        )

        # Ligne d'en-tête dédiée aux medleys.
        # Purement visuel : aucune donnée métier n'est modifiée.
        ttk.Style(self).configure("ShowAudio.Treeview", rowheight=26)
        self.tree.configure(style="ShowAudio.Treeview")
        self.tree.tag_configure(
            "medley_header",
            font=("", 10, "bold"),
        )

        headers = {
            "export": "PROD.",
            "idx": "#",
            "show": "N° SHOW",
            "title": "TITRE",
            "duration": "DURÉE",
            "playback": "PLAYBACK ON",
            "status": "ÉTAT",
            "variants": "VAR.",
        }

        widths = {
            "export": 55,
            "idx": 40,
            "show": 65,
            "title": 210,
            "duration": 65,
            "playback": 125,
            "status": 90,
            "variants": 40,
        }

        for column in columns:
            self.tree.heading(
                column,
                text=headers[column],
            )
            self.tree.column(
                column,
                width=widths[column],
                minwidth=40,
                stretch=column in ("title", "playback"),
            )

        scroll = ttk.Scrollbar(table, orient="vertical", command=self.tree.yview)
        horizontal = ttk.Scrollbar(table, orient="horizontal", command=self.tree.xview)
        self.tree.configure(yscrollcommand=scroll.set, xscrollcommand=horizontal.set)
        self.tree.grid(row=0, column=0, sticky="nsew")
        scroll.grid(row=0, column=1, sticky="ns")
        horizontal.grid(row=1, column=0, sticky="ew")
        for binding in ("<MouseWheel>", "<Shift-MouseWheel>", "<Button-4>", "<Button-5>"):
            self.tree.bind(binding, self._scroll_tree)

        self.tree.bind(
            "<<TreeviewSelect>>",
            self.on_scene_selected,
        )

        self.tree.bind(
            "<Button-1>",
            self.on_export_column_click,
            add="+",
        )

        # Menu contextuel :
        # - Button-2 couvre notamment le clic secondaire macOS/Tk ;
        # - Button-3 couvre les autres configurations usuelles.
        self.tree.bind(
            "<Button-2>",
            self.on_export_context_menu,
            add="+",
        )
        self.tree.bind(
            "<Button-3>",
            self.on_export_context_menu,
            add="+",
        )

        self.export_context_menu = tk.Menu(
            self,
            tearoff=False,
        )
        self.export_context_menu.add_command(
            label="Cocher pour export",
            command=self.check_selected_scenes_for_export,
        )
        self.export_context_menu.add_command(
            label="Décocher pour export",
            command=self.uncheck_selected_scenes_for_export,
        )

        ttk.Label(
            right,
            text="SCÈNE",
            font=("", 11, "bold"),
        ).pack(anchor="w")

        ttk.Label(
            right,
            textvariable=self.scene_title_var,
            font=("", 14, "bold"),
            wraplength=330,
        ).pack(anchor="w", pady=(4, 12))

        details = ttk.Frame(right)
        details.pack(fill="x")

        self._detail_row(
            details,
            "État",
            self.scene_status_var,
            0,
        )
        self._detail_row(
            details,
            "Durée réelle",
            self.scene_duration_var,
            1,
        )
        self._detail_row(
            details,
            "Piste playback",
            self.scene_track_var,
            2,
        )
        self._detail_row(
            details,
            "Clip",
            self.scene_clip_var,
            3,
        )

        ttk.Separator(
            right,
            orient="horizontal",
        ).pack(fill="x", pady=8)

        ttk.Label(
            right,
            text="VARIANTE RÔLE / ARTISTE",
            font=("", 11, "bold"),
        ).pack(anchor="w", pady=(0, 10))

        form = ttk.Frame(right)
        form.pack(fill="x")

        self.role_combo = self._combo_row(
            form,
            "Rôle",
            self.role_var,
            0,
        )
        self.artist_combo = self._combo_row(
            form,
            "Artiste / nom",
            self.artist_var,
            1,
        )
        self.key_combo = self._combo_row(
            form,
            "Tonalité",
            self.key_var,
            2,
        )
        self.playback_combo = self._combo_row(
            form,
            "Playback",
            self.playback_var,
            3,
        )

        self.role_combo.bind(
            "<<ComboboxSelected>>",
            self._variant_identity_changed,
        )
        self.artist_combo.bind(
            "<<ComboboxSelected>>",
            self._variant_identity_changed,
        )
        self.role_combo.bind(
            "<FocusOut>",
            self._variant_identity_changed,
        )
        self.artist_combo.bind(
            "<FocusOut>",
            self._variant_identity_changed,
        )

        ttk.Label(
            form,
            textvariable=self.variant_summary_var,
            justify="left",
            wraplength=330,
        ).grid(
            row=4,
            column=0,
            columnspan=2,
            sticky="ew",
            pady=(10, 4),
        )

        actions = ttk.Frame(right)
        actions.pack(
            fill="x",
            pady=(16, 8),
        )

        ttk.Button(
            actions,
            text="ENREGISTRER",
            command=self.save_variant,
        ).pack(side="left")

        ttk.Button(
            actions,
            text="VIDER",
            command=self.clear_variant_fields,
        ).pack(side="left", padx=8)

        ttk.Separator(
            right,
            orient="horizontal",
        ).pack(fill="x", pady=8)

        ttk.Label(
            right,
            text=(
                "Principe : la tonalité et le playback sont "
                "attachés au couple rôle + artiste, pas seulement au titre."
            ),
            wraplength=330,
        ).pack(anchor="w")

        self._build_export_settings_ui(export_tab)
        scene_export = ttk.LabelFrame(export_tab, text="EXPORT DE LA SCÈNE", padding=8)
        scene_export.pack(fill="x", pady=(8, 0))
        ttk.Label(scene_export, textvariable=self.scene_export_summary_var,
                  wraplength=420).pack(anchor="w")
        self.export_scene_button = ttk.Button(
            scene_export, text="EXPORTER CETTE SCÈNE", state="disabled",
            command=lambda: self.request_export_ui(scene_only=True),
        )
        self.export_scene_button.pack(anchor="w", pady=(4, 0))
        for variable in [self.export_profile_var, self.export_sample_rate_var,
                         self.export_normalize_var, self.export_scenes_var,
                         self.export_medleys_var, self.export_keep_master_var,
                         *self.export_format_vars.values(), *self.export_quality_vars.values()]:
            variable.trace_add("write", lambda *_: self.invalidate_export_preparation())

    def _scroll_tree(self, event):
        units = scroll_units(event, self.tk.call("tk", "windowingsystem"))
        view = self.tree.xview_scroll if event.state & 1 else self.tree.yview_scroll
        view(units, "units")
        return "break"

    def _build_export_settings_ui(self, parent) -> None:
        frame = ttk.LabelFrame(parent, text="EXPORT — RÉGLAGES", padding=8)
        frame.pack(fill="x", pady=(14, 0))

        ttk.Label(frame, text="Source").grid(row=0, column=0, sticky="w")
        for column, (value, label) in enumerate((
                ("clean", "CLEAN"), ("mastered", "MASTERED"), ("direct", "DIRECT")), 1):
            ttk.Radiobutton(frame, text=label, value=value,
                            variable=self.export_profile_var).grid(row=0, column=column, sticky="w")

        self.export_quality_widgets = {}
        choices = {"mp3": ("192", "256", "320"), "wav": ("16", "24", "float32"),
                   "aiff": ("16", "24", "float32"), "flac": ("16", "24")}
        for row, name in enumerate(("mp3", "wav", "aiff", "flac"), 1):
            ttk.Checkbutton(frame, text=name.upper(), variable=self.export_format_vars[name],
                            command=self._sync_export_controls).grid(row=row, column=0, sticky="w")
            widget = ttk.Combobox(frame, state="readonly", width=10,
                                  textvariable=self.export_quality_vars[name], values=choices[name])
            widget.grid(row=row, column=1, columnspan=2, sticky="w")
            self.export_quality_widgets[name] = widget

        ttk.Label(frame, text="Fréquence").grid(row=5, column=0, sticky="w")
        ttk.Combobox(frame, state="readonly", width=10,
                     textvariable=self.export_sample_rate_var,
                     values=("44100", "48000", "88200", "96000")).grid(row=5, column=1, sticky="w")
        ttk.Checkbutton(frame, text="Scènes", variable=self.export_scenes_var).grid(row=6, column=0, sticky="w")
        ttk.Checkbutton(frame, text="Medleys complets", variable=self.export_medleys_var).grid(row=6, column=1, sticky="w")
        ttk.Checkbutton(frame, text="Normaliser", variable=self.export_normalize_var).grid(row=7, column=0, sticky="w")
        ttk.Checkbutton(frame, text="Conserver WAV maître",
                        variable=self.export_keep_master_var).grid(row=7, column=1, sticky="w")
        ttk.Button(frame, text="VÉRIFIER LES RÉGLAGES",
                   command=self.validate_export_settings_ui).grid(row=8, column=0, columnspan=3,
                                                                  sticky="w", pady=(6, 0))
        self._sync_export_controls()

    def _sync_export_controls(self) -> None:
        for name, widget in self.export_quality_widgets.items():
            widget.configure(state="readonly" if self.export_format_vars[name].get() else "disabled")

    def current_export_settings(self) -> dict:
        formats = []
        for name in ("mp3", "wav", "aiff", "flac"):
            if not self.export_format_vars[name].get():
                continue
            quality = self.export_quality_vars[name].get()
            formats.append({"format": name, **(
                {"bitrate_kbps": int(quality)} if name == "mp3"
                else {"bit_depth": quality}
            )})
        return normalize_export_settings({
            "audio_profile": self.export_profile_var.get(),
            "sample_rate": int(self.export_sample_rate_var.get()),
            "normalize": self.export_normalize_var.get(),
            "export_scenes": self.export_scenes_var.get(),
            "export_medleys": self.export_medleys_var.get(),
            "keep_master_wav": self.export_keep_master_var.get(),
            "formats": formats,
        })

    def validate_export_settings_ui(self) -> None:
        try:
            values = self.current_export_settings()
            self.info_var.set(
                "Réglages valides · " + values["audio_profile"].upper()
                + " · " + str(len(values["formats"])) + " format(s)."
            )
        except ValueError as exc:
            messagebox.showerror("Réglages d’export", str(exc))

    def invalidate_export_preparation(self) -> None:
        """Invalidate only the UI preparation; no Live or export action."""
        if "export_workflow_state" not in self.__dict__:
            return
        self.prepared_export_job = None
        self.export_preparation_valid = False
        self.set_export_workflow_state("IDLE")

    def set_export_workflow_state(self, state, *, current=0, total=0, title="", error=""):
        if state not in {"IDLE", "PREPARING", "READY", "EXPORTING", "DONE", "ERROR"}:
            raise ValueError("État export inconnu")
        if state == "READY" and not self.export_preparation_valid:
            raise ValueError("Préparation export absente")
        if state in {"IDLE", "PREPARING", "ERROR"}:
            self.export_preparation_valid = False
            self.prepared_export_job = None
        total = max(0, int(total))
        current = min(max(0, int(current)), total)
        if state in {"IDLE", "PREPARING", "ERROR"}:
            current = total = 0
        self.export_workflow_state = state
        labels = {"IDLE": "À préparer", "PREPARING": "Préparation…",
                  "READY": "Prêt à exporter", "EXPORTING": "Export en cours",
                  "DONE": "Export terminé", "ERROR": "Erreur export"}
        text = labels[state]
        if state == "EXPORTING" and total:
            text = f"Export {current} / {total}" + (f" — {title}" if title else "")
        if state == "ERROR" and error:
            text += " — " + str(error)
        self.export_state_var.set(text)
        self.export_counter_var.set(f"{current} / {total}")
        self.export_progress.configure(maximum=max(1, total), value=current)
        busy = state in {"PREPARING", "EXPORTING"}
        self.prepare_export_button.configure(state="disabled" if busy else "normal")
        enabled = state in {"READY", "DONE"} and self.export_preparation_valid
        self.launch_export_button.configure(state="normal" if enabled else "disabled")
        self.cancel_export_button.configure(state="normal" if state == "EXPORTING" else "disabled")
        self._refresh_scene_export_ui()

    def _refresh_scene_export_ui(self):
        if "export_workflow_state" not in self.__dict__:
            return
        item = self.current_item or {}
        reference = item.get("reference_playback") or {}
        self.scene_export_summary_var.set(
            (status_label(item) + " · " + str(reference.get("track_name") or "—")
             + "\n" + str(reference.get("clip_name") or "—")
             + " · " + format_duration(item.get("duration_seconds")))
            if item else "Aucune scène sélectionnée"
        )
        enabled = (self.export_preparation_valid and
                   self.export_workflow_state in {"READY", "DONE"} and item.get("exportable"))
        self.export_scene_button.configure(state="normal" if enabled else "disabled")

    def _prepare_batch_items(
        self,
        job: dict,
        snapshot: Optional[dict] = None,
    ) -> list[dict]:
        """Adapte le job UI au contrat du moteur batch sans lancer de rendu.

        Règle métier :
        LOCATOR = START
        AUDIO = DUREE
        """
        snapshot = snapshot if snapshot is not None else (self.snapshot or {})
        arrangement = snapshot.get("arrangement") or {}

        markers = list(arrangement.get("markers") or [])
        tempo = arrangement.get("tempo")

        if not markers:
            raise ValueError("Aucun locator Arrangement disponible")

        try:
            tempo = float(tempo)
        except (TypeError, ValueError) as exc:
            raise ValueError("Tempo Live absent ou invalide") from exc

        if tempo <= 0:
            raise ValueError("Tempo Live <= 0")

        settings = dict(job.get("settings") or {})
        batch_items = []

        for job_item in job.get("items") or []:
            source = dict(job_item.get("source_item") or {})

            duration = source.get("duration_seconds")
            if duration is None:
                raise ValueError(
                    f"Durée audio absente pour "
                    f"{source.get('title') or source.get('scene_name') or source.get('id')}"
                )

            if job_item.get("type") == "medley_full":
                zone = resolve_medley_zone(source, snapshot.get("scenes") or [], markers, tempo=tempo)
            else:
                zone = resolve_scene_zone(
                    source, markers,
                    expected_duration_seconds=float(duration), tempo=tempo,
                )

            outputs = []

            for output in job_item.get("outputs") or []:
                specification = dict(output.get("settings") or {})

                specification["format"] = (
                    output.get("format")
                    or specification.get("format")
                )

                specification["filename"] = output.get("filename")

                outputs.append(specification)

            if not outputs:
                raise ValueError(
                    f"Aucune sortie finale pour "
                    f"{source.get('title') or source.get('scene_name') or source.get('id')}"
                )

            batch_items.append({
                "id": job_item.get("id"),
                "type": job_item.get("type"),
                "source_item": source,
                "zone": zone,
                "settings": {
                    "sample_rate": settings.get("sample_rate", 48000),
                    "normalize": settings.get("normalize", False),
                },
                "outputs": outputs,
            })

        return batch_items

    @staticmethod
    def _export_business_key(item: dict) -> str:
        """Identité de remappage indépendante du scene_index courant."""
        title = (
            item.get("scene_name")
            or item.get("title")
            or item.get("name")
            or ""
        )
        return normalize_arrangement_title(title)

    def _selected_export_business_keys(self) -> frozenset[str]:
        selected = set(self.export_selected_scene_indices)
        keys = set()

        for item in (self.model or {}).get("items") or []:
            try:
                scene_index = int(item.get("scene_index"))
            except (TypeError, ValueError):
                continue

            if scene_index not in selected:
                continue

            key = self._export_business_key(item)

            if not key:
                raise ValueError(
                    f"Identité métier vide pour scene_index={scene_index}"
                )

            if key in keys:
                raise ValueError(
                    f"Identité métier sélectionnée ambiguë : {key}"
                )

            keys.add(key)

        if selected and len(keys) != len(selected):
            missing = len(selected) - len(keys)
            raise ValueError(
                f"{missing} scène(s) sélectionnée(s) introuvable(s) "
                "dans le modèle courant"
            )

        return frozenset(keys)

    def _fresh_export_context(self):
        """Réutilise le snapshot identifié ou relit le Set après invalidation."""
        builder = ShowAudioSnapshotBuilder(config_path=CONFIG_PATH)

        status = builder.status()
        scenes = status.get("scenes") or []

        if not scenes:
            raise RuntimeError("Aucune scène dans le Set.")

        if isinstance(scenes, dict):
            indices = sorted(int(index) for index in scenes)
        else:
            indices = list(range(len(scenes)))

        document = (
            load_show_audio_document(CONFIG_PATH)
            if CONFIG_PATH.exists()
            else normalize_show_audio_document({})
        )
        cached = self.__dict__.get("snapshot") or {}
        cached_set = cached.get("set") or {}
        identity = export_identity(status)
        cached_identity = (cached_set.get("server_instance_id"), cached_set.get("id"),
                           cached_set.get("generation"), cached_set.get("name"))
        reuse = (identity is not None and identity == cached_identity
                 and document == self.__dict__.get("document")
                 and list(status.get("arrangement_markers") or []) ==
                     list((cached.get("arrangement") or {}).get("markers") or []))
        snapshot = cached if reuse else builder.build(indices)
        if not reuse and identity is not None:
            latest = export_identity(builder.status())
            acquired = snapshot.get("set") or {}
            acquired_identity = (acquired.get("server_instance_id"), acquired.get("id"),
                                 acquired.get("generation"), acquired.get("name"))
            if latest != identity or acquired_identity != identity:
                raise RuntimeError("Live Set ou serveur changé pendant la préparation. Recommencer.")

        discovered = snapshot.get("discovered_sources")

        if discovered is not None:
            document.update(discovered)
            document["playback_source_mode"] = "live"

        model = build_show_audio_model(snapshot, document)

        return snapshot, document, model

    def _remap_export_selection(
        self,
        model: dict,
        business_keys: frozenset[str],
    ) -> set[int]:
        if not business_keys:
            return set()

        matches = {}

        for item in model.get("items") or []:
            key = self._export_business_key(item)

            if key not in business_keys:
                continue

            try:
                scene_index = int(item.get("scene_index"))
            except (TypeError, ValueError):
                continue

            matches.setdefault(key, []).append(scene_index)

        remapped = set()

        for key in business_keys:
            indices = matches.get(key) or []

            if not indices:
                raise ValueError(
                    f"Scène sélectionnée absente du Set frais : {key}"
                )

            if len(indices) != 1:
                raise ValueError(
                    f"Scène sélectionnée ambiguë dans le Set frais : "
                    f"{key} ({len(indices)} correspondances)"
                )

            remapped.add(indices[0])

        return remapped

    def _prepared_batch_item_for_current_scene(self) -> dict:
        if not self.prepared_export_job:
            raise ValueError("Aucun export préparé")

        current = self.current_item or {}

        if not current.get("exportable"):
            raise ValueError("La scène courante n'est pas exportable")

        current_key = self._export_business_key(current)

        if not current_key:
            raise ValueError("Identité métier de la scène courante absente")

        matches = []

        for item in self.prepared_export_job.get("batch_items") or []:
            source = item.get("source_item") or {}

            if item.get("type") not in {"scene", "medley_part"}:
                continue

            if self._export_business_key(source) == current_key:
                matches.append(item)

        if not matches:
            raise ValueError(
                "La scène courante n'appartient pas à l'export préparé"
            )

        if len(matches) != 1:
            raise ValueError(
                "La scène courante est ambiguë dans l'export préparé"
            )

        return matches[0]

    def _get_scene_export_results(self):
        queue_instance = self.__dict__.get("_scene_export_results")

        if queue_instance is None:
            queue_instance = queue.Queue()
            self.__dict__["_scene_export_results"] = queue_instance

        return queue_instance

    def _run_single_scene_export(
        self,
        item: dict,
        output_directory: Path,
        prepared_generation,
        prepared_set_name: str,
        tempo: float,
    ) -> None:
        try:
            builder = ShowAudioSnapshotBuilder(config_path=CONFIG_PATH)
            status = builder.status()

            if not status.get("set_ready"):
                raise RuntimeError("Live Set non prêt juste avant l'export")

            prepared_identity = (self.__dict__.get("prepared_export_job") or {}).get("set_identity")
            if prepared_identity and all(value is not None and value != "" for value in prepared_identity):
                if export_identity(status) != tuple(prepared_identity):
                    raise RuntimeError("Identité du Live Set ou serveur modifiée. Relancer PRÉPARER EXPORT.")

            live_generation = status.get("set_generation")

            if live_generation != prepared_generation:
                raise RuntimeError(
                    "Le Live Set a changé depuis PRÉPARER EXPORT "
                    f"(génération préparée={prepared_generation}, "
                    f"génération actuelle={live_generation}). "
                    "Relancer PRÉPARER EXPORT."
                )

            live_set_name = str(
                status.get("current_set_name") or ""
            )

            if (
                prepared_set_name
                and live_set_name
                and live_set_name != prepared_set_name
            ):
                raise RuntimeError(
                    "Le Live Set courant n'est plus celui qui a été préparé. "
                    "Relancer PRÉPARER EXPORT."
                )

            batch_items = item if isinstance(item, list) else [item]
            completed_outputs = []
            for batch_item in batch_items:
                result = execute_batch_item(
                    batch_item, output_directory=output_directory, tempo=tempo,
                )
                if result.get("status") != "completed":
                    break
                completed_outputs.extend(result.get("outputs") or [])
            else:
                result = {"status": "completed", "outputs": completed_outputs,
                          "item_count": len(batch_items)}

            self._get_scene_export_results().put(
                ("result", result, str(output_directory))
            )

        except Exception as exc:
            traceback.print_exc()
            self._get_scene_export_results().put(
                ("error", str(exc), str(output_directory))
            )

    def _poll_single_scene_export(self) -> None:
        try:
            kind, payload, output_directory = (
                self._get_scene_export_results().get_nowait()
            )
        except queue.Empty:
            deadline = self.__dict__.get("_scene_export_deadline")
            if deadline is not None and time.monotonic() >= deadline:
                if not self.__dict__.get("_scene_export_timed_out", False):
                    self._scene_export_timed_out = True
                    self.set_export_workflow_state("ERROR", error="Délai export dépassé (330 s).")
                    self.info_var.set("Export bloqué : attente de fin du worker avant une nouvelle tentative.")
                    self.prepare_export_button.configure(state="disabled")
                # Le worker peut encore agir : ne jamais autoriser un second export.
            self.after(100, self._poll_single_scene_export)
            return

        self._scene_export_deadline = None
        if self.__dict__.get("_scene_export_timed_out", False):
            self._scene_export_timed_out = False
            self.prepare_export_button.configure(state="normal")
            self.info_var.set("Worker terminé après dépassement du délai. Vérifier le dossier puis préparer à nouveau.")
            return

        if kind == "error":
            self.set_export_workflow_state(
                "ERROR",
                error=str(payload),
            )
            self.info_var.set(
                "Export audio échoué · " + str(payload)
            )
            messagebox.showerror(
                "Export audio",
                str(payload),
            )
            return

        result = payload or {}

        if result.get("status") != "completed":
            error = (
                result.get("error")
                or "Le moteur d'export n'a pas terminé correctement"
            )

            self.set_export_workflow_state(
                "ERROR",
                error=str(error),
            )

            self.info_var.set(
                "Export audio échoué · " + str(error)
            )

            messagebox.showerror(
                "Export audio",
                str(error),
            )
            return

        self.set_export_workflow_state(
            "DONE",
            current=result.get("item_count", 1),
            total=result.get("item_count", 1),
        )

        outputs = result.get("outputs") or []

        self.info_var.set(
            f"Export audio terminé · {len(outputs)} fichier(s) · "
            f"{output_directory}"
        )

        output_lines = [
            str(output.get("path") or "")
            for output in outputs
            if output.get("path")
        ]

        detail = "\n".join(output_lines)

        messagebox.showinfo(
            "Export audio terminé",
            (
                f"{len(outputs)} fichier(s) créé(s)."
                + (f"\n\n{detail}" if detail else "")
            ),
        )

    def _start_single_scene_export(self, items=None) -> None:
        try:
            item = items if items is not None else self._prepared_batch_item_for_current_scene()
            batch_items = item if isinstance(item, list) else [item]

            job = self.prepared_export_job or {}

            prepared_generation = job.get("set_generation")
            prepared_set_name = str(job.get("set_name") or "")

            if prepared_generation is None:
                raise ValueError(
                    "Génération du Set préparé absente. "
                    "Relancer PRÉPARER EXPORT."
                )

            try:
                tempo = float(job.get("tempo"))
            except (TypeError, ValueError) as exc:
                raise ValueError(
                    "Tempo préparé absent ou invalide"
                ) from exc

            if tempo <= 0:
                raise ValueError("Tempo préparé <= 0")

            unsupported = [
                str(output.get("format") or "").casefold()
                for batch_item in batch_items
                for output in batch_item.get("outputs") or []
                if str(output.get("format") or "").casefold()
                not in {"mp3", "wav"}
            ]

            if unsupported:
                raise ValueError(
                    "Le moteur offline actuel supporte seulement "
                    "MP3 et WAV. Format(s) demandé(s) : "
                    + ", ".join(sorted(set(unsupported)))
                )

        except (ValueError, RuntimeError) as exc:
            messagebox.showerror(
                "Export audio",
                str(exc),
            )
            return

        directory = filedialog.askdirectory(
            title="Choisir le dossier d’export audio",
            mustexist=False,
        )

        if not directory:
            self.info_var.set("Export audio annulé avant lancement.")
            return

        output_directory = Path(directory).expanduser()

        first_item = batch_items[0]
        title = str(
            (first_item.get("source_item") or {}).get("scene_name")
            or (first_item.get("source_item") or {}).get("title")
            or first_item.get("id")
            or "Scène"
        )

        self.set_export_workflow_state(
            "EXPORTING",
            current=0,
            total=len(batch_items),
            title=title,
        )

        self.info_var.set(
            f"Export audio en cours · {title}"
        )

        self._scene_export_deadline = time.monotonic() + 330.0 * len(batch_items)
        self._scene_export_timed_out = False
        threading.Thread(
            target=self._run_single_scene_export,
            args=(
                item,
                output_directory,
                prepared_generation,
                prepared_set_name,
                tempo,
            ),
            daemon=True,
        ).start()

        self.after(
            100,
            self._poll_single_scene_export,
        )

    def request_export_selection_ui(self):
        if (
            not self.export_preparation_valid
            or self.export_workflow_state not in {"READY", "DONE"}
        ):
            return

        selected_medleys = self._selected_medley_ids()
        selected_scenes = set(
            self.export_selected_scene_indices
        )

        if selected_medleys:
            items = (self.prepared_export_job or {}).get("batch_items") or []
            medley_ids = [str((item.get("source_item") or {}).get("medley_id") or "")
                          for item in items if item.get("type") == "medley_full"]
            if set(medley_ids) != selected_medleys or len(medley_ids) != len(selected_medleys):
                messagebox.showerror("Export", "Sélection medley non résolvable. Relancer PRÉPARER EXPORT.")
                return
            self._start_single_scene_export(items=items)
            return

        if len(selected_scenes) > 1:
            items = []

            for item in (
                (self.prepared_export_job or {}).get("batch_items")
                or []
            ):
                if item.get("type") not in {"scene", "medley_part"}:
                    continue

                source_item = item.get("source_item") or {}

                try:
                    scene_index = int(
                        source_item.get("scene_index")
                    )
                except (TypeError, ValueError):
                    continue

                if scene_index in selected_scenes:
                    items.append(item)

            resolved_indices = []

            for item in items:
                try:
                    resolved_indices.append(
                        int(
                            (item.get("source_item") or {}).get(
                                "scene_index"
                            )
                        )
                    )
                except (TypeError, ValueError):
                    pass

            if (
                set(resolved_indices) != selected_scenes
                or len(resolved_indices) != len(selected_scenes)
            ):
                messagebox.showerror(
                    "Export",
                    "Sélection de scènes non résolvable. "
                    "Relancer PRÉPARER EXPORT.",
                )
                return

            self._start_single_scene_export(
                items=items
            )
            return

        if len(selected_scenes) != 1:
            self.info_var.set(
                "Aucune scène sélectionnée pour l'export."
            )
            return

        selected_index = next(
            iter(selected_scenes)
        )

        current_index = None

        if self.current_item:
            try:
                current_index = int(
                    self.current_item.get("scene_index")
                )
            except (TypeError, ValueError):
                current_index = None

        if current_index != selected_index:
            self.current_item = next(
                (
                    item
                    for item in self.model.get("items") or []
                    if item.get("exportable")
                    and int(item.get("scene_index")) == selected_index
                ),
                None,
            )

        if not self.current_item:
            self.info_var.set(
                "Scène sélectionnée introuvable dans le modèle courant."
            )
            return

        self.request_export_ui(
            scene_only=True
        )

    def request_export_ui(self, scene_only=False):
        if (
            not self.export_preparation_valid
            or self.export_workflow_state not in {"READY", "DONE"}
        ):
            return

        if scene_only:
            if not (self.current_item or {}).get("exportable"):
                return

            self.event_generate("<<SceneExportRequested>>")
            self._start_single_scene_export()
            return

        self.event_generate("<<ExportRequested>>")
        self.info_var.set(
            "Export global non connecté dans cette version. "
            "Utiliser EXPORTER LA SÉLECTION."
        )

    def request_cancel_export_ui(self):
        if self.export_workflow_state == "EXPORTING":
            self.event_generate("<<ExportCancelRequested>>")

    def prepare_export_ui(self) -> None:
        """Reconstruit un contexte Live frais puis matérialise le job d'export."""
        if (self.__dict__.get("_scene_export_timed_out", False)
                or self._loading or self.export_workflow_state in {"PREPARING", "EXPORTING"}):
            return

        self.set_export_workflow_state("PREPARING")
        self.info_var.set("Préparation export · lecture fraîche du Set…")
        self.update_idletasks()

        try:
            business_keys = self._selected_export_business_keys()
            selected_medley_ids = frozenset(
                self._selected_medley_ids()
            )
            settings = self.current_export_settings()

            snapshot, document, model = self._fresh_export_context()

            fresh_medley_ids = {
                str(medley.get("id") or "")
                for medley in document.get("medleys") or []
                if str(medley.get("id") or "")
            }

            missing_medleys = (
                selected_medley_ids
                - fresh_medley_ids
            )

            if missing_medleys:
                raise ValueError(
                    "Medley sélectionné absent de la configuration fraîche : "
                    + ", ".join(
                        sorted(missing_medleys)
                    )
                )

            fresh_selected = self._remap_export_selection(
                model,
                business_keys,
            )

            plan = build_export_plan(document, snapshot)

            plan["items"] = [
                item
                for item in plan.get("items") or []
                if (
                    (
                        item.get("type") == "medley_full"
                        and str(
                            item.get("medley_id") or ""
                        )
                        in selected_medley_ids
                    )
                    or (
                        item.get("type") != "medley_full"
                        and item.get("scene_index")
                        in fresh_selected
                    )
                )
            ]

            selected_full_medleys = [
                item
                for item in plan.get("items") or []
                if item.get("type") == "medley_full"
            ]

            available_ids = [str(item.get("medley_id") or "") for item in selected_full_medleys]
            if any(available_ids.count(key) != 1 for key in selected_medley_ids):
                raise ValueError("Medley incomplet, non contigu ou non exportable : "
                                 + ", ".join(sorted(selected_medley_ids)))

            # Injecter les variantes métier fraîches dans les items du plan.
            # Elles serviront à CL Audio Export pour commuter automatiquement
            # les playbacks rôle/artiste pendant le rendu.
            model_items_by_scene = {}
            for model_item in model.get("items") or []:
                try:
                    model_items_by_scene[int(model_item.get("scene_index"))] = model_item
                except (TypeError, ValueError):
                    continue

            for plan_item in plan.get("items") or []:
                if plan_item.get("type") == "medley_full":
                    merged_variants = []
                    numbers = {
                        int(value)
                        for value in plan_item.get("scene_numbers") or []
                        if str(value).strip()
                    }

                    for model_item in model.get("items") or []:
                        try:
                            number = int(model_item.get("scene_number"))
                        except (TypeError, ValueError):
                            continue

                        if number in numbers:
                            merged_variants.extend(
                                dict(value)
                                for value in model_item.get("variants") or []
                                if isinstance(value, dict)
                            )

                    plan_item["variants"] = merged_variants

                else:
                    try:
                        scene_index = int(plan_item.get("scene_index"))
                    except (TypeError, ValueError):
                        scene_index = None

                    model_item = model_items_by_scene.get(scene_index) or {}
                    plan_item["variants"] = [
                        dict(value)
                        for value in model_item.get("variants") or []
                        if isinstance(value, dict)
                    ]

            job = build_export_job(plan, settings)
            if selected_medley_ids and not settings.get("export_medleys"):
                raise ValueError("Activer l'export des medleys sélectionnés dans les réglages")

            batch_items = self._prepare_batch_items(
                job,
                snapshot=snapshot,
            )

            arrangement = snapshot.get("arrangement") or {}
            set_info = snapshot.get("set") or {}

            # L'inventaire Live sert uniquement à résoudre les groupes
            # PLAYBACK... / SAISON... pendant l'export.
            for batch_item in batch_items:
                batch_item["track_inventory"] = [
                    dict(track)
                    for track in snapshot.get("tracks") or []
                    if isinstance(track, dict)
                ]

            job["batch_items"] = batch_items
            job["tempo"] = float(arrangement.get("tempo"))
            job["set_generation"] = set_info.get("generation")
            job["set_identity"] = (set_info.get("server_instance_id"), set_info.get("id"),
                                   set_info.get("generation"), set_info.get("name"))
            job["set_name"] = set_info.get("name") or ""

        except (ValueError, RuntimeError) as exc:
            self.set_export_workflow_state(
                "ERROR",
                error=str(exc),
            )
            messagebox.showerror("Export", str(exc))
            return

        count = job["metrics"]["selected_item_count"]
        outputs = job["metrics"]["final_output_count"]

        if not count:
            self.set_export_workflow_state(
                "ERROR",
                error="Aucun élément à exporter",
            )
            return

        self.snapshot = snapshot
        self.document = document
        self.model = model
        self.export_selected_scene_indices = fresh_selected

        if self.current_item:
            old_key = self._export_business_key(self.current_item)

            self.current_item = next(
                (
                    item
                    for item in model.get("items") or []
                    if self._export_business_key(item) == old_key
                ),
                None,
            )

        self.prepared_export_job = job
        self.export_preparation_valid = True

        self.populate_tree()
        self._refresh_variant_choices()
        self._refresh_variant_summary()
        self._refresh_export_marks()

        self.set_export_workflow_state(
            "READY",
            total=count,
        )

        generation = job.get("set_generation")
        set_name = job.get("set_name") or "Set Live"

        self.info_var.set(
            f"Export préparé sur Set frais · {count} prise(s) · "
            f"{outputs} fichier(s) · génération {generation}"
        )

        messagebox.showinfo(
            "Export préparé",
            f"{set_name}\n"
            f"Génération : {generation}\n"
            f"{count} prise(s) · {outputs} fichier(s) final(aux).\n\n"
            "Aucun rendu n'a encore été lancé.",
        )

    def _combo_row(
        self,
        parent,
        label: str,
        variable: tk.StringVar,
        row: int,
    ):
        ttk.Label(
            parent,
            text=label + " :",
            width=16,
        ).grid(
            row=row,
            column=0,
            sticky="w",
            pady=4,
        )

        combo = ttk.Combobox(
            parent,
            textvariable=variable,
            state="normal",
        )
        combo.grid(
            row=row,
            column=1,
            sticky="ew",
            pady=4,
        )

        parent.columnconfigure(1, weight=1)
        return combo

    def _current_scene_variants(self) -> list[dict]:
        if not self.current_item:
            return []

        return [
            dict(value)
            for value in self.current_item.get("variants") or []
            if isinstance(value, dict)
        ]

    @staticmethod
    def _unique_text_values(values) -> tuple[str, ...]:
        result = []
        seen = set()

        for value in values:
            value = str(value or "").strip()
            if not value:
                continue

            key = value.casefold()
            if key in seen:
                continue

            seen.add(key)
            result.append(value)

        return tuple(result)

    def _refresh_variant_choices(self) -> None:
        variants = self._current_scene_variants()

        document_variants = [
            value
            for value in self.document.get("variants") or []
            if isinstance(value, dict)
        ]

        roles = self._unique_text_values(
            value.get("role")
            for value in document_variants
        )
        artists = self._unique_text_values(
            value.get("artist")
            for value in document_variants
        )
        default_keys = (
            "Original",
            "C", "Cm",
            "C#", "C#m",
            "Db", "Dbm",
            "D", "Dm",
            "Eb", "Ebm",
            "E", "Em",
            "F", "Fm",
            "F#", "F#m",
            "Gb", "Gbm",
            "G", "Gm",
            "Ab", "Abm",
            "A", "Am",
            "Bb", "Bbm",
            "B", "Bm",
            "-3", "-2", "-1",
            "+1", "+2", "+3",
        )

        keys = self._unique_text_values(
            list(default_keys)
            + [
                value.get("key")
                for value in document_variants
            ]
        )

        playbacks = []

        if self.current_item:
            reference = self.current_item.get("reference_playback") or {}
            if reference.get("track_name"):
                playbacks.append(reference.get("track_name"))
            if reference.get("clip_name"):
                playbacks.append(reference.get("clip_name"))

            for playback in self.current_item.get("active_playbacks") or []:
                if not isinstance(playback, dict):
                    continue
                playbacks.append(playback.get("track_name"))
                playbacks.append(playback.get("clip_name"))

        if self.current_item:
            for scene in self.snapshot.get("scenes") or []:
                if scene.get("scene_index") != self.current_item.get("scene_index"):
                    continue
                for clip in scene.get("clips") or []:
                    if clip.get("playback_track"):
                        playbacks.append(clip.get("track_name"))
                        playbacks.append(clip.get("clip_name"))

        playbacks.extend(
            value.get("playback")
            for value in variants
        )

        if self.role_combo is not None:
            self.role_combo.configure(values=roles)

        if self.artist_combo is not None:
            self.artist_combo.configure(values=artists)

        if self.key_combo is not None:
            self.key_combo.configure(values=keys)

        if self.playback_combo is not None:
            self.playback_combo.configure(
                values=self._unique_text_values(playbacks)
            )

    def _variant_summary_text(self) -> str:
        variants = self._current_scene_variants()

        if not variants:
            return "Aucune variante enregistrée pour cette scène."

        lines = []

        for variant in variants:
            role = str(
                variant.get("role") or "—"
            ).strip() or "—"

            artist = str(
                variant.get("artist") or "—"
            ).strip() or "—"

            key = str(
                variant.get("key") or "—"
            ).strip() or "—"

            playback = str(
                variant.get("playback") or "—"
            ).strip() or "—"

            lines.append(
                f"{role} · {artist}"
                f"  —  tonalité : {key}"
                f"  —  playback : {playback}"
            )

        return "\n".join(lines)

    def _refresh_variant_summary(self) -> None:
        self.variant_summary_var.set(
            self._variant_summary_text()
        )

    def _variant_identity_changed(self, event=None) -> None:
        role = self.role_var.get().strip().casefold()
        artist = self.artist_var.get().strip().casefold()

        if not role or not artist:
            return

        matches = []

        for variant in self._current_scene_variants():
            if (
                str(variant.get("role") or "").strip().casefold() == role
                and
                str(variant.get("artist") or "").strip().casefold() == artist
            ):
                matches.append(variant)

        if len(matches) != 1:
            return

        variant = matches[0]

        self.key_var.set(
            str(variant.get("key") or "").strip()
        )
        self.playback_var.set(
            str(variant.get("playback") or "").strip()
        )
        self._refresh_variant_summary()

    def _detail_row(
        self,
        parent,
        label: str,
        variable: tk.StringVar,
        row: int,
    ) -> None:
        ttk.Label(
            parent,
            text=label + " :",
            width=16,
        ).grid(
            row=row,
            column=0,
            sticky="nw",
            pady=4,
        )

        ttk.Label(
            parent,
            textvariable=variable,
            wraplength=250,
        ).grid(
            row=row,
            column=1,
            sticky="nw",
            pady=4,
        )

    def _entry_row(
        self,
        parent,
        label: str,
        variable: tk.StringVar,
        row: int,
    ) -> None:
        ttk.Label(
            parent,
            text=label + " :",
            width=16,
        ).grid(
            row=row,
            column=0,
            sticky="w",
            pady=5,
        )

        ttk.Entry(
            parent,
            textvariable=variable,
            width=46,
        ).grid(
            row=row,
            column=1,
            sticky="ew",
            pady=5,
        )

        parent.columnconfigure(
            1,
            weight=1,
        )

    def refresh_from_live(self) -> None:
        if self._loading:
            return
        self.invalidate_export_preparation()
        self._loading = True
        self.reload_button.configure(state="disabled")
        self.info_var.set("Lecture du Set… connexion au contrôleur")
        # Aucun appel Tk dans le worker : l'interface reste réactive.
        threading.Thread(target=self._load_from_live, daemon=True).start()
        self.after(50, self._poll_live_load)

    def _load_from_live(self) -> None:
        try:
            builder = ShowAudioSnapshotBuilder(config_path=CONFIG_PATH, progress=self._load_progress.put)
            status = builder.status()
            scenes = status.get("scenes") or []
            if not scenes:
                raise RuntimeError("Aucune scène dans le Set.")
            indices = sorted(int(index) for index in scenes) if isinstance(scenes, dict) else range(len(scenes))
            snapshot = builder.build(indices)
            document = (
                load_show_audio_document(CONFIG_PATH)
                if CONFIG_PATH.exists()
                else normalize_show_audio_document({})
            )
            model = build_show_audio_model(snapshot, document)
            self._load_results.put((snapshot, document, model, None))
        except Exception as exc:
            traceback.print_exc()
            self._load_results.put((None, None, None, str(exc)))

    def _poll_live_load(self) -> None:
        while not self._load_progress.empty():
            path = self._load_progress.get_nowait()
            if "track-hierarchy" in path:
                stage = "découverte des groupes et pistes"
            elif "clip-info" in path:
                index = path.split("track_index=", 1)[1].split("&", 1)[0]
                stage = f"vérification des sources audio · piste {int(index) + 1}"
            elif "scene-clips" in path:
                stage = "lecture des scènes et clips"
            elif "tracks-bulk" in path:
                stage = "lecture des pistes ON/OFF"
            else:
                stage = "connexion au contrôleur"
            self.info_var.set("Lecture du Set… " + stage)
        try:
            snapshot, document, model, error = self._load_results.get_nowait()
        except queue.Empty:
            self.after(50, self._poll_live_load)
            return

        try:
            if error is not None:
                raise RuntimeError(error)
            # Une variante peut avoir été enregistrée pendant le scan : relire
            # le document avant d'ajouter uniquement les sources découvertes.
            document = load_show_audio_document(CONFIG_PATH)
            discovered = snapshot.get("discovered_sources")
            if discovered is not None:
                document.update(discovered)
                document["playback_source_mode"] = "live"
                save_show_audio_document(CONFIG_PATH, document)
            model = build_show_audio_model(snapshot, document)
            self.snapshot, self.document, self.model = snapshot, document, model
            if self.current_item:
                current_index = self.current_item.get("scene_index")
                self.current_item = next((item for item in model["items"]
                                          if item["scene_index"] == current_index), None)
            self.populate_tree()
            self._refresh_variant_choices()
            self._refresh_variant_summary()
            metrics = snapshot.get("metrics", {})
            message = (f"{len(model['items'])} scènes · "
                       f"{metrics.get('total_seconds', 0):.2f}s · "
                       f"{model['metrics']['exportable_count']} exportables")
            if not snapshot.get("playback_tracks"):
                message += " · Aucune source playback configurée dans show_audio.json."
            elif not model['metrics']['exportable_count']:
                message += " · Aucun playback autorisé ON avec une durée valide."
            self.info_var.set(message)
        except Exception as exc:
            traceback.print_exc()
            self.info_var.set(f"Erreur de lecture : {exc}")
            messagebox.showerror("CL Audio Export", str(exc))
        finally:
            self._loading = False
            self.reload_button.configure(state="normal")

    def save_medley_definition(self, title, scene_indices, medley_id=None):
        document = upsert_medley_from_scenes(
            load_show_audio_document(CONFIG_PATH), self.model,
            title=title, scene_indices=scene_indices, medley_id=medley_id,
        )
        save_show_audio_document(CONFIG_PATH, document)
        self.document = document
        self.populate_tree()
        self.info_var.set(f"Medley « {title.strip()} » enregistré.")

    def open_medley_editor(self):
        if self._loading or not self.model.get("items"):
            self.info_var.set("Attends la fin du chargement du Set pour choisir les titres du medley.")
            return
        existing_dialog = self.__dict__.get('_medley_editor')
        if existing_dialog is not None and existing_dialog.winfo_exists():
            existing_dialog.lift()
            return
        dialog = tk.Toplevel(self)
        self._medley_editor = dialog
        dialog.title("Choisir les titres d'un medley")
        dialog.geometry("740x580")
        dialog.transient(self)
        dialog.grab_set()
        frame = ttk.Frame(dialog, padding=14)
        frame.pack(fill="both", expand=True)
        medleys = list(self.document.get('medleys') or [])
        current_id = [None]
        names = tk.StringVar(dialog)
        error = tk.StringVar(dialog)
        summary = tk.StringVar(dialog)
        ttk.Label(frame, text="Créer un medley ou choisir un medley existant :").pack(anchor="w")
        choices = ttk.Combobox(frame, state="readonly", values=["Nouveau medley"] + [m.get('title') or m['id'] for m in medleys])
        choices.current(0)
        choices.pack(fill="x", pady=(4, 10))
        ttk.Label(frame, text="Nom du medley").pack(anchor="w")
        title_entry = ttk.Entry(frame, textvariable=names)
        title_entry.pack(fill="x", pady=(4, 10))
        ttk.Label(frame, text="Titres dans l'ordre du Set — Maj pour une plage, ⌘ pour plusieurs titres.").pack(anchor="w")
        list_frame = ttk.Frame(frame)
        list_frame.pack(fill="both", expand=True, pady=(6, 8))
        members = tk.Listbox(list_frame, selectmode="extended", exportselection=False)
        scrollbar = ttk.Scrollbar(list_frame, orient="vertical", command=members.yview)
        members.configure(yscrollcommand=scrollbar.set)
        members.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        items = sorted(self.model['items'], key=lambda item: int(item['scene_index']))
        for item in items:
            number = int(item['scene_index']) + 1
            show = f" · SHOW {item['show_number']}" if item.get('show_number') else ""
            members.insert("end", f"LIVE {number:03d}{show} — {item.get('title') or '(sans titre)'}")

        def summarize(event=None):
            summary.set(f"{len(members.curselection())} titre(s) sélectionné(s) · ordre du Set conservé")
        members.bind('<<ListboxSelect>>', summarize)

        def choose(event=None):
            error.set('')
            members.selection_clear(0, 'end')
            index = choices.current() - 1
            if index < 0:
                current_id[0] = None
                names.set('')
                selected = self._selected_tree_scene_indices()
            else:
                medley = medleys[index]
                current_id[0] = medley['id']
                names.set(medley.get('title') or '')
                selected = {i for i, group in self._medley_ui_by_scene().items() if group['id'] == current_id[0]}
            positions = []
            for position, item in enumerate(items):
                if int(item['scene_index']) in selected:
                    members.selection_set(position)
                    positions.append(position)
            if positions:
                members.see(positions[0])
            summarize()
        choices.bind('<<ComboboxSelected>>', choose)

        def save():
            try:
                indices = [int(items[int(position)]['scene_index']) for position in members.curselection()]
                self.save_medley_definition(names.get(), indices, current_id[0])
            except (ValueError, OSError) as exc:
                error.set(str(exc))
                return
            dialog.destroy()
        ttk.Label(frame, textvariable=summary).pack(anchor="w")
        ttk.Label(frame, textvariable=error, foreground="#d64b4b", wraplength=700).pack(fill="x", pady=(4, 8))
        actions = ttk.Frame(frame)
        actions.pack(fill="x")
        ttk.Button(actions, text="Annuler", command=dialog.destroy).pack(side="right")
        save_button = ttk.Button(actions, text="ENREGISTRER LE MEDLEY", command=save)
        save_button.pack(side="right", padx=8)
        # Contrôles nommés pour la validation runtime du véritable dialogue.
        dialog.member_list, dialog.title_var = members, names
        dialog.existing_combo, dialog.save_button = choices, save_button
        dialog.error_var = error
        choose()
        title_entry.focus_set()

    def _medley_ui_by_scene(self) -> dict[int, dict]:
        """Retourne le medley UI auquel appartient chaque scene_index.

        Les medleys utilisent les numeros LIVE/show (ex. 40),
        tandis que le modele interne utilise scene_index (ex. 39).
        On construit donc explicitement la correspondance a partir
        de show_number au lieu de supposer scene_index == numero LIVE.
        """
        result: dict[int, dict] = {}

        medleys = build_medleys(self.document, self.snapshot)

        show_number_to_scene_index: dict[int, int] = {}

        for item in self.model.get("items") or []:
            try:
                scene_index = int(item.get("scene_index"))
            except (TypeError, ValueError):
                continue

            raw_show_number = item.get("show_number")

            try:
                show_number = int(raw_show_number)
            except (TypeError, ValueError):
                # Secours compatible avec le modele actuel :
                # scene_index 39 -> numero LIVE 40.
                show_number = scene_index + 1

            if show_number > 0:
                show_number_to_scene_index[show_number] = scene_index

        for medley in medleys or []:
            numbers = []

            for value in medley.get("scene_numbers") or []:
                try:
                    number = int(value)
                except (TypeError, ValueError):
                    continue

                if number > 0:
                    numbers.append(number)

            if not numbers:
                continue

            medley_data = {
                "id": medley.get("id") or "",
                "title": str(
                    medley.get("title") or ""
                ).strip(),
                "scene_numbers": numbers,
                "numbering": medley.get("numbering"),
            }

            live_to_index = {
                int(item.get("scene_number") or int(item["scene_index"]) + 1): int(item["scene_index"])
                for item in self.model.get("items") or []
            } if medley.get("numbering") == "live" else show_number_to_scene_index
            for live_number in numbers:
                scene_index = live_to_index.get(live_number)

                if scene_index is not None:
                    result[scene_index] = medley_data

        return result

    def _medley_ui_title(self, medley: dict) -> str:
        """Titre lisible du medley."""
        title = str(
            medley.get("title") or ""
        ).strip()

        if title:
            return title

        return "MEDLEY"

    def _medley_ui_parts(
        self,
        medley: dict,
    ) -> list[str]:
        """Résout les titres des scènes composant le medley.

        scene_numbers contient les numeros LIVE/show.
        Le modele interne peut utiliser un scene_index different.
        """
        by_show_number = {}

        for item in self.model.get("items") or []:
            try:
                scene_index = int(item.get("scene_index"))
            except (TypeError, ValueError):
                continue

            raw_show_number = (
                item.get("scene_number") or scene_index + 1
                if medley.get("numbering") == "live"
                else item.get("show_number")
            )

            try:
                show_number = int(raw_show_number)
            except (TypeError, ValueError):
                show_number = scene_index + 1

            title = str(
                item.get("title")
                or item.get("scene_name")
                or ""
            ).strip()

            if title and show_number > 0:
                by_show_number[show_number] = title

        parts = []

        for value in medley.get("scene_numbers") or []:
            try:
                live_number = int(value)
            except (TypeError, ValueError):
                continue

            title = by_show_number.get(live_number)

            if title:
                parts.append(title)

        return parts

    def _insert_medley_separator(self, medley: dict) -> None:
        """Bannière informative, jamais une scène sélectionnable pour l'export."""
        name = self._medley_ui_title(medley)
        composition = " / ".join(self._medley_ui_parts(medley))
        title = f"◆ MEDLEY — {name}"
        if composition:
            # Éviter de répéter la composition quand elle sert déjà de nom.
            title = ("◆ MEDLEY —" if name == composition else title) + "\n" + composition
        # Une bannière ne doit pas agrandir toutes les lignes du tableau.
        # La composition reste lisible par défilement horizontal et dans l'éditeur.
        title = title.replace("\n", " · ")
        self.tree.insert(
            "", "end", iid=f"medley-header-{medley['id']}",
            values=(
                (
                    "🟢 MEDLEY"
                    if str(medley.get("id") or "") in self._selected_medley_ids()
                    else "⚫ MEDLEY"
                ),
                "",
                "",
                title,
                "",
                "",
                "",
                "",
            ),
            tags=("medley_header",),
        )

    def populate_tree(self) -> None:
        selected_index = None

        if not self.export_selection_initialized:
            # Au démarrage, aucune scène n'est présélectionnée.
            # L'utilisateur choisit explicitement ce qu'il veut exporter.
            self.export_selected_scene_indices = set()
            self.export_selected_medley_ids = set()
            self.export_selection_initialized = True

        if self.current_item:
            selected_index = self.current_item.get(
                "scene_index"
            )

        # Nettoyage de la liste.
        for iid in self.tree.get_children():
            self.tree.delete(iid)

        show_all = bool(
            self.show_all_var.get()
        )

        # ----------------------------------------------------
        # 1. Construire la liste des scènes affichables.
        # ----------------------------------------------------
        scene_items = []

        for item in self.model.get("items") or []:
            if (
                not show_all
                and not item.get("exportable")
            ):
                continue

            try:
                scene_index = int(
                    item["scene_index"]
                )
            except (TypeError, ValueError):
                continue

            scene_items.append(
                (scene_index, item)
            )

        # Le regroupement visuel utilise explicitement la correspondance
        # numéro SHOW/LIVE -> scene_index. Ne jamais supposer ici que
        # scene_index == numéro LIVE - 1.
        medley_by_scene = self._medley_ui_by_scene()

        # ----------------------------------------------------
        # 3. Afficher les scènes et insérer directement la
        #    ligne MEDLEY avant la première scène concernée.
        # ----------------------------------------------------
        opened_medleys = set()

        for scene_index, item in scene_items:

            medley_info = medley_by_scene.get(
                scene_index
            )

            if medley_info:
                medley_id = medley_info["id"]

                if medley_id not in opened_medleys:

                    self._insert_medley_separator(medley_info)

                    opened_medleys.add(
                        medley_id
                    )

            reference = (
                item.get("reference_playback")
                or {}
            )

            iid = f"scene-{scene_index}"

            self.tree.insert(
                "",
                "end",
                iid=iid,
                values=(
                    (
                        "🟢 PROD"
                        if scene_index
                        in self.export_selected_scene_indices
                        else "⚫ —"
                    ),
                    f"{scene_index:03d}",
                    item.get("show_number") or "",
                    item.get("title") or "",
                    format_duration(
                        item.get("duration_seconds")
                    ),
                    reference.get("track_name") or "",
                    status_label(item),
                    len(item.get("variants") or []),
                ),
            )

            if scene_index == selected_index:
                self.tree.selection_set(iid)
                self.tree.see(iid)

        self._update_export_selection_summary()

    def _scene_index_from_iid(self, iid: str) -> Optional[int]:
        value = str(iid or "").strip()

        if not value.startswith("scene-"):
            return None

        value = value.split("-", 1)[1]

        try:
            return int(value)
        except (TypeError, ValueError):
            return None

    def _selected_medley_ids(self) -> set[str]:
        selected = self.__dict__.get(
            "export_selected_medley_ids"
        )

        if selected is None:
            selected = set()
            self.__dict__[
                "export_selected_medley_ids"
            ] = selected

        return selected

    @staticmethod
    def _medley_id_from_iid(iid: str) -> Optional[str]:
        value = str(iid or "").strip()
        prefix = "medley-header-"

        if not value.startswith(prefix):
            return None

        medley_id = value[len(prefix):].strip()

        return medley_id or None

    def _medley_scene_indices(
        self,
        medley_id: str,
    ) -> set[int]:
        result = set()

        for scene_index, medley in (
            self._medley_ui_by_scene().items()
        ):
            if str(medley.get("id") or "") != medley_id:
                continue

            result.add(int(scene_index))

        return result

    def _toggle_medley_export_selection(
        self,
        medley_id: str,
    ) -> None:
        medley_id = str(medley_id or "").strip()

        if not medley_id:
            return

        selected_medleys = self._selected_medley_ids()

        if medley_id in selected_medleys:
            selected_medleys.remove(medley_id)
        else:
            selected_medleys.add(medley_id)

            self.export_selected_scene_indices.difference_update(
                self._medley_scene_indices(medley_id)
            )

        self._refresh_export_marks()

    def _toggle_scene_export_selection(
        self,
        scene_index: int,
    ) -> None:
        scene_index = int(scene_index)

        if scene_index in self.export_selected_scene_indices:
            self.export_selected_scene_indices.remove(
                scene_index
            )
        else:
            self.export_selected_scene_indices.add(
                scene_index
            )

            medley = self._medley_ui_by_scene().get(
                scene_index
            )

            if medley:
                self._selected_medley_ids().discard(
                    str(medley.get("id") or "")
                )

        self._refresh_export_marks()

    def _update_export_selection_summary(self) -> None:
        scene_count = len(
            self.export_selected_scene_indices
        )
        medley_count = len(
            self._selected_medley_ids()
        )

        scene_label = (
            f"{scene_count} scène sélectionnée"
            if scene_count == 1
            else f"{scene_count} scènes sélectionnées"
        )

        if medley_count:
            medley_label = (
                f"{medley_count} medley complet"
                if medley_count == 1
                else f"{medley_count} medleys complets"
            )

            label = f"{scene_label} + {medley_label}"
        else:
            label = scene_label

        self.export_selection_summary_var.set(
            label
        )

        selection = (
            frozenset(
                self.export_selected_scene_indices
            ),
            frozenset(
                self._selected_medley_ids()
            ),
        )

        if (
            self.__dict__.get(
                "_prepared_selection_ui"
            )
            != selection
        ):
            self.invalidate_export_preparation()

        self._prepared_selection_ui = selection

    def _refresh_export_marks(self) -> None:
        """Rafraîchit les sélections scènes et medleys."""

        selected_medleys = self._selected_medley_ids()

        for iid in self.tree.get_children():
            values = list(
                self.tree.item(iid, "values")
            )

            if not values:
                continue

            medley_id = self._medley_id_from_iid(
                iid
            )

            if medley_id is not None:
                values[0] = (
                    "🟢 MEDLEY"
                    if medley_id in selected_medleys
                    else "⚫ MEDLEY"
                )

                self.tree.item(
                    iid,
                    values=values,
                )
                continue

            scene_index = self._scene_index_from_iid(
                iid
            )

            if scene_index is None:
                continue

            values[0] = (
                "🟢  PROD"
                if scene_index
                in self.export_selected_scene_indices
                else "⚫  —"
            )

            self.tree.item(
                iid,
                values=values,
            )

        self._update_export_selection_summary()

    def _selected_tree_scene_indices(self) -> set[int]:
        result = set()

        for iid in self.tree.selection():
            scene_index = self._scene_index_from_iid(iid)

            if scene_index is not None:
                result.add(scene_index)

        return result

    def select_all_exportable_scenes(self) -> None:
        selected = set()

        for item in self.model.get("items") or []:
            if not item.get("exportable"):
                continue

            try:
                selected.add(
                    int(item.get("scene_index"))
                )
            except (TypeError, ValueError):
                continue

        self.export_selected_scene_indices = selected

        # "Tout cocher" signifie ici tous les titres individuels.
        # On évite volontairement de sélectionner en plus les
        # medleys complets afin de ne jamais créer de doublons.
        self._selected_medley_ids().clear()

        self._refresh_export_marks()

    def clear_export_selection(self) -> None:
        self.export_selected_scene_indices.clear()
        self._selected_medley_ids().clear()
        self._refresh_export_marks()

    def select_visible_scenes(self) -> None:
        selected_now = set()

        for iid in self.tree.get_children():
            scene_index = self._scene_index_from_iid(
                iid
            )

            if scene_index is None:
                continue

            self.export_selected_scene_indices.add(
                scene_index
            )
            selected_now.add(scene_index)

        if selected_now:
            medley_by_scene = self._medley_ui_by_scene()

            for scene_index in selected_now:
                medley = medley_by_scene.get(
                    scene_index
                )

                if medley:
                    self._selected_medley_ids().discard(
                        str(medley.get("id") or "")
                    )

        self._refresh_export_marks()

    def check_selected_scenes_for_export(self) -> None:
        for iid in self.tree.selection():
            medley_id = self._medley_id_from_iid(
                iid
            )

            if medley_id is not None:
                self._selected_medley_ids().add(
                    medley_id
                )

                self.export_selected_scene_indices.difference_update(
                    self._medley_scene_indices(
                        medley_id
                    )
                )
                continue

            scene_index = self._scene_index_from_iid(
                iid
            )

            if scene_index is None:
                continue

            self.export_selected_scene_indices.add(
                scene_index
            )

            medley = self._medley_ui_by_scene().get(
                scene_index
            )

            if medley:
                self._selected_medley_ids().discard(
                    str(medley.get("id") or "")
                )

        self._refresh_export_marks()

    def uncheck_selected_scenes_for_export(self) -> None:
        for iid in self.tree.selection():
            medley_id = self._medley_id_from_iid(
                iid
            )

            if medley_id is not None:
                self._selected_medley_ids().discard(
                    medley_id
                )
                continue

            scene_index = self._scene_index_from_iid(
                iid
            )

            if scene_index is not None:
                self.export_selected_scene_indices.discard(
                    scene_index
                )

        self._refresh_export_marks()

    def on_export_context_menu(self, event):
        iid = self.tree.identify_row(event.y)

        if not iid:
            return

        # Si le clic droit se fait sur une ligne qui ne fait pas encore
        # partie de la sélection multiple, elle devient la sélection.
        if iid not in self.tree.selection():
            self.tree.selection_set(iid)

        try:
            self.export_context_menu.tk_popup(
                event.x_root,
                event.y_root,
            )
        finally:
            self.export_context_menu.grab_release()

        return "break"

    def on_export_column_click(self, event) -> None:
        region = self.tree.identify_region(
            event.x,
            event.y,
        )

        if region != "cell":
            return

        column = self.tree.identify_column(
            event.x
        )

        if column != "#1":
            return

        iid = self.tree.identify_row(
            event.y
        )

        if not iid:
            return

        medley_id = self._medley_id_from_iid(
            iid
        )

        if medley_id is not None:
            self._toggle_medley_export_selection(
                medley_id
            )

            if iid not in self.tree.selection():
                self.tree.selection_set(iid)

            return "break"

        scene_index = self._scene_index_from_iid(
            iid
        )

        if scene_index is None:
            return

        self._toggle_scene_export_selection(
            scene_index
        )

        if iid not in self.tree.selection():
            self.tree.selection_set(iid)

        return "break"

    def on_scene_selected(self, _event=None) -> None:
        selection = self.tree.selection()

        if not selection:
            return

        iid = selection[0]

        try:
            scene_index = int(
                iid.split("-", 1)[1]
            )
        except Exception:
            return

        item = next(
            (
                value
                for value in self.model.get("items") or []
                if int(value["scene_index"])
                == scene_index
            ),
            None,
        )

        if item is None:
            return

        self.current_item = item
        self._refresh_scene_export_ui()
        self._refresh_variant_choices()
        self._refresh_variant_summary()

        reference = (
            item.get("reference_playback")
            or {}
        )

        self.scene_title_var.set(
            f"{scene_index:03d} — "
            f"{item.get('title') or item.get('scene_name')}"
        )

        self.scene_status_var.set(
            status_label(item)
        )

        self.scene_duration_var.set(
            format_duration(
                item.get("duration_seconds")
            )
        )

        self.scene_track_var.set(
            reference.get("track_name")
            or "—"
        )

        self.scene_clip_var.set(
            reference.get("clip_name")
            or "—"
        )

        variants = list(
            item.get("variants") or []
        )

        if len(variants) == 1:
            variant = variants[0]

            self.role_var.set(
                variant.get("role") or ""
            )
            self.artist_var.set(
                variant.get("artist") or ""
            )
            self.key_var.set(
                variant.get("key") or ""
            )
            self.playback_var.set(
                variant.get("playback") or ""
            )

        else:
            self.clear_variant_fields()

    def clear_variant_fields(self) -> None:
        self.role_var.set("")
        self.artist_var.set("")
        self.key_var.set("")
        self.playback_var.set("")

    def save_variant(self) -> None:
        if not self.current_item:
            messagebox.showwarning(
                "CL Audio Export",
                "Sélectionne d'abord une scène.",
            )
            return

        item = self.current_item

        try:
            updated = upsert_scene_variant(
                self.document,
                scene_index=int(
                    item["scene_index"]
                ),
                scene_name=item.get(
                    "scene_name", ""
                ),
                number=(
                    item.get("show_number")
                    or str(
                        int(item["scene_index"]) + 1
                    )
                ),
                title=item.get("title") or "",
                role=self.role_var.get(),
                artist=self.artist_var.get(),
                key=self.key_var.get(),
                playback=self.playback_var.get(),
            )

            save_show_audio_document(
                CONFIG_PATH,
                updated,
            )

            self.document = updated

            self.model = build_show_audio_model(
                self.snapshot,
                self.document,
            )

            current_index = int(
                item["scene_index"]
            )

            self.current_item = next(
                (
                    value
                    for value in self.model["items"]
                    if int(value["scene_index"])
                    == current_index
                ),
                None,
            )

            self.populate_tree()
            self._refresh_variant_choices()
            self._refresh_variant_summary()

            self.info_var.set(
                "Variante enregistrée."
            )

        except Exception as exc:
            messagebox.showerror(
                "CL Audio Export",
                str(exc),
            )


def main() -> int:
    app = ShowAudioBuilderDesktop()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
