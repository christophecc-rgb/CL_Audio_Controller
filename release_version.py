"""Release identity; independent of data schemas and runtime protocols."""
import os

RELEASE_VERSION = '2.3.0'
RELEASE_BUILD = '23001'

def bundle_version():
    return os.environ.get('CL_AUDIO_VERSION', RELEASE_VERSION)

def bundle_build():
    return os.environ.get('CL_BUILD_NUMBER', RELEASE_BUILD)

if __name__ == '__main__':
    import sys
    print(bundle_build() if '--build' in sys.argv else bundle_version())
