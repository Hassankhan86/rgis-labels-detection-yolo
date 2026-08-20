"""Online equivalent of the confirmation / counting bookkeeping that
``track_and_count.py`` does after `merge_tracks()` returns: a canonical
(merged) track only counts as a confirmed unique label once its total
hit count reaches ``min_hits``.

The offline script assigns the clean 1..N display ids ordered by each
confirmed track's *first frame*, because it already knows every track's
full timeline before drawing anything. A live session doesn't have that
luxury -- a display id is assigned the moment a track *crosses* the
min_hits threshold, in the order that happens. This is the natural
online analogue: ids, once shown, never change or get renumbered.
"""

from __future__ import annotations

from collections import Counter as _Counter


class LabelCounter:
    def __init__(self, min_hits: int) -> None:
        self.min_hits = min_hits
        self.merged_hits: _Counter[int] = _Counter()
        self.merged_class: dict[int, int] = {}
        self.confirmed_ids: set[int] = set()
        self.display_id: dict[int, int] = {}
        self._next_display_id = 1

    def register_hit(self, canonical: int, cls_id: int) -> tuple[bool, int | None]:
        """Record one more matched frame for `canonical`. Returns
        (just_confirmed, display_id) -- display_id is None until/unless
        this canonical track has reached min_hits."""
        self.merged_hits[canonical] += 1
        self.merged_class[canonical] = cls_id

        just_confirmed = False
        if canonical not in self.confirmed_ids and self.merged_hits[canonical] >= self.min_hits:
            self.confirmed_ids.add(canonical)
            self.display_id[canonical] = self._next_display_id
            self._next_display_id += 1
            just_confirmed = True

        return just_confirmed, self.display_id.get(canonical)

    @property
    def total(self) -> int:
        return len(self.confirmed_ids)

    def per_class(self, names: dict[int, str] | None = None) -> dict[str | int, int]:
        counts = _Counter(self.merged_class[cid] for cid in self.confirmed_ids)
        if names is None:
            return dict(counts)
        return {names.get(cls_id, cls_id): n for cls_id, n in counts.items()}

    def summary(self, names: dict[int, str] | None = None) -> dict:
        return {
            "total_unique_labels": self.total,
            "per_class": self.per_class(names),
        }
