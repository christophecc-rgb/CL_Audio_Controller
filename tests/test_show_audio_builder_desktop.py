from show_audio_builder_desktop import (
    find_scene_variant,
    format_duration,
    medley_groups_for_builder,
    status_label,
    upsert_scene_variant,
)


def test_format_duration_desktop():
    assert format_duration(266.1003) == "4:26.10"
    assert format_duration(None) == "—"


def test_status_label():
    assert status_label({"status": "ready"}) == "PRÊT"
    assert status_label(
        {"status": "no_playback"}
    ) == "SANS PLAYBACK"


def test_medley_groups_use_business_model_and_live_indices():
    document = {
        "medleys": [{
            "id": "medley_40_43",
            "title": "GIGI / NEVER / LOVE / DANCING QUEEN",
            "scene_numbers": [40, 41, 42, 43],
        }],
    }
    snapshot = {
        "scenes": [
            {
                "scene_index": index,
                "scene_name": title + " ; 120 ; C",
                "reference": {"duration_seconds": 10, "track_name": "PB"},
            }
            for index, title in zip(
                (39, 40, 41, 42),
                ("GIGI", "NEVER", "LOVE", "DANCING QUEEN"),
            )
        ],
    }

    groups = medley_groups_for_builder(document, snapshot)

    assert set(groups) == {39, 40, 41, 42}
    assert groups[39]["id"] == "medley_40_43"
    assert [part["title"] for part in groups[39]["parts"]] == [
        "GIGI", "NEVER", "LOVE", "DANCING QUEEN",
    ]


def test_find_scene_variant_unique():
    variants = [
        {
            "scene_index": 2,
            "role": "ROXY",
        },
        {
            "scene_index": 8,
            "role": "JADE",
        },
    ]

    result = find_scene_variant(
        variants,
        2,
    )

    assert result["role"] == "ROXY"


def test_upsert_scene_variant_creates_role_artist_mapping():
    document = {
        "version": 1,
        "revision": 0,
        "variants": [],
    }

    result = upsert_scene_variant(
        document,
        scene_index=2,
        scene_name="TOXIC ; BPM ; KEY ; 4:25",
        number="3",
        title="TOXIC",
        role="ROXY",
        artist="Mathilde",
        key="Gm",
        playback="TOXIC_Gm.wav",
    )

    assert len(result["variants"]) == 1

    variant = result["variants"][0]

    assert variant["role"] == "ROXY"
    assert variant["artist"] == "Mathilde"
    assert variant["key"] == "Gm"
    assert variant["playback"] == "TOXIC_Gm.wav"
    assert variant["scene_index"] == 2


def test_upsert_updates_same_role_artist_not_duplicate():
    document = {
        "version": 1,
        "revision": 0,
        "variants": [
            {
                "id": "old",
                "number": "3",
                "title": "TOXIC",
                "role": "ROXY",
                "artist": "Mathilde",
                "key": "Fm",
                "playback": "OLD.wav",
                "scene_index": 2,
                "scene_name": "TOXIC",
                "export": True,
            }
        ],
    }

    result = upsert_scene_variant(
        document,
        scene_index=2,
        scene_name="TOXIC",
        number="3",
        title="TOXIC",
        role="roxy",
        artist="mathilde",
        key="Gm",
        playback="NEW.wav",
    )

    assert len(result["variants"]) == 1
    assert result["variants"][0]["key"] == "Gm"
    assert result["variants"][0]["playback"] == "NEW.wav"


def test_same_scene_can_have_multiple_role_artist_variants():
    document = {
        "version": 1,
        "revision": 0,
        "variants": [],
    }

    document = upsert_scene_variant(
        document,
        scene_index=2,
        scene_name="TOXIC",
        number="3",
        title="TOXIC",
        role="ROXY",
        artist="Mathilde",
        key="Gm",
        playback="TOXIC_Gm.wav",
    )

    document = upsert_scene_variant(
        document,
        scene_index=2,
        scene_name="TOXIC",
        number="3",
        title="TOXIC",
        role="JADE",
        artist="Naomi",
        key="Am",
        playback="TOXIC_Am.wav",
    )

    assert len(document["variants"]) == 2


def test_unique_text_values_is_case_insensitive_and_preserves_first():
    from show_audio_builder_desktop import ShowAudioBuilderDesktop

    assert ShowAudioBuilderDesktop._unique_text_values(
        ["ROXY", "roxy", "", "JADE", "Roxy"]
    ) == (
        "ROXY",
        "JADE",
    )


def test_medley_ui_title_fallback():
    from show_audio_builder_desktop import ShowAudioBuilderDesktop

    instance = object.__new__(ShowAudioBuilderDesktop)

    assert instance._medley_ui_title({
        "title": "FRENCH CANCAN",
    }) == "FRENCH CANCAN"

    assert instance._medley_ui_title({
        "title": "",
    }) == "MEDLEY"


class Value:
    def __init__(self, value=None):
        self.value = value
    def get(self):
        return self.value
    def set(self, value):
        self.value = value


class Choice:
    def configure(self, **kwargs):
        self.values = kwargs.get("values")


class Tree:
    def __init__(self):
        self.rows = {}
    def get_children(self):
        return tuple(self.rows)
    def delete(self, iid):
        del self.rows[iid]
    def insert(self, parent, where, *, iid, **kwargs):
        assert iid not in self.rows
        self.rows[iid] = kwargs
    def selection_set(self, iid):
        self.selected = iid
    def see(self, iid):
        pass


def desktop_fixture():
    from show_audio_builder_desktop import ShowAudioBuilderDesktop
    app = object.__new__(ShowAudioBuilderDesktop)
    app.tree = Tree()
    app.export_selection_initialized = False
    app.export_selected_scene_indices = set()
    app.export_selected_medley_ids = set()
    app.current_item = None
    app.show_all_var = Value(True)
    app.export_medleys_var = Value(True)
    app.export_selection_summary_var = Value()
    app.variant_summary_var = Value()
    app.info_var = Value()
    for name in ("role", "artist", "key", "playback"):
        setattr(app, name + "_var", Value(""))
        setattr(app, name + "_combo", Choice())
    return app


