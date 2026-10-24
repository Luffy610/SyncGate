# ADR-0006: On-device vision pipeline on LiteRT

- **Status:** Proposed — model choices confirmed at M0; the licence of every model and dataset must be cleared (TBD-L2) before GA
- **Date:** 24-10-2026
- **Deciders:** ML, Engineering, Legal
- **Related:** PRD §8.3 · TC-01, TC-02, TC-03 · FR-ATT-01..03, FR-ENR-04 · NFR-PERF-02, NFR-ACC-01..07 · ADR-0002, ADR-0007, ADR-0008, ADR-0009, ADR-0018

## Context

All face processing must run **on the phone**, offline, on budget hardware, with **no cloud matching** (TC-01) and **no dependence on neural accelerators** (TC-02). The pipeline must also cope with factory conditions: low light, backlight from an open gate, dust on the lens, masks, helmets, turbans, head scarves, bindi/tilak and safety glasses (NFR-ACC-02..06).

## Decision

### 1. Runtime

- **LiteRT** (formerly TensorFlow Lite) on **both** platforms, with the **same `.tflite` files**. This gives one model format, one quantisation flow and cross-platform parity.
  - Android: `com.google.ai.edge.litert` with the **XNNPACK** CPU delegate by default (4 threads), and the **GPU delegate** enabled only on devices that pass a start-up self-test. NNAPI is not used (deprecated, and inconsistent on budget SoCs).
  - iOS: LiteRT for iOS (CPU/XNNPACK; Metal delegate optional). Core ML conversion is optional later. It is not needed to hit targets on supported iPhones.
- All models are **INT8 post-training quantised**, with float fallbacks kept only in the benchmark app. Total model budget: **≤25 MB** (TC-02). Expected: ~12 MB.

### 2. Pipeline stages

```
Camera (front, 640×480 YUV/BGRA, 15 fps when active)
  │
  ├─► [Presence]   BlazeFace-class short-range detector @ 128×128, every frame (idle: 3–5 fps)
  │                 → largest face box + 6 keypoints
  ├─► [Quality]    size ≥ 90 px inter-ocular-equivalent, yaw/pitch ≤ 20°, blur (Laplacian var),
  │                 brightness/contrast, occlusion hints → QualityHint events to UI
  ├─► [Align]      5-point similarity transform → 112×112 RGB crop (in memory only)
  ├─► [Liveness]   passive PAD model on the crop + multi-frame cues (ADR-0007)
  ├─► [Embed]      MobileFaceNet-class INT8 → L2-normalised 512-d (or 128-d) vector
  └─► [Match]      exact 1:N cosine vs TemplateVault (ADR-0009) → Match / NoMatch event
```

| Stage | Model / method | Input | Target latency on reference phone (p95) |
|---|---|---|---|
| Detection | BlazeFace short-range class (Apache-2.0 weights) | 128×128 | ≤25 ms |
| Quality | Classical CV (Laplacian variance, luminance histogram, keypoint pose estimate) | crop | ≤10 ms |
| Alignment | Similarity transform from eyes, nose, mouth keypoints | 112×112 | ≤5 ms |
| Liveness | Passive PAD CNN (MiniFASNet class) at 80×80 + temporal cues | crop(s) | ≤120 ms |
| Embedding | MobileFaceNet class, INT8 | 112×112 | ≤150 ms |
| Match | Dot products over ≤150 vectors | 512-d | <1 ms |
| **Total (decision)** | | | **≤700 ms p95**, typically ~350 ms |

### 3. Frame handling and privacy

- Frames are processed in a **native ring buffer of 2**, with "keep only latest" back-pressure. No frame is ever written to disk, logged or sent to Dart.
- Crops and intermediate tensors are **zeroed** after use. Buffers are allocated once and reused.
- The **only outputs** that leave native code are events with IDs, scores and hints. See the event contract in [ADR-0002](0002-cross-platform-framework-flutter.md).

### 4. Environmental resilience

| Condition | Measure |
|---|---|
| Low light (≤30 lux) | Exposure/ISO bias via CameraX `ExposureState` / `AVCaptureDevice.exposureTargetBias`; **screen fill light** (UI turns the gate screen near-white at max brightness when a face is present and luma is low); gamma/CLAHE on the crop before embedding |
| Backlight (open gate behind the worker) | Face-weighted metering (`MeteringPoint` on the detected face / `exposurePointOfInterest`); setup check warns and suggests repositioning (design 07) |
| Dirty lens | Rolling blur and contrast score over 5 minutes of detected faces. Below threshold → "Clean the camera" prompt on gate and admin (NFR-ACC-05) |
| Masks | Mask-aware embedding (periocular-weighted, or a model fine-tuned with masked data) + optional masked enrolment sample ([ADR-0008](0008-enrolment-and-template-management.md)) |
| Helmets, turbans, scarves, glasses | Included in fine-tuning/validation data. Enrolment asks the worker to wear what they usually wear at the gate. |
| Distance | Phone on a stand at 0.6–1 m. Quality gate rejects faces that are too small, with a "Come closer" hint. |

### 5. Model sourcing and licences (blocking, TBD-L2)

| Model | Candidate source | Licence status |
|---|---|---|
| Face detector | MediaPipe BlazeFace short-range weights | Apache-2.0 — acceptable; record in model card |
| Embedding | **No public pre-trained weights with a clean commercial licence are assumed.** Popular open weights (e.g. InsightFace model zoo) are **non-commercial** and must not ship. | **Open.** Options: (a) train MobileFaceNet in-house on datasets licensed for commercial use plus consented South Asian data; (b) license a commercial on-device model/SDK; (c) commission training. Decide in M0. |
| Liveness | MiniFASNet-class architecture; weights trained in-house or licensed | **Open** — verify any third-party weights |

Each model ships with a **model card** in `ml/models/`: version, SHA-256, training data provenance, licence, evaluation results by demographic slice, and intended-use limits.

### 6. Versioning and migration (NFR-OPS-02)

- Templates are stamped with `model_id` + `model_version`. A new embedding model that changes the vector space triggers a **re-enrolment campaign**. Old templates stay usable until each worker is re-enrolled, with the gate trying both models for a transition window. For ≤25 workers this takes minutes, which keeps the migration simple.

## Options considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **LiteRT, own models (chosen)** | One format on both OSs; full control; no per-device fees; works on CPU | We own training and evaluation; licence clearance work | Chosen |
| Google ML Kit face detection + own embedding | Easy detection API | Closed source; detection-only; behaviour differs between platforms | Not needed; BlazeFace on LiteRT gives the same detector everywhere |
| Commercial face SDK (on-device) | Fast to market; vendor-tuned accuracy and PAD | Licence cost per device; vendor lock-in; must verify it is truly offline and stores nothing off-device | Kept as fallback for the embedding/PAD licence problem |
| Apple Vision / Core ML only on iOS | Uses Neural Engine | Different results from Android; double work | Rejected for Phase 1 |
| Cloud matching | Easier models | Violates TC-01 and the privacy positioning | Rejected |

## Consequences

- ML owns a training and evaluation pipeline ([ADR-0020](0020-testing-strategy-and-ml-evaluation.md)) and the model cards.
- GA is **blocked** until TBD-L2 is resolved for the embedding and liveness models.
