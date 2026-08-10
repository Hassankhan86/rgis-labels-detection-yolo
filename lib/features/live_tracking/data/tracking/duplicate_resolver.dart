import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../../core/utils/nms_utils.dart';
import 'track_history.dart';

/// One raw track id's [start, end] frame interval. A plain mutable class
/// (not a record) on purpose: it must be shared *by reference* between
/// [IncrementalDuplicateResolver._ownInterval] and whichever group's
/// interval list it currently belongs to, so extending a still-growing
/// track's own end frame is visible everywhere it's referenced — mirrors
/// the Python resolver's own comment about its mutable `[start, end]`
/// lists.
class _Interval {
  _Interval(this.start, this.end);
  int start;
  int end;
}

/// Online equivalent of `merge_tracks()` in `yolo11/track_and_count.py`,
/// evaluated the moment each new raw track id first appears instead of
/// once after an entire video has been decoded.
///
/// Direct port of `live_camera_pipeline/duplicate_resolver.py`'s
/// `IncrementalDuplicateResolver` — same online Union-Find merge
/// predicate: same class, the candidate predecessor's own track already
/// ended, gap since then <= [maxGap], the successor's start position lands
/// within [distanceFactor] box-diagonals of where the predecessor's own
/// recent velocity predicts it should be, and merging never joins two
/// groups that were ever on screen at the same time (the interval-overlap
/// guard). See that file's module docstring for why this is safe/
/// equivalent to the offline pass, and the one rare edge case where it
/// isn't (handled the same way here: logged, not auto-un-merged).
class IncrementalDuplicateResolver {
  IncrementalDuplicateResolver(this.maxGap, this.distanceFactor);

  final int maxGap;
  final double distanceFactor;

  final Map<int, TrackHistory> histories = {};
  final Map<int, int> _parent = {};
  final Map<int, List<_Interval>> _intervals = {};
  final Map<int, _Interval> _ownInterval = {};

  int _find(int tid) {
    while (_parent[tid] != tid) {
      _parent[tid] = _parent[_parent[tid]!]!;
      tid = _parent[tid]!;
    }
    return tid;
  }

  bool _overlaps(int rootA, int rootB) {
    for (final a in _intervals[rootA]!) {
      for (final b in _intervals[rootB]!) {
        if (a.start <= b.end && b.start <= a.end) return true;
      }
    }
    return false;
  }

  bool _union(int tidA, int tidB) {
    final ra = _find(tidA);
    final rb = _find(tidB);
    if (ra == rb || _overlaps(ra, rb)) return false;
    _parent[rb] = ra;
    _intervals[ra]!.addAll(_intervals[rb]!);
    return true;
  }

  int? _findMergeCandidate(int tidB, int clsB, Box boxB, int frameIdx) {
    final bx = (boxB.left + boxB.right) / 2;
    final by = (boxB.top + boxB.bottom) / 2;
    final bw = boxB.right - boxB.left;
    final bh = boxB.bottom - boxB.top;
    final bdiag = math.sqrt(bw * bw + bh * bh);

    final candidates = <(double, int)>[];
    for (final entry in histories.entries) {
      final tidA = entry.key;
      final histA = entry.value;
      if (tidA == tidB || histA.classId != clsB) continue;

      final gap = frameIdx - histA.endFrame;
      if (gap <= 0 || gap > maxGap) continue;

      final (predX, predY) = histA.predict(frameIdx);
      final dx = predX - bx;
      final dy = predY - by;
      final dist = math.sqrt(dx * dx + dy * dy);
      final threshold = distanceFactor * math.max(histA.boxDiagonal(-1), bdiag);
      if (dist <= threshold) candidates.add((dist, tidA));
    }

    candidates.sort((a, b) => a.$1.compareTo(b.$1));
    for (final candidate in candidates) {
      if (_union(candidate.$2, tidB)) return candidate.$2;
    }
    return null;
  }

  /// Feed one raw-tracker detection for this frame. Returns the canonical
  /// (merged) id that [tid] currently resolves to.
  int observe(int tid, int clsId, Box box, int frameIdx) {
    if (!histories.containsKey(tid)) {
      histories[tid] = TrackHistory(classId: clsId);
      _parent[tid] = tid;
      final interval = _Interval(frameIdx, frameIdx);
      _ownInterval[tid] = interval;
      _intervals[tid] = [interval];
      _findMergeCandidate(tid, clsId, box, frameIdx);
    } else {
      final interval = _ownInterval[tid]!;
      final prevEnd = interval.end;
      interval.end = frameIdx;
      final root = _find(tid);
      if (root != tid && _overlapRegressed(root, tid, prevEnd, frameIdx)) {
        debugPrint(
          'IncrementalDuplicateResolver: track $tid resumed after being '
          'merged into canonical $root; the two are now provably '
          'concurrent (same physical label assumption may be wrong for '
          'this group)',
        );
      }
    }

    final hist = histories[tid]!;
    hist.frames.add(frameIdx);
    hist.boxes.add(box);
    return _find(tid);
  }

  bool _overlapRegressed(int root, int tid, int prevEnd, int newEnd) {
    final own = _ownInterval[tid]!;
    final start = own.start;
    for (final interval in _intervals[root]!) {
      if (identical(interval, own)) continue;
      final sa = interval.start;
      final ea = interval.end;
      final overlappedBefore = start <= ea && sa <= prevEnd;
      final overlapsNow = start <= ea && sa <= newEnd;
      if (overlapsNow && !overlappedBefore) return true;
    }
    return false;
  }
}
