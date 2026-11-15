"""Reference implementation of the SyncGate face pipeline (ADR-0006).

This is the *spec* the Dart pipeline in ``packages/sg_vision`` mirrors, stage
for stage, with the same constants. It runs the exact ``.tflite`` files that
ship in the app.

  frame (RGB, any size)
    -> detect   BlazeFace short-range, 128x128 letterbox, [-1, 1] input
    -> refine   second BlazeFace pass on a square crop around the face
    -> align    4-point similarity transform onto the ArcFace template
                (eyes, nose tip, mouth centre) -> 112x112 RGB
    -> embed    SFace (MobileFaceNet, SFace loss), 0..255 RGB input,
                128-d output, L2-normalised
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
from ai_edge_litert.interpreter import Interpreter

DET_SIZE = 128
DET_SCORE_MIN = 0.5
DET_NMS_IOU = 0.3
REFINE_CROP_SCALE = 2.0  # crop side = scale * max(box w, h)
ALIGN_SIZE = 112

# ArcFace 112x112 template: right eye, left eye (subject's), nose tip, mouth
# centre (midpoint of the two mouth corners of the 5-point template).
ARCFACE_4PT = np.array(
    [
        [38.2946, 51.6963],
        [73.5318, 51.5014],
        [56.0252, 71.7366],
        [(41.5493 + 70.7299) / 2, (92.3655 + 92.2041) / 2],
    ],
    dtype=np.float64,
)


def ssd_anchors() -> np.ndarray:
    """896 anchor centres for BlazeFace short-range (MediaPipe options)."""
    out = []
    for stride, per_cell in ((8, 2), (16, 6)):
        n = DET_SIZE // stride
        for y in range(n):
            for x in range(n):
                for _ in range(per_cell):
                    out.append(((x + 0.5) / n, (y + 0.5) / n))
    return np.array(out, dtype=np.float32)


ANCHORS = ssd_anchors()


@dataclass
class Face:
    score: float
    box: np.ndarray  # x0, y0, x1, y1 in frame pixels
    kps: np.ndarray  # 6 x 2 in frame pixels: r-eye, l-eye, nose, mouth, r-ear, l-ear


def _iou(a: np.ndarray, b: np.ndarray) -> float:
    ix = max(0.0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0.0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / union if union > 0 else 0.0


def weighted_nms(boxes, kps, scores):
    order = np.argsort(-scores)
    remaining = list(order)
    faces = []
    while remaining:
        top = remaining[0]
        group = [i for i in remaining if _iou(boxes[top], boxes[i]) > DET_NMS_IOU]
        remaining = [i for i in remaining if i not in group]
        w = scores[group][:, None]
        faces.append(
            Face(
                score=float(scores[top]),
                box=(boxes[group] * w).sum(0) / w.sum(),
                kps=(kps[group] * w[:, :, None]).sum(0) / w.sum(),
            )
        )
    return faces


class Detector:
    def __init__(self, model: Path):
        self.it = Interpreter(str(model), num_threads=4)
        self.it.allocate_tensors()
        self.inp = self.it.get_input_details()[0]["index"]
        outs = {d["name"]: d["index"] for d in self.it.get_output_details()}
        self.reg, self.cls = outs["regressors"], outs["classificators"]

    def _run(self, rgb: np.ndarray, m: np.ndarray) -> list[Face]:
        """Runs on the 128x128 warp of ``rgb`` by affine ``m`` (frame -> input)."""
        x = cv2.warpAffine(rgb, m, (DET_SIZE, DET_SIZE), flags=cv2.INTER_LINEAR, borderValue=0)
        x = x.astype(np.float32) / 127.5 - 1.0
        self.it.set_tensor(self.inp, x[None])
        self.it.invoke()
        raw = self.it.get_tensor(self.reg)[0]
        logit = np.clip(self.it.get_tensor(self.cls)[0, :, 0].astype(np.float64), -100, 100)
        score = 1 / (1 + np.exp(-logit))
        keep = score >= DET_SCORE_MIN
        if not keep.any():
            return []
        raw, score, anc = raw[keep], score[keep], ANCHORS[keep]
        cx = raw[:, 0] / DET_SIZE + anc[:, 0]
        cy = raw[:, 1] / DET_SIZE + anc[:, 1]
        w = raw[:, 2] / DET_SIZE
        h = raw[:, 3] / DET_SIZE
        boxes = np.stack([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], 1) * DET_SIZE
        kps = np.stack(
            [raw[:, 4 + 2 * k : 6 + 2 * k] / DET_SIZE + anc for k in range(6)], 1
        ) * DET_SIZE
        # Map input coordinates back to the frame.
        inv = cv2.invertAffineTransform(m)
        def back(p):
            return p @ inv[:, :2].T + inv[:, 2]
        boxes = np.concatenate([back(boxes[:, :2]), back(boxes[:, 2:])], 1)
        kps = back(kps.reshape(-1, 2)).reshape(-1, 6, 2)
        return weighted_nms(boxes, kps, score)

    def detect(self, rgb: np.ndarray, refine: bool = True) -> Face | None:
        h, w = rgb.shape[:2]
        side = max(w, h)
        s = DET_SIZE / side
        # Letterbox: centre the frame in a square, scale to 128.
        m = np.array([[s, 0, (side - w) / 2 * s], [0, s, (side - h) / 2 * s]], np.float64)
        faces = self._run(rgb, m)
        if not faces:
            return None
        face = max(faces, key=lambda f: f.score)
        if not refine:
            return face
        bw, bh = face.box[2] - face.box[0], face.box[3] - face.box[1]
        cx, cy = (face.box[0] + face.box[2]) / 2, (face.box[1] + face.box[3]) / 2
        crop = REFINE_CROP_SCALE * max(bw, bh)
        s = DET_SIZE / crop
        m = np.array([[s, 0, (crop / 2 - cx) * s], [0, s, (crop / 2 - cy) * s]], np.float64)
        refined = self._run(rgb, m)
        if not refined:
            return face
        return max(refined, key=lambda f: f.score)


def similarity_transform(src: np.ndarray, dst: np.ndarray) -> np.ndarray:
    """Least-squares similarity (Umeyama, no reflection) mapping src -> dst."""
    n = src.shape[0]
    mu_s, mu_d = src.mean(0), dst.mean(0)
    s0, d0 = src - mu_s, dst - mu_d
    var_s = (s0**2).sum() / n
    cov = d0.T @ s0 / n
    u, sig, vt = np.linalg.svd(cov)
    d = np.ones(2)
    if np.linalg.det(u) * np.linalg.det(vt) < 0:
        d[-1] = -1
    r = u @ np.diag(d) @ vt
    scale = (sig * d).sum() / var_s
    t = mu_d - scale * r @ mu_s
    return np.hstack([scale * r, t[:, None]])


def align(rgb: np.ndarray, kps: np.ndarray, template: np.ndarray = ARCFACE_4PT) -> np.ndarray:
    """112x112 crop. ``template`` is where the 4 keypoints should land; the
    shipped value is calibrated for BlazeFace (see evaluate.calibrate_template)."""
    m = similarity_transform(kps[:4].astype(np.float64), template)
    return cv2.warpAffine(rgb, m, (ALIGN_SIZE, ALIGN_SIZE), flags=cv2.INTER_LINEAR, borderValue=0)


class Embedder:
    """SFace. With ``flip`` the crop and its mirror image are embedded and
    summed (test-time augmentation), then L2-normalised."""

    def __init__(self, model: Path, flip: bool = True):
        self.flip = flip
        self.it = Interpreter(str(model), num_threads=4)
        self.it.allocate_tensors()
        self.inp = self.it.get_input_details()[0]["index"]
        self.out = self.it.get_output_details()[0]["index"]

    def _raw(self, rgb: np.ndarray) -> np.ndarray:
        self.it.set_tensor(self.inp, rgb.astype(np.float32)[None])
        self.it.invoke()
        return self.it.get_tensor(self.out)[0].astype(np.float64)

    def embed(self, aligned_rgb: np.ndarray) -> np.ndarray:
        v = self._raw(aligned_rgb)
        if self.flip:
            v = v + self._raw(aligned_rgb[:, ::-1])
        return v / (np.linalg.norm(v) + 1e-12)


def yaw_estimate(kps: np.ndarray) -> float:
    """Signed head-yaw proxy in [-1, 1] from the nose between the two ears.

    0 = frontal. Positive = the face turned towards the subject's left
    (nose moves towards the left-ear keypoint in the image).
    """
    r_ear, l_ear, nose = kps[4], kps[5], kps[2]
    span = l_ear[0] - r_ear[0]
    if abs(span) < 1e-6:
        return 0.0
    t = (nose[0] - r_ear[0]) / span  # 0.5 when frontal
    return float(np.clip((t - 0.5) * 2, -1, 1))
