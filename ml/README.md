# ml/: face models, evaluation and fixtures

Everything needed to rebuild, check and test the face-recognition models that ship in [`packages/sg_vision/assets/models`](../packages/sg_vision/assets/models) (ADR-0006, ADR-0009, ADR-0020).

## Results (LFW, shipped INT8 models, full pipeline)

From [`reports/sface-int8-lfw.md`](reports/sface-int8-lfw.md), produced by `eval/evaluate.py`:

| Measure | Result |
|---|---|
| **LFW verification accuracy** (standard 10-fold protocol, 6,000 pairs, detect → align → embed on gate-sized frames) | **99.23 %** ± 0.51 (model alone on LFW's own aligned crops: 99.53 %) |
| **Gate decisions correct**, 25-worker gate, default *Standard* preset (10,000 simulated galleries) | **97.06 %** |
| Genuine walk-ups recognised (TPIR), *Standard* | 94.13 % (*Relaxed*: 96.12 %) |
| Impostors accepted (FPIR), *Standard* | 0.01 % (*Relaxed*: 0.06 %; ADR-0009 cap: 0.1 %) |
| Wrong worker matched | 0.00 % |
| Rank-1 identification (closed set, per frame) | 99.57 % |
| Failure to find the face | 0.09 % |

The Dart end-to-end test (`packages/sg_vision/test/e2e`) runs the same models through the app's own services on 100 enrolled workers and 100 impostors and gets the same picture: 93 % recognised, 0 % impostors accepted, 0 wrong workers, 96.5 % correct decisions.

**What this does and does not show.** LFW is web photos of public figures, and gate frames here are LFW faces placed in synthetic 640×480 frames. It is a public, repeatable check that the models, alignment and matching rules work. It does not replace the consented factory field set (ADR-0020), and it says nothing about spoofing (no liveness model ships yet; ADR-0007). The genuine pairs are often years apart with one enrolment photo each, so recognition at a real gate, with same-week multi-angle enrolment, should be better than the TPIR above.

## Layout

| Path | What |
|---|---|
| `eval/pipeline.py` | Reference pipeline: the spec the Dart code mirrors |
| `eval/evaluate.py` | Evaluation: LFW 10-fold, per-comparison FAR/FRR, 1:N gate simulation, threshold choice, writes `manifest.json` and the report |
| `eval/lfw_bin.py`, `eval/lfw_data.py` | Safe LFW loading (the `.bin` pickle is tokenised, never unpickled) |
| `eval/synth.py` | Synthetic gate frames from LFW crops |
| `scripts/fetch_lfw.sh`, `scripts/fetch_models.sh` | Downloads, pinned by SHA-256, into `.cache/ml` (git-ignored) |
| `scripts/convert_sface.py` | SFace ONNX → LiteRT, INT8 dynamic-range |
| `scripts/make_e2e_fixtures.py` | Frames and parity data for the Dart tests |
| `models/` | Model cards |
| `reports/` | Evaluation reports (generated) |
| `datasets/README.md` | Data provenance and handling rules |

## Reproduce

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r ml/requirements.txt

ml/scripts/fetch_lfw.sh .cache/ml

# Evaluation (≈ 20 min on 4 cores); rewrites the report and manifest.json.
python -I ml/eval/evaluate.py --data .cache/ml \
  --models packages/sg_vision/assets/models \
  --report ml/reports/sface-int8-lfw.md \
  --manifest packages/sg_vision/assets/models/manifest.json

# Fixtures for the Dart e2e and parity tests (≈ 30 s).
python -I ml/scripts/make_e2e_fixtures.py --data .cache/ml --out .cache/ml/e2e
melos run test
```

Rebuilding the embedder from the upstream ONNX file (needs TensorFlow):

```bash
pip install -r ml/requirements-convert.txt
ml/scripts/fetch_models.sh .cache/ml
python -I ml/scripts/convert_sface.py --onnx .cache/ml/models/sface.onnx --out .cache/ml/build
cp .cache/ml/build/sface_int8_dr.tflite .cache/ml/models/blaze_face_short_range.tflite packages/sg_vision/assets/models/
```

Then re-run the evaluation: it records the new SHA-256s and re-derives the thresholds.

CI runs the Dart face tests on every PR (`.github/workflows/pr.yml`) and the full evaluation nightly (`ml-eval.yml`), which fails if the numbers or thresholds drift from what is committed.

## How thresholds are chosen

`T_match` per preset is the score at which the **per-comparison** false-accept rate over ~59 million impostor pairs is 2.5 × 10⁻⁶ (*Strict*), 1 × 10⁻⁵ (*Standard*, default) or 4 × 10⁻⁵ (*Relaxed*). With 25 workers, even *Relaxed* keeps the system false-accept rate at or under ADR-0009's 0.1 %, and the gate simulation confirms it. The margin is ADR-0009's starting value, 0.08. The enrolment duplicate threshold is `T_match(Standard) + 0.05` and the adaptive-template threshold `+ 0.15` (ADR-0008).
