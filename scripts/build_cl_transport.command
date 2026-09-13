#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec "${CL_PYTHON:-python3}" "$PROJECT_DIR/scripts/build_cl_transport.py" "$@"
