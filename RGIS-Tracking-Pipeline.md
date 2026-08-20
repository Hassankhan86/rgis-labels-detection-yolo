# RGIS Tracking Pipeline — How It Works

Scope: **Python only** — `yolo11/4-track_and_count.py` (offline, two-pass) and
`live_camera_pipeline/` (live, one-pass causal port of the same algorithm),
both from the `02-RGIS_Flutter` project. The Flutter/Dart mobile port is
deliberately out of scope here.

---

## 1. Why two tracking layers exist

A single BoT-SORT pass was not enough on this project's own test footage:

- Switching from ByteTrack to BoT-SORT alone took the raw ID count on video 1
  from 12 down to 10 — an improvement, but a manual ground-truth count of the
  same video found only **8** actual physical labels.
- Confirmed visually: one physical label tracked as one ID at frame 144 had
  become a *different* ID by frame 196 — same crate, same screen position.

**Why BoT-SORT's own ID continuity isn't enough, verified against its actual
defaults** (`ultralytics/cfg/trackers/botsort.yaml`, installed in this
project's `venv314`):

```yaml
track_buffer: 30   # frames to keep a lost track alive before dropping it for good
gmc_method: sparseOptFlow   # global motion compensation via optical flow
```

BoT-SORT only remembers a lost track for **30 frames (~1 second at 30fps)**
before permanently dropping it — any reacquisition after that gets a brand
new ID, no matter how obviously it's the same physical object. Real
occlusions on a shelf-pan video (camera panning past a divider, motion blur,
briefly leaving frame) routinely exceed one second. That gap is exactly what
layer 2 exists to close — the project's own merge window (`merge_max_gap`,
see below) is set to **150 frames, 5x BoT-SORT's own internal memory**, on
purpose.

*(Note: an earlier draft of these notes attributed the 150-frame choice to
BoT-SORT's own Kalman filter "killing" a track at frame 150. That's not what
the installed config says — BoT-SORT's own buffer is 30, not 150. The real
story is arguably a better one: layer 2's whole reason to exist is that it
deliberately reaches 5x further than BoT-SORT can reach on its own.)*

**Why BoT-SORT over ByteTrack specifically**: `botsort.yaml` has
`gmc_method: sparseOptFlow` (optical-flow-based global motion compensation);
`bytetrack.yaml` has no such field at all. A panning camera shifts every
pixel in the frame — without motion compensation, a tracker's own
frame-to-frame motion prediction goes stale mid-pan, and a label that never
left the picture gets treated as lost and reassigned a new ID on
"reacquisition."

---

## 2. Execution flow — offline script (`4-track_and_count.py`)

```
 ┌─────────────────────────────────────────────────────────────┐
 │ PASS 1 — decode + detect + track, once, caching everything   │
 │                                                                │
 │  for each frame:                                              │
 │    model.track(frame, persist=True, tracker="botsort.yaml")   │
 │    → for each (track_id, class_id, box, conf):                │
 │        histories[track_id].frames.append(frame_idx)           │
 │        histories[track_id].boxes.append(box)                  │
 │        frame_detections[frame_idx].append(...)                │
 └─────────────────────────────────────────────────────────────┘
                              │
                              ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ merge_tracks(histories, max_gap, distance_factor)              │
 │  → global Union-Find pass, using every track's FINAL           │
 │    start/end frame (only knowable now that decoding is done)   │
 │  → returns id_map: raw_track_id -> canonical_id                │
 └─────────────────────────────────────────────────────────────┘
                              │
                              ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ build_draw_frames(...)                                         │
 │  → regroup all detections by canonical id                      │
 │  → EMA-smooth box coordinates in frame order                   │
 │  → "coast" (repeat last box) through short gaps                │
 └─────────────────────────────────────────────────────────────┘
                              │
                              ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ PASS 2 — re-read the video from the start, draw, write         │
 │                                                                │
 │  for each frame:                                               │
 │    draw confirmed (>= min_hits) canonical boxes + display id   │
 │    draw running "Unique labels: N" counter                     │
 │    write frame to <video>_tracked.mp4                          │
 └─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                 print total unique count + per-class breakdown
```

**Why two passes instead of one**: `merge_tracks()` needs every track's
*final* start/end frame to decide which raw IDs are the same physical label
— that information doesn't exist until the whole video has been decoded
once. Pass 2 then draws with full hindsight (every canonical track's
complete, already-merged timeline).

---

## 3. Live variant (`live_camera_pipeline/`) — same algorithm, causal

