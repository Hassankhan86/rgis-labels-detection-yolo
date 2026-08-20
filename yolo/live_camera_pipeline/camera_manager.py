"""Live camera capture with reconnect handling.

Wraps ``cv2.VideoCapture`` for a webcam/USB camera during Windows/edge-PC
development. Frame acquisition is intentionally isolated behind this one
class so the rest of the pipeline never touches cv2.VideoCapture directly
-- swapping this out for a Flutter camera-plugin frame feed later (see
README "Future Android/Flutter integration") means replacing this file
only.
"""

from __future__ import annotations

import logging
import time

import cv2

from .errors import CameraError

logger = logging.getLogger(__name__)


class CameraManager:
    def __init__(
        self,
        source: int | str = 0,
        width: int | None = None,
        height: int | None = None,
        reconnect_attempts: int = 5,
        reconnect_delay_s: float = 1.0,
    ) -> None:
        self.source = source
        self.width = width
        self.height = height
        self.reconnect_attempts = reconnect_attempts
        self.reconnect_delay_s = reconnect_delay_s
        self._cap: cv2.VideoCapture | None = None

    def open(self) -> None:
        cap = cv2.VideoCapture(self.source)
        if self.width:
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
        if self.height:
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)
        if not cap.isOpened():
            cap.release()
            raise CameraError(f"Could not open camera source: {self.source!r}")
        self._cap = cap

    def release(self) -> None:
        if self._cap is not None:
            self._cap.release()
            self._cap = None

    @property
    def is_open(self) -> bool:
        return self._cap is not None and self._cap.isOpened()

    @property
    def fps(self) -> float:
        if self._cap is None:
            return 30.0
        return self._cap.get(cv2.CAP_PROP_FPS) or 30.0

    @property
    def frame_size(self) -> tuple[int, int]:
        if self._cap is None:
            return (self.width or 1280, self.height or 720)
        w = int(self._cap.get(cv2.CAP_PROP_FRAME_WIDTH)) or (self.width or 1280)
        h = int(self._cap.get(cv2.CAP_PROP_FRAME_HEIGHT)) or (self.height or 720)
        return (w, h)

    def read(self):
        """Read one frame. Transparently reconnects on a dropped camera or
        an empty/corrupt frame. Returns None only after exhausting
        `reconnect_attempts` -- callers should treat that as "give up"."""
        if not self.is_open and not self._reconnect():
            return None

        ok, frame = self._cap.read()
        if ok and frame is not None and frame.size > 0:
            return frame

        logger.warning("Empty/failed frame read from camera source %r", self.source)
        if not self._reconnect():
            return None

        ok, frame = self._cap.read()
        if ok and frame is not None and frame.size > 0:
            return frame
        return None

    def _reconnect(self) -> bool:
        for attempt in range(1, self.reconnect_attempts + 1):
            logger.warning(
                "Camera disconnected; reconnect attempt %d/%d",
                attempt,
                self.reconnect_attempts,
            )
            self.release()
            time.sleep(self.reconnect_delay_s)
            try:
                self.open()
                return True
            except CameraError as exc:
                logger.warning("Reconnect attempt %d failed: %s", attempt, exc)
        logger.error(
            "Camera source %r unrecoverable after %d attempts",
            self.source,
            self.reconnect_attempts,
        )
        return False

    def __enter__(self) -> "CameraManager":
        self.open()
        return self

    def __exit__(self, *exc_info) -> None:
        self.release()
