import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sg_vision/src/pipeline/geometry.dart';
import 'package:sg_vision/src/pipeline/rgb_image.dart';
import 'package:sg_vision/src/pipeline/tensor_model.dart';

/// Keypoint order of BlazeFace (subject's right/left).
enum FaceKeypoint { rightEye, leftEye, noseTip, mouthCentre, rightEar, leftEar }

/// One detected face in frame pixels.
final class DetectedFace {
  const new({
    required this.score,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.keypoints,
  });

  final double score;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Six points in [FaceKeypoint] order.
  final List<Point2> keypoints;

  double get width => right - left;
  double get height => bottom - top;
  Point2 get centre => Point2((left + right) / 2, (top + bottom) / 2);
  Point2 operator [](FaceKeypoint k) => keypoints[k.index];

  /// Distance between the eye centres, in pixels.
  double get interOcular =>
      this[FaceKeypoint.rightEye].distanceTo(this[FaceKeypoint.leftEye]);

  /// Signed head-yaw proxy in [-1, 1]: where the nose sits between the ears.
  /// 0 is frontal; the sign flips with the turn direction (and with mirrored
  /// frames, so callers must not rely on which sign means "left").
  double get yaw {
    final r = this[FaceKeypoint.rightEar];
    final l = this[FaceKeypoint.leftEar];
    final span = l.x - r.x;
    if (span.abs() < 1e-6) return 0;
    final t = (this[FaceKeypoint.noseTip].x - r.x) / span;
    return ((t - 0.5) * 2).clamp(-1.0, 1.0);
  }
}

/// MediaPipe BlazeFace short-range (Apache-2.0) on LiteRT, with a second
/// pass on a crop around the face for sharper keypoints. Mirrors
/// `ml/eval/pipeline.py` `Detector`.
final class BlazeFaceDetector {
  new(
    this._model, {
    this.inputSize = 128,
    this.scoreMin = 0.5,
    this.nmsIou = 0.3,
    this.refineCropScale = 2.0,
  }) : _anchors = _ssdAnchors(inputSize);

  final TensorModel _model;
  final int inputSize;
  final double scoreMin;
  final double nmsIou;
  final double refineCropScale;
  final Float32List _anchors;

  /// 896 anchor centres (x, y) for the short-range model.
  static Float32List _ssdAnchors(int size) {
    final out = <double>[];
    for (final (stride, perCell) in const [(8, 2), (16, 6)]) {
      final n = size ~/ stride;
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          for (var k = 0; k < perCell; k++) {
            out
              ..add((x + 0.5) / n)
              ..add((y + 0.5) / n);
          }
        }
      }
    }
    return Float32List.fromList(out);
  }

  /// The most confident face in [frame], or `null`.
  DetectedFace? detect(RgbImage frame, {bool refine = true}) {
    final side = math.max(frame.width, frame.height).toDouble();
    final s = inputSize / side;
    // Letterbox: centre the frame in a square, scale to the input size.
    final letterbox = Affine.scaleTranslate(
      s,
      (side - frame.width) / 2 * s,
      (side - frame.height) / 2 * s,
    );
    final first = _best(_run(frame, letterbox));
    if (first == null || !refine) return first;

    final crop = refineCropScale * math.max(first.width, first.height);
    final c = first.centre;
    final rs = inputSize / crop;
    final cropTx = Affine.scaleTranslate(
      rs,
      (crop / 2 - c.x) * rs,
      (crop / 2 - c.y) * rs,
    );
    return _best(_run(frame, cropTx)) ?? first;
  }

  /// Frees the model.
  void close() => _model.close();

  static DetectedFace? _best(List<DetectedFace> faces) {
    if (faces.isEmpty) return null;
    return faces.reduce((a, b) => b.score > a.score ? b : a);
  }

  List<DetectedFace> _run(RgbImage frame, Affine frameToInput) {
    final img = warpAffine(frame, frameToInput, inputSize, inputSize);
    toFloatTensor(img, scale: 1 / 127.5, offset: -1, into: _model.input);
    img.wipe();
    _model.invoke();
    final reg = _model.output('regressors');
    final cls = _model.output('classificators');
    final back = frameToInput.inverse();
    final size = inputSize.toDouble();

    final cands = <_Candidate>[];
    for (var i = 0; i < cls.length; i++) {
      final logit = cls[i].clamp(-100.0, 100.0);
      final score = 1 / (1 + math.exp(-logit));
      if (score < scoreMin) continue;
      final ax = _anchors[2 * i];
      final ay = _anchors[2 * i + 1];
      final r = i * 16;
      final cx = (reg[r] / size + ax) * size;
      final cy = (reg[r + 1] / size + ay) * size;
      final w = reg[r + 2];
      final h = reg[r + 3];
      final tl = back.apply(Point2(cx - w / 2, cy - h / 2));
      final br = back.apply(Point2(cx + w / 2, cy + h / 2));
      final kps = Float64List(12);
      for (var k = 0; k < 6; k++) {
        final p = back.apply(
          Point2(
            (reg[r + 4 + 2 * k] / size + ax) * size,
            (reg[r + 5 + 2 * k] / size + ay) * size,
          ),
        );
        kps[2 * k] = p.x;
        kps[2 * k + 1] = p.y;
      }
      cands.add(_Candidate(score, [tl.x, tl.y, br.x, br.y], kps));
    }
    return _weightedNms(cands);
  }

  List<DetectedFace> _weightedNms(List<_Candidate> cands) {
    cands.sort((a, b) => b.score.compareTo(a.score));
    final faces = <DetectedFace>[];
    var remaining = cands;
    while (remaining.isNotEmpty) {
      final top = remaining.first;
      final group = <_Candidate>[];
      final rest = <_Candidate>[];
      for (final c in remaining) {
        (_iou(top.box, c.box) > nmsIou ? group : rest).add(c);
      }
      remaining = rest;
      var wSum = 0.0;
      final box = List<double>.filled(4, 0);
      final kps = List<double>.filled(12, 0);
      for (final c in group) {
        wSum += c.score;
        for (var j = 0; j < 4; j++) {
          box[j] += c.box[j] * c.score;
        }
        for (var j = 0; j < 12; j++) {
          kps[j] += c.kps[j] * c.score;
        }
      }
      faces.add(
        DetectedFace(
          score: top.score,
          left: box[0] / wSum,
          top: box[1] / wSum,
          right: box[2] / wSum,
          bottom: box[3] / wSum,
          keypoints: [
            for (var k = 0; k < 6; k++)
              Point2(kps[2 * k] / wSum, kps[2 * k + 1] / wSum),
          ],
        ),
      );
    }
    return faces;
  }

  static double _iou(List<double> a, List<double> b) {
    final ix = math.max(0, math.min(a[2], b[2]) - math.max(a[0], b[0]));
    final iy = math.max(0, math.min(a[3], b[3]) - math.max(a[1], b[1]));
    final inter = ix * iy;
    final union =
        (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter;
    return union > 0 ? inter / union : 0;
  }
}

final class _Candidate {
  const new(this.score, this.box, this.kps);

  final double score;
  final List<double> box;
  final Float64List kps;
}
