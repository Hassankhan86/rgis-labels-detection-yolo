# Model assets

Place your exported model here:

- `model.onnx` — a yolo11n detect export (`imgsz=960`, opset=12, no baked-in
  NMS), trained on the 3-class (`large`/`medium`/`small`) dataset in
  `yolo/dataset2_training/`. See `yolo/README.md` for how it was trained and
  exported.
- `labels.txt` — one class name per line, in the same order as training
  (`large`, `medium`, `small`, matching `yolo/dataset2_training/data.yaml`).
  Edit it if you retrain with different/more classes.

Both paths are fixed in `lib/core/constants/app_constants.dart`
(`modelAssetPath`, `labelsAssetPath`) — rename the files to match, or edit
the constants.