def test_populate_inserts_one_banner_before_first_member_preserving_show_numbers():
    app = desktop_fixture()
    app.snapshot = {"scenes": []}
    app.document = {"medleys": [{"id": "disco", "title": "DISCO", "scene_numbers": [8, 9]}]}
    app.model = {"items": [
        {"scene_index": 40, "show_number": "8", "title": "GIGI", "exportable": True},
        {"scene_index": 41, "show_number": "9", "title": "NEVER", "exportable": True},
    ]}
    assert set(app._medley_ui_by_scene()) == {40, 41}
    app.populate_tree()
    assert app.tree.get_children() == ("medley-header-disco", "scene-40", "scene-41")
    banner = app.tree.rows["medley-header-disco"]
    assert "GIGI / NEVER" in banner["values"][3]
    assert app._scene_index_from_iid("medley-header-disco") is None
    assert app.export_selected_scene_indices == set()
    app.populate_tree()
    assert len(app.tree.rows) == 3
    app.export_medleys_var.set(False)
    app.populate_tree()
    assert len(app.tree.rows) == 3
    assert "medley" not in app.export_selection_summary_var.get()



def test_medley_full_selection_is_independent_from_member_scenes():
    app = desktop_fixture()

    app.export_selected_scene_indices = {
        40,
        41,
    }

    app._medley_ui_by_scene = lambda: {
        40: {
            "id": "disco",
        },
        41: {
            "id": "disco",
        },
    }

    app._refresh_export_marks = lambda: None

    app._toggle_medley_export_selection(
        "disco"
    )

    assert app.export_selected_medley_ids == {
        "disco"
    }

    assert app.export_selected_scene_indices == set()

    app._toggle_scene_export_selection(
        40
    )

    assert app.export_selected_medley_ids == set()
    assert app.export_selected_scene_indices == {
        40
    }


def test_clicking_second_member_drops_full_medley_selection():
    app = desktop_fixture()

    app.export_selected_medley_ids = {
        "disco"
    }

    app._medley_ui_by_scene = lambda: {
        40: {
            "id": "disco",
        },
        41: {
            "id": "disco",
        },
    }

    app._refresh_export_marks = lambda: None

    app._toggle_scene_export_selection(
        41
    )

    assert app.export_selected_medley_ids == set()
    assert app.export_selected_scene_indices == {
        41
    }


def test_medley_selection_summary_counts_only_selected_medleys():
    app = desktop_fixture()

    app.export_selected_scene_indices = {
        29
    }

    app.export_selected_medley_ids = {
        "disco"
    }

    app.invalidate_export_preparation = (
        lambda: None
    )

    app._update_export_selection_summary()

    assert (
        "1 scène sélectionnée"
        in app.export_selection_summary_var.get()
    )

    assert (
        "1 medley complet"
        in app.export_selection_summary_var.get()
    )


def test_medley_header_shows_its_own_selection_state():
    app = desktop_fixture()

    app.snapshot = {
        "scenes": [],
    }

    app.document = {
        "medleys": [{
            "id": "disco",
            "title": "DISCO",
            "scene_numbers": [8, 9],
        }],
    }

    app.model = {
        "items": [
            {
                "scene_index": 40,
                "show_number": "8",
                "title": "GIGI",
                "exportable": True,
            },
            {
                "scene_index": 41,
                "show_number": "9",
                "title": "NEVER",
                "exportable": True,
            },
        ],
    }

    app.export_selection_initialized = True
    app.export_selected_medley_ids = {
        "disco"
    }

    app.populate_tree()

    banner = app.tree.rows[
        "medley-header-disco"
    ]

    assert banner["values"][0] == "🟢 MEDLEY"


def test_prepare_medleys_are_never_included_implicitly():
    import inspect
    import show_audio_builder_desktop as desktop

    source = inspect.getsource(
        desktop.ShowAudioBuilderDesktop.prepare_export_ui
    )

    assert "selected_medley_ids" in source
    assert 'item.get("medley_id")' in source
    assert (
        'item.get("type") == "medley_full"'
        in source
    )

    assert "selected_full_medleys" in source
    assert "raise ValueError(" in source
    assert "selected_medley_ids" in source



def test_main_export_button_targets_selection_handler():
    import inspect
    import show_audio_builder_desktop as desktop

    source = inspect.getsource(
        desktop.ShowAudioBuilderDesktop._build_ui
    )

    assert "EXPORTER LA SÉLECTION" in source
    assert "command=self.request_export_selection_ui" in source


def test_export_selection_single_scene_uses_real_scene_path():
    app = desktop_fixture()

    app.export_preparation_valid = True
    app.export_workflow_state = "READY"
    app.export_selected_scene_indices = {29}
    app.export_selected_medley_ids = set()

    selected = {
        "scene_index": 29,
        "title": "ANNONCE",
        "exportable": True,
    }

    app.model = {
        "items": [selected],
    }

    app.current_item = None

    calls = []

    app.request_export_ui = lambda scene_only=False: calls.append(
        scene_only
    )

    app.request_export_selection_ui()

    assert app.current_item is selected
    assert calls == [True]


def test_export_selection_multiple_scenes_starts_prepared_batch_in_order():
    app = desktop_fixture()

    app.export_preparation_valid = True
    app.export_workflow_state = "READY"
    app.export_selected_scene_indices = {29, 30}
    app.export_selected_medley_ids = set()

    second = {
        "id": "scene_030",
        "type": "scene",
        "source_item": {
            "scene_index": 29,
            "scene_name": "ANNONCE",
        },
    }
    first = {
        "id": "scene_031",
        "type": "scene",
        "source_item": {
            "scene_index": 30,
            "scene_name": "TOXIC",
        },
    }

    app.prepared_export_job = {
        "batch_items": [second, first],
    }

    calls = []

    app._start_single_scene_export = (
        lambda items=None: calls.append(items)
    )

    app.request_export_selection_ui()

    assert calls == [[second, first]]


