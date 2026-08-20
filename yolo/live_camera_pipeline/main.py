"""CLI entry point for the live-camera label counter.

Run from the RGIS_Flutter repo root (so the package import resolves):

    python -m live_camera_pipeline.main --camera 0

See README.md for full run instructions, keyboard controls, and
performance tuning notes.
"""

from __future__ import annotations

import argparse
import logging

from .config import PipelineConfig
from .errors import ModelLoadError
from .pipeline import LiveCountingPipeline


def parse_args() -> argparse.Namespace:
    defaults = PipelineConfig()
    parser = argparse.ArgumentParser(description=__doc__)

    parser.add_argument("--model", default=defaults.model_path, help="Path to YOLO model weights.")
    parser.add_argument("--device", default=defaults.device, help='"auto", "cpu", or "cuda:0".')
    parser.add_argument("--camera", default=defaults.camera_source, help="Camera index or video path/URL.")
    parser.add_argument("--capture-width", type=int, default=defaults.capture_width)
    parser.add_argument("--capture-height", type=int, default=defaults.capture_height)
    parser.add_argument("--tracker", default=defaults.tracker_cfg, help="Ultralytics tracker config (botsort.yaml).")
    parser.add_argument("--conf", type=float, default=defaults.conf, help="Detection confidence threshold.")
    parser.add_argument("--imgsz", type=int, default=defaults.imgsz, help="Inference image size (smaller = faster).")
    parser.add_argument("--min-hits", type=int, default=defaults.min_hits)
    parser.add_argument("--merge-max-gap", type=int, default=defaults.merge_max_gap)
    parser.add_argument("--merge-distance-factor", type=float, default=defaults.merge_distance_factor)
    parser.add_argument("--smooth-alpha", type=float, default=defaults.smooth_alpha)
    parser.add_argument("--coast-frames", type=int, default=defaults.coast_frames)
    parser.add_argument("--output-dir", default=defaults.output_dir, help="Where recorded sessions are saved.")
    parser.add_argument("--display-scale", type=float, default=defaults.display_scale)
    parser.add_argument("-v", "--verbose", action="store_true", help="Debug-level logging.")

    return parser.parse_args()


def main() -> None:
    args = parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    camera_source: int | str = args.camera
    if isinstance(camera_source, str) and camera_source.isdigit():
        camera_source = int(camera_source)

    config = PipelineConfig(
        model_path=args.model,
        device=args.device,
        tracker_cfg=args.tracker,
        conf=args.conf,
        imgsz=args.imgsz,
        min_hits=args.min_hits,
        merge_max_gap=args.merge_max_gap,
        merge_distance_factor=args.merge_distance_factor,
        smooth_alpha=args.smooth_alpha,
        coast_frames=args.coast_frames,
        camera_source=camera_source,
        capture_width=args.capture_width,
        capture_height=args.capture_height,
        output_dir=args.output_dir,
        display_scale=args.display_scale,
    )

    try:
        pipeline = LiveCountingPipeline(config)
    except ModelLoadError as exc:
        logging.getLogger(__name__).error("Model loading failed: %s", exc)
        raise SystemExit(1) from exc

    pipeline.run_camera_loop()


if __name__ == "__main__":
    main()
