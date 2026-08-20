"""Per-raw-track-ID trajectory, identical in shape and math to the
``TrackHistory`` dataclass in ``yolo11/track_and_count.py``.

It is reproduced here (rather than imported) so this package stays
self-contained and importable on its own -- e.g. copied onto an edge
device without the rest of the repo, or eventually frozen into a mobile
build. The fields and formulas are intentionally byte-for-byte identical
to the original so `predict()` extrapolation behaves exactly the same
whether it's fed from a decoded video file or a live camera frame.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class TrackHistory:
    """Per-frame trajectory of one raw tracker ID."""

    class_id: int
    frames: list[int] = field(default_factory=list)
    boxes: list[tuple[float, float, float, float]] = field(default_factory=list)

    @property
    def start_frame(self) -> int:
        return self.frames[0]

    @property
    def end_frame(self) -> int:
        return self.frames[-1]

    def center(self, index: int) -> tuple[float, float]:
        left, top, right, bottom = self.boxes[index]
        return ((left + right) / 2, (top + bottom) / 2)

    def box_diagonal(self, index: int) -> float:
        left, top, right, bottom = self.boxes[index]
        return ((right - left) ** 2 + (bottom - top) ** 2) ** 0.5

    def predict(self, frame_idx: int, lookback: int = 10) -> tuple[float, float]:
        """Extrapolate this track's own recent velocity to `frame_idx`."""
        n = min(lookback, len(self.frames) - 1)
        cx1, cy1 = self.center(-1)
        if n <= 0:
            return (cx1, cy1)
        f0 = self.frames[-1 - n]
        cx0, cy0 = self.center(-1 - n)
        dframes = self.frames[-1] - f0
        if dframes == 0:
            return (cx1, cy1)
        vx = (cx1 - cx0) / dframes
        vy = (cy1 - cy0) / dframes
        ahead = frame_idx - self.end_frame
        return (cx1 + vx * ahead, cy1 + vy * ahead)
