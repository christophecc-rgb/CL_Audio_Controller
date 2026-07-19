# Third-party software notices

This document inventories the third-party software used to build or run CL Audio Controller 2.0.0. It is an operational summary, not legal advice. Before distributing a binary, the exact license texts shipped by the resolved packages should be collected with the release and checked against the final bundle.

## Runtime and bundled dependencies

| Component | Version | License | Redistribution / attribution summary |
|---|---:|---|---|
| CPython | 3.14.5 | PSF License Agreement | Preserve the Python copyright and license notices when redistributing the embedded interpreter. |
| Flask | 3.1.3 | BSD-3-Clause | Retain copyright, license conditions and disclaimer in source and binary distributions. No endorsement. |
| Werkzeug | 3.1.8 | BSD-3-Clause | Retain copyright, license conditions and disclaimer. No endorsement. |
| Jinja2 | 3.1.6 | BSD-3-Clause | Retain copyright, license conditions and disclaimer. No endorsement. |
| MarkupSafe | 3.0.3 | BSD-3-Clause | Retain copyright, license conditions and disclaimer. No endorsement. |
| itsdangerous | 2.2.0 | BSD-3-Clause | Retain copyright, license conditions and disclaimer. No endorsement. |
| Click | 8.4.1 | BSD-3-Clause | Retain copyright, license conditions and disclaimer. No endorsement. |
| Blinker | 1.9.0 | MIT | Retain copyright and license notice. |
| python-osc | 1.10.2 | The Unlicense | Public-domain dedication with fallback terms; retaining the notice is recommended. |
| pywebview | 6.2.1 | BSD-3-Clause | Retain copyright, license conditions and disclaimer. No endorsement. |
| pyobjc-core | 12.2 | MIT | Retain copyright and license notice. |
| pyobjc-framework-Cocoa | 12.2 | MIT | Retain copyright and license notice. |
| pyobjc-framework-WebKit | 12.2 | MIT | Retain copyright and license notice. |
| bottle | 0.13.4 | MIT | Retain copyright and license notice. |
| proxy-tools | 0.1.0 | MIT | Retain copyright and license notice. |
| typing-extensions | 4.15.0 | PSF-2.0 | Preserve the applicable Python Software Foundation license notice. |

The macOS Cocoa and WebKit system frameworks are used through PyObjC. They are operating-system components and are not copied into this source repository as independently distributed third-party source.

## Build-only dependencies

| Component | Version | License | Redistribution / attribution summary |
|---|---:|---|---|
| PyInstaller | 6.21.0 | GPL-2.0-or-later with PyInstaller bootloader exception; selected files under Apache-2.0 | The exception permits distribution of proprietary or differently licensed bundles. Comply with the licenses of bundled dependencies. Modifications to PyInstaller itself remain subject to its terms. |
| pyinstaller-hooks-contrib | 2026.6 | GPL-2.0-or-later with applicable exception and/or Apache-2.0, file-dependent | Build tool; retain upstream notices if any of its material is redistributed or modified. Verify the files included by the exact release. |
| packaging | 26.2 | Apache-2.0 OR BSD-2-Clause | Retain the selected license and notices if redistributed. |
| altgraph | 0.17.5 | MIT | Retain copyright and license notice if redistributed. |
| macholib | 1.16.4 | MIT | Retain copyright and license notice if redistributed. |
| setuptools | 82.0.1 | MIT | Retain copyright and license notice if redistributed. |

Build tools do not automatically impose their license on CL Audio Controller's own source code. PyInstaller expressly permits bundles to use another license, provided the licenses of all bundled dependencies are respected.

## External software and integrations

| Component | Version | Status | License / action before distribution |
|---|---|---|---|
| AbletonOSC | Commit unknown; the supplied installer targets `master` | Installed externally without Git metadata; not vendored in this repository | MIT. Pin a commit or release, retain its license when redistributing it, and avoid claiming endorsement. |
| Ableton Live | User-installed version | Required external commercial application | Proprietary Ableton software. Do not redistribute Ableton components; document the required compatible versions. |
| Max for Live | Supplied with compatible Ableton Live editions | External runtime for the included `.maxpat` bridge | Proprietary Ableton/Cycling '74 technology. Verify authorship and redistribution rights for the project's patch and any compiled `.amxd`. |
| macOS | 11 or later for the reference bundle | External operating system | Apple proprietary software; no Apple system component should be redistributed separately. |

## Project assets requiring ownership confirmation

The following project-owned or locally supplied material has no provenance statement in the repository and must be checked before public release:

- `assets/` images and photographs;
- `CL_AUDIO.icns`, `icon.iconset/` and logo files;
- `M4L/XFADER_OSC_BRIDGE_v8_OSC_REMOTE_STORE_ID.maxpat`;
- `M4L/LTC Display v2.0 Remote Config.maxpat` et son `.amxd`, dérivés du
  périphérique LTC Display v1.9 fourni localement ;
- screenshots, model images and venue-related artwork;
- installation and diagnostic scripts derived from earlier workspaces.

## Release checklist

1. Preserve the project's MIT `LICENSE` and keep third-party notices separate from it.
2. Confirm ownership or permission for every image, icon and Max for Live resource.
3. Pin AbletonOSC to a commit or release instead of downloading a moving branch.
4. Generate a license report from the clean, locked build environment and compare it with this inventory.
5. Include all required third-party license texts and copyright notices with distributed binaries.

## Authoritative references

- Flask and Pallets projects: <https://github.com/pallets/flask>
- pywebview: <https://github.com/r0x0r/pywebview>
- python-osc: <https://github.com/attwad/python-osc>
- PyObjC: <https://github.com/ronaldoussoren/pyobjc>
- PyInstaller license: <https://pyinstaller.org/en/stable/license.html>
- AbletonOSC: <https://github.com/ideoforms/AbletonOSC>
- Python license: <https://docs.python.org/3/license.html>
