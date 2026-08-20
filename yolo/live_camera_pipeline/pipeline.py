"""Application orchestrator.

Wires CameraManager -> StreamTracker -> IncrementalDuplicateResolver ->
LabelCounter -> BoxSmoother -> Renderer -> SessionRecorder into the same
per-frame flow ``track_and_count.py`` runs per frame, just live instead
of from a decoded file, and split into an explicit start/stop recording
session (Option 1 in the brief).

`LiveCountingPipeline.process_frame()` is the reusable, camera-agnostic
core -- it takes a decoded BGR frame (numpy array) in and returns an
annotated frame + running stats out. `run_camera_loop()` is a thin
Windows/edge-PC demo harness around it (OpenCV window + keyboard). A
future Flutter bridge only needs to call `start_session()` /
`process_frame(frame)` / `stop_session()` with frames it decodes itself
-- see README "Future Android/Flutter integration".
"""

from __future__ import annotations

import logging
import time

import cv2

from .camera_manager import CameraManager
from .config import PipelineConfig
from .counter import LabelCounter
from .detector import Detector
from .duplicate_resolver import IncrementalDuplicateResolver
from .errors import CameraError, ModelLoadError
from .fps_meter import FPSMeter
from .renderer import Renderer
from .session_recorder import SessionRecorder
from .smoother import BoxSmoother
from .tracker import StreamTracker

logger = logging.getLogger(__name__)


class LiveCountingPipeline:
    def __init__(self, config: PipelineConfig) -> None:
        self.config = config

        self.detector = Detector(config.model_path, device=config.device)
        self.tracker = StreamTracker(
            self.detector, config.tracker_cfg, config.conf, config.imgsz
        )
        self.renderer = Renderer(self.detector.names)
        self.recorder = SessionRecorder(config.output_dir, config.output_fourcc)
        self.fps_meter = FPSMeter()

        self.resolver: IncrementalDuplicateResolver | None = None
        self.counter: LabelCounter | None = None
        self.smoother: BoxSmoother | None = None
        self.frame_index = 0
        self.recording = False

    # --- Session control (maps to the record / stop buttons in Option 1) ---

    def start_session(self, fps: float, width: int, height: int, filename: str | None = None):
        if self.recording:
            raise RuntimeError("start_session() called while a session is already active")

        self.resolver = IncrementalDuplicateResolver(
            self.config.merge_max_gap, self.config.merge_distance_factor
        )
        self.counter = LabelCounter(self.config.min_hits)
        self.smoother = BoxSmoother(self.config.smooth_alpha, self.config.coast_frames)
        self.tracker.reset()  # tracker state must not leak between sessions
        self.frame_index = 0

        path = self.recorder.start(fps, width, height, filename)
        self.recording = True
        logger.info("Session started")
        return path

    def stop_session(self) -> dict:
        if not self.recording:
            raise RuntimeError("stop_session() called with no active session")

        summary = self.counter.summary(self.detector.names) if self.counter else {}
        saved_path = self.recorder.stop()
        self.recording = False
        summary["saved_path"] = str(saved_path) if saved_path else None
        summary["frames_processed"] = self.frame_index
        logger.info("Session stopped: %s", summary)
        return summary

    # --- Per-frame processing (camera-agnostic core) ---

    def process_frame(self, frame):
        """Run detection -> tracking -> duplicate resolution -> counting
        -> smoothing -> drawing on one frame. Must be called within an
        active session (after start_session(), before stop_session())."""
        if not self.recording:
            raise RuntimeError("process_frame() called outside an active session")

        self.frame_index += 1
        self.fps_meter.tick()

        detections = self.tracker.update(frame, self.frame_index)
        for tid, cls_id, box, conf in detections:
            canonical = self.resolver.observe(tid, cls_id, box, self.frame_index)
            _, _ = self.counter.register_hit(canonical, cls_id)
            self.smoother.update(canonical, cls_id, box, conf, self.frame_index)

        drawables = self.smoother.drawable(self.frame_index, self.counter.confirmed_ids)
        annotated = self.renderer.draw(
            frame,
            drawables,
            self.counter.display_id,
            self.counter.total,
            self.fps_meter.fps,
            self.frame_index,
            recording=True,
        )
        self.recorder.write(annotated)
        return annotated, self.counter.summary(self.detector.names)

    # --- Desktop/edge-PC demo harness ---

    def run_camera_loop(self) -> None:
        cfg = self.config
        camera = CameraManager(
            cfg.camera_source,
            cfg.capture_width,
            cfg.capture_height,
            cfg.reconnect_attempts,
            cfg.reconnect_delay_s,
        )
        try:
            camera.open()
        except CameraError as exc:
            logger.error("Cannot start: %s", exc)
            return

        idle_fps = FPSMeter()
        print(
            "Camera open. Controls: [r] start recording  [s] stop recording  "
            "[q] / ESC quit"
        )
        try:
            while True:
                frame = camera.read()
                if frame is None:
                    logger.error("Camera unrecoverable, exiting.")
                    break

                if self.recording:
                    display_frame, _ = self.process_frame(frame)
                else:
                    idle_fps.tick()
                    display_frame = self._draw_idle_hud(frame, idle_fps.fps)

                if cfg.display_scale != 1.0:
                    h, w = display_frame.shape[:2]
                    display_frame = cv2.resize(
                        display_frame,
                        (round(w * cfg.display_scale), round(h * cfg.display_scale)),
                    )
                cv2.imshow(cfg.window_name, display_frame)

                key = cv2.waitKey(1) & 0xFF
                if key in (ord("q"), 27):  # 'q' or ESC
                    break
                elif key == ord("r") and not self.recording:
                    w, h = camera.frame_size
                    self.start_session(camera.fps, w, h)
                elif key == ord("s") and self.recording:
                    summary = self.stop_session()
                    print(f"Saved: {summary}")
        except KeyboardInterrupt:
            logger.info("Interrupted by user")
        finally:
            if self.recording:
                summary = self.stop_session()
                print(f"Saved (on exit): {summary}")
            camera.release()
            cv2.destroyAllWindows()

    @staticmethod
    def _draw_idle_hud(frame, fps: float):
        cv2.putText(
            frame, f"Live preview (idle) - FPS: {fps:.1f} - press 'r' to record",
            (16, 34), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 200, 255), 2, cv2.LINE_AA,
        )
        return frame