def test_export_selection_full_medley_starts_batch_once():
    app = desktop_fixture()
    app.export_preparation_valid = True
    app.export_workflow_state = "READY"
    app.export_selected_scene_indices = set()
    app.export_selected_medley_ids = {"disco"}
    item = {"type": "medley_full", "source_item": {"medley_id": "disco"}}
    app.prepared_export_job = {"batch_items": [item]}
    calls = []
    app._start_single_scene_export = lambda items=None: calls.append(items)
    app.request_export_selection_ui()
    assert calls == [[item]]


def test_variant_choices_and_exact_role_artist_fill_keep_blank_key():
    app = desktop_fixture()
    variants = [
        {"role": "Meneuse", "artist": "Jade", "key": "", "playback": "SUPREME (C)"},
        {"role": "Meneuse", "artist": "Mathilde", "key": "Gm", "playback": "SUPREME (B)"},
    ]
    app.document = {"variants": variants}
    app.current_item = {"scene_index": 32, "variants": variants}
    app.snapshot = {"scenes": [{"scene_index": 32, "clips": [
        {"playback_track": True, "track_on": False, "track_name": "New artist", "clip_name": "Muted option"},
        {"playback_track": False, "clip_name": "LTC"},
    ]}]}
    app._refresh_variant_choices()
    assert app.role_combo.values == ("Meneuse",)
    assert app.artist_combo.values == ("Jade", "Mathilde")
    assert app.key_var.get() == ""
    assert "Gm" in app.key_combo.values
    assert "Muted option" in app.playback_combo.values
    assert "New artist" in app.playback_combo.values
    assert "LTC" not in app.playback_combo.values
    app.role_var.set("Meneuse")
    app.artist_var.set("Jade")
    app.key_var.set("OLD")
    app._variant_identity_changed()
    assert app.key_var.get() == ""
    assert app.playback_var.get() == "SUPREME (C)"
    app.artist_var.set("Mathilde")
    app._variant_identity_changed()
    assert app.key_var.get() == "Gm"
    assert app.playback_var.get() == "SUPREME (B)"
    assert "Jade" in app.variant_summary_var.get()
    assert "Mathilde" in app.variant_summary_var.get()


def test_save_variant_immediately_refreshes_summary_choices_and_count(tmp_path, monkeypatch):
    import show_audio_builder_desktop as desktop
    from show_audio_model import build_show_audio_model
    from show_audio_builder import save_show_audio_document
    app = desktop_fixture()
    app.snapshot = {"scenes": [{"scene_index": 32, "scene_name": "3 - SUPREME"}]}
    app.document = {"variants": [], "medleys": [], "playback_tracks": ["PB"]}
    path = tmp_path / "show_audio.json"
    save_show_audio_document(path, app.document)
    monkeypatch.setattr(desktop, "CONFIG_PATH", path)
    app.model = build_show_audio_model(app.snapshot, app.document)
    app.current_item = app.model["items"][0]
    app.role_var.set("Meneuse")
    app.artist_var.set("Jade")
    app.playback_var.set("SUPREME (C)")
    app.save_variant()
    assert app.tree.rows["scene-32"]["values"][-1] == 1
    assert "SUPREME (C)" in app.variant_summary_var.get()
    assert "Jade" in app.artist_combo.values
    assert app.document["playback_tracks"] == ["PB"]
    app.key_var.set("Cm")
    app.save_variant()
    assert app.tree.rows["scene-32"]["values"][-1] == 1
    assert "Cm" in app.variant_summary_var.get()


def test_load_failure_is_visible_and_keeps_previous_model(monkeypatch):
    import queue
    import show_audio_builder_desktop as desktop
    app = desktop_fixture()
    app._loading = True
    app._load_results = queue.Queue()
    app._load_progress = queue.Queue()
    app._load_results.put((None, None, None, "HTTP snapshot indisponible"))
    app.reload_button = Choice()
    app.model = {"items": [{"scene_index": 32}]}
    errors = []
    monkeypatch.setattr(desktop.messagebox, "showerror", lambda *args: errors.append(args))
    app._poll_live_load()
    assert "HTTP snapshot indisponible" in app.info_var.get()
    assert app.model["items"] == [{"scene_index": 32}]
    assert not app._loading
    assert errors


def test_medley_editor_uses_live_numbers_even_when_show_number_differs():
    from show_audio_builder_desktop import upsert_medley_from_scenes
    from show_audio_medleys import build_medleys
    from show_audio_model import build_show_audio_model
    snapshot = {"scenes": [
        {"scene_index": 30, "scene_name": "1 - ALPHA", "reference": {"duration_seconds": 10}},
        {"scene_index": 31, "scene_name": "2 - BETA", "reference": {"duration_seconds": 12}},
    ]}
    model = build_show_audio_model(snapshot)
    original = {"variants": [], "playback_tracks": ["PB"], "revision": 4}
    document = upsert_medley_from_scenes(original, model, title="NEW", scene_indices=[31, 30])
    assert document["medleys"][0]["scene_numbers"] == [31, 32]
    assert document["medleys"][0]["numbering"] == "live"
    assert document["playback_tracks"] == ["PB"]
    assert "medleys" not in original
    assert document["revision"] == 5
    business = build_medleys(document, snapshot)[0]
    assert [part['scene_index'] for part in business['parts']] == [30, 31]
    assert business['status'] == 'ready'
    app = desktop_fixture()
    app.document, app.snapshot, app.model = document, snapshot, model
    assert set(app._medley_ui_by_scene()) == {30, 31}
    group = app._medley_ui_by_scene()[30]
    assert app._medley_ui_parts(group) == ["ALPHA", "BETA"]


def test_medley_editor_rejects_gaps_and_overlaps_and_updates_existing():
    import pytest
    from show_audio_builder_desktop import upsert_medley_from_scenes
    model = {"items": [{"scene_index": i} for i in range(4)]}
    with pytest.raises(ValueError, match="au moins deux"):
        upsert_medley_from_scenes({}, model, title="A", scene_indices=[0])
    with pytest.raises(ValueError, match="consécutifs"):
        upsert_medley_from_scenes({}, model, title="A", scene_indices=[0, 2])
    doc = upsert_medley_from_scenes({}, model, title="A", scene_indices=[0, 1])
    with pytest.raises(ValueError, match="appartient déjà"):
        upsert_medley_from_scenes(doc, model, title="B", scene_indices=[1, 2])
    existing_id = doc['medleys'][0]['id']
    doc['medleys'][0]['export_full'] = False
    updated = upsert_medley_from_scenes(doc, model, title="A revised", scene_indices=[1, 2], medley_id=existing_id)
    assert len(updated['medleys']) == 1
    assert updated['medleys'][0]['id'] == existing_id
    assert updated['medleys'][0]['scene_numbers'] == [2, 3]
    assert updated['medleys'][0]['export_full'] is False


