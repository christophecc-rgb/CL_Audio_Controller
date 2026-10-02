"""Run the real X-Fader function without importing/starting the backend."""
import ast
from pathlib import Path
import types
import unittest
from unittest.mock import Mock


class CrossfaderTargetTests(unittest.TestCase):
    def test_applied_host_routes_normalization_and_lazy_send(self):
        tree = ast.parse((Path(__file__).resolve().parents[1] / 'app.py').read_text())
        function = next(n for n in tree.body if isinstance(n, ast.FunctionDef)
                        and n.name == 'send_crossfader_m4l')
        transport = types.SimpleNamespace(host='127.0.0.1', send_to=Mock())
        scope = {'ableton_transport': transport, 'M4L_PORT': 9001,
                 'M4L_IP': '127.0.0.1', 'print': Mock()}
        exec(compile(ast.Module(body=[function], type_ignores=[]), '<crossfader>', 'exec'), scope)
        transport.send_to.assert_not_called()
        for host in ('127.0.0.1', 'MacBook-Pro.local', ''):
            transport.host = host
            for value, address, payload in ((-2, '/xfader/a', 1), (2, '/xfader/b', 1),
                                           (0, '/xfader/center', 1), (.4, '/xfader/value', .4)):
                with self.subTest(host=host, value=value):
                    self.assertTrue(scope['send_crossfader_m4l'](value)[0])
                    transport.send_to.assert_called_with(host or '127.0.0.1', 9001, address, payload)


if __name__ == '__main__':
    unittest.main()
