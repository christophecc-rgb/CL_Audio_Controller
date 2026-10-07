"""Dedicated ShowCue grants reuse the signed remote boundary, never admin access."""
import hashlib
import hmac
import json
import secrets
import unittest
from unittest import mock
from tests import test_show_cues as cue_tests
from remote_security import canonical_request, device_permissions
from show_cues import load_show_document


class ShowCuePermissionTests(cue_tests.ShowCueRouteTests):
    # Inherit fixture, but don't rerun every parent test in this module.
    def signed_request(self, path, payload, grants=None, posts=None, secure=True,
                       invalid=False, paired=True, method='PUT'):
        manager = self.app_module.remote_security
        if not hasattr(self, 'device'):
            code = manager.new_code('operator')
            pending = manager.request_pair(code, 'Test phone', 'Test operator')
            manager.approve(pending['request_id'])
            self.device = manager.claim(pending['request_id'], pending['claim'])
        if grants is not None:
            manager.change_permissions(self.device['device_id'], grants, posts or [])
        body = json.dumps(payload).encode()
        stamp = str(manager.clock()); nonce = secrets.token_hex(16)
        signature = hmac.new(hashlib.sha256(self.device['token'].encode()).digest(),
                             canonical_request(method, path, body, stamp, nonce), hashlib.sha256).hexdigest()
        headers = {'Content-Type': 'application/json'}
        if paired:
            headers.update({'X-CL-Device': self.device['device_id'], 'X-CL-Timestamp': stamp,
                            'X-CL-Nonce': nonce, 'X-CL-Signature': 'invalid' if invalid else signature})
        return self.app_module.app.test_client().open(path, method=method, data=body, headers=headers,
            base_url=('https' if secure else 'http')+'://show.local:8443',
            environ_overrides={'REMOTE_ADDR': '192.168.1.160'})

    def grants(self, **kwargs):
        return {'go': True, 'edit_cues': False, 'edit_notes': False, **kwargs}

    def test_remote_cue_grants_and_legacy_fallback(self):
        manager = self.app_module.remote_security; manager.set_armed(True)
        path = '/show-info/cues/cue_base'; payload = {'session_id': self.session_id, 'text': 'Changed'}
        self.assertEqual(self.signed_request(path, payload).status_code, 403)
        self.assertEqual(device_permissions(manager.devices[self.device['device_id']]), self.grants())
        # No admin unlock and show mode: dedicated grant still succeeds.
        manager.admin_sessions.clear(); manager.mode = 'show'
        result = self.signed_request(path, payload, self.grants(edit_cues=True))
        self.assertEqual(result.status_code, 200, result.json)
        self.assertEqual(result.json['cue']['text'], 'Changed')
        for options, reason in [({'secure':False}, 'HTTPS'), ({'invalid':True}, 'Signature'), ({'paired':False}, 'Appareil')]:
            result = self.signed_request(path, payload, **options)
            self.assertEqual(result.status_code, 403); self.assertIn(reason, result.json['error'])
        manager.set_armed(False)
        self.assertEqual(self.signed_request(path, payload).status_code, 403)

    def test_note_post_scope_merge_and_no_general_bypass(self):
        manager=self.app_module.remote_security; manager.set_armed(True)
        for post, text in [('GENERAL','General'), ('RETOURS','Returns'), ('PLATEAU','Stage')]:
            result=self.client.put('/show-info/cues/cue_base/notes/'+post,json={'session_id':self.session_id,'text':text})
            self.assertEqual(result.status_code,200,result.json)
        payload={'session_id':self.session_id,'text':'FOH line 1\nline 2'}
        result=self.signed_request('/show-info/cues/cue_base/notes/FOH',payload,self.grants(edit_notes=True),['FOH'])
        self.assertEqual(result.status_code,200,result.json)
        builder=result.json['cue']['builder']
        self.assertEqual(builder['notes'],'General')
        self.assertEqual(builder['notes_by_post'],{'FOH':payload['text'],'RETOURS':'Returns','PLATEAU':'Stage'})
        result=self.signed_request('/show-info/cues/cue_base/notes/LUMIERE',payload)
        self.assertEqual(result.status_code,403);self.assertIn('LUMIERE',result.json['error'])
        self.assertEqual(self.signed_request('/show-info/cues/cue_base/notes/GENERAL',payload).status_code,403)
        result=self.signed_request('/show-info/cues/cue_base',{'session_id':self.session_id,'builder':{'notes_by_post':{'LUMIERE':'bypass'}}},self.grants(edit_cues=True),['FOH'])
        self.assertEqual(result.status_code,403)
        # General partial edit cannot drop any post notes.
        result=self.signed_request('/show-info/cues/cue_base',{'session_id':self.session_id,'builder':{'notes':'New general'}})
        self.assertEqual(result.status_code,200,result.json)
        self.assertEqual(result.json['cue']['builder']['notes_by_post'],builder['notes_by_post'])

    def test_go_grant_does_not_grant_administration(self):
        manager=self.app_module.remote_security;manager.set_armed(True)
        result=self.signed_request('/action',{'action':'go'},self.grants(go=False),method='POST')
        self.assertEqual(result.status_code,403);self.assertIn('GO',result.json['error'])
        result=self.signed_request('/security/admin/arm',{'armed':False},method='POST')
        self.assertEqual(result.status_code,403)

    def test_create_delete_and_multiple_posts(self):
        manager=self.app_module.remote_security;manager.set_armed(True)
        result=self.signed_request('/show-info/cues',{'session_id':self.session_id,'mode':'manual','text':'New','posts':['FOH'],'section':'PRÉPARATION'},self.grants(edit_cues=True,edit_notes=True),['FOH','LUMIERE'],method='POST')
        self.assertEqual(result.status_code,201,result.json)
        cue=result.json['cue'];path='/show-info/cues/'+cue['id']
        result=self.signed_request(path+'/notes/LUMIERE',{'session_id':self.session_id,'text':'Light'})
        self.assertEqual(result.status_code,200,result.json)
        result=self.signed_request(path+'?session_id='+self.session_id,{},method='DELETE')
        self.assertEqual(result.status_code,200,result.json)

    def test_dedicated_grants_survive_reload_and_do_not_grant_admin(self):
        from remote_security import RemoteSecurity
        manager=self.app_module.remote_security;manager.set_armed(True)
        self.signed_request('/show-info/cues/cue_base',{'session_id':self.session_id,'text':'New'},self.grants(edit_notes=True),['FOH'])
        restored=RemoteSecurity(manager.directory);restored.load()
        record=restored.devices[self.device['device_id']]
        self.assertEqual(record['permissions'],self.grants(edit_notes=True))
        self.assertEqual(record['posts'],['FOH'])
        manager.admin_sessions.clear()
        result=self.signed_request('/network-config',{},method='POST')
        self.assertEqual(result.status_code,403)
        self.assertIn('déverrouillage',result.json['error'])

    def test_identity_diagnostics_never_echo_secret_headers(self):
        manager=self.app_module.remote_security;manager.set_armed(True)
        path='/show-info/cues/cue_base';payload={'session_id':self.session_id,'text':'Note'}
        missing=self.signed_request(path,payload,self.grants(edit_cues=True),paired=False)
        self.assertEqual(missing.status_code,403)
        self.assertFalse(missing.json['auth_diagnostic']['device_known'])
        self.assertTrue(missing.json['auth_diagnostic']['https'])
        self.assertTrue(all(value is False for value in missing.json['auth_diagnostic']['headers'].values()))
        invalid=self.signed_request(path,payload,invalid=True)
        self.assertEqual(invalid.status_code,403)
        details=invalid.json['auth_diagnostic']
        self.assertEqual(details['requested_device_id'],self.device['device_id'])
        self.assertTrue(details['device_known']);self.assertTrue(all(details['headers'].values()))
        self.assertNotIn(self.device['token'],invalid.get_data(as_text=True))
        unknown='f'*32
        result=self.app_module.app.test_client().put(path,json=payload,base_url='https://show.local:8443',environ_overrides={'REMOTE_ADDR':'192.168.1.160'},headers={'Origin':'https://show.local:8443','X-CL-Device':unknown,'X-CL-Signature':'DO-NOT-ECHO-SIGNATURE','X-CL-Nonce':'DO-NOT-ECHO-NONCE','X-CL-Timestamp':'123'})
        self.assertEqual(result.status_code,403)
        self.assertEqual(result.json['auth_diagnostic']['requested_device_id'],unknown)
        self.assertEqual(result.json['auth_diagnostic']['origin'],'https://show.local:8443')
        self.assertFalse(result.json['auth_diagnostic']['device_known'])
        self.assertNotIn('DO-NOT-ECHO',result.get_data(as_text=True))

    def test_note_session_and_strict_payload(self):
        for payload, status in [({'session_id':'wrong','text':'test'},409),
                                ({'session_id':self.session_id,'text':'test','builder':{}},400)]:
            result=self.client.put('/show-info/cues/cue_base/notes/FOH',json=payload)
            self.assertEqual(result.status_code,status,result.json)

# Parent test cases are already covered in tests/test_show_cues.py.
for _name in list(vars(cue_tests.ShowCueRouteTests)):
    if _name.startswith('test_'):
        setattr(ShowCuePermissionTests, _name, None)