def test_saving_medley_refreshes_banner_without_changing_variants(tmp_path, monkeypatch):
    import show_audio_builder_desktop as desktop
    from show_audio_builder import save_show_audio_document, load_show_audio_document
    from show_audio_model import build_show_audio_model
    app = desktop_fixture()
    app.snapshot = {"scenes": [
        {"scene_index": i, "scene_name": title}
        for i, title in zip((63, 64, 65, 66), ("DUA", "FREE", "PROUD", "CANT"))
    ]}
    app.document = {"variants": [{"scene_index": 63, "role": "R", "artist": "A", "playback": "PB"}], "playback_tracks": ["PB"]}
    path = tmp_path / 'show_audio.json'
    before = save_show_audio_document(path, app.document)
    monkeypatch.setattr(desktop, 'CONFIG_PATH', path)
    app.model = build_show_audio_model(app.snapshot, app.document)
    app.save_medley_definition('SECOND', [63, 64, 65, 66])
    saved = load_show_audio_document(path)
    assert saved['variants'] == before['variants']
    assert saved['playback_tracks'] == ['PB']
    assert saved['medleys'][0]['scene_numbers'] == [64, 65, 66, 67]
    assert app.tree.get_children()[0].startswith('medley-header-')
    assert app.tree.get_children()[1] == 'scene-63'


class ExportWidget:
    def __init__(self):
        self.options = {}
    def configure(self, **kwargs):
        self.options.update(kwargs)


def workflow_fixture():
    app = desktop_fixture()
    app.export_workflow_state = "IDLE"
    app.prepared_export_job = None
    app.export_preparation_valid = False
    app._loading = False
    for name in ("export_state_var", "export_counter_var", "scene_export_summary_var"):
        setattr(app, name, Value())
    for name in ("export_progress", "prepare_export_button", "launch_export_button",
                 "cancel_export_button", "export_scene_button"):
        setattr(app, name, ExportWidget())
    app.set_export_workflow_state("IDLE")
    return app


def test_export_workflow_states_and_invalidation():
    import pytest
    app = workflow_fixture()
    assert app.launch_export_button.options['state'] == 'disabled'
    assert app.export_state_var.get() == 'À préparer'
    app.set_export_workflow_state('PREPARING')
    assert app.prepare_export_button.options['state'] == 'disabled'
    with pytest.raises(ValueError, match='absente'):
        app.set_export_workflow_state('READY')
    app.prepared_export_job = {'items': [1]}
    app.export_preparation_valid = True
    app.set_export_workflow_state('READY', total=22)
    assert app.launch_export_button.options['state'] == 'normal'
    app.set_export_workflow_state('EXPORTING', current=7, total=22, title='PARIS MON AMOUR')
    assert app.export_state_var.get() == 'Export 7 / 22 — PARIS MON AMOUR'
    assert app.export_progress.options == {'maximum': 22, 'value': 7}
    assert app.launch_export_button.options['state'] == 'disabled'
    assert app.prepare_export_button.options['state'] == 'disabled'
    assert app.cancel_export_button.options['state'] == 'normal'
    app.set_export_workflow_state('DONE', current=22, total=22)
    assert app.cancel_export_button.options['state'] == 'disabled'
    app.invalidate_export_preparation()
    assert app.export_workflow_state == 'IDLE'
    assert app.export_progress.options['value'] == 0
    assert app.launch_export_button.options['state'] == 'disabled'
    app.set_export_workflow_state('ERROR', error='Connexion perdue')
    assert app.export_state_var.get() == 'Erreur export — Connexion perdue'
    assert app.launch_export_button.options['state'] == 'disabled'


def test_scene_export_request_connects_only_scene_path(monkeypatch):
    app = workflow_fixture()
    events = []
    starts = []

    app.event_generate = events.append

    app.request_export_ui()
    app.request_cancel_export_ui()

    assert not events

    app.export_preparation_valid = True
    app.prepared_export_job = {"batch_items": []}
    app.set_export_workflow_state("READY")

    app.current_item = {"exportable": False}
    app._refresh_scene_export_ui()

    assert app.export_scene_button.options["state"] == "disabled"

    app.request_export_ui(scene_only=True)

    assert not events

    app.current_item = {
        "exportable": True,
        "duration_seconds": 32,
        "reference_playback": {
            "track_name": "Tableaux",
            "clip_name": "ANNONCE",
        },
    }

    app._refresh_scene_export_ui()

    assert app.export_scene_button.options["state"] == "normal"
    assert "ANNONCE" in app.scene_export_summary_var.get()

    monkeypatch.setattr(
        app,
        "_start_single_scene_export",
        lambda: starts.append(True),
    )

    app.request_export_ui(scene_only=True)

    assert events == ["<<SceneExportRequested>>"]
    assert starts == [True]

    app.request_export_ui()

    assert events == [
        "<<SceneExportRequested>>",
        "<<ExportRequested>>",
    ]

    assert starts == [True]

    app.set_export_workflow_state("EXPORTING")
    app.request_cancel_export_ui()

    assert events[-1] == "<<ExportCancelRequested>>"



