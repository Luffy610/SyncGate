"""LFW (View 2) loading: images from lfw.bin, identities from pairs.txt."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

from lfw_bin import read_lfw_bin


@dataclass
class Lfw:
    # Unique images, RGB uint8 112x112, and their identity names.
    images: list[np.ndarray]
    names: list[str]
    # The 6,000 protocol pairs as indices into ``images``, with same flags,
    # in the 10 folds of 600 the protocol defines.
    pairs: np.ndarray  # (6000, 2)
    same: np.ndarray  # (6000,) bool


def load_lfw(bin_path: Path, pairs_path: Path) -> Lfw:
    blobs, flags = read_lfw_bin(bin_path)
    lines = pairs_path.read_text().strip().splitlines()[1:]
    if len(lines) != len(flags):
        raise ValueError("pairs.txt does not match lfw.bin")

    keys: list[tuple[str, int]] = []
    pair_same = []
    for line in lines:
        f = line.split()
        if len(f) == 3:
            keys += [(f[0], int(f[1])), (f[0], int(f[2]))]
            pair_same.append(True)
        else:
            keys += [(f[0], int(f[1])), (f[2], int(f[3]))]
            pair_same.append(False)
    if pair_same != list(flags):
        raise ValueError("pairs.txt order differs from lfw.bin")

    index: dict[tuple[str, int], int] = {}
    images: list[np.ndarray] = []
    names: list[str] = []
    slots = []
    for key, blob in zip(keys, blobs):
        if key not in index:
            bgr = cv2.imdecode(np.frombuffer(blob, np.uint8), cv2.IMREAD_COLOR)
            index[key] = len(images)
            images.append(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
            names.append(key[0])
        slots.append(index[key])
    pairs = np.array(slots).reshape(-1, 2)
    return Lfw(images, names, pairs, np.array(flags))
