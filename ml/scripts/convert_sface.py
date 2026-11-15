"""Convert OpenCV Zoo SFace (ONNX, NCHW) to LiteRT .tflite (NHWC).

Produces, in --out:
  sface_fp32.tflite        float reference (benchmark/eval only)
  sface_int8_dr.tflite     INT8 weights, float activations (dynamic-range
                           quantisation). This is the file the app ships.

Usage (from the repo root, inside the ml venv):
  python -I ml/scripts/convert_sface.py --onnx .cache/ml/models/sface.onnx --out .cache/ml/build
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--onnx", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args()

    import onnx

    args.out.mkdir(parents=True, exist_ok=True)
    work = args.out / "sface_work"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir()

    # The 2021 export lists every initializer as a graph input; drop those so
    # converters treat weights as constants.
    model = onnx.load(str(args.onnx))
    init_names = {i.name for i in model.graph.initializer}
    keep = [i for i in model.graph.input if i.name not in init_names]
    del model.graph.input[:]
    model.graph.input.extend(keep)
    cleaned = work / "sface_clean.onnx"
    onnx.save(model, str(cleaned))

    # onnx2tf (TF backend): NCHW -> NHWC SavedModel + float32 tflite.
    # Its own flatbuffer-direct INT8 export gives a constant output for this
    # graph, so quantisation goes through TensorFlow's converter instead.
    tf_dir = work / "tf"
    subprocess.run(
        [sys.executable, "-m", "onnx2tf", "-i", str(cleaned), "-o", str(tf_dir),
         "-tb", "tf_converter", "-osd", "-n"],
        check=True,
    )
    shutil.copy(next(tf_dir.glob("*_float32.tflite")), args.out / "sface_fp32.tflite")

    import tensorflow as tf

    conv = tf.lite.TFLiteConverter.from_saved_model(str(tf_dir))
    conv.optimizations = [tf.lite.Optimize.DEFAULT]  # dynamic-range INT8 weights
    (args.out / "sface_int8_dr.tflite").write_bytes(conv.convert())

    for f in sorted(args.out.glob("*.tflite")):
        print(f"{f.name}: {f.stat().st_size / 1e6:.1f} MB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
