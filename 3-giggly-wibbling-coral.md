# Speeding up recorded-video batch inference

## Status (updated after on-device testing)

Since this plan was first written: the user exported an INT8 ONNX model
(`yolo/7-export_int8.py`, written for this) and manually swapped it into
`assets/models/model.onnx` (10.8MB fp32 -> 3.27MB int8), then rebuilt and ran
the app on the connected Android phone (`23021RAAEG`). **Recorded-video
"detecting" (batch inference) is still too slow.**

The app's own device log explains why quantization alone didn't fix it —
see the new finding under Step 3 below: the int8 graph is barely
NNAPI-accelerated (only ~20% of nodes), so most of it is still running on
CPU/XNNPACK with added per-partition overhead. Meanwhile **Step 1 — frame
skipping, the single biggest lever identified in the original investigation
— was never implemented**; `video_batch_repository_impl.dart` still runs
full inference on literally every extracted frame regardless of model
format. This plan now re-centers Step 1 as the immediate next action, and
downgrades quantization to "keep, but don't expect it to be the fix."

## Context

Recorded-video batch processing (`video_processing` feature) runs the same
ONNX detection engine used by live tracking over *every* extracted frame,
sequentially, on-device. That's slow, and the user wants to know (a) how to
export the trained YOLO11n model to INT8 to speed it up, and (b) whether
LoRA/QLoRA are relevant alternatives.

Investigation of the actual repo state turned up three things worth acting on,
in order of effort-to-impact:

1. **The single biggest lever is already scaffolded but unused.**
   `VideoBatchRepositoryImpl.processVideo` (`lib/features/video_processing/data/repositories/video_batch_repository_impl.dart:45-49`)
   takes a `frameStep` parameter, but it's asserted to always be `1`:
   `assert(frameStep == 1, 'frameStep > 1 is a reserved seam, not yet implemented.')`.
   Every extracted frame currently gets a full model inference — no skipping
   happens today, despite `CLAUDE.md` describing frame-skipping as if it were
   live. `BoxSmoother.drawable(frameIdx)` (`lib/features/live_tracking/data/tracking/box_smoother.dart:70-94`)
   is a pure query that can be called on frames where `update()` wasn't — it
   already "coasts" the last smoothed box for up to `coastFrames` frames
   (default `3`, `lib/features/live_tracking/domain/live_tracking_config.dart:14`).
   This means the seam can be turned on with no new tracking logic: skip
   inference on most frames, still draw a coasted box, still write every
   frame so the output video stays full-length. This is a ~3x cut in
   inference calls for free, with no model change and no accuracy risk on the
   frames that *are* inferred.

2. **Hardware execution providers are already wired but unverified.**
   `OnnxDetectionEngine.loadModel` (`lib/features/detection/data/engines/onnx_detection_engine.dart:59-97`)
   already requests NNAPI (Android) / CoreML (iOS) / XNNPACK, falling back to
   plain CPU, and already logs `requested=... available=...` from
   `getAvailableProviders()` specifically so you can tell whether they're
   really accelerating anything on your device vs. silently falling back to
   CPU per-node. A comment there notes plain CPU alone measured ~3.3s/frame
   at 960x960 on a mid-range Android phone. Worth checking this log on your
   actual test device *before* assuming quantization is the missing piece —
   if NNAPI isn't actually engaging, that's an independent, likely larger,
   problem than fp32 vs int8.

3. **INT8 export is already half-written in the training notebook.**
   `yolo/1-colab_train.ipynb`'s export cell already has a commented-out line:
   `export_model.export(format='onnx', imgsz=960, opset=12, nms=False, simplify=True, int8=True, data='dataset/data.yaml')`.
   `data=` there is stale — the real, currently-tracked data yaml for the
   checkpoint that's actually in `assets/models/` is
   `yolo/dataset2_training/data.yaml`. `ultralytics>=8.3.0` (the pin in
   `yolo/requirements.txt`) supports `int8=True` for ONNX export via ORT's
   static quantization, calibrated from that data yaml's images.

## Recommended plan

### Step 1 — Enable video-batch frame skipping (NEXT — this is the actual fix)

- `video_batch_repository_impl.dart`: replace the `assert(frameStep == 1, ...)`
  with real logic — only run `_engine.runInferenceOnTensor` and the
  tracker/resolver/counter/smoother `.update()` calls
  (lines ~103-125) when `(frameIndex - 1) % frameStep == 0`; on skipped
  frames, just call `smoother.drawable(frameIndex)` and annotate with that,
  same as today. `frameIndex` already increments correctly for every
  extracted frame regardless (line 89), so `BoxSmoother`'s gap math keeps
  working unchanged.
