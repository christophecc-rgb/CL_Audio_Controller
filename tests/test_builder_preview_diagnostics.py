import io
from tests import test_showcue_builder as builder_tests
from showcue_builder import export_csv


class BuilderPreviewDiagnosticTests(builder_tests.ShowCueBuilderRouteTests):
    def test_import_save_preview_reports_incomplete_distribution_and_preserves_order(self):
        sections = [('PRE-SHOW', '18:00:00:00'), ('PRÉSHOW', ''), ('PRESHOW', '18:10:00:00'), ('ENTRACTE', ''), ('SHOW', '00:01:00:00'), ('SHOW', '00:25:00:00'), ('FIN', '')]
        document = {'cues': [{'id': f'builder_case{i}', 'section': section, 'timecode': tc, 'text': f'Action {i}', 'role': 'AVA'} for i, (section, tc) in enumerate(sections)],
                    'distribution': [{'role': 'AVA', 'artist': 'Oriane', 'active': True, 'equipment_slots': [{'type': 'MICRO', 'value': 'HF1'}, {'type': 'IEM', 'value': 'PSM1'}, {'type': 'ÉQUIPEMENT', 'value': ''}]}]}
        document['distribution'].append({'role': 'AVA', 'artist': 'Aurélia', 'active': False, 'equipment_slots': [{'type': 'MICRO', 'value': 'HF2'}, {'type': 'IEM', 'value': 'PSM2'}, {'type': 'ÉQUIPEMENT', 'value': ''}]})
        failed_import = self.client.post('/show-info/builder/import', data={'file': (io.BytesIO(export_csv(document)), 'case.csv')})
        assert failed_import.status_code == 400
        assert 'champ value vide' in failed_import.json['message']
        assert failed_import.json['diagnostics']['validation']['ready'] is False
        # Legacy documents already saved before strict import still receive the preview diagnostic.
        preview = document
        saved = self.client.put('/show-info/builder/document', json={'session_id': self.session_id, 'document': preview})
        assert saved.status_code == 200
        failed = self.client.post('/show-info/builder/showcue-preview', json={'session_id': self.session_id})
        assert failed.status_code == 400
        assert 'distribution index 1 (AVA / Oriane), équipement 3, champ value vide' in failed.json['message']
        assert 'distribution index 2 (AVA / Aurélia), équipement 3, champ value vide' in failed.json['message']
        # Explicit user correction, not a silent normalization of invalid data.
        corrected = saved.json['document']
        for row in corrected['distribution']:
            row['equipment_slots'][2]['value'] = 'Accessoire'
        accepted = self.client.put('/show-info/builder/document', json={'session_id': self.session_id, 'document': corrected})
        assert accepted.status_code == 200
        reloaded = self.client.get('/show-info/builder/document').json['document']
        assert [c['id'] for c in reloaded['cues']] == [c['id'] for c in preview['cues']]
        passed = self.client.post('/show-info/builder/showcue-preview', json={'session_id': self.session_id})
        assert passed.status_code == 200, passed.json

    def test_import_compatibility_diagnostics_are_returned_without_save(self):
        response = self.client.post('/show-info/builder/import', data={'file': (io.BytesIO('Titre\n\ntimecode;Téxte;Détail\n;Annonce;original\n'.encode('utf-8-sig')), 'numbers.csv')})
        assert response.status_code == 200, response.json
        assert response.json['saved'] is False
        assert response.json['diagnostics']['encoding'] == 'utf-8-sig'
        assert response.json['diagnostics']['conduite']['header_row'] == 3
        assert response.json['unknown_columns'] == ['Détail']
        assert response.json['document']['import_source']['tables'][0]['rows'][0][2] == 'original'

    def test_import_failure_returns_structured_missing_columns(self):
        response = self.client.post('/show-info/builder/import', data={'file': (io.BytesIO(b'TC;Notes\n;Test\n'), 'missing.csv')})
        assert response.status_code == 400
        assert response.json['diagnostics']['conduite_candidates'][0]['missing_columns'] == ['TEXTE']
