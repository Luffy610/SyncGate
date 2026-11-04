# sg_vision

On-device face recognition for SyncGate: camera → detect → align → embed → match, entirely on the phone and offline (ADR-0006). The UI sees only a texture ID and small events (`FaceSeen`, `QualityHint`, `Match`, `NoMatch`, `PipelineStats`); frames and face vectors stay inside this package and are wiped after use.

## Pipeline

```
front camera (YUV420 / BGRA, 640×480-class, 15 fps)
  → RawFrame ──(keep only latest)──► vision isolate
      → BlazeFace short-range @128 (letterboxed)      detect
      → second BlazeFace pass on a crop of the face    refine keypoints
      → quality gate: size, light, backlight, yaw, blur → QualityHint
      → 4-point similarity warp → 112×112              align (calibrated template)
      → SFace INT8 (+ mirrored crop) → 128-d unit vector embed
  → GateEngine: exact 1:N cosine, margin, 2-of-3 frames  → Match / NoMatch
  → EnrolmentEngine: front/left/right/(mask), ≥3 frames each, duplicate check
```

| Stage | File | Notes |
|---|---|---|
| Colour + rotation | `pipeline/rgb_image.dart` | NV21/NV12/I420 and BGRA → upright RGB |
| Geometry | `pipeline/geometry.dart` | similarity fit (closed-form Umeyama), bilinear warp matching OpenCV |
| Detector | `pipeline/face_detector.dart` | BlazeFace anchors, weighted NMS, refine pass |
| Embedder | `pipeline/face_embedder.dart` | SFace, flip test-time augmentation |
| Quality | `pipeline/quality.dart` | ADR-0006 quality hints |
| Matching | `pipeline/matcher.dart`, `pipeline/gate_engine.dart` | ADR-0009 rule: `T_match`, margin, multi-frame agreement, retry window, cooldown, adaptive slot |
| Enrolment | `pipeline/enrolment_engine.dart` | ADR-0008 guided capture, mean templates, duplicate check |
| Templates | `pipeline/templates.dart` | `TemplateVault` interface + in-memory vault |
| Runtime | `runtime/` | `CameraFrameSource`, `IsolateVisionRunner`, real `GateVisionService` / `EnrolmentCaptureService` / `CameraCheckService`, `VisionPreview` |

The Python reference in [`ml/eval/pipeline.py`](../../ml/eval/pipeline.py) is the spec; `test/e2e/pipeline_parity_test.dart` checks this Dart port against it stage by stage.

## Models

| File | Model | Licence | Size |
|---|---|---|---|
| `assets/models/blaze_face_short_range.tflite` | MediaPipe BlazeFace short-range | Apache-2.0 | 0.2 MB |
| `assets/models/sface_int8_dr.tflite` | OpenCV Zoo SFace (MobileFaceNet, SFace loss), INT8 weights | Apache-2.0 | 9.9 MB |
| `assets/models/manifest.json` | hashes, alignment template, thresholds per preset | — | — |

`ModelAssets` refuses to load a model whose SHA-256 differs from the manifest. Model cards, the conversion script and the evaluation report are in [`ml/`](../../ml/README.md).

## Using it

```dart
final stack = VisionStack(
  source: CameraFrameSource(),          // or ScriptedFrameSource() in tests
  runner: IsolateVisionRunner(),        // or InlineVisionRunner() in tests
  vault: InMemoryTemplateVault(),       // encrypted native vault: ADR-0010
  loadAssets: ModelAssets.fromBundle,
);
final gate = LiteRtGateVisionService(stack: stack, activeWorkers: ...);
final enrol = LiteRtEnrolmentCaptureService(stack: stack);
final check = LiteRtCameraCheckService(stack: stack);
```

The app binds these in `apps/mobile/lib/src/app/vision_wiring.dart`. In the dev flavour, `--dart-define=VISION=real` swaps the scripted camera for the real one.

## Tests

```bash
flutter test                       # unit tests (no data needed)
# Face-recognition end-to-end + parity tests need the LFW fixtures:
ml/scripts/fetch_lfw.sh .cache/ml
python -I ml/scripts/make_e2e_fixtures.py --data .cache/ml --out .cache/ml/e2e
flutter test test/e2e              # from packages/sg_vision
```

## Not done yet

- **Liveness / anti-spoofing (ADR-0007)** is not in this package yet. `GateEngine` takes a `LivenessEstimator` and rejects silently below its threshold, but no PAD model ships: it needs a model with a clean licence and the in-house attack set to calibrate it. Until then a printed photo of an enrolled worker can mark attendance.
- **Encrypted template vault (ADR-0010)**: templates are kept in memory only.
- **Mask-specific threshold** (`T_match_mask`, ADR-0009 §3): the mask slot is matched with the normal threshold.
- **Device testing**: rotation, mirroring and the preview were written against the `camera` plugin API but not yet run on a phone.
