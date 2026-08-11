"""
Reads the flat Label Studio export in dataset2/ (images/, labels/, classes.txt)
and writes a ready-to-train YOLO dataset, split into train/valid/test -- same
layout as dataset1/ (Roboflow-style: each split has its own images/ and
labels/ subfolder):

    dataset2_ready/train/images/*.jpg
    dataset2_ready/train/labels/*.txt
    dataset2_ready/valid/images/*.jpg
    dataset2_ready/valid/labels/*.txt
    dataset2_ready/test/images/*.jpg
    dataset2_ready/test/labels/*.txt
    dataset2_ready/data.yaml

Label rows are already YOLO-segmentation polygons ("cls x1 y1 x2 y2 ...").
They're copied through unchanged -- Ultralytics accepts polygon rows for
both detect (auto-converts to the enclosing box) and segment tasks, so no
reformatting is needed either way.

Usage:
    python prepare_dataset.py
    python prepare_dataset.py --valid-ratio 0.15 --test-ratio 0.15
"""

import argparse
import json
import random
import shutil
from collections import Counter
from pathlib import Path

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp"}


def load_class_names(source: Path) -> list[str]:
    classes_txt = source / "classes.txt"
    if classes_txt.exists():
        names = [line.strip() for line in classes_txt.read_text().splitlines() if line.strip()]
        if names:
            return names

    notes_json = source / "notes.json"
    if notes_json.exists():
        data = json.loads(notes_json.read_text())
        cats = sorted(data["categories"], key=lambda c: c["id"])
        return [c["name"] for c in cats]

    raise FileNotFoundError(f"No classes.txt or notes.json found under {source}")


def collect_pairs(source: Path) -> list[tuple[Path, Path]]:
    images_dir = source / "images"
    labels_dir = source / "labels"
    pairs = []
    for img_path in sorted(images_dir.iterdir()):
        if img_path.suffix.lower() not in IMAGE_EXTS:
            continue
        label_path = labels_dir / f"{img_path.stem}.txt"
        if not label_path.exists():
            print(f"skipping {img_path.name}: no matching label file")
            continue
        pairs.append((img_path, label_path))
    return pairs


def filtered_label_lines(label_path: Path, num_classes: int) -> list[str]:
    """Drops rows referencing a class id outside the known 0..num_classes-1 range."""
    lines = []
    for line in label_path.read_text().splitlines():
        line = line.strip()
        if line and int(line.split()[0]) < num_classes:
            lines.append(line)
    return lines


def warn_about_unknown_classes(pairs: list[tuple[Path, Path]], num_classes: int) -> None:
    dropped = Counter()
    dropped_files = set()
    for _, label_path in pairs:
        for line in label_path.read_text().splitlines():
            line = line.strip()
            if line and int(line.split()[0]) >= num_classes:
                dropped[int(line.split()[0])] += 1
                dropped_files.add(label_path.name)
    if dropped:
        print(f"WARNING: label rows reference class ids outside the {num_classes} known classes "
              f"(classes.txt only defines ids 0..{num_classes - 1}): {dict(dropped)} instance(s), "
              f"in {len(dropped_files)} file(s): {sorted(dropped_files)}")
        print("These rows are dropped from the output -- this is a labeling error upstream in "
              "Label Studio (e.g. a class created then removed). Fix it at the source in "
              "dataset2/labels/ if those instances matter, then re-run this script.")


def instance_counts(pairs: list[tuple[Path, Path]], num_classes: int) -> Counter:
    counts = Counter()
    for _, label_path in pairs:
        for line in filtered_label_lines(label_path, num_classes):
            counts[int(line.split()[0])] += 1
    return counts


def write_pair(img_path: Path, label_path: Path, split_dir: Path, num_classes: int) -> None:
    shutil.copy2(img_path, split_dir / "images" / img_path.name)
    lines = filtered_label_lines(label_path, num_classes)
    (split_dir / "labels" / f"{img_path.stem}.txt").write_text("\n".join(lines) + ("\n" if lines else ""))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parent.parent / "dataset2")
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parent.parent / "dataset2_ready")
    parser.add_argument("--valid-ratio", type=float, default=0.15)
    parser.add_argument("--test-ratio", type=float, default=0.15)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    names = load_class_names(args.source)
    print(f"classes ({len(names)}): {names}")

    pairs = collect_pairs(args.source)
    print(f"{len(pairs)} labeled images found in {args.source}")
    warn_about_unknown_classes(pairs, len(names))

    rng = random.Random(args.seed)
    shuffled = pairs[:]
    rng.shuffle(shuffled)

    n_total = len(shuffled)
    n_valid = max(1, round(n_total * args.valid_ratio))
    n_test = max(1, round(n_total * args.test_ratio))
    n_train = n_total - n_valid - n_test
    if n_train < 1:
        raise SystemExit(f"valid+test ratios leave no images for train (out of {n_total} total) -- lower them.")

    splits = {
        "train": shuffled[:n_train],
        "valid": shuffled[n_train:n_train + n_valid],
        "test": shuffled[n_train + n_valid:],
    }
    print(f"split: {n_train} train / {n_valid} valid / {n_test} test (of {n_total} total)")

    if args.out.exists():
        shutil.rmtree(args.out)
    for split in splits:
        (args.out / split / "images").mkdir(parents=True, exist_ok=True)
        (args.out / split / "labels").mkdir(parents=True, exist_ok=True)

    for split, split_pairs in splits.items():
        for img_path, label_path in split_pairs:
            write_pair(img_path, label_path, args.out / split, len(names))
        counts = instance_counts(split_pairs, len(names))
        print(f"{split} instance counts:", {names[c]: n for c, n in sorted(counts.items())})

    missing_from_valid = [
        names[c] for c in range(len(names))
        if instance_counts(splits["valid"], len(names)).get(c, 0) == 0
    ]
    if missing_from_valid:
        print(f"WARNING: {missing_from_valid} have zero instances in valid -- per-class val metrics "
              "for them will be meaningless with a dataset this small.")

    data_yaml = args.out / "data.yaml"
    data_yaml.write_text(
        "train: train/images\n"
        "val: valid/images\n"
        "test: test/images\n\n"
        f"nc: {len(names)}\n"
        f"names: {names!r}\n"
    )
    print(f"wrote {data_yaml}")


if __name__ == "__main__":
    main()
