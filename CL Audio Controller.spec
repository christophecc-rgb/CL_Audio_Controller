# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['launcher_control.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('app.py', '.'),
        ('remote_window.py', '.'),
        ('cl_audio_logo.png', '.'),
        ('templates', 'templates'),
        ('static', 'static'),
        ('assets', 'assets'),
        ('M4L', 'M4L'),
        ('arrangement_markers.json', '.'),
    ],
    hiddenimports=['osc_transport', 'ltc_receiver', 'pythonosc.dispatcher', 'pythonosc.osc_server', 'pythonosc.udp_client'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['markupsafe._speedups'],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='CL Audio Controller',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch='universal2',
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
    name='CL Audio Controller',
)
app = BUNDLE(
    coll,
    name='CL Audio Controller.app',
    icon='CL_AUDIO.icns',
    bundle_identifier='com.claudio.controller',
    info_plist={
        'CFBundleDisplayName': 'CL Audio Controller',
        'CFBundleShortVersionString': '2.0.0',
        'CFBundleVersion': '4',
        'NSHighResolutionCapable': True,
    },
)
