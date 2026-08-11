# Training: small / medium / large label detector

Scripts to train a 3-class YOLO model (`small`, `medium`, `large`) on
`dataset2/`, replacing the old 1-class (`price_label`) model described in
the root `README.md`. **Nothing here has been run** — inspect the scripts
and the plan below, then run it yourself.

```
training/
  prepare_dataset.py   # dataset2/ (flat Label Studio export) -> dataset/ (train/val split)
  train.py              # trains yolo11n and/or yolo26n
  export.py             # best.pt -> assets/models/model.onnx + labels.txt
  requirements.txt
```

## Detection or segmentation?

**Detection.** Three reasons, all specific to this project:

1. **The app only speaks plain detect output.** `onnx_detection_engine.dart`
   decodes a fixed tensor shape — `[1, 4 + numClasses, numBoxes]`, raw boxes
   + per-class scores, no masks, no NMS baked in (the app does its own NMS
   with user-adjustable thresholds). A segmentation export adds a mask-
   prototype tensor and per-box mask coefficients; an OBB export adds an
   angle channel. Either would need new Dart decode logic before it could
   replace the current model. Detection drops in with zero app changes.
2. **You don't need a mask.** The end goal is "which of 3 known categories
   is this tag, and where" — a box answers that. A pixel-accurate outline
   only matters if something downstream measures shelf area or tag shape,
   which nothing in this app currently does.
3. **33 images is little enough that simplicity wins.** Segmentation asks
   the model to also learn precise polygon boundaries from the same tiny
   data — strictly harder to fit well than boxes, for no accuracy payoff
   on this task, on nano-sized models.

**You don't need to reformat your labels either way.** Your `dataset2/labels/*.txt`
rows are already YOLO-segmentation polygons (`cls x1 y1 x2 y2 ...`), because
that's what Label Studio exported. Ultralytics auto-converts polygon rows to
their enclosing box when `task=detect` (see `segments2boxes` in their
dataloader) — `prepare_dataset.py` copies the label files through unchanged
and `train.py` defaults to `task=detect`. If bounding boxes ever prove too
loose (e.g. adjacent tilted tags overlapping enough to confuse NMS), the
same labels support `--task segment` or a future OBB pass without
relabeling — that's a "phase 2" experiment, not where to start.

## Reality check on the dataset

| | dataset1 (old, 1-class) | dataset2 (new, 3-class) |
|---|---|---|
| images | 43 (32/5/6 train/val/test) | 33, unsplit |
| instances | ~1 class only | large: **55**, medium: **315**, small: **842** |

Two problems stack on top of each other here:

- **It's a small dataset**, smaller than the one already used for a single
  class, now split three ways.
- **It's heavily imbalanced** — `small` outnumbers `large` by ~15x. A model
  trained naively on this will likely learn `small` well and barely learn
  `large` at all, since it sees so few examples and gradient updates are
  dominated by the majority class.

`prepare_dataset.py --oversample-rare` addresses the imbalance by
duplicating training images that contain under-represented classes (`large`,
then `medium`) until their instance counts are closer to `small`'s — a copy-
based oversample, not synthetic data, so it doesn't invent anything, but it
does mean those images get more gradient weight. The val split is left
untouched so validation metrics stay honest.

The dataset-size problem has no code fix — the honest ceiling on accuracy is
set by how much labeled data exists. If `large`-class recall is still poor
after training, the fix is more labeled images containing `large` tags, not
more epochs or a bigger model.

One thing worth double-checking on your end, since it's about your physical
setup and not something visible in the code: are `small`/`medium`/`large`
**fixed physical tag sizes**, or could a `small` tag photographed up close
look the same pixel-size as a `large` tag photographed farther away? If
camera distance isn't roughly consistent between training photos and real
usage, the model has no reliable size cue to key off regardless of how much
data it gets.

## Training recipe and why

- **`imgsz=960`** — matches `AppConstants.modelInputSize` (960), which is
  what the currently bundled model was exported at. (Note: the root
  `README.md`'s own export example uses `imgsz=640` — that's stale/inconsistent
  with the actual constant; 960 is what the app's fallback and the existing
  `model.onnx` actually use, and what these scripts default to. Just pick
  one value and keep the training `imgsz` and `export.py --imgsz` consistent
  — the app itself reads the real input size from the ONNX file at load
  time, so it isn't hardcoded to 960.)
- **`scale=0.3`, `degrees=10`** (Ultralytics defaults are `scale=0.5`,
  `degrees=0.0`) — your classes are visually near-identical tags that differ
  mainly by *size*, so aggressive random rescaling is an augmentation that
  actively fights your label signal (it can make a `small` tag's crop look
  `medium`-sized during training). Turned down, not off, since some scale
  jitter still helps generalize to different shelf distances. Mild rotation
  is turned on instead, since your polygons show the tags are photographed
  at an angle, not fronto-parallel.
- **`epochs=200`, `patience=50`** — nano models are cheap enough to run long
  with early stopping doing the real work of picking when to stop, given how
  little data there is to overfit to.
- **`--freeze`** — not used by default, but exposed as an option. If you see
  training loss keep dropping while val metrics get worse (classic overfit
  on 33 images), try `--freeze 10` to lock the pretrained backbone and only
  fine-tune the head/neck.
- Both models train from **COCO-pretrained weights** (`yolo11n.pt`,
  `yolo26n.pt`), not from scratch — required for a dataset this size to
  converge to anything useful.

## Running it

```bash
cd training
pip install -r requirements.txt
pip install -U ultralytics   # needed for yolo26n support specifically

python prepare_dataset.py --oversample-rare

python train.py --arch yolo11n
python train.py --arch yolo26n     # separate run, compare results.png / mAP in runs/
```

Compare the two under `runs/yolo11n_detect/` vs `runs/yolo26n_detect/`
(`results.png`, `results.csv`, per-class metrics in the final val log) and
pick whichever generalizes better on your `val` split — with a dataset this
small, don't be surprised if the difference is mostly noise rather than a
clear winner.

```bash
python export.py --weights runs/yolo11n_detect/weights/best.pt
```

`export.py` prints the exported ONNX output shape. **Check it says
`[1, 7, N]`** (4 box coords + 3 classes) before treating the export as a
drop-in replacement — flagging this explicitly because YOLO26 is built
around an end-to-end/NMS-free head, and if Ultralytics' ONNX export for it
emits an already-postprocessed output instead of the raw per-box tensor,
`onnx_detection_engine.dart`'s decode loop will silently misinterpret it. If
the shape doesn't match, either export YOLO11 instead or update the Dart
decode logic to match whatever YOLO26 actually produces.

Once the shape checks out, `export.py` has already copied `model.onnx` and
written a 3-line `labels.txt` (`large`/`medium`/`small`, in training class
order) into `assets/models/`. Hot-restart the app (asset directory changes
need a full restart, not hot reload) to pick it up.
