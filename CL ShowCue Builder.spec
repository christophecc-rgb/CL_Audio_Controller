# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['showcue_builder_desktop.py'],
    pathex=[], binaries=[], datas=[],
    hiddenimports=['webview'], hookspath=[], hooksconfig={}, runtime_hooks=[],
    excludes=['markupsafe._speedups', 'PIL'], noarchive=False, optimize=0,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz, a.scripts, [], exclude_binaries=True, name='CL ShowCue Builder',
    debug=False, bootloader_ignore_signals=False, strip=False, upx=False,
    console=False, disable_windowed_traceback=False, argv_emulation=False,
    target_arch=__import__('os').environ.get('CL_BUILD_ARCH', 'universal2'), codesign_identity=None, entitlements_file=None,
    icon=['assets/app_icons/CL_Cue_Editor.icns'],
)
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False,
               upx_exclude=[], name='CL ShowCue Builder')
app = BUNDLE(
    coll, name='CL Cue Editor.app', icon='assets/app_icons/CL_Cue_Editor.icns',
    bundle_identifier='com.claudio.showcue.builder',
    info_plist={'CFBundleDisplayName': 'CL Cue Editor',
                'CFBundleShortVersionString': '1.0.0',
                'CFBundleVersion': '1', 'LSMinimumSystemVersion': '11.0', 'NSHighResolutionCapable': True},
)
