"""Navigation QR cannot create or broaden remote access."""
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from flask import Flask
from security_http import attach_security

class ShowCueAccessTests(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory()
        self.app=Flask(__name__)
        self.manager=attach_security(self.app,directory=Path(self.directory.name))
        self.client=self.app.test_client()
        self.app.extensions['cl_remote_tls'].snapshot=lambda:{'ready':True,'server_url':'https://show.local:8443'}
    def tearDown(self): self.directory.cleanup()
    def test_qr_uses_configured_url_without_grant(self):
        before=(dict(self.manager.devices),dict(self.manager.admin_sessions),self.manager.armed,self.manager.mode)
        result=self.client.get('/security/showcue-qr',base_url='http://127.0.0.1:5050')
        self.assertEqual(result.status_code,200)
        self.assertEqual(result.json['url'],'https://show.local:8443/show-info')
        self.assertIn('<svg',result.json['svg'])
        self.assertEqual(before,(dict(self.manager.devices),dict(self.manager.admin_sessions),self.manager.armed,self.manager.mode))
    def test_remote_cannot_request_qr(self):
        result=self.client.get('/security/showcue-qr',base_url='http://show.local:8443',environ_overrides={'REMOTE_ADDR':'192.168.1.8'})
        self.assertEqual(result.status_code,403)
    def test_inactive_tls_and_launcher_do_not_provide_qr(self):
        self.app.extensions['cl_remote_tls'].snapshot=lambda:{'ready':False}
        self.assertEqual(self.client.get('/security/showcue-qr',base_url='http://127.0.0.1:5050').status_code,403)
        app=Flask('launcher');attach_security(app,launcher=True,directory=Path(self.directory.name))
        self.assertEqual(app.test_client().get('/security/showcue-qr',base_url='http://127.0.0.1:5055').status_code,403)

if __name__=='__main__': unittest.main()
