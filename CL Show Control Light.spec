import sys
from pathlib import Path

# PyInstaller peut exécuter ce .spec avec un cwd différent du dépôt.
_spec_dir = Path(SPECPATH).resolve()
if str(_spec_dir) not in sys.path:
    sys.path.insert(0, str(_spec_dir))

from release_version import bundle_version, bundle_build
# -*- mode: python ; coding: utf-8 -*-
# Only the dedicated local interface is shipped; FULL remains a separate bundle.
a = Analysis(
    ['launcher_light.py'], pathex=[], binaries=[],
    datas=[('templates/light.html', 'templates'),
           ('static/light.css', 'static'), ('static/light.js', 'static'),
           ('static/remote-auth.js', 'static'),
           ('static/remote-pair.html', 'static'), ('static/remote-pair.js', 'static'),
           ('static/remote-check.html', 'static'), ('static/remote-check.js', 'static'),
           ('static/security-panel.html', 'static'), ('static/security-panel.js', 'static')],
    hiddenimports=['webview.platforms.cocoa', 'app'],
    excludes=['PIL', 'markupsafe._speedups', 'light_runtime', 'light_timing', 'launcher_control', 'bonjour_remote',
              'webview.platforms.gtk', 'webview.platforms.qt',
              'PyQt5', 'PyQt6', 'PySide2', 'PySide6', 'gi'],
    noarchive=False, optimize=0,
)
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True,
          name='CL Show Control Light', console=False, strip=False, upx=False,
          argv_emulation=False, target_arch=__import__('os').environ.get('CL_BUILD_ARCH', 'universal2'), codesign_identity=None,
          icon='assets/app_icons/CL_Ableton.icns')
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False,
               name='CL Show Control Light')
app = BUNDLE(coll, name='CL Show Control Light.app',
             icon='assets/app_icons/CL_Ableton.icns',
             bundle_identifier='com.claudio.showcontrollight',
             info_plist={'CFBundleDisplayName': 'CL Show Control Light',
                         'CFBundleShortVersionString': bundle_version(),
                         'CFBundleVersion': bundle_build(), 'LSMinimumSystemVersion': '11.0',
                         'NSHighResolutionCapable': True})
