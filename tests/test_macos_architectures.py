import subprocess
import tempfile
import unittest
from pathlib import Path
from scripts.verify_macos_architectures import audit


class ArchitectureAuditTests(unittest.TestCase):
    def test_nested_arm_only_binary_is_rejected_even_with_universal_launcher(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'main.c'
            source.write_text('int main(void) { return 0; }\n')
            subprocess.run(['/usr/bin/clang', '-arch', 'arm64', '-arch', 'x86_64', str(source), '-o', str(root/'launcher')], check=True, capture_output=True)
            self.assertTrue(audit(root, 'universal2')['ok'])
            nested = root / 'Contents/Frameworks'
            nested.mkdir(parents=True)
            subprocess.run(['/usr/bin/lipo', str(root/'launcher'), '-thin', 'arm64', '-output', str(nested/'dependency')], check=True)
            report = audit(root, 'universal2')
            self.assertFalse(report['ok'])
            self.assertIn('Contents/Frameworks/dependency', report['errors'][0])
            self.assertTrue(audit(root, 'arm64')['ok'])
            self.assertFalse(audit(root, 'x86_64')['ok'])

    def test_empty_tree_is_not_reported_as_compatible(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertFalse(audit(directory, 'universal2')['ok'])