- Default `frameStep` to `3` at the call site
  (`lib/features/video_processing/presentation/providers/video_processing_state_provider.dart:42`,
  currently calls `processVideo(sourceVideoPath: sourceVideoPath)` with no
  `frameStep` — pass `frameStep: 3`). `3` matches `coastFrames`'s default of
  `3` in `LiveTrackingConfig`, so the coasting window fully covers the gap
  between real detections.
- Don't wire this into `AppSettings`/the Settings screen yet — that's a
  bigger, separate change (persistence key, UI toggle) and isn't needed to
  get the speed win. Treat it as a follow-up if you want it user-adjustable
  later.

**Accuracy tradeoff — read before picking a default.** Skipping frames
doesn't degrade what the model sees on the frames it *does* run (same
resolution, same weights) — the risk is temporal:

- A label visible for only a frame or two (fast pan, brief occlusion
  clearing) can land entirely inside a skipped gap and never get detected.
- More importantly: `LabelCounter.registerHit` (called from the block being
  gated behind `frameStep`) only fires on inference frames, and
  `LabelCounter` requires `minHits` (default `3`) *consecutive* hits before
  a label counts as confirmed. That confirmation now spans roughly
  `minHits × frameStep` real video frames instead of `minHits` — at
  `frameStep=3` that's ~9 real frames (~0.3s at 30fps) a label must stay in
  view before it's counted, vs. ~3 frames (~0.1s) today. Labels that pass
  through frame faster than that risk going uncounted where they wouldn't
  have before.
- Track-identity/merge logic (`IncrementalDuplicateResolver`'s
  `mergeMaxGap=20`) is not at similar risk — it keys off real frame indices,
  not inference-call counts, so it still measures true elapsed frames
  regardless of `frameStep`.

Given this, treat `frameStep=3` as a starting hypothesis, not a settled
default: validate unique-label counts on real recorded footage against
`frameStep=1` before trusting it (see Verification), and consider starting
at `frameStep=2` instead if your footage includes fast passes or labels
that are only briefly in view — it still roughly halves inference calls
with a smaller confirmation-delay penalty.

### Step 2 — Verify hardware EPs are actually engaging (done — result below)