A live camera has no "end of video" to wait for, so `merge_tracks()`
(a single batch decision) becomes `IncrementalDuplicateResolver.observe()`
(evaluated the instant each new raw track ID first appears). The predicate
is identical — same class, predecessor already ended, gap ≤ `merge_max_gap`,
predicted position within `merge_distance_factor` box-diagonals, no overlap
with the target group's existing intervals.

Why this is safe: BoT-SORT never reuses a dropped ID, and never creates a new
ID for something it can still track internally. So by the time the code sees
a brand-new raw ID, any earlier ID that could plausibly be the same physical
label has, for practical purposes, already stopped growing — which is
exactly the information the offline pass has by construction, just obtained
in real time instead of after the fact.

One documented edge case where online and offline can diverge: if a
"predecessor" track resumes *after* something else has already been merged
into it (because BoT-SORT's own 30-frame buffer hadn't actually expired
yet), the offline pass would see the full interval and correctly refuse that
merge as a same-time overlap — the online resolver can't know that in
advance. When it happens, `observe()` detects the now-provably-wrong merge
and **logs a warning**; it does not attempt to silently auto-un-merge. This
is called out explicitly rather than swept under the rug.

**Session model** (`LiveCountingPipeline`): idle preview (no detection
running, saves power) → press `r` → `start_session()` creates a *fresh*
resolver/counter/smoother and resets tracker state exactly once →
`process_frame()` runs the full pipeline every frame, tracker state persists
for the entire session → press `s` → `stop_session()` returns the final
summary. Tracker state is never reset mid-session, and never carries over
from a previous session.

---

## 4. The core pieces, plainly

- **`TrackHistory`** — one raw BoT-SORT ID's full per-frame trajectory
  (frame numbers + boxes). `predict(frame_idx)` extrapolates the track's own
  last-known velocity (computed from up to the last 10 frames) forward to a
  target frame — simple constant-velocity motion, not a Kalman filter.
- **`merge_tracks()` / `IncrementalDuplicateResolver`** — Union-Find: each
  raw track starts as its own group. Two groups merge when *all* of: same
  class · candidate predecessor already ended · gap ≤ `merge_max_gap` ·
  predicted position within `merge_distance_factor` box-diagonals of the
  actual position · the merge would not join two groups that were ever
  on-screen at the same time (the interval-overlap guard — this is what
  stops a cluster of unrelated flicker tracks in the same area from
  chaining into one bloated ID).
- **`LabelCounter`** — a canonical (merged) track only becomes a *confirmed*
  unique label once its accumulated hit count reaches `min_hits`, filtering
  out one-frame flicker (motion blur, a stray false positive) before it can
  claim its own count. Confirmed tracks get a clean, permanent display ID
  (1, 2, 3, ...) in the order they were confirmed.
- **`BoxSmoother`** — EMA (exponential moving average) on drawn box
  coordinates so they don't visibly jitter frame to frame, plus "coasting"
  (keep drawing the last smoothed box for a bounded number of frames after a
  miss) so a brief detection gap doesn't make the box flicker off and back
  on.

---

## 5. Parameter reference

All defaults below are the script's/config's actual defaults, verified
directly from `parse_args()` (`4-track_and_count.py`) and `PipelineConfig`
(`live_camera_pipeline/config.py`) — the two are kept numerically identical
on purpose so a live session and an offline run behave the same way unless
deliberately retuned.

