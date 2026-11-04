"""Biometric evaluation of the shipped face pipeline on LFW (ADR-0020 §2).

Steps:
  1. Calibrate the BlazeFace->ArcFace alignment template (folds 6-10 only).
  2. Embed every unique LFW image (7,701) through the *whole* pipeline on
     ``--frames`` synthetic gate frames each (detect -> refine -> align ->
     embed), plus the reference "already aligned crop" path.
  3. Metrics:
       - LFW 10-fold verification accuracy (standard protocol, 6,000 pairs);
       - per-comparison FAR / FRR over all unique-image pairs;
       - 1:N gate simulation, N = 25, 10,000 random galleries, with the
         ADR-0009 acceptance rule (threshold, margin, 2-of-3 frames);
       - quality-metric distributions used to set the gate's quality gate.
  4. Pick thresholds per preset and write ``manifest.json`` (model files,
     hashes, template, thresholds) and a Markdown report.

Usage (repo root, ml venv):
  python -I ml/eval/evaluate.py --data .cache/ml --models packages/sg_vision/assets/models \
      --report ml/reports/sface-int8-lfw.md --manifest packages/sg_vision/assets/models/manifest.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lfw_data import load_lfw  # noqa: E402
from pipeline import (  # noqa: E402
    ARCFACE_4PT,
    DET_NMS_IOU,
    DET_SCORE_MIN,
    REFINE_CROP_SCALE,
    Detector,
    Embedder,
    align,
    yaw_estimate,
)
from synth import make_frame  # noqa: E402

DETECTOR_FILE = "blaze_face_short_range.tflite"
EMBEDDER_FILE = "sface_int8_dr.tflite"
GALLERY_N = 25
TRIALS = 10_000
MARGIN = 0.08  # ADR-0009 starting value
# Per-comparison FAR targets per preset. ADR-0009: system FAR <= 0.1% at
# N = 25  ->  per-comparison FAR ~ 0.004% (4e-5). Even "Relaxed" honours it.
PRESET_FAR = {"strict": 2.5e-6, "standard": 1e-5, "relaxed": 4e-5}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def laplacian_var(rgb112: np.ndarray) -> float:
    g = rgb112.astype(np.float64) @ np.array([0.299, 0.587, 0.114])
    lap = g[:-2, 1:-1] + g[2:, 1:-1] + g[1:-1, :-2] + g[1:-1, 2:] - 4 * g[1:-1, 1:-1]
    return float(lap.var())


def mean_luma(rgb: np.ndarray) -> float:
    return float((rgb.astype(np.float64) @ np.array([0.299, 0.587, 0.114])).mean())


# ---------------------------------------------------------------- calibration


def calibrate_template(det: Detector, images, idx) -> np.ndarray:
    """Where BlazeFace puts its 4 keypoints on ArcFace-aligned crops."""
    pts = []
    bg = np.full((480, 640, 3), 128, np.uint8)
    for i in idx:
        s = 2.0
        m = np.array([[s, 0, 320 - 56 * s], [0, s, 240 - 56 * s]], np.float64)
        frame = bg.copy()
        warped = cv2.warpAffine(images[i], m, (640, 480), flags=cv2.INTER_LINEAR)
        mask = cv2.warpAffine(np.ones((112, 112), np.uint8), m, (640, 480)) > 0
        frame[mask] = warped[mask]
        face = det.detect(frame)
        if face is None:
            continue
        inv = cv2.invertAffineTransform(m)
        pts.append(face.kps[:4] @ inv[:, :2].T + inv[:, 2])
    return np.median(np.array(pts), axis=0)


# ------------------------------------------------------------------- metrics


def tenfold(sims: np.ndarray, same: np.ndarray) -> tuple[float, float, float]:
    grid = np.arange(-1.0, 1.0, 0.0025)
    accs, ths = [], []
    for k in range(10):
        test = np.zeros(len(sims), bool)
        test[k * 600 : (k + 1) * 600] = True
        tr = ~test
        acc_tr = [((sims[tr] >= t) == same[tr]).mean() for t in grid]
        t = grid[int(np.argmax(acc_tr))]
        accs.append(((sims[test] >= t) == same[test]).mean())
        ths.append(t)
    return float(np.mean(accs)), float(np.std(accs)), float(np.mean(ths))


def far_frr_tables(enrol: np.ndarray, probe: np.ndarray, names: np.ndarray, ok: np.ndarray):
    """Scores of every enrol-frame vs probe-frame pair of distinct images."""
    keep = np.where(ok)[0]
    e, p, n = enrol[keep], probe[keep], names[keep]
    sims = e @ p.T
    same = n[:, None] == n[None, :]
    np.fill_diagonal(same, False)
    diag = np.eye(len(keep), dtype=bool)
    impostor = sims[~same & ~diag]
    genuine = sims[same]
    return np.sort(impostor), np.sort(genuine)


def threshold_at_far(impostor_sorted: np.ndarray, far: float) -> float:
    k = int(np.ceil(len(impostor_sorted) * (1 - far)))
    return float(impostor_sorted[min(k, len(impostor_sorted) - 1)]) + 1e-6


def gate_simulation(emb, ok, names, t_match, margin, frames, rng):
    """1:N at N=25 with the ADR-0009 rule. ``emb``: (images, frames, 128)."""
    by_name: dict[str, list[int]] = {}
    for i, n in enumerate(names):
        if ok[i].all():
            by_name.setdefault(n, []).append(i)
    multi = [n for n, v in by_name.items() if len(v) >= 2]
    single = list(by_name)
    out = {"genuine": 0, "correct": 0, "misid": 0, "rejected": 0,
           "impostor": 0, "false_accept": 0, "rank1_frames": 0, "rank1_total": 0}

    def decide(gallery, probe_frames):
        votes = []
        for f in probe_frames:
            scores = (gallery["emb"] @ f)  # (templates,)
            per_worker = np.full(GALLERY_N, -1.0)
            np.maximum.at(per_worker, gallery["owner"], scores)
            order = np.argsort(-per_worker)
            s1, s2 = per_worker[order[0]], per_worker[order[1]]
            votes.append((order[0], per_worker, s1 >= t_match and s1 - s2 >= margin))
        accepted = [w for w, _, a in votes if a]
        for w in set(accepted):
            if accepted.count(w) >= 2:
                return w, votes
        return None, votes

    use = min(3, frames)
    for _ in range(TRIALS):
        workers = rng.choice(multi, GALLERY_N, replace=False)
        enrol_imgs, probe_imgs = [], []
        for n in workers:
            a, b = rng.choice(by_name[n], 2, replace=False)
            enrol_imgs.append(a)
            probe_imgs.append(b)
        # One template per worker: the normalised mean of the enrolment
        # frames (ADR-0008 asks for >= 3 good frames per angle). LFW has a
        # single photo per enrolment, so this is the front slot only.
        g_emb = emb[enrol_imgs].mean(1)
        g_emb /= np.linalg.norm(g_emb, axis=1, keepdims=True)
        gallery = {"emb": g_emb, "owner": np.arange(GALLERY_N)}

        # A genuine walk-up.
        w = int(rng.integers(GALLERY_N))
        got, votes = decide(gallery, emb[probe_imgs[w], :use])
        out["genuine"] += 1
        out["rank1_total"] += len(votes)
        out["rank1_frames"] += sum(1 for top, _, _ in votes if top == w)
        if got is None:
            out["rejected"] += 1
        elif got == w:
            out["correct"] += 1
        else:
            out["misid"] += 1

        # An impostor: someone not enrolled in this gallery.
        enrolled = set(workers)
        while True:
            n = single[int(rng.integers(len(single)))]
            if n not in enrolled:
                break
        i = by_name[n][int(rng.integers(len(by_name[n])))]
        got, _ = decide(gallery, emb[i, :use])
        out["impostor"] += 1
        if got is not None:
            out["false_accept"] += 1
    return out


# ---------------------------------------------------------------------- main


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", type=Path, required=True, help="dir with lfw/lfw.bin and lfw/pairs.txt")
    ap.add_argument("--models", type=Path, required=True)
    ap.add_argument("--frames", type=int, default=3)
    ap.add_argument("--seed", type=int, default=20261104)
    ap.add_argument("--report", type=Path, required=True)
    ap.add_argument("--manifest", type=Path, required=True)
    ap.add_argument("--limit", type=int, default=0, help="debug: only the first N pairs")
    ap.add_argument("--no-flip", action="store_true", help="disable flip test-time augmentation")
    args = ap.parse_args()

    t0 = time.time()
    lfw = load_lfw(args.data / "lfw" / "lfw.bin", args.data / "lfw" / "pairs.txt")
    det = Detector(args.models / DETECTOR_FILE)
    emb_model = Embedder(args.models / EMBEDDER_FILE, flip=not args.no_flip)
    rng = np.random.default_rng(args.seed)
    names = np.array(lfw.names)
    n_img = len(lfw.images)
    print(f"LFW: {n_img} unique images, {len(set(lfw.names))} identities", flush=True)

    # 1. Template calibration on images used only in folds 6-10.
    calib_idx = sorted(set(lfw.pairs[3000:].ravel().tolist()))[:1500]
    template = calibrate_template(det, lfw.images, calib_idx)
    print("template:", np.round(template, 2).tolist(), flush=True)

    # 2. Embeddings.
    F = args.frames
    crop_emb = np.zeros((n_img, 128))
    pipe_emb = np.zeros((n_img, F, 128))
    pipe_emb_arc = np.zeros((n_img, 128))  # frame 0 with the uncalibrated template
    ok = np.zeros((n_img, F), bool)
    quality = {"iod": [], "yaw": [], "blur": [], "luma": []}
    work = range(n_img) if not args.limit else sorted(set(lfw.pairs[: args.limit].ravel()))
    for c, i in enumerate(work):
        crop_emb[i] = emb_model.embed(lfw.images[i])
        for f in range(F):
            frame = make_frame(lfw.images[i], rng)
            face = det.detect(frame)
            if face is None:
                continue
            ok[i, f] = True
            a = align(frame, face.kps, template)
            pipe_emb[i, f] = emb_model.embed(a)
            if f == 0:
                pipe_emb_arc[i] = emb_model.embed(align(frame, face.kps, ARCFACE_4PT))
                quality["iod"].append(float(np.linalg.norm(face.kps[0] - face.kps[1])))
                quality["yaw"].append(abs(yaw_estimate(face.kps)))
                quality["blur"].append(laplacian_var(a))
                quality["luma"].append(mean_luma(a))
        if c % 500 == 0:
            print(f"  embedded {c}/{len(work)}  ({time.time() - t0:.0f}s)", flush=True)

    # 3a. LFW 10-fold verification.
    pairs, same = lfw.pairs, lfw.same
    if args.limit:
        pairs, same = pairs[: args.limit], same[: args.limit]

    def pair_sims(e1, e2, valid):
        s = np.einsum("ij,ij->i", e1[pairs[:, 0]], e2[pairs[:, 1]])
        s[~valid] = -1.0  # failure to acquire counts as "different"
        return s

    all_ok = np.ones(n_img, bool)
    v_pipe = ok[pairs[:, 0], 0] & ok[pairs[:, 1], min(1, F - 1)]
    results = {
        "crop_reference": tenfold(pair_sims(crop_emb, crop_emb, all_ok[pairs[:, 0]]), same)
        if not args.limit else None,
        "pipeline_arcface_template": tenfold(
            pair_sims(pipe_emb_arc, pipe_emb_arc, ok[pairs[:, 0], 0] & ok[pairs[:, 1], 0]), same)
        if not args.limit else None,
        "pipeline": tenfold(
            pair_sims(pipe_emb[:, 0], pipe_emb[:, min(1, F - 1)], v_pipe), same)
        if not args.limit else None,
    }
    fta = 1 - ok.mean()

    # 3b. Per-comparison FAR / FRR on all unique-image pairs: enrolment
    # template (mean of an image's frames) vs one probe frame of another image.
    enrol_t = pipe_emb.mean(1)
    enrol_t /= np.linalg.norm(enrol_t, axis=1, keepdims=True) + 1e-12
    imp, gen = far_frr_tables(enrol_t, pipe_emb[:, 0], names, ok.all(1))
    thresholds = {k: threshold_at_far(imp, far) for k, far in PRESET_FAR.items()}
    per_cmp = {
        k: {"threshold": t, "far": float((imp >= t).mean()), "frr": float((gen < t).mean())}
        for k, t in thresholds.items()
    }
    # Same table for the reference path (LFW's own aligned crops, no
    # detector): separates model error from detection/alignment error.
    imp_c, gen_c = far_frr_tables(crop_emb, crop_emb, names, np.ones(n_img, bool))
    per_cmp_ref = {}
    for k, far in PRESET_FAR.items():
        t = threshold_at_far(imp_c, far)
        per_cmp_ref[k] = {"threshold": t, "far": float((imp_c >= t).mean()), "frr": float((gen_c < t).mean())}
    del imp_c, gen_c

    # 3c. Gate simulation per preset.
    sims = {}
    for k, t in thresholds.items():
        r = gate_simulation(pipe_emb, ok, lfw.names, t, MARGIN, F, np.random.default_rng(args.seed + 1))
        sims[k] = r
        print(k, r, flush=True)

    # 4. Thresholds and manifest.
    std = thresholds["standard"]
    manifest = {
        "schema": 1,
        "detector": {
            "file": DETECTOR_FILE,
            "sha256": sha256(args.models / DETECTOR_FILE),
            "input": 128,
            "score_min": DET_SCORE_MIN,
            "nms_iou": DET_NMS_IOU,
            "refine_crop_scale": REFINE_CROP_SCALE,
        },
        "embedder": {
            "file": EMBEDDER_FILE,
            "sha256": sha256(args.models / EMBEDDER_FILE),
            "model_id": "sface-mbf",
            "model_version": "2021dec-int8dr",
            "dims": 128,
        },
        "template": np.round(template, 4).tolist(),
        "thresholds": {
            "presets": {k: round(v, 4) for k, v in thresholds.items()},
            "margin": MARGIN,
            # Duplicate check at enrolment is stricter than the gate (ADR-0008).
            "duplicate": round(std + 0.05, 4),
            # Adaptive template refresh only on very confident matches.
            "adapt": round(std + 0.15, 4),
        },
        "evaluation": {
            "dataset": "LFW view 2 (6,000 pairs; 7,701 images; 4,281 identities)",
            "lfw_10fold_accuracy_pipeline": results["pipeline"][0] if results["pipeline"] else None,
            "gate_sim_standard": sims["standard"],
        },
    }
    args.manifest.write_text(json.dumps(manifest, indent=2) + "\n")

    write_report(args.report, results, fta, per_cmp, per_cmp_ref, sims, quality, template, len(imp), len(gen), F)
    print(f"done in {time.time() - t0:.0f}s")
    return 0


def pct(x: float) -> str:
    return f"{100 * x:.2f}%"


def write_report(path, results, fta, per_cmp, per_cmp_ref, sims, quality, template, n_imp, n_gen, frames):
    L = []
    L.append("# Face pipeline evaluation: BlazeFace + SFace (INT8) on LFW\n")
    L.append("Generated by `ml/eval/evaluate.py`. Do not edit by hand.\n")
    L.append("## 1. LFW verification (standard 10-fold protocol, 6,000 pairs)\n")
    L.append("| Path | Accuracy | ± std | mean threshold |")
    L.append("|---|---|---|---|")
    labels = {
        "crop_reference": "Reference: SFace on LFW's own aligned crops",
        "pipeline_arcface_template": "Full pipeline, plain ArcFace template",
        "pipeline": "**Full pipeline as shipped** (detect → refine → calibrated align → embed)",
    }
    for k, lab in labels.items():
        r = results[k]
        if r:
            L.append(f"| {lab} | **{pct(r[0])}** | {pct(r[1])} | {r[2]:.3f} |")
    L.append(f"\nFailure to acquire (no face found) on synthetic frames: {pct(fta)}.\n")
    L.append("## 2. Per-comparison error rates (all unique-image pairs)\n")
    L.append(f"{n_imp:,} impostor and {n_gen:,} genuine comparisons: enrolment template (mean of a photo's "
             f"frames) vs one probe frame of a different photo.\n")
    L.append("| Preset | T_match | FAR (per comparison) | FRR (per comparison) | Reference FRR (aligned crops, same FAR) |")
    L.append("|---|---|---|---|---|")
    for k, r in per_cmp.items():
        ref = per_cmp_ref[k]
        L.append(f"| {k} | {r['threshold']:.4f} | {r['far']:.2e} | {pct(r['frr'])} | {pct(ref['frr'])} |")
    L.append("\n## 3. Gate simulation (1:N, N = 25, 10,000 galleries, ADR-0009 rule)\n")
    L.append(f"Each worker has 1 template (mean of {frames} enrolment frames of one photo); each walk-up gives {min(3, frames)} frames; a match needs "
             f"score ≥ T_match, margin ≥ {MARGIN} over the next worker, and the same worker in ≥ 2 frames.\n")
    L.append("| Preset | Identification accuracy (TPIR) | Not recognised (FNIR) | Wrong worker | Impostor accepted (FPIR) | Correct decisions | Rank-1 (per frame, no threshold) |")
    L.append("|---|---|---|---|---|---|---|")
    for k, r in sims.items():
        g, i = r["genuine"], r["impostor"]
        correct = (r["correct"] + (i - r["false_accept"])) / (g + i)
        L.append(
            f"| {k} | **{pct(r['correct'] / g)}** | {pct(r['rejected'] / g)} | {pct(r['misid'] / g)} | "
            f"{pct(r['false_accept'] / i)} | **{pct(correct)}** | {pct(r['rank1_frames'] / r['rank1_total'])} |"
        )
    L.append("\n## 4. Quality metrics on accepted synthetic frames (sets the gate's quality gate)\n")
    L.append("| Metric | p1 | p5 | p50 | p95 |")
    L.append("|---|---|---|---|---|")
    for k, v in quality.items():
        v = np.array(v)
        L.append(f"| {k} | {np.percentile(v, 1):.1f} | {np.percentile(v, 5):.1f} | {np.percentile(v, 50):.1f} | {np.percentile(v, 95):.1f} |")
    L.append("\n## 5. Calibrated alignment template (BlazeFace keypoints → 112×112)\n")
    L.append("| Point | ArcFace | Calibrated |")
    L.append("|---|---|---|")
    for name, a, c in zip(["right eye", "left eye", "nose tip", "mouth centre"], ARCFACE_4PT, template):
        L.append(f"| {name} | ({a[0]:.1f}, {a[1]:.1f}) | ({c[0]:.1f}, {c[1]:.1f}) |")
    L.append("\n## Caveats\n")
    L.append("- LFW is web photos of public figures, not factory gates. It is a standard, public check of the "
             "model and pipeline, **not** a substitute for the consented field set in ADR-0020.")
    L.append("- Faces are synthetic placements of LFW crops in gate-sized frames; real pose, light and lens "
             "conditions will be harder (and same-day enrolment easier) than here.")
    L.append("- LFW genuine pairs are often years apart; gate probes are days from enrolment, so field FNIR "
             "should be lower than the per-comparison FRR above.")
    L.append("- No liveness (PAD) numbers: LFW has no attacks. See ADR-0007.")
    path.write_text("\n".join(L) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