Checked the device log from the actual `flutter run -d fbb7ab88` session
(`onnx_detection_engine.dart:93`'s diagnostic print):

```
[OnnxDetectionEngine] requested=[OrtProvider.NNAPI, OrtProvider.XNNPACK, OrtProvider.CPU]
                       available=[OrtProvider.CPU, OrtProvider.NNAPI, OrtProvider.XNNPACK]
```

So all three providers are present on-device — NNAPI isn't missing/broken.
But the ORT-internal NNAPI log lines right above that tell a more important
story (see Step 3 — this is about the int8 graph specifically, not EP
availability in general).

### Step 3 — INT8 post-training quantization of the ONNX export (done — result is concerning)

Done: `yolo/7-export_int8.py` (Ultralytics `int8=True` ONNX export, QDQ
static quantization calibrated from `dataset2_training/data.yaml`) exported
`yolo11n-best-int8.onnx`, and the user manually swapped it into
`assets/models/model.onnx`, rebuilt, and ran it on-device.

**Finding — this is very likely why speed didn't improve.** The same device
log that confirmed NNAPI is available also shows ONNX Runtime's own NNAPI
partitioning result for the *loaded (int8) graph*:

```
W/onnxruntime: NnapiExecutionProvider::GetCapability, number of partitions supported by NNAPI: 62
               number of nodes in the graph: 988  number of nodes supported by NNAPI: 197
```

Only ~20% of the graph's nodes (197 of 988) are NNAPI-eligible, split
across 62 separate partitions. That means execution ping-pongs between
NNAPI and XNNPACK/CPU 62 times per frame, paying a hand-off (memory
copy/sync) cost at every boundary — and the ~988-node count itself is a
symptom: static QDQ quantization inserts a `QuantizeLinear`/
`DequantizeLinear` pair around nearly every op, which roughly doubles node
count and is exactly the kind of op ORT's Android NNAPI EP tends to have
patchy support for. A fp32 export of the same model would have far fewer
nodes and, historically, much better NNAPI coverage — so this int8 export
may well be running *more slowly* than fp32 despite being "int8", purely
from EP fragmentation, independent of raw arithmetic cost.

**What to do with this:**
- Don't block on fixing this — it doesn't affect Step 1 at all, and Step 1
  alone should already deliver the bulk of the needed speedup regardless of
  which model format is loaded.
- If you want to pursue int8 further afterward: the fp32 export
  (`yolo/yolo11n-best.onnx`) is still on disk untouched — worth doing a
  quick side-by-side timing of a few frames (fp32 vs int8, same device,
  same providers) to confirm the fragmentation is actually costing you
  wall-clock time before investing more here. If it is, try re-exporting
  with `quant_format=QOperator` instead of the QDQ default (via
  `onnxruntime.quantization.quantize_static` directly, bypassing
  Ultralytics' `int8=True` convenience wrapper, which hardcodes QDQ) — ORT's
  NNAPI EP has historically had better luck with QOperator-style quantized
  graphs than QDQ ones. Or simply accept that on this device, fp32 + NNAPI
  may be the faster combination and keep int8 only if a future device shows
  better NNAPI coverage for it.
- Accuracy comparison (fp32 vs int8 per-class mAP via `yolo/7-export_int8.py`'s
  built-in `--compare-fp32` check) is still worth running before deciding
  whether to keep the int8 model at all, independent of the speed question —
  watch the `large` class per the original reasoning below.

### On LoRA / QLoRA specifically

Not applicable here — skip them. LoRA/QLoRA are parameter-efficient
*fine-tuning* techniques: they freeze the base model and train small
low-rank adapter matrices instead, to cut GPU memory during training of
models too large to fully fine-tune (QLoRA additionally 4-bit-quantizes the
frozen base weights during training for the same reason). Two reasons they
don't help your problem:

- They're a *training-cost* lever, not an *inference-speed* lever. LoRA
  adapters get merged back into the base weights before deployment, so the
  deployed model has the exact same architecture and inference cost as a
  fully fine-tuned one — zero effect on the video-processing latency you're
  trying to fix.
- There's no training-cost problem to solve here anyway: YOLO11n is already
  2.58M params / 6.4 GFLOPs, and the existing Colab notebook already fully
  fine-tunes it for 250 epochs on a single free-tier T4 GPU with no memory
  pressure (`1-colab_train.ipynb`).

### If Steps 1-3 still aren't enough

Lower priority, higher effort/risk — only worth pursuing after measuring the
above:

- **Lower `imgsz`** (960 → 640/736): biggest remaining lever (cost scales
  roughly with H×W), but the model was trained at 960 specifically for
  small, distant shelf labels — exporting at a lower size without retraining
  risks `small`-class recall. If you go here, retrain at the lower `imgsz`
  and re-validate rather than just re-exporting the existing checkpoint at a
  different size.
- **Swap to the TFLite backend**: `lib/features/detection/data/engines/tflite_detection_engine.dart`
  already exists in this codebase as an intentional, currently-unimplemented
  swap point (per `CLAUDE.md`) specifically so a second `DetectionEngine`
  implementation can be dropped in behind `DetectionRepository` without
  touching callers. TFLite's int8 + NNAPI/GPU-delegate path is generally
  more mature/better op-covered on Android than ONNX Runtime Mobile's NNAPI
  EP. Real engineering effort (implement the stub), so only worth it if
  ONNX int8 + EP tuning doesn't get you far enough.
- **Pruning / distillation**: likely not worth it — the model is already a
  "nano" variant and the dataset (33-43 images) is too small to safely
  fine-tune recovery after aggressive pruning.

## Verification

- `flutter analyze` and `flutter test` after the Step 1 code change.
- Manually run a recorded video through the batch-process tab before/after
  Step 1 on the connected phone: confirm the output video is still
  full-length/smooth (coasted boxes look continuous, not jumpy) and that
  unique-label counts are in the same ballpark as before (since
  `LabelCounter`/tracker logic is untouched, they should match closely).
- Time the same recorded video's batch-processing wall-clock before/after
  Step 1 — this is the number that should visibly move. Do this with
  whichever model is currently in `assets/models/model.onnx` (int8 is fine)
  so Step 1's win is measured on top of current reality, not a hypothetical.
- Separately, if pursuing the Step 3 fragmentation question further: time
  fp32 vs int8 head-to-head on the same device/build to confirm whether
  int8 is actually faster, slower, or a wash here — don't assume from the
  partition counts alone, measure it.
- Per-class `mAP50-95` comparison (fp32 vs int8) via
  `yolo/7-export_int8.py --compare-fp32`, specifically checking `large`
  doesn't collapse, before committing to keeping the int8 model long-term.
