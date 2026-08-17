"""
Runs a trained checkpoint over a folder of images and saves annotated
predictions (boxes + labels + confidence drawn, one fixed color per class).
Only files with a known image extension are picked up -- anything else in
that folder is ignored.

Each run gets its own output folder under test_results/predict --
auto-numbered (predict, predict2, predict3, ...) so nothing gets overwritten.

Usage:
    python 2-test_model.py path/to/some/images
    python 2-test_model.py path/to/some/images --weights content/runs/yolo26n_detect/weights/best.pt
    python 2-test_model.py path/to/some/images --conf 0.35
"""

import argparse
from pathlib import Path

import cv2
from ultralytics import YOLO
from ultralytics.utils.files import increment_path

HERE = Path(__file__).resolve().parent
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp"}

# OpenCV uses BGR, not RGB.
CLASS_COLORS_BGR = {
    "small": (0, 255, 0),        # green
    "medium": (255, 0, 0),       # blue
    "large": (0, 0, 255),        # red
    "price_label": (0, 165, 255), # orange
}
DEFAULT_COLOR_BGR = (0, 255, 255)  # any class not in the map above
BOX_THICKNESS = 5
FONT_SCALE = 3


def draw_predictions(result, save_path: Path) -> dict:
    img = result.orig_img.copy()
    counts: dict = {}
    for box in result.boxes:
        cls_id = int(box.cls.item())
        name = result.names[cls_id]
        conf = float(box.conf.item())
        x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
        color = CLASS_COLORS_BGR.get(name, DEFAULT_COLOR_BGR)

        cv2.rectangle(img, (x1, y1), (x2, y2), color, BOX_THICKNESS)
        label = f"{name} {conf:.2f}"
        (tw, th), baseline = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, FONT_SCALE, BOX_THICKNESS)
        cv2.rectangle(img, (x1, y1 - th - baseline - 2), (x1 + tw + 2, y1), color, -1)
        cv2.putText(img, label, (x1 + 1, y1 - baseline), cv2.FONT_HERSHEY_SIMPLEX,
                    FONT_SCALE, (255, 255, 255), BOX_THICKNESS, cv2.LINE_AA)

        counts[name] = counts.get(name, 0) + 1

    cv2.imwrite(str(save_path), img)
    return counts


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("images", type=Path, help="Folder of images to predict on.")
    parser.add_argument("--weights", type=Path, default=HERE / "yolo11n-best.pt")
    parser.add_argument("--imgsz", type=int, default=960, help="Should match the imgsz the checkpoint was trained at.")
    parser.add_argument("--conf", type=float, default=0.5, help="Matches AppConstants.defaultConfidenceThreshold.")
    parser.add_argument("--iou", type=float, default=0.45, help="Matches AppConstants.defaultIouThreshold.")
    parser.add_argument("--project", type=Path, default=HERE / "test_results")
    parser.add_argument("--name", type=str, default="predict")
    args = parser.parse_args()

    if not args.weights.exists():
        raise SystemExit(f"{args.weights} not found.")
    if not args.images.is_dir():
        raise SystemExit(f"{args.images} is not a folder.")

    image_paths = sorted(p for p in args.images.iterdir() if p.suffix.lower() in IMAGE_EXTS)
    if not image_paths:
        raise SystemExit(f"No images ({', '.join(sorted(IMAGE_EXTS))}) found in {args.images}.")

    model = YOLO(str(args.weights))

    print(f"=== running predictions on {len(image_paths)} image(s) from {args.images} ===")
    results = model.predict(
        source=[str(p) for p in image_paths],
        imgsz=args.imgsz,
        conf=args.conf,
        iou=args.iou,
        save=False,  # custom drawing below instead of Ultralytics' default per-class palette
    )

    save_dir = increment_path(args.project / args.name, exist_ok=False)
    save_dir.mkdir(parents=True, exist_ok=True)

    for r in results:
        img_path = Path(r.path)
        counts = draw_predictions(r, save_dir / img_path.name)
        print(f"  {img_path.name}: {counts or '{}'}")

    print(f"\nSaved to {save_dir}")


if __name__ == "__main__":
    main()
