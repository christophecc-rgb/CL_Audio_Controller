import tempfile
from pathlib import Path
from showcue_builder import save_builder_document, load_builder_document


def test_batch_fields_and_manual_group_order_survive_reload():
    cues = [{'id': f'builder_batch{i}', 'text': f'Cue {i}', 'phase': 'SHOW', 'section': 'SHOW', 'timecode': f'00:00:{i:02}:00', 'foh': True, 'lum': False} for i in range(12)]
    selected = cues[1:9]
    for cue in selected:
        cue.update(phase='PRESHOW', section='PRÉPA', type='ACTION', foh=False, lum=True)
    reordered = [cues[0], *cues[9:], *selected]
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'showcue_builder.json'
        save_builder_document(path, {'cues': reordered, 'distribution': []})
        result = load_builder_document(path)['cues']
        assert [c['id'] for c in result] == [c['id'] for c in reordered]
        for actual, expected in zip(result, reordered):
            for key in ['phase', 'section', 'timecode', 'foh', 'lum']:
                assert actual[key] == expected[key]
