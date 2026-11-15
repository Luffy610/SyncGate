# ADR-0006: On-device vision pipeline on LiteRT

- **Status:** In review
- **Proposed outcome:** Proposed — model choices confirmed at M0; the licence of every model and dataset must be cleared (TBD-L2) before GA
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

## Amendment 1 (04-11-2026): first implementation

The pipeline is implemented in `packages/sg_vision` and evaluated in `ml/` ([report](../../ml/reports/sface-int8-lfw.md)). Where it differs from the decision above:

| Topic | Decision above | As built | Why |
|---|---|---|---|
| Where inference runs | Native Kotlin/Swift pipeline; no frame reaches Dart | **One Dart pipeline** on a background isolate, LiteRT through [`flutter_litert`](https://pub.dev/packages/flutter_litert) (Apache-2.0, classic Interpreter API, XNNPACK, 4 threads) | One implementation on both OSes gives strict Android/iOS parity, and the CI host runs the *same* `.tflite` files and code as the phones. Frames are copied into isolate memory, never written, logged or sent, and zeroed after analysis, so §3's privacy guarantee holds. A native path stays open if profiling on the reference phone needs it. |
| Detector | BlazeFace short-range | As decided (Apache-2.0, float16, 0.2 MB) plus a **second pass on a crop around the face** for sharper keypoints | Keypoints at 128 px on a full frame are too coarse for alignment. |
| Alignment | 5-point similarity transform | **4-point** (eyes, nose tip, mouth centre) onto a template **calibrated for BlazeFace** on LFW folds 6–10 | BlazeFace has no mouth corners, and its points sit slightly off the ArcFace ones. |
| Embedding | MobileFaceNet class, INT8, licence open (TBD-L2) | **SFace 2021dec** (MobileFaceNet trained with the SFace loss, OpenCV Zoo), INT8 dynamic-range, 9.9 MB, 128-d, plus flip test-time augmentation | The weights are published under Apache-2.0 by their authors. **TBD-L2 stays open for the training-data provenance**, which Legal must still clear before GA. |
| Liveness | MiniFASNet-class PAD (ADR-0007) | **Not shipped yet.** The gate engine has the hook (`LivenessEstimator`, silent reject) | Needs weights with a clean licence and the in-house PAD set to calibrate. GA stays blocked on ADR-0007. |
| Model integrity | Model card with SHA-256 | SHA-256s in `assets/models/manifest.json`; the app refuses a model that does not match | |

Thresholds per preset (`T_match`, margin, `T_dup`, `T_adapt`) are produced by `ml/eval/evaluate.py` and shipped in the manifest, as ADR-0009 asks.

## Amendment 2 (15-11-2026): frame orientation is measured, not trusted

**What happened.** The first run on an iPhone recognised people poorly and enrolment was erratic. Cause: `camera_avfoundation` delivers stream frames already upright for the way the phone is held, yet reports `sensorOrientation = 90` for every camera. `sg_vision` turned each frame by that value, so every face reached the models lying on its side. Reproduced on the LFW frames: turned 90°, the pipeline rejects **83 %** of genuine pairs (upright: 8 %), accepts more impostors, and the head-turn estimate saturates, which breaks the enrolment steps and the quality hints. Android (CameraX) does stream frames in sensor orientation, so it was not affected.

**Decisions.**

1. On iOS the camera source applies no rotation; on Android it applies the sensor orientation.
2. The pipeline no longer trusts either. An **upright guard** (`pipeline/upright_guard.dart`) runs the detector in all four orientations on the first frames that contain a face and keeps the orientation where the detector is most confident and the face looks upright. Over five frames this chose correctly in every trial on LFW frames (one frame: 98 %). Until it settles, faces are detected but never matched or enrolled. Afterwards it costs nothing, and it recalibrates if faces keep appearing tilted (30 in a row).
3. A face tilted more than 45° is never used for matching (`QualityPolicy.maxRoll`).
4. The dev flavour can show **live diagnostics** (`VISION_DIAGNOSTICS=true`; on by default in `scripts/run-on-device`): frame size, applied correction, speed, detector confidence, head pose, light, sharpness and the best match score against its threshold, over the preview and in the console. Numbers and worker IDs only. It is never enabled in staging or prod.
5. Two smaller robustness changes from the same review: the multi-frame agreement window stretches on phones that analyse frames slowly (ADR-0009 §2 still needs 2 of the last 3 frames), and the enrolment pose windows are wider (front within about 18°, sides beyond about 16° with no upper limit).

**Lesson.** A host test with correctly oriented frames cannot catch a camera-contract error. The parity suite now feeds frames turned 90°, 180° and 270° and requires the pipeline to correct itself; device runs remain mandatory before any release (ADR-0020).
