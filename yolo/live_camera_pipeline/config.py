"""Central configuration for the live counting pipeline.

Every field mirrors a tuning knob from ``track_and_count.py``'s
``parse_args()`` (same names, same defaults) plus the additional knobs a
live camera source needs. Keeping the counting-related defaults identical
means a live session and an offline video run behave the same way unless
you deliberately retune them.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent
REPO_ROOT = THIS_DIR.parent


@dataclass
class PipelineConfig:
    # --- Model ---
    model_path: str = str(REPO_ROOT / "artifacts" / "yolo11n-best.pt")
    device: str = "auto"  # "auto" | "cpu" | "cuda:0" | ...

    # --- Detection / tracking (same defaults as track_and_count.py) ---
    tracker_cfg: str = "botsort.yaml"
    conf: float = 0.5
    imgsz: int | None = None  # None = model/tracker default

    # --- Duplicate resolution / counting (same defaults as track_and_count.py) ---
    min_hits: int = 3
    merge_max_gap: int = 150
    merge_distance_factor: float = 4.0
    smooth_alpha: float = 0.5
    coast_frames: int = 10

    # --- Camera ---
    camera_source: int | str = 0  # device index, or a path/URL for testing
    capture_width: int | None = 1280
    capture_height: int | None = 720
    reconnect_attempts: int = 5
    reconnect_delay_s: float = 1.0

    # --- Output ---
    output_dir: str = str(REPO_ROOT / "live_camera_pipeline" / "recordings")
    output_fourcc: str = "mp4v"

    # --- Display ---
    window_name: str = "RGIS Live Label Counter"
    display_scale: float = 1.0