def test_prepare_batch_items_resolves_locator_from_audio_duration():
    app = workflow_fixture()

    app.snapshot = {
        "arrangement": {
            "markers": [
                {
                    "name": "3. Toxic ; BPM ; KEY ; 4:25",
                    "time": 6590.0,
                },
                {
                    "name": "4. AUTRE",
                    "time": 7000.0,
                },
            ],
            "tempo": 120.0,
        },
        "set": {
            "name": "S8. v12 tdest",
            "generation": 1,
            "ready": True,
        },
    }

    job = {
        "settings": {
            "sample_rate": 48000,
            "normalize": False,
        },
        "items": [{
            "id": "scene_004",
            "type": "scene",
            "source_item": {
                "id": "scene_004",
                "type": "scene",
                "scene_index": 3,
                "scene_name": "TOXIC ; BPM ; KEY ; 4:25",
                "title": "TOXIC",
                "duration_seconds": 266.1003723144531,
            },
            "outputs": [{
                "kind": "final",
                "format": "wav",
                "settings": {
                    "format": "wav",
                    "bit_depth": "24",
                },
                "filename": "004 - TOXIC [wav_24].wav",
            }],
        }],
    }

    items = app._prepare_batch_items(job)

    assert len(items) == 1

    item = items[0]
    zone = item["zone"]

    assert item["id"] == "scene_004"
    assert zone["locator_name"] == "3. Toxic ; BPM ; KEY ; 4:25"
    assert zone["start_beats"] == 6590.0
    assert zone["duration_source"] == "audio_reference"
    assert zone["expected_duration_seconds"] == 266.1003723144531
    assert zone["duration_beats"] == 532.2007446289062

    assert item["settings"] == {
        "sample_rate": 48000,
        "normalize": False,
    }

    assert item["outputs"] == [{
        "format": "wav",
        "bit_depth": "24",
        "filename": "004 - TOXIC [wav_24].wav",
    }]


def test_prepare_batch_items_never_uses_next_locator_for_duration():
    app = workflow_fixture()

    app.snapshot = {
        "arrangement": {
            "markers": [
                {
                    "name": "50. In voyage",
                    "time": 29435.466797,
                },
                {
                    "name": "51. Top Voyage",
                    "time": 29509.464844,
                },
            ],
            "tempo": 120.0,
        },
        "set": {
            "generation": 1,
            "ready": True,
        },
    }

    duration = 31.9992733001709

    job = {
        "settings": {
            "sample_rate": 48000,
            "normalize": False,
        },
        "items": [{
            "id": "scene_voyage",
            "type": "scene",
            "source_item": {
                "scene_index": 49,
                "scene_name": "16 - in voyage",
                "title": "16 - in voyage",
                "duration_seconds": duration,
            },
            "outputs": [{
                "format": "wav",
                "settings": {
                    "format": "wav",
                    "bit_depth": "24",
                },
                "filename": "voyage.wav",
            }],
        }],
    }

    item = app._prepare_batch_items(job)[0]
    zone = item["zone"]

    expected_beats = duration * 120.0 / 60.0

    assert abs(zone["duration_beats"] - expected_beats) < 1e-9
    assert abs(
        zone["end_beats"]
        - (29435.466797 + expected_beats)
    ) < 1e-9

    next_locator = 29509.464844

    assert abs(
        zone["end_beats"] - next_locator
    ) > 1.0


def test_prepare_batch_items_flattens_mp3_settings():
    app = workflow_fixture()

    app.snapshot = {
        "arrangement": {
            "markers": [
                {
                    "name": "29. Annonce",
                    "time": 19390.220703,
                },
            ],
            "tempo": 120.0,
        },
        "set": {
            "generation": 1,
            "ready": True,
        },
    }

    job = {
        "settings": {
            "sample_rate": 48000,
            "normalize": False,
        },
        "items": [{
            "id": "annonce",
            "type": "scene",
            "source_item": {
                "scene_index": 29,
                "scene_name": "ANNONCE",
                "duration_seconds": 32.0,
            },
            "outputs": [{
                "format": "mp3",
                "settings": {
                    "format": "mp3",
                    "bitrate_kbps": 320,
                },
                "filename": "ANNONCE.mp3",
            }],
        }],
    }

    item = app._prepare_batch_items(job)[0]

    assert item["zone"]["expected_duration_seconds"] == 32.0
    assert item["zone"]["duration_beats"] == 64.0
    assert item["outputs"][0]["bitrate_kbps"] == 320
    assert item["outputs"][0]["filename"] == "ANNONCE.mp3"



def test_export_selection_is_remapped_by_business_identity():
    app = workflow_fixture()

    app.model = {
        "items": [{
            "scene_index": 2,
            "scene_name": "3 - TOXIC",
        }],
    }

    app.export_selected_scene_indices = {2}

    keys = app._selected_export_business_keys()

    fresh_model = {
        "items": [{
            "scene_index": 3,
            "scene_name": "TOXIC ; BPM ; KEY ; 4:25",
        }],
    }

    remapped = app._remap_export_selection(
        fresh_model,
        keys,
    )

    assert keys == frozenset({"toxic"})
    assert remapped == {3}


def test_export_selection_remap_rejects_missing_scene():
    import pytest

    app = workflow_fixture()

    with pytest.raises(
        ValueError,
        match="absente du Set frais",
    ):
        app._remap_export_selection(
            {"items": []},
            frozenset({"toxic"}),
        )


def test_export_selection_remap_rejects_ambiguous_scene():
    import pytest

    app = workflow_fixture()

    model = {
        "items": [
            {
                "scene_index": 3,
                "scene_name": "TOXIC",
            },
            {
                "scene_index": 47,
                "scene_name": "TOXIC",
            },
        ],
    }

    with pytest.raises(
        ValueError,
        match="ambiguë",
    ):
        app._remap_export_selection(
            model,
            frozenset({"toxic"}),
        )


