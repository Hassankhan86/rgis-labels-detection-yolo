"""
Creates a new Label Studio project and imports dataset3 (43 images across
its frozen train/valid/test split) with the existing YOLO-segmentation
polygon labels brought in as pre-annotations ("predictions") -- so the
project opens with polygons already drawn per class (small/medium/large/
price_label(untiered)), ready to review or correct rather than label from
scratch.

Requires a Label Studio Personal Access Token: in the Label Studio UI,
account avatar (top right) -> Account & Settings -> Access Token.

This talks to a real, documented Label Studio REST API (projects, import,
predictions) but hasn't been run against this specific instance/version yet
-- run it for real (drop --dry-run) and we'll fix anything that doesn't
match based on actual responses.

Usage:
    python 4-push_to_labelstudio.py --token <your-token> --dry-run
    python 4-push_to_labelstudio.py --token <your-token>
    python 4-push_to_labelstudio.py --token <your-token> --skip-predictions
"""

import argparse
import base64
import json
import re
from pathlib import Path

import requests
from PIL import Image

HERE = Path(__file__).resolve().parent
SPLITS = ("train", "valid", "test")
IMAGE_EXTS = {".jpg", ".jpeg", ".png"}

# small / medium / large / price_label(untiered), by classes.txt line order.
LABEL_COLORS = ["#3BB273", "#4C6EF5", "#E8590C", "#F2C438"]


def load_class_names(dataset_dir: Path) -> list[str]:
    return [line.strip() for line in (dataset_dir / "classes.txt").read_text().splitlines() if line.strip()]


def build_label_config(names: list[str]) -> str:
    labels_xml = "\n".join(
        f'    <Label value="{name}" background="{LABEL_COLORS[i % len(LABEL_COLORS)]}"/>'
        for i, name in enumerate(names)
    )
    return f"""<View>
  <Image name="image" value="$image" zoom="true"/>
  <PolygonLabels name="label" toName="image">
{labels_xml}
  </PolygonLabels>
</View>"""


def decode_jwt_payload(token: str) -> dict | None:
    parts = token.split(".")
    if len(parts) != 3:
        return None  # not a JWT -- e.g. a legacy Label Studio API token
    padded = parts[1] + "=" * (-len(parts[1]) % 4)
    try:
        return json.loads(base64.urlsafe_b64decode(padded))
    except Exception:
        return None


def resolve_auth_header(session: requests.Session, url: str, token: str) -> str:
    """Legacy tokens aren't JWTs -> used as-is. A JWT *access* token is used
    as-is. A JWT *refresh* token (Label Studio's Account & Settings page can
    hand out either) is exchanged for a fresh access token first, since a
    refresh token isn't itself valid for authenticating regular API calls."""
    payload = decode_jwt_payload(token)
    if payload is None:
        return f"Token {token}"

    if payload.get("token_type") == "refresh":
        print("Given token is a JWT refresh token -- exchanging it for an access token...")
        resp = session.post(f"{url}/api/token/refresh/", json={"refresh": token})
        resp.raise_for_status()
        return f"Bearer {resp.json()['access']}"

    return f"Bearer {token}"


# Label Studio names uploaded files "<8-hex-char-hash>-<original filename>".
UPLOAD_FILENAME_RE = re.compile(r"^[0-9a-f]{8}-(.+)$")


def fetch_existing_tasks(session: requests.Session, url: str, project_id: int) -> dict[str, dict]:
    """Maps original filename -> {'id': task_id, 'total_predictions': n} for
    every task already in the project, so re-running this script is safe:
    already-uploaded images aren't re-uploaded, already-predicted tasks
    aren't given duplicate predictions."""
    resp = session.get(f"{url}/api/tasks/", params={"project": project_id, "page_size": 10000})
    resp.raise_for_status()
    mapping = {}
    for task in resp.json()["tasks"]:
        basename = task.get("data", {}).get("image", "").rsplit("/", 1)[-1]
        m = UPLOAD_FILENAME_RE.match(basename)
        filename = m.group(1) if m else basename
        mapping[filename] = {"id": task["id"], "total_predictions": task.get("total_predictions", 0)}
    return mapping


