"""FULL product and distribution identity, separate from component/protocol versions."""
import argparse
import os
import re

FULL_VERSION = '2.2.0'
FULL_BUILD = '6'


def full_version():
    value = os.environ.get('CL_AUDIO_VERSION', FULL_VERSION)
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', value):
        raise ValueError('CL_AUDIO_VERSION doit être une version x.y.z')
    return value


def full_build():
    value = os.environ.get('CL_BUILD_NUMBER', FULL_BUILD)
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', value):
        raise ValueError('CL_BUILD_NUMBER doit contenir un à trois nombres séparés par des points')
    return value


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true')
    args = parser.parse_args()
    try:
        print(full_build() if args.build else full_version())
    except ValueError as error:
        parser.error(str(error))
