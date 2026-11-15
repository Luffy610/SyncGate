#!/usr/bin/env bash
# Downloads the upstream model files the shipped .tflite files are built
# from, into .cache/ml/models (git-ignored), pinned by SHA-256.
#   blaze_face_short_range.tflite - MediaPipe, Apache-2.0 (shipped as is)
#   sface.onnx                    - OpenCV Zoo SFace 2021dec, Apache-2.0
#                                   (converted by convert_sface.py)
set -euo pipefail
DEST="${1:-.cache/ml}/models"
mkdir -p "$DEST"

fetch() { # url file sha256
  if [[ -f "$DEST/$2" ]] && echo "$3  $DEST/$2" | sha256sum -c --quiet - 2>/dev/null; then
    return
  fi
  curl -fsSL --retry 4 --retry-delay 2 -o "$DEST/$2.part" "$1"
  echo "$3  $DEST/$2.part" | sha256sum -c --quiet -
  mv "$DEST/$2.part" "$DEST/$2"
}

fetch https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/latest/blaze_face_short_range.tflite \
  blaze_face_short_range.tflite b4578f35940bf5a1a655214a1cce5cab13eba73c1297cd78e1a04c2380b0152f
fetch https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx \
  sface.onnx 0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79
echo "models ready in $DEST"
