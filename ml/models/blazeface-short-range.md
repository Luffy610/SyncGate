# Model card: BlazeFace short-range (face detection)

| | |
|---|---|
| File | `packages/sg_vision/assets/models/blaze_face_short_range.tflite` |
| SHA-256 | `b4578f35940bf5a1a655214a1cce5cab13eba73c1297cd78e1a04c2380b0152f` |
| Upstream | MediaPipe Tasks face detector, `blaze_face_short_range/float16/latest` (Google Cloud Storage `mediapipe-models`) |
| Licence | Apache-2.0 |
| Size | 0.2 MB, float16 weights |
| Input | 1×128×128×3 float32 RGB in [-1, 1], letterboxed |
| Output | 896 anchors × (box + 6 keypoints) regressions and scores |
| Post-processing | SSD anchors (strides 8, 16), sigmoid score ≥ 0.5, weighted NMS at IoU 0.3, then a second pass on a crop of 2× the face size for sharper keypoints |
| Keypoints used | right eye, left eye, nose tip, mouth centre (alignment); ears (yaw estimate) |
| Evaluation | Failure to find the face: 0.09 % of LFW gate frames ([report](../reports/sface-int8-lfw.md)) |

Designed for faces within ~2 m of the camera, which suits a phone on a stand at 0.6–1 m (ADR-0006 §4).
