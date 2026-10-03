import tempfile
import unittest
from pathlib import Path
from remote_security import RemoteSecurity, SecurityError

class DevelopmentAccessTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.directory = Path(self.tmp.name)
        self.backend = RemoteSecurity(self.directory)
        self.backend.set_password('development-test-password', initial=True)
        self.launcher = RemoteSecurity(self.directory, namespace='launcher')
    def tearDown(self):
        self.tmp.cleanup()
    def test_persistent_access_shared_locally_after_restart(self):
        self.backend.unlock('development-test-password', duration='development')
        self.launcher.admin('', local=True)
        restarted = RemoteSecurity(self.directory)
        restarted.admin('', local=True)
        self.assertEqual(restarted.snapshot()['mode'], 'development')
        self.assertEqual(restarted.admin_status('')['mode'], 'development')
        self.assertFalse(restarted.armed)
        self.assertEqual((self.directory/'local-development.json').stat().st_mode & 0o777, 0o600)
    def test_persistent_access_does_not_authorize_remote_admin(self):
        token = self.backend.unlock('development-test-password', duration='development')
        with self.assertRaises(SecurityError): self.backend.admin(token)
        self.assertFalse(self.backend.admin_sessions)
    def test_lock_and_show_revoke_shared_access(self):
        for action in [lambda: self.backend.lock_admin(), lambda: self.backend.set_mode('show')]:
            self.backend.unlock('development-test-password', duration='development')
            self.launcher.admin('', local=True)
            action()
            with self.assertRaises(SecurityError): self.launcher.admin('', local=True)
            self.assertEqual(self.launcher.mode, 'show')
    def test_password_change_revokes_persistent_access(self):
        self.backend.unlock('development-test-password', duration='development')
        self.launcher.admin('', local=True)
        self.backend.set_password('new-development-password')
        with self.assertRaises(SecurityError): self.launcher.admin('', local=True)
    def test_wrong_password_and_normal_session_do_not_persist(self):
        with self.assertRaises(SecurityError): self.backend.unlock('wrong-password', duration='development')
        token = self.backend.unlock('development-test-password', duration='session')
        self.backend.admin(token)
        with self.assertRaises(SecurityError): self.launcher.admin('', local=True)
        self.assertFalse((self.directory/'local-development.json').exists())

if __name__ == '__main__': unittest.main()
