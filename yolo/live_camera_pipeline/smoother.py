"""Online equivalent of ``build_draw_frames()`` in ``yolo11/track_and_count.py``.

The offline version folds an exponential moving average over each
canonical track's boxes in frame order, and "coasts" (keeps drawing the
last smoothed box) for up to `coast_frames` frames whenever a detection
is briefly missing. Both of those are already causal, forward-only
computations in the original -- it just happens to run them after the
fact, over a track's full recorded range. This class does the identical
math, one frame at a time, as detections actually arrive.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class _SmoothState:
    cls_id: int
    box: tuple[float, float, float, float]
    conf: float
    last_frame: int


class BoxSmoother:
    def __init__(self, smooth_alpha: float, coast_frames: int) -> None:
        self.smooth_alpha = smooth_alpha
        self.coast_frames = coast_frames
        self._state: dict[int, _SmoothState] = {}

    def update(
        self,
        canonical: int,
        cls_id: int,
        box: tuple[float, float, float, float],
        conf: float,
        frame_idx: int,
    ) -> None:
        prev = self._state.get(canonical)
        if prev is None:
            smoothed = box
        else:
            a = self.smooth_alpha
            smoothed = tuple(a * r + (1 - a) * s for r, s in zip(box, prev.box))
        self._state[canonical] = _SmoothState(cls_id, smoothed, conf, frame_idx)

    def drawable(
        self, frame_idx: int, confirmed_ids: set[int]
    ) -> list[tuple[int, int, tuple[float, float, float, float], float]]:
        """Return (canonical, cls_id, box, conf) for every confirmed track
        that either has a detection this frame or is still within its
        coasting window. Prunes tracks that have coasted past their
        window so memory doesn't grow across a long session."""
        out = []
        stale = []
        for canonical, state in self._state.items():
            gap = frame_idx - state.last_frame
            if gap > self.coast_frames:
                stale.append(canonical)
                continue
            if canonical in confirmed_ids:
                out.append((canonical, state.cls_id, state.box, state.conf))
        for canonical in stale:
            del self._state[canonical]
        return out
