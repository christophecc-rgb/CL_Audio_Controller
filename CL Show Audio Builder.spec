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
    excludes=['markupsafe._speedups', 'PIL'], noarchive=False, optimize=0,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz, a.scripts, [], exclude_binaries=True, name='CL Show Audio Builder',
    debug=False, bootloader_ignore_signals=False, strip=False, upx=False,
    console=False, disable_windowed_traceback=False, argv_emulation=False,
    target_arch=__import__('os').environ.get('CL_BUILD_ARCH', 'universal2'), codesign_identity=None, entitlements_file=None,
    icon=['assets/app_icons/CL_Audio_Export.icns'],
)
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False,
               upx_exclude=[], name='CL Show Audio Builder')
app = BUNDLE(
    coll, name='CL Audio Export.app', icon='assets/app_icons/CL_Audio_Export.icns',
    bundle_identifier='com.claudio.showaudio.builder',
    info_plist={'CFBundleDisplayName': 'CL Audio Export',
                'CFBundleShortVersionString': '1.0.0',
                'CFBundleVersion': '1', 'LSMinimumSystemVersion': '12.0', 'NSHighResolutionCapable': True,
                'NSAppleEventsUsageDescription': 'Configurer les exports audio dans Ableton Live.'},
)
