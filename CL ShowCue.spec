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
    excludes=[],
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
    target_arch='arm64',
    codesign_identity=None,
    entitlements_file=None,
    icon=['CL_AUDIO.icns'],
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
    icon='CL_AUDIO.icns',
    bundle_identifier='com.claudio.showcue',
    info_plist={
        'CFBundleDisplayName': 'CL ShowCue',
        'CFBundleShortVersionString': '1.0.0',
        'CFBundleVersion': '1',
        'NSHighResolutionCapable': True,
    },
)
