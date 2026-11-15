# Datasets

Face data is personal data. **None of it is ever committed** (ADR-0020); everything below is downloaded into `.cache/ml/`, which git ignores.

| Dataset | Used for | Source | Pinned SHA-256 | Terms |
|---|---|---|---|---|
| LFW view 2, `lfw.bin` (InsightFace format: 12,000 aligned 112×112 crops, 6,000 pairs) | Evaluation; Dart e2e fixtures | Git LFS mirror, see `ml/scripts/fetch_lfw.sh` | `9b711dca…569593` | LFW is released for research. It is a public benchmark; it does not train anything here. |
| LFW `pairs.txt` | Identity labels for the pairs | davidsandberg/facenet mirror | `ea42330c…dc1592` | As LFW |

`lfw.bin` is a Python pickle, which could run code if unpickled. `ml/eval/lfw_bin.py` only tokenises it and rejects any file that contains callable or import opcodes.

Still to collect, under the consent process in ADR-0020: the consented gate gallery/probe set (≥ 300 identities, balanced by Monk skin tone, gender and age band, in normal light, low light, backlight, masks, helmets, turbans, scarves and glasses), and the PAD attack set for liveness (ADR-0007).
