# Model card: SFace INT8 (face embedding)

| | |
|---|---|
| File | `packages/sg_vision/assets/models/sface_int8_dr.tflite` |
| SHA-256 | `0674d82dde9de9476c6e2d9a80f9dfb67ab2ae3a1192fa22a2ba5bcc4a41864a` |
| `model_id` / `model_version` | `sface-mbf` / `2021dec-int8dr` (stamped on every template) |
| Architecture | MobileFaceNet trained with the SFace (sigmoid-constrained hypersphere) loss; Zhong et al., *IEEE TIP* 2021 |
| Upstream | OpenCV Zoo `face_recognition_sface_2021dec.onnx`, SHA-256 `0ba9fbfa…e79` |
| Licence | Apache-2.0 (upstream model directory `LICENSE`) |
| Conversion | `ml/scripts/convert_sface.py`: onnx2tf (NCHW → NHWC), then TensorFlow Lite converter, dynamic-range INT8 weights / float activations |
| Size | 9.9 MB (float: 38.5 MB) |
| Input | 1×112×112×3 float32, RGB, 0–255, aligned with the calibrated template in `manifest.json` |
| Output | 128-d; L2-normalised by the app. The app also embeds the mirrored crop and sums (flip test-time augmentation). |
| Agreement with upstream | cosine ≥ 0.999 to the ONNX float model on LFW crops |
| Evaluation | [`ml/reports/sface-int8-lfw.md`](../reports/sface-int8-lfw.md): LFW 99.23 % through the full pipeline; per-preset thresholds |

## Intended use

1:N identification of up to ~25 enrolled, consenting workers on one phone at a factory gate, combined with the ADR-0009 rule (threshold, margin, multi-frame agreement). Not for surveillance, identifying people who have not enrolled, or any use without the worker's consent.

## Open items before GA

- **TBD-L2 (training data).** The weights are Apache-2.0, but the model was trained on public research face datasets whose terms must be reviewed by Legal for commercial use (ADR-0006 §5).
- **Fairness (ADR-0009 §5).** LFW is not balanced by skin tone, gender or age and is mostly not South Asian. FRR per demographic slice must be measured on the consented field set before release.
- **Masks.** No mask-specific threshold (`T_match_mask`) is calibrated yet.
