/// Online equivalent of the confirmation/counting bookkeeping
/// `track_and_count.py` does after `merge_tracks()` returns: a canonical
/// (merged) track only counts as a confirmed unique label once its total
/// hit count reaches [minHits].
///
/// Direct port of `live_camera_pipeline/counter.py`'s `LabelCounter`. A
/// display id is assigned the moment a track *crosses* the min-hits
/// threshold, in the order that happens — ids, once shown, never change or
/// get renumbered (the natural online analogue of the offline script's
/// clean 1..N numbering by first-seen frame, which requires knowing every
/// track's full timeline up front).
class LabelCounter {
  LabelCounter(this.minHits);

  final int minHits;

  final Map<int, int> _mergedHits = {};
  final Map<int, int> mergedClass = {};
  final Set<int> confirmedIds = {};
  final Map<int, int> displayId = {};
  int _nextDisplayId = 1;

  /// Records one more matched frame for [canonical]. Returns
  /// `(justConfirmed, displayId)` — `displayId` is null until/unless this
  /// canonical track has reached [minHits].
  (bool, int?) registerHit(int canonical, int clsId) {
    _mergedHits[canonical] = (_mergedHits[canonical] ?? 0) + 1;
    mergedClass[canonical] = clsId;

    var justConfirmed = false;
    if (!confirmedIds.contains(canonical) &&
        _mergedHits[canonical]! >= minHits) {
      confirmedIds.add(canonical);
      displayId[canonical] = _nextDisplayId;
      _nextDisplayId++;
      justConfirmed = true;
    }
    return (justConfirmed, displayId[canonical]);
  }

  int get total => confirmedIds.length;

  /// Per-class breakdown of confirmed labels, keyed by class name (falling
  /// back to the numeric class id as a string if unnamed).
  Map<String, int> perClass(Map<int, String> names) {
    final counts = <String, int>{};
    for (final canonical in confirmedIds) {
      final clsId = mergedClass[canonical]!;
      final name = names[clsId] ?? clsId.toString();
      counts[name] = (counts[name] ?? 0) + 1;
    }
    return counts;
  }
}
