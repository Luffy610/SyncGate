"""Build the gate-camera fixtures the Dart end-to-end tests run on.

Writes to --out (default .cache/ml/e2e, git-ignored; ADR-0020: face data is
never committed):

  e2e.json          galleries of 25 workers (enrolment photo != gate photo)
                    plus impostors who are not enrolled
  g*/...jpg         synthetic 640x480 gate frames (ml/eval/synth.py)
  parity/*.png      a few lossless frames, and
  parity.json       what the Python reference pipeline finds in them
                    (keypoints, embedding), so the Dart port can be checked
                    stage by stage

Usage (repo root, ml venv):
  python -I ml/scripts/make_e2e_fixtures.py --data .cache/ml --out .cache/ml/e2e
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ml" / "eval"))

from lfw_data import load_lfw  # noqa: E402
from pipeline import Detector, Embedder, align  # noqa: E402
from synth import make_frame  # noqa: E402

MODELS = ROOT / "packages" / "sg_vision" / "assets" / "models"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--galleries", type=int, default=4)
    ap.add_argument("--workers", type=int, default=25)
    ap.add_argument("--frames", type=int, default=3)
    ap.add_argument("--parity", type=int, default=12)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    lfw = load_lfw(args.data / "lfw" / "lfw.bin", args.data / "lfw" / "pairs.txt")
    rng = np.random.default_rng(args.seed)
    by_name: dict[str, list[int]] = {}
    for i, n in enumerate(lfw.names):
        by_name.setdefault(n, []).append(i)
    multi = sorted(n for n, v in by_name.items() if len(v) >= 2)
    names = sorted(by_name)
    rng.shuffle(multi)
    used: set[str] = set()

    shutil.rmtree(args.out, ignore_errors=True)
    args.out.mkdir(parents=True)

    def frames(img_idx: int, prefix: str) -> list[str]:
        files = []
        for f in range(args.frames):
            rel = f"{prefix}_{f}.jpg"
            path = args.out / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            rgb = make_frame(lfw.images[img_idx], rng)
            cv2.imwrite(str(path), cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR), [cv2.IMWRITE_JPEG_QUALITY, 95])
            files.append(rel)
        return files

    galleries = []
    for g in range(args.galleries):
        workers = []
        for k in range(args.workers):
            name = multi.pop()
            used.add(name)
            a, b = rng.choice(by_name[name], 2, replace=False)
            wid = f"g{g}-w{k:02d}"
            workers.append({
                "id": wid,
                "name": name,
                "enrol": frames(int(a), f"g{g}/{wid}_enrol"),
                "gate": frames(int(b), f"g{g}/{wid}_gate"),
            })
        impostors = []
        while len(impostors) < args.workers:
            name = names[int(rng.integers(len(names)))]
            if name in used:
                continue
            used.add(name)
            i = by_name[name][int(rng.integers(len(by_name[name])))]
            impostors.append({"name": name, "gate": frames(int(i), f"g{g}/imp{len(impostors):02d}_{name[:12]}")})
        galleries.append({"workers": workers, "impostors": impostors})

    # Parity frames: lossless, with the reference pipeline's answers.
    manifest = json.loads((MODELS / "manifest.json").read_text())
    template = np.array(manifest["template"])
    det = Detector(MODELS / manifest["detector"]["file"])
    emb = Embedder(MODELS / manifest["embedder"]["file"])
    parity = []
    (args.out / "parity").mkdir()
    for k in range(args.parity):
        i = int(rng.integers(len(lfw.images)))
        rgb = make_frame(lfw.images[i], rng)
        rel = f"parity/p{k:02d}.png"
        cv2.imwrite(str(args.out / rel), cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR))
        face = det.detect(rgb)
        entry = {"file": rel, "face": None}
        if face is not None:
            entry["face"] = {
                "score": float(face.score),
                "box": [float(x) for x in face.box],
                "keypoints": [[float(x), float(y)] for x, y in face.kps],
                "embedding": [float(x) for x in emb.embed(align(rgb, face.kps, template))],
            }
        parity.append(entry)

    (args.out / "e2e.json").write_text(json.dumps({
        "source": "LFW view 2 via ml/eval/synth.py",
        "frames_per_photo": args.frames,
        "galleries": galleries,
    }, indent=1))
    (args.out / "parity.json").write_text(json.dumps(parity, indent=1))
    n = sum(1 for _ in args.out.rglob("*.jpg"))
    print(f"wrote {n} frames, {len(parity)} parity frames to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
