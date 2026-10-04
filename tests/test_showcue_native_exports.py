"""The native export journey writes only temporary destinations, never user shows."""
import base64
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from showcue_builder_desktop import BuilderRecoveryApi


class NativeExportTests(unittest.TestCase):
    def test_save_as_csv_xlsx_and_archive_in_chosen_desktop(self):
        with tempfile.TemporaryDirectory() as directory:
            desktop = Path(directory) / 'Bureau'
            desktop.mkdir()
            bridge = BuilderRecoveryApi()
            bridge.window = Mock()
            for suffix, payload in [('.csv', b'cue;nom\n1;Test'), ('.xlsx', b'PK spreadsheet'), ('.showcue', b'PK archive')]:
                target = desktop / ('Show' + suffix)
                bridge.window.create_file_dialog.return_value = (str(target),)
                result = bridge.save_export('Show'+suffix, base64.b64encode(payload).decode())
                self.assertEqual(result, {'status': 'saved', 'path': str(target)})
                self.assertEqual(target.read_bytes(), payload)
                self.assertEqual(bridge.window.create_file_dialog.call_args.kwargs['save_filename'], 'Show'+suffix)
            self.assertFalse(list(desktop.glob('.showcue-export-*')))

    def test_cancel_and_failed_write_do_not_report_success(self):
        bridge = BuilderRecoveryApi()
        bridge.window = Mock()
        bridge.window.create_file_dialog.return_value = None
        self.assertEqual(bridge.save_export('Show.csv', 'YQ=='), {'status': 'cancelled'})
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)/'Show.csv'
            target.write_bytes(b'old')
            bridge.window.create_file_dialog.return_value = (str(target),)
            with patch('showcue_builder_desktop.os.replace', side_effect=OSError('Disque indisponible')):
                result = bridge.save_export('Show.csv', 'YQ==')
            self.assertEqual(result['status'], 'error')
            self.assertEqual(target.read_bytes(), b'old')
            self.assertFalse(list(target.parent.glob('.showcue-export-*')))
        self.assertEqual(bridge.save_export('Show.exe', 'YQ==')['status'], 'error')

    def test_native_close_checks_webkit_off_the_cocoa_callback(self):
        import showcue_builder_desktop as desktop
        window = Mock()
        guard = desktop.BuilderCloseGuard(window)
        with patch.object(desktop.threading, 'Thread') as worker:
            self.assertFalse(guard())
            window.evaluate_js.assert_not_called()
            worker.return_value.start.assert_called_once()
            self.assertFalse(guard())  # A second request cannot open another prompt.
            self.assertEqual(worker.call_count, 1)
            check = worker.call_args.kwargs['target']
        window.evaluate_js.return_value = False
        check()
        window.destroy.assert_not_called()
        with patch.object(desktop.threading, 'Thread') as worker:
            self.assertFalse(guard())
            check = worker.call_args.kwargs['target']
        window.evaluate_js.return_value = True
        check()
        window.destroy.assert_called_once()
        self.assertTrue(guard())  # The approved second close can complete.

    def test_native_close_fallback_and_persistent_drafts_configuration(self):
        import showcue_builder_desktop as desktop
        from unittest.mock import MagicMock
        window = MagicMock()
        callbacks = []
        window.events.closing.__iadd__.side_effect = lambda callback: callbacks.append(callback)
        with patch.object(desktop, 'backend_available', return_value=True), patch.object(desktop.webview, 'create_window', return_value=window), patch.object(desktop.webview, 'start') as start:
            desktop.main()
        self.assertFalse(start.call_args.kwargs['private_mode'])
        self.assertTrue(start.call_args.kwargs['storage_path'].endswith('CueEditorWebView'))
        self.assertEqual(start.call_args.kwargs['localization']['global.saveFile'], 'Enregistrer sous…')
        window.evaluate_js.return_value = None
        window.create_confirmation_dialog.return_value = False
        with patch.object(desktop.threading, 'Thread') as worker:
            self.assertFalse(callbacks[0]())
            worker.call_args.kwargs['target']()
        window.destroy.assert_not_called()