| Parameter | Default | What it controls | Increase it | Decrease it |
|---|---|---|---|---|
| `--tracker` | `botsort.yaml` | Which Ultralytics tracker assigns frame-to-frame IDs (layer 1). | N/A (choice, not a scale) — `botsort.yaml` adds motion compensation for a panning camera. | Switching to `bytetrack.yaml` drops motion compensation: cheaper, but more ID switches whenever the camera pans, since a shifted frame makes its motion prediction go stale. |
| `--conf` | `0.5` | Minimum detection confidence kept before tracking even sees it. | Fewer, higher-confidence detections reach the tracker — fewer false positives, but real labels near the threshold start getting missed (more false negatives, i.e. under-counting). | More detections (including weaker ones) reach the tracker — catches more real labels, but also more noise/false positives for `min_hits` and the merge logic to have to filter out. |
| `--min-hits` | `3` | How many accumulated hits a *merged* track needs before it counts as a confirmed unique label. | Stricter — filters more flicker/false positives, but a label only ever glimpsed briefly (occluded fast, or near the edge of frame) may never get confirmed at all (under-counting). | More permissive — confirms labels faster, but short-lived false positives (a stray misdetection lasting a couple of frames) are more likely to get counted as if they were real (over-counting). |
| `--merge-max-gap` | `150` frames (~5s @ 30fps) | Max frame gap between a track ending and a same-class candidate starting, for them to still be considered the same reacquired physical label. | More lenient — bridges longer occlusions (label hidden behind a shelf divider for several seconds), but risks wrongly merging two genuinely different physical labels of the same class that happen to occupy similar space over a longer window. | Stricter, safer against false merges — but a label occluded for longer than this gap gets counted as two separate labels (over-counting), since BoT-SORT itself already dropped the original ID at 30 frames regardless. |
| `--merge-distance-factor` | `4.0` (× box diagonal) | Spatial tolerance: how far the predicted reacquisition position can be from where the new track actually starts, in units of box diagonals. | More lenient — merges more, tolerates a fast-moving camera or imprecise extrapolation, but risks merging two different, nearby physical labels of the same class (e.g. two adjacent `small` tags). | Stricter — safer against merging different labels, but constant-velocity extrapolation error grows with distance/time, so a real reacquisition after non-linear camera motion (a pan that changes direction) is more likely to be missed and left as two separate IDs. |
| `--smooth-alpha` | `0.5` (range 0–1) | EMA weight: how much the newest raw detection influences the drawn box vs. the previous smoothed value. | Toward `1.0` — snappier, tracks the raw detection more closely, but more jitter passes through visibly. `1.0` disables smoothing entirely. | Toward `0` — smoother, less visible jitter, but the drawn box visibly lags behind the label's real position ("trails" it), especially during motion. |
| `--coast-frames` | `10` | How many consecutive missed-detection frames to keep drawing the last smoothed box before letting it disappear. | More tolerant of brief misses (motion blur, one skipped frame) — box doesn't flicker off — but risks drawing a "ghost" box for longer after a label has genuinely left frame or moved. | Less tolerant — box disappears sooner after a real miss (more honest to what's actually being detected right now), but more visible on/off flicker for brief, harmless gaps. `0` disables coasting. |
| `--output-scale` (offline only) | `0.5` | Resize factor applied to the annotated output video. | Toward `1.0` — full source resolution, more detail, but a much larger, more slowly-decoding file (the original motivation: 4K phone video at full scale stutters on playback). | Toward `0` — smaller, faster-to-play file, but less visual detail in the saved output (doesn't affect detection/tracking accuracy at all — this only touches what gets *drawn and saved*). |
| `imgsz` (live only, config.py) | `None` → model's own trained size (960 for the bundled model) | Resolution the frame is resized to before inference. | Better detection of small/distant labels (more pixels-on-target), but compute cost grows roughly with the square of resolution — directly lowers achievable FPS. Documented in `live_camera_pipeline/README.md` as "the single biggest lever on CPU performance." | Faster inference, higher FPS — but small or distant labels can fall below the resolution needed to detect them at all, increasing missed detections. |
| `capture_width` / `capture_height` (live only) | `1280` / `720` | Resolution requested from the camera hardware itself (before any resizing for inference). | Higher-fidelity source frames — helpful headroom if `imgsz` is also high — but more raw pixels to convert/letterbox every frame even before inference starts. | Cheaper to capture and preprocess, but coarser source detail to begin with. |
| `reconnect_attempts` / `reconnect_delay_s` (live only) | `5` / `1.0s` | How patiently `CameraManager` retries after a camera read failure/disconnect before giving up. | More resilient to a flaky camera or a slow device reconnect — but a real camera loss takes longer to surface as an error, appearing as a longer freeze. | Fails faster and surfaces an error sooner — but less tolerant of a transient, recoverable hiccup. |

### Parameters that aren't really "increase/decrease" knobs

- **`--model`** — path to the trained weights (`yolo11n-best.pt` by
  default). The real lever here isn't a number, it's *which* model: a larger
  YOLO variant (s/m/l instead of n) generally detects more reliably at the
  cost of slower inference — the "increase/decrease" axis is model size, not
  a parameter value.
- **`--video` / `--output` / `camera_source`** — input/output locations, not
  tuning knobs.
- **`device`** (live only, `auto`/`cpu`/`cuda:0`) — a selection, not a
  scale. `Detector` auto-picks CUDA if available and silently falls back to
  CPU if GPU init fails, so this is mostly "let it decide" rather than
  something to tune by hand.
