# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['launcher_control.py'],
    pathex=[],
    binaries=[
        (
            'tools/ableton_mtc_bridge/CLAbletonMTCBridge',
            'tools/ableton_mtc_bridge',
        ),
    ],
    datas=[
        ('app.py', '.'),
        ('config/ableton_remote_discovery.json', 'config'),
        ('device_profiles.py', '.'),
        ('show_cues.py', '.'),
        ('showcue_builder.py', '.'),
        ('showcue_pdf_import.py', '.'),
        ('showcue_session_archive.py', '.'),
        ('cl_transport.py', '.'),
        ('resources/Console_Libraries', 'resources/Console_Libraries'),
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
    hiddenimports=['app', 'pypdf', 'showcue_pdf_import', 'showcue_session_archive', 'cl_transport', 'show_audio_print_engine', 'osc_transport', 'bonjour_remote', 'ltc_receiver', 'show_cues', 'showcue_builder', 'device_profiles', 'pythonosc.dispatcher', 'pythonosc.osc_server', 'pythonosc.udp_client'],
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
    name='CL Audio Controller',
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
    name='CL Show Control.app',
    icon='CL_AUDIO.icns',
    bundle_identifier='com.claudio.controller',
    info_plist={
        'CFBundleDisplayName': 'CL Show Control',
        'CFBundleShortVersionString': '2.2.0',
        'CFBundleVersion': '6',
        'LSMinimumSystemVersion': '11.0', 'NSHighResolutionCapable': True,
    },
)
