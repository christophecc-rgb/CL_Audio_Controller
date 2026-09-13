# -*- mode: python ; coding: utf-8 -*-

from pathlib import Path

project_root = Path(SPECPATH).resolve()
ffmpeg = project_root / 'vendor' / 'ffmpeg' / 'macos' / 'ffmpeg'

if not ffmpeg.is_file():
    raise RuntimeError(f'FFmpeg Universal 2 requis pour construire le bundle MP3: {ffmpeg}')

a = Analysis(
    ['show_audio_builder_desktop.py'],
    pathex=[], binaries=[(str(ffmpeg), '.')], datas=[('show_audio.json', '.')],
    hiddenimports=[], hookspath=[], hooksconfig={}, runtime_hooks=[],
    excludes=[], noarchive=False, optimize=0,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz, a.scripts, [], exclude_binaries=True, name='CL Show Audio Builder',
    debug=False, bootloader_ignore_signals=False, strip=False, upx=False,
    console=False, disable_windowed_traceback=False, argv_emulation=False,
    target_arch='arm64', codesign_identity=None, entitlements_file=None,
    icon=['CL_AUDIO.icns'],
)
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False,
               upx_exclude=[], name='CL Show Audio Builder')
app = BUNDLE(
    coll, name='CL Show Audio Builder.app', icon='CL_AUDIO.icns',
    bundle_identifier='com.claudio.showaudio.builder',
    info_plist={'CFBundleDisplayName': 'CL Show Audio Builder',
                'CFBundleShortVersionString': '1.0.0',
                'CFBundleVersion': '1', 'NSHighResolutionCapable': True,
                'NSAppleEventsUsageDescription': 'Configurer les exports audio dans Ableton Live.'},
)
