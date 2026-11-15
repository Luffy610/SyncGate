import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sg_vision/src/pipeline/face_detector.dart';
import 'package:sg_vision/src/pipeline/geometry.dart';
import 'package:sg_vision/src/pipeline/rgb_image.dart';
import 'package:sg_vision/src/pipeline/tensor_model.dart';

/// Side of the aligned face crop the embedder takes.
const alignedSize = 112;

/// The similarity transform that puts [face]'s eyes, nose tip and mouth
/// centre on [template] in a 112×112 crop.
Affine alignmentFor(DetectedFace face, List<Point2> template) =>
    Affine.similarity(face.keypoints.sublist(0, 4), template);

/// The aligned 112×112 RGB face crop. Wipe it after use.
RgbImage alignFace(RgbImage frame, DetectedFace face, List<Point2> template) =>
    warpAffine(frame, alignmentFor(face, template), alignedSize, alignedSize);

/// SFace (MobileFaceNet trained with the SFace loss; Apache-2.0, OpenCV Zoo)
/// on LiteRT. Input: aligned RGB, 0..255. Output: an L2-normalised vector.
///
/// With [flip] the crop and its mirror image are both embedded and summed
/// (test-time augmentation), as in `ml/eval/pipeline.py` `Embedder`.
final class SFaceEmbedder {
  new(this._model, {this.dims = 128, this.flip = true})
    : _output = _model.outputNames.single;

  final TensorModel _model;

  /// The model's only output (its name depends on the converter).
  final String _output;
  final int dims;
  final bool flip;

  Float32List embed(RgbImage aligned) {
    final sum = Float64List(dims);
    _accumulate(aligned, sum, mirror: false);
    if (flip) _accumulate(aligned, sum, mirror: true);
    return l2Normalise(sum);
  }

  /// Frees the model.
  void close() => _model.close();

  void _accumulate(RgbImage img, Float64List sum, {required bool mirror}) {
    toFloatTensor(img, mirror: mirror, into: _model.input);
    _model.invoke();
    final out = _model.output(_output);
    for (var i = 0; i < dims; i++) {
      sum[i] += out[i];
    }
  }
}

/// [v] scaled to unit length, as float32.
Float32List l2Normalise(List<double> v) {
  var n = 0.0;
  for (final x in v) {
    n += x * x;
  }
  n = math.sqrt(n) + 1e-12;
  return Float32List.fromList([for (final x in v) x / n]);
}

/// Cosine similarity of two unit vectors.
double cosine(Float32List a, Float32List b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

/// The unit-length mean of several unit vectors (a template from frames).
Float32List meanEmbedding(Iterable<Float32List> vs) {
  final it = vs.toList();
  if (it.isEmpty) throw ArgumentError('no embeddings');
  final sum = Float64List(it.first.length);
  for (final v in it) {
    for (var i = 0; i < v.length; i++) {
      sum[i] += v[i];
    }
  }
  return l2Normalise(sum);
}