def test_fresh_export_context_uses_new_live_snapshot(monkeypatch):
    import show_audio_builder_desktop as desktop

    app = workflow_fixture()

    class FakeBuilder:
        def __init__(self, **kwargs):
            self.kwargs = kwargs

        def status(self):
            return {
                "scenes": {
                    "3": {},
                    "4": {},
                },
            }

        def build(self, indices):
            assert indices == [3, 4]

            return {
                "version": 2,
                "arrangement": {
                    "markers": [
                        {
                            "name": "3. Toxic",
                            "time": 6590.0,
                        },
                    ],
                    "tempo": 120.0,
                },
                "set": {
                    "name": "FRESH SET",
                    "generation": 42,
                    "ready": True,
                },
                "scenes": [],
                "playback_tracks": [],
                "metrics": {},
            }

    monkeypatch.setattr(
        desktop,
        "ShowAudioSnapshotBuilder",
        FakeBuilder,
    )

    monkeypatch.setattr(
        desktop,
        "CONFIG_PATH",
        desktop.Path("/tmp/does-not-exist-show-audio.json"),
    )

    monkeypatch.setattr(
        desktop,
        "build_show_audio_model",
        lambda snapshot, document: {
            "items": [],
            "metrics": {
                "exportable_count": 0,
            },
        },
    )

    snapshot, document, model = app._fresh_export_context()

    assert snapshot["set"]["generation"] == 42
    assert snapshot["set"]["name"] == "FRESH SET"
    assert snapshot["arrangement"]["tempo"] == 120.0
    assert isinstance(document, dict)
    assert model["items"] == []



def test_current_scene_resolves_exactly_one_prepared_batch_item():
    app = workflow_fixture()

    app.current_item = {
        "scene_index": 3,
        "scene_name": "TOXIC",
        "exportable": True,
    }

    app.prepared_export_job = {
        "batch_items": [{
            "id": "scene_004",
            "type": "scene",
            "source_item": {
                "scene_index": 3,
                "scene_name": "3. Toxic ; BPM ; KEY ; 4:25",
            },
            "zone": {
                "start_beats": 6590.0,
                "duration_beats": 532.2007446289062,
            },
            "outputs": [{
                "format": "wav",
                "filename": "004 - TOXIC.wav",
            }],
        }],
    }

    item = app._prepared_batch_item_for_current_scene()

    assert item["id"] == "scene_004"


def test_current_scene_rejects_item_not_in_prepared_job():
    import pytest

    app = workflow_fixture()

    app.current_item = {
        "scene_index": 3,
        "scene_name": "TOXIC",
        "exportable": True,
    }

    app.prepared_export_job = {
        "batch_items": [{
            "id": "annonce",
            "type": "scene",
            "source_item": {
                "scene_name": "ANNONCE",
            },
        }],
    }

    with pytest.raises(
        ValueError,
        match="n'appartient pas",
    ):
        app._prepared_batch_item_for_current_scene()


def test_single_scene_worker_rejects_generation_change(monkeypatch, tmp_path):
    import show_audio_builder_desktop as desktop

    app = workflow_fixture()

    class FakeBuilder:
        def __init__(self, **kwargs):
            pass

        def status(self):
            return {
                "set_ready": True,
                "set_generation": 12,
                "current_set_name": "SHOW",
            }

    monkeypatch.setattr(
        desktop,
        "ShowAudioSnapshotBuilder",
        FakeBuilder,
    )

    called = []

    monkeypatch.setattr(
        desktop,
        "execute_batch_item",
        lambda *args, **kwargs: called.append((args, kwargs)),
    )

    app._run_single_scene_export(
        {"id": "toxic"},
        tmp_path,
        11,
        "SHOW",
        120.0,
    )

    kind, error, directory = app._scene_export_results.get_nowait()

    assert kind == "error"
    assert "a changé" in error
    assert "génération préparée=11" in error
    assert "génération actuelle=12" in error
    assert called == []


def test_single_scene_worker_calls_engine_once_after_generation_check(
    monkeypatch,
    tmp_path,
):
    import show_audio_builder_desktop as desktop

    app = workflow_fixture()

    class FakeBuilder:
        def __init__(self, **kwargs):
            pass

        def status(self):
            return {
                "set_ready": True,
                "set_generation": 42,
                "current_set_name": "SHOW",
            }

    monkeypatch.setattr(
        desktop,
        "ShowAudioSnapshotBuilder",
        FakeBuilder,
    )

    calls = []

    def fake_execute(item, **kwargs):
        calls.append((item, kwargs))
        return {
            "id": item["id"],
            "status": "completed",
            "outputs": [{
                "format": "wav",
                "path": str(tmp_path / "TOXIC.wav"),
            }],
        }

    monkeypatch.setattr(
        desktop,
        "execute_batch_item",
        fake_execute,
    )

    item = {
        "id": "scene_004",
        "type": "scene",
    }

    app._run_single_scene_export(
        item,
        tmp_path,
        42,
        "SHOW",
        120.0,
    )

    assert len(calls) == 1
    assert calls[0][0] is item
    assert calls[0][1]["output_directory"] == tmp_path
    assert calls[0][1]["tempo"] == 120.0

    kind, result, directory = app._scene_export_results.get_nowait()

    assert kind == "result"
    assert result["status"] == "completed"


def test_start_single_scene_export_uses_background_thread(
    monkeypatch,
    tmp_path,
):
    import show_audio_builder_desktop as desktop

    app = workflow_fixture()

    app.current_item = {
        "scene_index": 3,
        "scene_name": "TOXIC",
        "exportable": True,
    }

    batch_item = {
        "id": "scene_004",
        "type": "scene",
        "source_item": {
            "scene_index": 3,
            "scene_name": "TOXIC",
        },
        "outputs": [{
            "format": "wav",
            "filename": "TOXIC.wav",
        }],
    }

    app.prepared_export_job = {
        "set_generation": 42,
        "set_name": "SHOW",
        "tempo": 120.0,
        "batch_items": [batch_item],
    }

    app.export_preparation_valid = True
    app.set_export_workflow_state(
        "READY",
        total=1,
    )

    monkeypatch.setattr(
        desktop.filedialog,
        "askdirectory",
        lambda **kwargs: str(tmp_path),
    )

    started = []

    class FakeThread:
        def __init__(
            self,
            target,
            args,
            daemon,
        ):
            self.target = target
            self.args = args
            self.daemon = daemon

        def start(self):
            started.append(
                (self.target, self.args, self.daemon)
            )

    monkeypatch.setattr(
        desktop.threading,
        "Thread",
        FakeThread,
    )

    scheduled = []

    app.after = lambda delay, callback: scheduled.append(
        (delay, callback)
    )

    app._start_single_scene_export()

    assert app.export_workflow_state == "EXPORTING"
    assert len(started) == 1
    assert started[0][0] == app._run_single_scene_export
    assert started[0][1][0] is batch_item
    assert started[0][1][2] == 42
    assert started[0][1][4] == 120.0
    assert started[0][2] is True
    assert scheduled[0][1] == app._poll_single_scene_export


