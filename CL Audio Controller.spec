# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['launcher_control.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('app.py', '.'),
        ('device_profiles.py', '.'),
        ('show_cues.py', '.'),
        ('showcue_builder.py', '.'),
        ('console_title_library.py', '.'),
        ('remote_window.py', '.'),
        ('cl_audio_logo.png', '.'),
        ('templates', 'templates'),
        ('static', 'static'),
        ('assets', 'assets'),
        ('arrangement_markers.json', '.'),
        ('show_cues.json', '.'),
        ('show_cues_audio', 'show_cues_audio'),
    ],
    hiddenimports=['osc_transport', 'ltc_receiver', 'show_cues', 'showcue_builder', 'device_profiles', 'pythonosc.dispatcher', 'pythonosc.osc_server', 'pythonosc.udp_client'],
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
    name='CL Audio Show Control.app',
    icon='CL_AUDIO.icns',
    bundle_identifier='com.claudio.controller',
    info_plist={
        'CFBundleDisplayName': 'CL Audio Show Control',
        'CFBundleShortVersionString': '2.2.0',
        'CFBundleVersion': '6',
        'NSHighResolutionCapable': True,
    },
)
