"""Small generic helpers with no counting logic in them."""

from __future__ import annotations

from pathlib import Path


def unique_output_path(path: Path) -> Path:
    """Create the parent folder if missing, and if `path` already exists,
    append _2, _3, ... to the stem until a free filename is found, so a
    previous session's recording is never overwritten. Same behavior as
    the helper of the same name in ``track_and_count.py``."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        return path
    counter = 2
    while True:
        candidate = path.with_name(f"{path.stem}_{counter}{path.suffix}")
        if not candidate.exists():
            return candidate
        counter += 1
