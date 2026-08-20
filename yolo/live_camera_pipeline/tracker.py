"""Thin wrapper around ``model.track(..., persist=True, tracker="botsort.yaml")``
-- the exact same call ``track_and_count.py`` makes per frame. This class
adds nothing to the tracking algorithm itself; it only manages *when* the
tracker's internal state is (re)initialized, and turns a failed call into
a logged, skipped frame instead of crashing a live session.

Session semantics
------------------
Ultralytics keeps BoT-SORT state alive across calls when ``persist=True``.
Passing ``persist=False`` forces it to reinitialize. A "session" here
(one continuous recording, matching Option 1 in the brief: record button
pressed -> stopped) should keep tracker state alive for its entire
duration and never restart mid-session. `reset()` is called exactly once,
by the pipeline, when a *new* recording session starts; every frame
within a session uses `persist=True` after that first call.
"""

from __future__ import annotations

import logging

from .detector import Detector

logger = logging.getLogger(__name__)

Detection = tuple[int, int, tuple[float, float, float, float], float]  # (tid, cls_id, box, conf)


class StreamTracker:
    def __init__(
        self,
        detector: Detector,
        tracker_cfg: str = "botsort.yaml",
        conf: float = 0.5,
        imgsz: int | None = None,
    ) -> None:
        self.detector = detector
        self.tracker_cfg = tracker_cfg
        self.conf = conf
        self.imgsz = imgsz
        self._persist = False

    def reset(self) -> None:
        """Force the next `update()` call to reinitialize tracker state.
        Call this once at the start of every new recording session."""
        self._persist = False

    def update(self, frame, frame_index: int) -> list[Detection]:
        kwargs = dict(
            persist=self._persist,
            tracker=self.tracker_cfg,
            conf=self.conf,
            verbose=False,
        )
        if self.imgsz is not None:
            kwargs["imgsz"] = self.imgsz

        try:
            results = self.detector.model.track(frame, **kwargs)
            self._persist = True
        except Exception as exc:
            logger.error("Tracker failure on frame %d: %s", frame_index, exc)
            return []

        result = results[0]
        track_ids = result.boxes.id
        if track_ids is None:
            return []

        class_ids = result.boxes.cls.int().tolist()
        confs = result.boxes.conf.tolist()
        boxes = result.boxes.xyxy.tolist()

        return [
            (tid, cls_id, tuple(box), conf)
            for tid, cls_id, box, conf in zip(
                track_ids.int().tolist(), class_ids, boxes, confs
            )
        ]
