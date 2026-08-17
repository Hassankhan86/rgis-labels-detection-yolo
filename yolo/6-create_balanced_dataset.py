"""
Materializes dataset4's oversample as an actual standalone dataset,
dataset4_aug/ -- same idea as 5-balance_dataset.py's train_oversampled.txt (a
path list Ultralytics reads with duplicates), but here the duplicates are
real copied image/label file pairs on disk in standard YOLO layout, rather
than a list of repeated paths back into dataset4. Use this version if you
want dataset4_aug/ to be a self-contained, inspectable dataset (e.g. to hand
off, open in an image viewer, or import elsewhere) instead of relying on a
list file that only Ultralytics understands.

The weighting is class-agnostic -- it duplicates whichever class is rarest
in the source, whatever that happens to be. In dataset3 that was `small`
vs `large` (~15x); in dataset4 it's `price_label` (~6.4x rarer than
`medium`), and this script needs no changes to handle either case.

Only train/ is duplicated. valid/ and test/ are copied through 1:1
unchanged, so evaluation stays honest and the frozen split promised in
dataset4/README.txt (the 6 test images must never be used for training)
carries over untouched.

Output layout (nc=4, matches dataset4/classes.txt: small/medium/large/price_label):
    dataset4_aug/images/{train,valid,test}/*.jpg
    dataset4_aug/labels/{train,valid,test}/*.txt
    dataset4_aug/classes.txt
    dataset4_aug/data.yaml
    dataset4_aug/README.txt

Usage:
    python 6-create_balanced_dataset.py
    python 6-create_balanced_dataset.py --max-repeat 8
"""

import argparse
import math
import shutil
from collections import Counter
from pathlib import Path

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp"}


def load_classes(root: Path) -> list[str]:
    return [line.strip() for line in (root / "classes.txt").read_text().splitlines() if line.strip()]


def class_counts_in_label(label_path: Path) -> Counter:
    counts = Counter()
    for line in label_path.read_text().splitlines():
        line = line.strip()
        if line:
            counts[int(line.split()[0])] += 1
    return counts


def instance_counts(labels_dir: Path) -> Counter:
    counts = Counter()
    for label_path in labels_dir.iterdir():
        counts.update(class_counts_in_label(label_path))
    return counts


def copy_split_unchanged(src_root: Path, dst_root: Path, split: str) -> None:
    """valid/test: straight 1:1 copy, no duplication -- these must reflect the
    true class distribution for evaluation to mean anything."""
    src_images = src_root / "images" / split
    src_labels = src_root / "labels" / split
    dst_images = dst_root / "images" / split
    dst_labels = dst_root / "labels" / split
    dst_images.mkdir(parents=True, exist_ok=True)
    dst_labels.mkdir(parents=True, exist_ok=True)
    for img_path in sorted(src_images.iterdir()):
        if img_path.suffix.lower() not in IMAGE_EXTS:
            continue
        shutil.copy2(img_path, dst_images / img_path.name)
        shutil.copy2(src_labels / f"{img_path.stem}.txt", dst_labels / f"{img_path.stem}.txt")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parent / "dataset4")
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parent / "dataset4_aug")
    parser.add_argument(
        "--max-repeat",
        type=int,
        default=6,
        help="Cap on how many times any single train image is duplicated -- without a cap, an "
        "image containing the single rarest class could dominate the epoch and the model "
        "would effectively overfit to that one photo's background/lighting.",
    )
    args = parser.parse_args()

    source, out = args.source, args.out
    names = load_classes(source)
    nc = len(names)

    if out.exists():
        raise SystemExit(f"{out} already exists -- remove it first if you want to regenerate.")

    train_images_dir = source / "images" / "train"
    train_labels_dir = source / "labels" / "train"

    before_counts = instance_counts(train_labels_dir)
    print("train instance counts (before):", {names[c]: before_counts.get(c, 0) for c in range(nc)})

    max_count = max(before_counts.values())
    class_weight = {c: max_count / before_counts[c] for c in before_counts}
    print("per-class repeat weight (relative to majority class):",
          {names[c]: round(w, 2) for c, w in sorted(class_weight.items())})

    out_images = out / "images" / "train"
    out_labels = out / "labels" / "train"
    out_images.mkdir(parents=True, exist_ok=True)
    out_labels.mkdir(parents=True, exist_ok=True)

    image_paths = sorted(p for p in train_images_dir.iterdir() if p.suffix.lower() in IMAGE_EXTS)
    n_written = 0
    for img_path in image_paths:
        label_path = train_labels_dir / f"{img_path.stem}.txt"
        counts_here = class_counts_in_label(label_path)
        weight = max((class_weight[c] for c in counts_here), default=1.0)
        repeat = max(1, min(args.max_repeat, math.ceil(weight)))

        for copy_idx in range(1, repeat + 1):
            suffix = "" if copy_idx == 1 else f"_dup{copy_idx}"
            dst_img = out_images / f"{img_path.stem}{suffix}{img_path.suffix}"
            dst_lbl = out_labels / f"{img_path.stem}{suffix}.txt"
            shutil.copy2(img_path, dst_img)
            shutil.copy2(label_path, dst_lbl)
            n_written += 1

    for split in ("valid", "test"):
        copy_split_unchanged(source, out, split)

    shutil.copy2(source / "classes.txt", out / "classes.txt")

    data_yaml = out / "data.yaml"
    data_yaml.write_text(
        "train: images/train\n"
        "val: images/valid\n"
        "test: images/test\n\n"
        f"nc: {nc}\n"
        f"names: {names!r}\n"
    )

    readme = out / "README.txt"
    readme.write_text(
        f"{out.name} -- class-balanced oversample of {source.name}, YOLO-detect format\n"
        f"{'=' * 70}\n"
        f"Generated by 6-create_balanced_dataset.py from {source}/.\n"
        f"train/ images containing under-represented classes are duplicated on disk\n"
        f"(filenames get a _dupN suffix; label content is copied unchanged --\n"
        f"no coordinates are altered, this is repetition, not synthetic data).\n"
        f"valid/ and test/ are copied 1:1 from {source.name}, untouched -- the same\n"
        f"6 frozen test images from {source.name}/README.txt, still never to be trained on.\n"
        f"max_repeat cap: {args.max_repeat}\n"
    )

    after_counts = instance_counts(out_labels)
    print()
    print(f"{len(image_paths)} source train images -> {n_written} files written to {out_images}")
    print("train instance counts (after, physical duplicates):",
          {names[c]: after_counts.get(c, 0) for c in range(nc)})
    for split in ("valid", "test"):
        n = len(list((out / 'images' / split).iterdir()))
        print(f"{split}: {n} images copied unchanged")
    print()
    print(f"wrote {out}/ (images/, labels/, classes.txt, data.yaml, README.txt)")
    print(f"train with: yolo task=detect mode=train data={out.name}/data.yaml model=yolo11n.pt epochs=250 imgsz=960")


if __name__ == "__main__":
    main()
