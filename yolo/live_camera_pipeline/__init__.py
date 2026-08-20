"""Real-time (live camera) shelf-label detection, tracking, and counting.

This package is a live-camera adaptation of ``yolo11/track_and_count.py``.
It reuses the exact same algorithms (YOLO11n detection, BoT-SORT tracking
with GMC, Union-Find track merging, constant-velocity extrapolation, EMA
smoothing, coasting, min-hits confirmation) but restructures them so every
decision is made causally, frame by frame, from a live camera feed instead
of two passes over a prerecorded video file.

See README.md in this folder for module-by-module documentation.
"""

__version__ = "0.1.0"
