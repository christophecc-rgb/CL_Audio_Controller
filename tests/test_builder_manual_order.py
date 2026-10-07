import tempfile
from pathlib import Path
from showcue_builder import save_builder_document, load_builder_document


def test_manual_preshow_untimed_position_survives_save_reload():
    cues = [
        {'id': 'builder_p1', 'section': 'PRESHOW', 'timecode': '18:00:00:00', 'text': 'Début'},
        {'id': 'builder_pn', 'section': 'PRESHOW', 'timecode': '', 'text': 'Action manuelle'},
        {'id': 'builder_p2', 'section': 'PRESHOW', 'timecode': '18:10:00:00', 'text': 'Suite'},
        {'id': 'builder_e', 'section': 'ENTRACTE', 'text': 'Entracte'},
        {'id': 'builder_s', 'section': 'SHOW', 'timecode': '00:01:00:00', 'text': 'Show'},
        {'id': 'builder_f', 'section': 'FIN', 'text': 'Fin'},
    ]
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'showcue_builder.json'
        save_builder_document(path, {'cues': cues, 'distribution': []})
        assert [cue['id'] for cue in load_builder_document(path)['cues']] == ['builder_p1', 'builder_pn', 'builder_p2', 'builder_e', 'builder_s', 'builder_f']