def test_global_export_request_still_does_not_run_engine(monkeypatch):
    import show_audio_builder_desktop as desktop

    app = workflow_fixture()

    app.export_preparation_valid = True
    app.prepared_export_job = {
        "batch_items": [{"id": "scene_004"}],
    }

    app.set_export_workflow_state(
        "READY",
        total=1,
    )

    events = []
    app.event_generate = events.append

    monkeypatch.setattr(
        desktop,
        "execute_batch_item",
        lambda *args, **kwargs: (_ for _ in ()).throw(
            AssertionError("Le moteur ne doit pas être appelé")
        ),
    )

    app.request_export_ui(scene_only=False)

    assert events == ["<<ExportRequested>>"]
    assert app.export_workflow_state == "READY"


def test_prepare_export_uses_existing_builders(monkeypatch):
    import show_audio_builder_desktop as desktop
    app = workflow_fixture()
    app.document, app.snapshot = {}, {}
    app.export_selected_scene_indices = {3}
    app.current_export_settings = lambda: {}
    app.update_idletasks = lambda: None
    monkeypatch.setattr(desktop, 'build_export_plan', lambda *args: {'items': [{'scene_index': 3}]})
    def build(plan, settings):
        assert app.export_workflow_state == 'PREPARING'
        assert len(plan['items']) == 1
        return {'metrics': {'selected_item_count': 1, 'final_output_count': 1}}
    monkeypatch.setattr(desktop, 'build_export_job', build)
    monkeypatch.setattr(
        app,
        '_prepare_batch_items',
        lambda job, snapshot=None: [],
    )
    monkeypatch.setattr(desktop.messagebox, 'showinfo', lambda *args: None)

    app.model = {
        'items': [{
            'scene_index': 3,
            'scene_name': 'TOXIC',
        }],
    }

    fresh_snapshot = {
        'arrangement': {
            'tempo': 120.0,
            'markers': [],
        },
        'set': {
            'name': 'TEST SET',
            'generation': 7,
        },
    }

    fresh_model = {
        'items': [{
            'scene_index': 3,
            'scene_name': 'TOXIC',
        }],
    }

    monkeypatch.setattr(
        app,
        '_fresh_export_context',
        lambda: (fresh_snapshot, {}, fresh_model),
    )

    app.populate_tree = lambda: None
    app._refresh_variant_choices = lambda: None
    app._refresh_variant_summary = lambda: None
    app._refresh_export_marks = lambda: None

    app.prepare_export_ui()
    assert app.export_workflow_state == 'READY'
    assert app.launch_export_button.options['state'] == 'normal'


def test_fresh_context_reuses_only_matching_identity_and_document(monkeypatch):
    import show_audio_builder_desktop as desktop
    from copy import deepcopy
    app = workflow_fixture()
    app.document = desktop.normalize_show_audio_document({})
    app.snapshot = {'set': {'server_instance_id': 'server', 'id': '/set.als',
                           'generation': 42, 'name': 'SET'},
                    'arrangement': {'markers': []}, 'scenes': []}
    status = {'server_instance_id': 'server', 'current_set_id': '/set.als',
              'set_generation': 42, 'current_set_name': 'SET', 'set_ready': True,
              'scenes': {'0': 'ANNONCE'}}
    scans = []

    class Builder:
        def __init__(self, **kwargs): pass
        def status(self): return status
        def build(self, indices):
            scans.append(indices)
            snapshot = deepcopy(app.snapshot)
            snapshot['set'].update(server_instance_id=status['server_instance_id'],
                id=status['current_set_id'], generation=status['set_generation'], name=status['current_set_name'])
            return snapshot

    monkeypatch.setattr(desktop, 'ShowAudioSnapshotBuilder', Builder)
    monkeypatch.setattr(desktop, 'CONFIG_PATH', desktop.Path('/tmp/cl-no-config-for-cache-test.json'))
    monkeypatch.setattr(desktop, 'build_show_audio_model', lambda snapshot, document: {'items': []})
    snapshot, _, _ = app._fresh_export_context()
    assert snapshot is app.snapshot
    assert scans == []
    for key, value in [('server_instance_id', 'new-server'), ('current_set_id', '/other.als'),
                       ('set_generation', 43), ('current_set_name', 'OTHER'), ('set_ready', False)]:
        old = status[key]
        status[key] = value
        app._fresh_export_context()
        status[key] = old
    assert len(scans) == 5
    app.document = {'changed': True}
    app._fresh_export_context()
    assert len(scans) == 6


def test_scroll_large_deltas_are_bounded():
    from types import SimpleNamespace
    from show_audio_builder_desktop import scroll_units
    for system in ('aqua', 'win32', 'x11'):
        assert scroll_units(SimpleNamespace(delta=12000), system) == -3
        assert scroll_units(SimpleNamespace(delta=-12000), system) == 3
        assert scroll_units(SimpleNamespace(delta=0), system) == 0
    assert scroll_units(SimpleNamespace(delta=120), 'win32') == -1
    assert scroll_units(SimpleNamespace(num=4), 'x11') == -1
    assert scroll_units(SimpleNamespace(num=5), 'x11') == 1


def test_export_watchdog_reports_error_and_ignores_late_success(monkeypatch):
    import show_audio_builder_desktop as desktop
    app = workflow_fixture()
    app._scene_export_deadline = 10
    app.after = lambda *args: None
    monkeypatch.setattr(desktop.time, 'monotonic', lambda: 11)
    app._poll_single_scene_export()
    assert app.export_workflow_state == 'ERROR'
    assert app._scene_export_timed_out
    app._get_scene_export_results().put(('result', {'status': 'completed'}, '/tmp'))
    app._poll_single_scene_export()
    assert app.export_workflow_state == 'ERROR'
    assert not app._scene_export_timed_out


