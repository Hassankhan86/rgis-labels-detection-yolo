"""Online equivalent of ``merge_tracks()`` in ``yolo11/track_and_count.py``.

The offline function runs once, after an entire video has been decoded,
over *final* per-track histories. A live camera has no "end of video" to
wait for, so this module applies the exact same merge predicate --

    * same class
    * the candidate predecessor's own track already ended
    * gap between predecessor end and successor start <= merge_max_gap
    * successor's start position lands within merge_distance_factor
      box-diagonals of where the predecessor's own recent velocity
      predicts it should be
    * merging would not join two groups that were ever on screen at the
      same time (the interval-overlap guard)

-- at the moment each *new* raw tracker ID first appears, instead of once
at the end. Everything is causal: a new track is only ever compared
against tracks that have already stopped producing detections as of the
current frame.

Why this is safe / equivalent
------------------------------
Ultralytics' BoT-SORT never reuses a numeric track ID after dropping it,
and it never creates a new ID for an object it can still associate
internally (that's what its own track_buffer / motion-compensated
re-identification is for). So by the time our code sees a brand-new raw
ID, any earlier ID that could plausibly be "the same physical label" has,
for our purposes, already stopped growing -- which is exactly the
information the offline pass has by construction (it just gets it after
the fact instead of in real time).

One real edge case where online and offline CAN diverge: if a
"predecessor" track's raw ID resumes reporting detections *after* we've
already merged some other, newer track into it (because it was only
gapped within BoT-SORT's own short-term buffer, not actually dropped),
the offline pass would see the full, later interval and correctly skip
that merge as a same-time overlap -- something this resolver cannot
know in advance. When it happens, `observe()` detects the now-provably-
wrong merge (the group's own intervals start overlapping) and logs a
warning; it does not attempt to auto-un-merge, since Union-Find doesn't
support that cheaply. In practice this is rare (it requires the
*wrong* candidate to look like a better spatial match than the truth
for `merge_max_gap` frames) and mirrors the kind of approximation the
original algorithm's own docstring already acknowledges it makes.
"""

from __future__ import annotations

import logging

from .track_history import TrackHistory

logger = logging.getLogger(__name__)


class IncrementalDuplicateResolver:
    def __init__(self, max_gap: int, distance_factor: float) -> None:
        self.max_gap = max_gap
        self.distance_factor = distance_factor

        self.histories: dict[int, TrackHistory] = {}
        self._parent: dict[int, int] = {}
        # Per group-root, the frame intervals of every raw member merged
        # into it so far. Mirrors `merge_tracks`'s `intervals` exactly.
        self._intervals: dict[int, list[list[int]]] = {}
        # One mutable [start, end] per raw tid, shared by reference into
        # whichever group's interval list it currently belongs to, so
        # extending a still-growing track's own end frame is O(1) and is
        # automatically visible wherever that interval is referenced.
        self._own_interval: dict[int, list[int]] = {}

    def _find(self, tid: int) -> int:
        while self._parent[tid] != tid:
            self._parent[tid] = self._parent[self._parent[tid]]
            tid = self._parent[tid]
        return tid

    def _overlaps(self, root_a: int, root_b: int) -> bool:
        return any(
            sa <= eb and sb <= ea
            for sa, ea in self._intervals[root_a]
            for sb, eb in self._intervals[root_b]
        )

    def _union(self, tid_a: int, tid_b: int) -> bool:
        ra, rb = self._find(tid_a), self._find(tid_b)
        if ra == rb or self._overlaps(ra, rb):
            return False
        self._parent[rb] = ra
        self._intervals[ra].extend(self._intervals[rb])
        return True

    def _find_merge_candidate(
        self, tid_b: int, cls_b: int, box_b: tuple[float, float, float, float], frame_idx: int
    ) -> int | None:
        bx = (box_b[0] + box_b[2]) / 2
        by = (box_b[1] + box_b[3]) / 2
        bdiag = ((box_b[2] - box_b[0]) ** 2 + (box_b[3] - box_b[1]) ** 2) ** 0.5

        candidates: list[tuple[float, int]] = []
        for tid_a, hist_a in self.histories.items():
            if tid_a == tid_b or hist_a.class_id != cls_b:
                continue
            gap = frame_idx - hist_a.end_frame
            if gap <= 0 or gap > self.max_gap:
                continue
            pred_x, pred_y = hist_a.predict(frame_idx)
            dist = ((pred_x - bx) ** 2 + (pred_y - by) ** 2) ** 0.5
            threshold = self.distance_factor * max(hist_a.box_diagonal(-1), bdiag)
            if dist <= threshold:
                candidates.append((dist, tid_a))

        # Same tie-break as the offline pass: try the closest match first,
        # and only actually commit if it doesn't violate the overlap guard.
        for _, tid_a in sorted(candidates, key=lambda c: c[0]):
            if self._union(tid_a, tid_b):
                return tid_a
        return None

    def observe(
        self, tid: int, cls_id: int, box: tuple[float, float, float, float], frame_idx: int
    ) -> int:
        """Feed one raw-tracker detection for this frame. Returns the
        canonical (merged) id that `tid` currently resolves to."""
        if tid not in self.histories:
            self.histories[tid] = TrackHistory(class_id=cls_id)
            self._parent[tid] = tid
            interval = [frame_idx, frame_idx]
            self._own_interval[tid] = interval
            self._intervals[tid] = [interval]
            self._find_merge_candidate(tid, cls_id, box, frame_idx)
        else:
            interval = self._own_interval[tid]
            prev_end = interval[1]
            interval[1] = frame_idx
            root = self._find(tid)
            if root != tid and self._overlap_regressed(root, tid, prev_end, frame_idx):
                logger.warning(
                    "track %d resumed after being merged into canonical %d; "
                    "the two are now provably concurrent (same physical "
                    "label assumption may be wrong for this group)",
                    tid,
                    root,
                )

        hist = self.histories[tid]
        hist.frames.append(frame_idx)
        hist.boxes.append(tuple(box))
        return self._find(tid)

    def _overlap_regressed(self, root: int, tid: int, prev_end: int, new_end: int) -> bool:
        """True if extending `tid`'s interval to `new_end` newly overlaps
        another member of its own group (see module docstring)."""
        own = self._own_interval[tid]
        start = own[0]
        for interval in self._intervals[root]:
            if interval is own:
                continue
            sa, ea = interval
            overlapped_before = start <= ea and sa <= prev_end
            overlaps_now = start <= ea and sa <= new_end
            if overlaps_now and not overlapped_before:
                return True
        return False
