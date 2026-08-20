"""Draws boxes, track IDs, confidence, class name, and the HUD (FPS, total
count, frame number, recording indicator) onto a frame.

Purely cosmetic -- does not affect counting logic. Font/line scale is
derived from frame height instead of the original script's fixed sizes
(tuned for 4K video) since a live camera frame is typically 720p/1080p.
"""

from __future__ import annotations

import cv2

BOX_COLOR = (0, 255, 0)
HUD_COLOR = (0, 255, 0)
REC_COLOR = (0, 0, 255)


class Renderer:
    def __init__(self, class_names: dict[int, str]) -> None:
        self.class_names = class_names

    def draw(
        self,
        frame,
        drawables: list[tuple[int, int, tuple[float, float, float, float], float]],
        display_id: dict[int, int],
        total_count: int,
        fps: float,
        frame_index: int,
        recording: bool,
    ):
        h = frame.shape[0]
        box_scale = max(1, round(h / 480))
        font_scale = max(0.5, h / 960)
        thickness = max(1, round(h / 480))

        for canonical, cls_id, (left, top, right, bottom), conf in drawables:
            did = display_id.get(canonical)
            if did is None:
                continue
            p1, p2 = (int(left), int(top)), (int(right), int(bottom))
            cv2.rectangle(frame, p1, p2, BOX_COLOR, box_scale * 2)
            name = self.class_names.get(cls_id, cls_id)
            label = f"id:{did} {name} {conf:.2f}"
            cv2.putText(
                frame,
                label,
                (p1[0], max(0, p1[1] - 8)),
                cv2.FONT_HERSHEY_SIMPLEX,
                font_scale,
                BOX_COLOR,
                thickness,
                cv2.LINE_AA,
            )

        self._draw_hud(frame, total_count, fps, frame_index, recording, font_scale, thickness)
        return frame

    def _draw_hud(self, frame, total_count, fps, frame_index, recording, font_scale, thickness):
        lines = [
            f"Unique labels: {total_count}",
            f"FPS: {fps:.1f}",
            f"Frame: {frame_index}",
        ]
        y = int(30 * font_scale) + 10
        line_h = int(34 * font_scale)
        for text in lines:
            cv2.putText(
                frame, text, (16, y), cv2.FONT_HERSHEY_SIMPLEX,
                font_scale, HUD_COLOR, thickness, cv2.LINE_AA,
            )
            y += line_h

        if recording:
            cv2.circle(frame, (frame.shape[1] - 30, 30), 10, REC_COLOR, -1)
            cv2.putText(
                frame, "REC", (frame.shape[1] - 90, 38), cv2.FONT_HERSHEY_SIMPLEX,
                font_scale, REC_COLOR, thickness, cv2.LINE_AA,
            )
