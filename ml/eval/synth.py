"""Synthetic gate-camera frames from LFW crops.

LFW ships faces already cropped. To exercise the *whole* pipeline (detector,
keypoints, alignment) we paste each crop into a 640x480 frame the way the gate
camera would see a worker at 0.6-1 m: random size, position, in-plane tilt,
exposure and sensor noise, over a cluttered background. The detector then has
to find the face again and the aligner has to undo the tilt and scale.
"""

from __future__ import annotations

import cv2
import numpy as np

FRAME_W, FRAME_H = 640, 480


def _background(rng: np.random.Generator) -> np.ndarray:
    coarse = rng.uniform(30, 210, size=(6, 8, 3)).astype(np.float32)
    bg = cv2.resize(coarse, (FRAME_W, FRAME_H), interpolation=cv2.INTER_CUBIC)
    bg += rng.normal(0, 6, size=bg.shape).astype(np.float32)
    return bg


def make_frame(face_rgb: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """One RGB uint8 640x480 frame containing ``face_rgb`` (112x112)."""
    scale = rng.uniform(1.3, 2.2)
    angle = rng.uniform(-12, 12)
    size = 112 * scale
    cx = rng.uniform(0.7 * size, FRAME_W - 0.7 * size)
    cy = rng.uniform(0.7 * size, FRAME_H - 0.7 * size)
    m = cv2.getRotationMatrix2D((56.0, 56.0), angle, scale)
    m[:, 2] += (cx - 56.0, cy - 56.0)

    face = cv2.warpAffine(face_rgb.astype(np.float32), m, (FRAME_W, FRAME_H), flags=cv2.INTER_LINEAR)
    mask = np.zeros((112, 112), np.float32)
    cv2.rectangle(mask, (4, 4), (107, 107), 1.0, -1)
    mask = cv2.GaussianBlur(mask, (9, 9), 3)
    mask = cv2.warpAffine(mask, m, (FRAME_W, FRAME_H), flags=cv2.INTER_LINEAR)[..., None]

    frame = face * mask + _background(rng) * (1 - mask)
    frame = frame * rng.uniform(0.75, 1.2) + rng.uniform(-25, 25)
    frame += rng.normal(0, rng.uniform(1.5, 4.0), size=frame.shape)
    return np.clip(frame, 0, 255).astype(np.uint8)