def yolo_polygon_to_ls_result(line: str, names: list[str], img_w: int, img_h: int) -> dict:
    parts = line.split()
    cls_id = int(parts[0])
    coords = [float(v) for v in parts[1:]]
    # YOLO points are already normalized 0..1; Label Studio wants percent 0..100.
    points = [[coords[i] * 100, coords[i + 1] * 100] for i in range(0, len(coords), 2)]
    return {
        "original_width": img_w,
        "original_height": img_h,
        "image_rotation": 0,
        "value": {"points": points, "polygonlabels": [names[cls_id]]},
        "from_name": "label",
        "to_name": "image",
        "type": "polygonlabels",
        "origin": "manual",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--token", required=True, help="Label Studio Personal Access Token.")
    parser.add_argument("--url", default="http://localhost:8080")
    parser.add_argument("--dataset", type=Path, default=HERE / "dataset3")
    parser.add_argument("--project-name", default="RGIS tier labels v1 (dataset3)")
    parser.add_argument("--project-id", type=int, default=None,
                         help="Reuse an existing project instead of creating a new one "
                         "(e.g. to attach predictions to images already uploaded there).")
    parser.add_argument("--skip-predictions", action="store_true", help="Import images only, no pre-annotations.")
    parser.add_argument("--dry-run", action="store_true", help="Build everything but don't call the API.")
    args = parser.parse_args()

    names = load_class_names(args.dataset)
    print(f"classes ({len(names)}): {names}")
    label_config = build_label_config(names)

    if args.dry_run:
        print("\n--- label_config that would be used ---")
        print(label_config)

    # Gather (split, img_path, label_lines) up front -- used for both dry-run
    # reporting and the real run.
    all_items = []
    for split in SPLITS:
        images_dir = args.dataset / "images" / split
        labels_dir = args.dataset / "labels" / split
        for img_path in sorted(p for p in images_dir.iterdir() if p.suffix.lower() in IMAGE_EXTS):
            label_path = labels_dir / f"{img_path.stem}.txt"
            lines = [l for l in label_path.read_text().splitlines() if l.strip()] if label_path.exists() else []
            all_items.append((split, img_path, lines))

    if args.dry_run:
        for split, img_path, lines in all_items:
            print(f"  {split}/{img_path.name}: {len(lines)} polygon(s)")
        total_polygons = sum(len(lines) for _, _, lines in all_items)
        print(f"\nDry run: would import {len(all_items)} image(s), {total_polygons} polygon(s) total. "
              f"Drop --dry-run to actually push to {args.url}.")
        return

    session = requests.Session()
    session.headers.update({"Authorization": resolve_auth_header(session, args.url, args.token)})

    if args.project_id is not None:
        project_id = args.project_id
        print(f"using existing project id={project_id}")
    else:
        resp = session.post(
            f"{args.url}/api/projects/",
            json={
                "title": args.project_name,
                "label_config": label_config,
                "description": "Imported from yolo/dataset3 (frozen 43-image tier-label split).",
            },
        )
        resp.raise_for_status()
        project = resp.json()
        project_id = project["id"]
        print(f"created project id={project_id} title={project['title']!r}")

    # Phase 1: upload whatever isn't already a task in this project (matched
    # by original filename), so re-running this script never creates dupes.
    existing = fetch_existing_tasks(session, args.url, project_id)
    print(f"{len(existing)} task(s) already present in project")

    for split, img_path, _lines in all_items:
        if img_path.name in existing:
            continue
        with open(img_path, "rb") as f:
            upload_resp = session.post(
                f"{args.url}/api/projects/{project_id}/import",
                files={"file": (img_path.name, f, "application/octet-stream")},
            )
        upload_resp.raise_for_status()
        print(f"  uploaded {split}/{img_path.name}")

    # Phase 2: re-fetch so newly uploaded images have real task ids, then
    # attach predictions to whichever tasks don't already have any.
    existing = fetch_existing_tasks(session, args.url, project_id)
    total_polygons = 0

    if not args.skip_predictions:
        for split, img_path, lines in all_items:
            task = existing.get(img_path.name)
            if task is None:
                print(f"  WARNING: {img_path.name} still has no task after upload -- skipping predictions")
                continue
            if task["total_predictions"] > 0:
                print(f"  {img_path.name} -> task {task['id']} already has predictions, skipping")
                continue
            if not lines:
                print(f"  {img_path.name} -> task {task['id']} (no labels)")
                continue

            with Image.open(img_path) as im:
                img_w, img_h = im.size
            results = [yolo_polygon_to_ls_result(line, names, img_w, img_h) for line in lines]

            pred_resp = session.post(
                f"{args.url}/api/predictions/",
                json={"task": task["id"], "result": results, "model_version": "yolo-seg-dataset3-v1"},
            )
            pred_resp.raise_for_status()
            total_polygons += len(results)
            print(f"  {img_path.name} -> task {task['id']} ({len(results)} polygon(s))")

    print(f"\nDone: {len(all_items)} image(s), {total_polygons} new polygon prediction(s). "
          f"Open {args.url}/projects/{project_id}/data to review.")


if __name__ == "__main__":
    main()