def test_full_medley_preparation_through_batch_outputs(monkeypatch, tmp_path):
    import wave
    import pytest
    from pathlib import Path
    import show_audio_builder_desktop as desktop
    import show_audio_batch_export as batch
    from show_audio_export_settings import default_export_settings
    app = workflow_fixture()
    app.export_selected_scene_indices = set()
    app.export_selected_medley_ids = {"sing"}
    scenes = [{"scene_index": i + 39, "scene_name": name,
               "reference": {"duration_seconds": 1.0}}
              for i, name in enumerate(["GIGI", "NEVER", "LOVE", "DANCING QUEEN"])]
    snapshot = {"scenes": scenes, "set": {"generation": 42, "name": "SHOW"},
                "arrangement": {"tempo": 120, "markers": [
                    {"name": scene["scene_name"], "time": 10 + i * 2}
                    for i, scene in enumerate(scenes)] + [{"name": "NEXT", "time": 1000}]}}
    document = {"medleys": [{"id": "sing", "title": "SING SING",
                            "scene_numbers": [40, 41, 42, 43]}]}
    app.model = {"items": scenes}
    app.current_item = None
    settings = default_export_settings()
    settings["formats"] = [{"format": "mp3", "bitrate_kbps": 320}, {"format": "wav", "bit_depth": 24}]
    app.current_export_settings = lambda: settings
    app._fresh_export_context = lambda: (snapshot, document, {"items": scenes})
    for method in ["update_idletasks", "populate_tree", "_refresh_variant_choices", "_refresh_variant_summary", "_refresh_export_marks"]:
        setattr(app, method, lambda: None)
    monkeypatch.setattr(desktop.messagebox, "showerror", lambda *args: pytest.fail(str(args)))
    monkeypatch.setattr(desktop.messagebox, "showinfo", lambda *args: None)
    app.prepare_export_ui()
    assert app.export_workflow_state == "READY"
    assert app.export_selected_medley_ids == {"sing"}
    assert app.export_selected_scene_indices == set()
    items = app.prepared_export_job["batch_items"]
    assert len(items) == 1
    item = items[0]
    assert item["type"] == "medley_full"
    assert item["source_item"]["filename_stem"] == "MEDLEY 040-043 - SING SING"
    assert item["zone"]["scene_numbers"] == [40, 41, 42, 43]
    assert (item["zone"]["start_beats"], item["zone"]["end_beats"]) == (10, 18)
    assert item["zone"]["expected_duration_seconds"] == 4
    renders, encodes, calls = [], [], []
    def render(**kwargs):
        renders.append(kwargs)
        with wave.open(str(kwargs["output_path"]), "wb") as wav:
            wav.setparams((2, 3, 48000, 0, "NONE", "not compressed"))
            wav.writeframes(b"\0" * 4 * 48000 * 6)
        return {"status": batch.OFFLINE_SUCCESS}
    def encode(master, target, **kwargs):
        encodes.append(master)
        target.write_bytes(b"fake mp3" * 200)
        return {"path": str(target), "format": "mp3"}
    monkeypatch.setattr(batch, "execute_offline_wav", render)
    monkeypatch.setattr(batch, "encode_mp3", encode)
    def execute(item, **kwargs):
        calls.append(item)
        return batch.execute_batch_item(item, **kwargs)
    monkeypatch.setattr(desktop, "execute_batch_item", execute)
    class Builder:
        def __init__(self, **kwargs): pass
        def status(self):
            return {"set_ready": True, "set_generation": 42, "current_set_name": "SHOW"}
    monkeypatch.setattr(desktop, "ShowAudioSnapshotBuilder", Builder)
    monkeypatch.setattr(desktop.filedialog, "askdirectory", lambda **kwargs: str(tmp_path))
    class Thread:
        def __init__(self, target, args, daemon): self.target, self.args = target, args
        def start(self): self.target(*self.args)
    monkeypatch.setattr(desktop.threading, "Thread", Thread)
    app.after = lambda *args: None
    app.request_export_selection_ui()
    kind, result, _ = app._get_scene_export_results().get_nowait()
    assert kind == "result" and result["status"] == "completed"
    assert calls == [item]
    assert len(renders) == 1 and encodes == [renders[0]["output_path"]]
    assert {Path(o["path"]).name for o in result["outputs"]} == {
        "Medley SING SING.mp3", "Medley SING SING.wav"}
    assert not renders[0]["output_path"].exists()


def test_medley_batch_stops_on_failure(monkeypatch, tmp_path):
    import show_audio_builder_desktop as desktop
    app = workflow_fixture()
    class Builder:
        def __init__(self, **kwargs): pass
        def status(self):
            return {"set_ready": True, "set_generation": 42, "current_set_name": "SHOW"}
    monkeypatch.setattr(desktop, "ShowAudioSnapshotBuilder", Builder)
    items = [{"id": "first", "type": "medley_full"}, {"id": "second", "type": "medley_full"}]
    for fail in (False, True):
        calls = []
        def execute(item, **kwargs):
            calls.append(item)
            return {"status": "failed" if fail else "completed", "outputs": []}
        monkeypatch.setattr(desktop, "execute_batch_item", execute)
        app._run_single_scene_export(items, tmp_path, 42, "SHOW", 120)
        _, result, _ = app._get_scene_export_results().get_nowait()
        assert calls == (items[:1] if fail else items)
        assert result["status"] == ("failed" if fail else "completed")


def test_prepare_incomplete_medley_reports_error_without_starting(monkeypatch):
    import show_audio_builder_desktop as desktop
    from show_audio_export_settings import default_export_settings
    app = workflow_fixture()
    app.export_selected_scene_indices = set()
    app.export_selected_medley_ids = {"incomplete"}
    app.model = {"items": []}
    app.current_export_settings = default_export_settings
    app.update_idletasks = lambda: None
    app._fresh_export_context = lambda: ({"scenes": []}, {"medleys": [
        {"id": "incomplete", "title": "Missing", "scene_numbers": [1, 2]}]}, {"items": []})
    errors = []
    monkeypatch.setattr(desktop.messagebox, "showerror", lambda *args: errors.append(args))
    app.prepare_export_ui()
    assert app.export_workflow_state == "ERROR"
    assert "Medley incomplet" in errors[0][1]
    assert app.prepared_export_job is None
