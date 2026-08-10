# Model assets

Place your exported model here:

- `model.onnx` — **not included**, export it yourself (see the main
  [README.md](../../README.md#exporting-your-model-to-onnx)).
- `labels.txt` — one class name per line, in the same order as training.
  Already filled in with `price_label` to match this project's dataset
  (`yolo11/dataset/data.yaml`). Edit it if you retrain with different/more
  classes.

Both paths are fixed in `lib/core/constants/app_constants.dart`
(`modelAssetPath`, `labelsAssetPath`) — rename the files to match, or edit
the constants.
