"""Shared exception types so callers can catch failures by category."""

from __future__ import annotations


class CameraError(Exception):
    """Camera could not be opened, or is unrecoverable after reconnect attempts."""


class ModelLoadError(Exception):
    """The YOLO model weights could not be loaded on any available device."""


class TrackerError(Exception):
    """A single call into the tracker failed. Callers typically log and skip
    the frame rather than raise, since one bad frame should not kill a live
    session -- but the type exists so it can be raised where that's not safe."""
