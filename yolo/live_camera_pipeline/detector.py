"""YOLO11 model loading with device selection and a CPU fallback.

Same model weights/class as ``track_and_count.py`` (``YOLO(model_path)``);
this only adds device resolution (GPU-unavailable handling) and a clear
failure mode if the weights file is missing or corrupt.
"""

from __future__ import annotations

import logging
from pathlib import Path

from ultralytics import YOLO

from .errors import ModelLoadError

logger = logging.getLogger(__name__)


class Detector:
    def __init__(self, model_path: str, device: str = "auto") -> None:
        self.model_path = Path(model_path)
        if not self.model_path.exists():
            raise ModelLoadError(f"Model weights not found: {self.model_path}")

        self.device = self._resolve_device(device)
        self.model = self._load(self.device)

    @staticmethod
    def _resolve_device(device: str) -> str:
        if device != "auto":
            return device
        try:
            import torch

            return "cuda:0" if torch.cuda.is_available() else "cpu"
        except Exception:
            return "cpu"

    def _load(self, device: str) -> YOLO:
        try:
            model = YOLO(str(self.model_path))
            model.to(device)
            return model
        except Exception as exc:
            if device != "cpu":
                logger.warning("GPU unavailable/failed (%s); falling back to CPU", exc)
                self.device = "cpu"
                try:
                    model = YOLO(str(self.model_path))
                    model.to("cpu")
                    return model
                except Exception as cpu_exc:
                    raise ModelLoadError(
                        f"Failed to load model on CPU after GPU fallback: {cpu_exc}"
                    ) from cpu_exc
            raise ModelLoadError(f"Failed to load model: {exc}") from exc

    @property
    def names(self) -> dict[int, str]:
        return self.model.names
