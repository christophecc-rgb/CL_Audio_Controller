import sys
from pathlib import Path

# PyInstaller peut exécuter ce .spec avec un cwd différent du dépôt.
# On force donc le dossier contenant le .spec dans sys.path.
_spec_dir = Path(SPECPATH).resolve()
if str(_spec_dir) not in sys.path:
    sys.path.insert(0, str(_spec_dir))

from release_version import bundle_version, bundle_build
# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['showcue_desktop.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=['webview'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['markupsafe._speedups', 'PIL'],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='CL ShowCue',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=__import__('os').environ.get('CL_BUILD_ARCH', 'universal2'),
    codesign_identity=None,
    entitlements_file=None,
    icon=['assets/app_icons/CL_ShowCue.icns'],
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name='CL ShowCue',
)

app = BUNDLE(
    coll,
    name='CL ShowCue.app',
    icon='assets/app_icons/CL_ShowCue.icns',
    bundle_identifier='com.claudio.showcue',
    info_plist={
        'CFBundleDisplayName': 'CL ShowCue',
        'CFBundleShortVersionString': bundle_version(),
        'CFBundleVersion': bundle_build(),
        'LSMinimumSystemVersion': '11.0', 'NSHighResolutionCapable': True,
    },
)
