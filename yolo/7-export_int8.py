"""
Exports a trained checkpoint to an INT8-quantized ONNX model (static
post-training quantization, calibrated from the training data yaml), saved
under a new name alongside the existing fp32 export so neither gets
overwritten. Mirrors the (until now commented-out) int8 export line in
`1-colab_train.ipynb`'s export cell.

Usage:
    python 7-export_int8.py
    python 7-export_int8.py --weights yolo11n-best.pt --name yolo11n-best-int8
    python 7-export_int8.py --skip-compare   # skip the fp32-vs-int8 mAP check
"""

import argparse
import shutil
from pathlib import Path

import onnxruntime as ort
import yaml
from ultralytics import YOLO

HERE = Path(__file__).resolve().parent


def output_shape(onnx_path: Path) -> tuple:
    session = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    outputs = session.get_outputs()
    assert len(outputs) == 1, f"expected 1 output tensor, got {len(outputs)}"
    return tuple(outputs[0].shape)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--weights", type=Path, default=HERE / "yolo11n-best.pt")
    parser.add_argument(
        "--data",
        type=Path,
        default=HERE / "dataset2_training" / "data.yaml",
        help="Calibration (and validation) data yaml -- must match what --weights was trained on.",
    )
    parser.add_argument("--imgsz", type=int, default=960, help="Should match AppConstants.modelInputSize / training imgsz.")
    parser.add_argument("--opset", type=int, default=12)
    parser.add_argument(
        "--name",
        type=str,
        default="yolo11n-best-int8",
        help="Output filename stem (no extension) -- written to yolo/<name>.onnx.",
    )
    parser.add_argument(
        "--compare-fp32",
        type=Path,
        default=HERE / "yolo11n-best.onnx",
        help="Existing fp32 .onnx export to diff per-class mAP against. Pass a missing path (or --skip-compare) to disable.",
    )
    parser.add_argument("--skip-compare", action="store_true", help="Skip the fp32-vs-int8 mAP comparison.")
    args = parser.parse_args()

    if not args.weights.exists():
        raise SystemExit(f"{args.weights} not found.")
    if not args.data.exists():
        raise SystemExit(f"{args.data} not found.")

    with open(args.data) as f:
        nc = yaml.safe_load(f)["nc"]
    expected_channels = 4 + nc

    model = YOLO(str(args.weights))
    assert model.task == "detect", f"task is '{model.task}' -- the app only decodes a plain detect head"

    print(f"=== exporting {args.weights.name} -> INT8 ONNX (imgsz={args.imgsz}, calibrated from {args.data}) ===")
    exported = Path(
        model.export(
            format="onnx",
            imgsz=args.imgsz,
            opset=args.opset,
            nms=False,
            simplify=True,
            int8=True,
            data=str(args.data),
        )
    )

    out_path = HERE / f"{args.name}.onnx"
    shutil.move(str(exported), str(out_path))
    print(f"saved: {out_path}")

    # Sanity check the app's decode loop depends on -- a quantized export
    # that silently changed output shape would corrupt detection rather
    # than error loudly (see onnx_detection_engine.dart's doc comment).
    shape = output_shape(out_path)
    print(f"output shape: {shape} (expected [1, {expected_channels}, N] for nc={nc})")
    if len(shape) != 3 or shape[0] != 1 or shape[1] != expected_channels:
        raise SystemExit(
            "Shape mismatch! onnx_detection_engine.dart expects [1, 4+numClasses, numBoxes] -- "
            "do not drop this into assets/models/model.onnx as-is."
        )

    if not args.skip_compare and args.compare_fp32.exists():
        print("\n=== fp32 vs int8 per-class mAP50-95 (watch 'large' -- it's the rarest class) ===")
        for label, path in (("fp32", args.compare_fp32), ("int8", out_path)):
            metrics = YOLO(str(path)).val(data=str(args.data), imgsz=args.imgsz, verbose=False)
            per_class = dict(zip(metrics.names.values(), metrics.box.maps))
            print(f"{label}: overall mAP50-95={metrics.box.map:.3f}  per-class={per_class}")

    print(
        f"\nDone. To try it in the app: back up assets/models/model.onnx, then copy "
        f"{out_path.name} over it and do a full restart (not hot reload)."
    )


if __name__ == "__main__":
    main()
