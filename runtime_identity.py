"""Read-only identity of the actual process and source, independent of ownership."""
import hashlib
import os
from pathlib import Path
import sys
from functools import lru_cache

from build_identity import BUILD_ID


@lru_cache(maxsize=8)
def _source_metadata(source_path):
    try:
        path = Path(source_path)
        return {"source_sha256_short": hashlib.sha256(path.read_bytes()).hexdigest()[:12],
                "source_mtime": path.stat().st_mtime}
    except OSError:
        return {"source_sha256_short": None, "source_mtime": None}


def runtime_identity(source_path, *, backend_path=None):
    source = str(Path(source_path).resolve())
    return {"build_id": BUILD_ID, "pid": os.getpid(), "executable": sys.executable,
            "script_path": source, "backend_path": str(Path(backend_path).resolve()) if backend_path else source,
            "origin": "installed_bundle" if getattr(sys, "frozen", False) else "repo_dev",
            **_source_metadata(source)}
