from tests import test_showcue_builder as builder_tests


class BuilderRemoteReadOnlyTests(builder_tests.ShowCueBuilderRouteTests):
    def test_remote_builder_readable_but_writes_refused(self):
        client = self.app_module.app.test_client()
        remote = {'REMOTE_ADDR': '192.168.1.70'}
        response = client.get('/show-info/builder', base_url='https://show.local:8443', environ_overrides=remote)
        assert response.status_code == 200
        assert 'CONSULTATION DISTANTE' in response.get_data(as_text=True)
        assert 'data-builder-local="false"' in response.get_data(as_text=True)
        assert client.get('/show-info/builder/document', environ_overrides=remote).status_code == 200
        for path, method in [('/show-info/builder/document', 'PUT'), ('/show-info/builder/import', 'POST'), ('/show-info/builder/import.pdf', 'POST'), ('/show-info/builder/import-distribution', 'POST'), ('/show-info/builder/sessions/import', 'POST'), ('/show-info/builder/showcue-import', 'POST')]:
            result = client.open(path, method=method, json={}, base_url='https://show.local:8443', environ_overrides=remote)
            assert result.status_code == 403
            assert result.json.get('message') or result.json.get('error')
        local = self.client.get('/show-info/builder')
        assert 'data-builder-local="true"' in local.get_data(as_text=True)
        assert 'BUILDER — MODE LOCAL' in local.get_data(as_text=True)

    def test_even_authorized_remote_admin_cannot_write_builder(self):
        from unittest import mock
        manager = self.app_module.remote_security
        with mock.patch.object(manager, 'authorize', return_value={'id': 'remote', 'role': 'admin'}), mock.patch.dict(manager.admin_sessions, {'test-unlock': manager.clock() + 60}):
            result = self.client.put('/show-info/builder/document', json={}, base_url='https://show.local:8443', environ_overrides={'REMOTE_ADDR': '192.168.1.70'})
        assert result.status_code == 403
        assert 'poste local' in result.json['message']
