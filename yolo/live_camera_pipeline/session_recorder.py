"""Writes annotated frames to disk for the duration of one recording
session (Option 1 in the brief: record button pressed -> stop button
pressed -> video is saved)."""

from __future__ import annotations

import logging
import time
from pathlib import Path

import cv2

from .utils import unique_output_path

logger = logging.getLogger(__name__)


class SessionRecorder:
    def __init__(self, output_dir: str, fourcc: str = "mp4v") -> None:
        self.output_dir = Path(output_dir)
        self.fourcc = fourcc
        self._writer: cv2.VideoWriter | None = None
        self._path: Path | None = None

    @property
    def is_active(self) -> bool:
        return self._writer is not None

    def start(self, fps: float, width: int, height: int, filename: str | None = None) -> Path:
        if self.is_active:
            raise RuntimeError("SessionRecorder.start() called while already recording")

        filename = filename or f"session_{time.strftime('%Y%m%d_%H%M%S')}.mp4"
        path = unique_output_path(self.output_dir / filename)

        writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*self.fourcc), fps, (width, height))
        if not writer.isOpened():
            raise RuntimeError(f"Could not open video writer for {path}")

        self._writer = writer
        self._path = path
        logger.info("Recording started: %s", path)
        return path

    def write(self, frame) -> None:
        if self._writer is not None:
            self._writer.write(frame)

    def stop(self) -> Path | None:
        if self._writer is not None:
            self._writer.release()
            self._writer = None
        path, self._path = self._path, None
        if path is not None:
            logger.info("Recording saved: %s", path)
        return path
