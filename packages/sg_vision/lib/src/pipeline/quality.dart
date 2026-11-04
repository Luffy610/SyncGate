import 'dart:math' as math;

import 'package:sg_vision/src/pipeline/face_detector.dart';
import 'package:sg_vision/src/pipeline/rgb_image.dart';
import 'package:sg_vision/src/vision_event.dart';

/// Cheap image measurements for one detected face (ADR-0006 "Quality").
final class FaceQuality {
  const new({
    required this.interOcularFraction,
    required this.yaw,
    required this.faceLuma,
    required this.frameLuma,
    required this.sharpness,
  });

  /// Eye distance / the frame's longer side.
  final double interOcularFraction;

  /// See [DetectedFace.yaw].
  final double yaw;

  /// Mean luma (0..255) of the aligned face crop.
  final double faceLuma;

  /// Mean luma of the whole frame (subsampled).
  final double frameLuma;

  /// Variance of the Laplacian on the aligned crop: low means blurry.
  final double sharpness;

  /// 0..1 summary used for template metadata and the adaptive slot.
  double get score {
    double unit(double v, double lo, double hi) =>
        ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    return (unit(interOcularFraction, 0.04, 0.09) +
            (1 - unit(yaw.abs(), 0.2, 0.7)) +
            unit(faceLuma, 40, 90) +
            unit(sharpness, 20, 120)) /
        4;
  }
}

/// Limits for the quality gate, set from the quality percentiles in
/// `ml/reports/sface-int8-lfw.md` §4: each default sits below the 1st
/// percentile of faces the model still recognises, so the gate only asks
/// for a fix when one is really needed (too small, dark, back-lit, blurry,
/// or turned nearly side-on).
final class QualityPolicy {
  const new({
    this.minInterOcularFraction = 0.045,
    this.maxYaw = 0.95,
    this.minFaceLuma = 40,
    this.backlightDelta = 60,
    this.minSharpness = 20,
  });

  final double minInterOcularFraction;
  final double maxYaw;
  final double minFaceLuma;

  /// Frame brighter than the face by this much (with a dim face) = backlit.
  final double backlightDelta;
  final double minSharpness;

  /// The first problem to fix, or `null` if the frame is usable.
  QualityIssue? issue(FaceQuality q) {
    if (q.interOcularFraction < minInterOcularFraction) {
      return QualityIssue.tooFar;
    }
    if (q.faceLuma < minFaceLuma) {
      return q.frameLuma - q.faceLuma > backlightDelta
          ? QualityIssue.backlight
          : QualityIssue.tooDark;
    }
    if (q.frameLuma - q.faceLuma > backlightDelta && q.faceLuma < 80) {
      return QualityIssue.backlight;
    }
    if (q.yaw.abs() > maxYaw) return QualityIssue.turnLess;
    if (q.sharpness < minSharpness) return QualityIssue.blurry;
    return null;
  }
}

double _luma(int r, int g, int b) => 0.299 * r + 0.587 * g + 0.114 * b;

/// Mean luma of [img], sampling every [step]-th pixel.
double meanLuma(RgbImage img, {int step = 1}) {
  final d = img.data;
  var sum = 0.0;
  var n = 0;
  for (var y = 0; y < img.height; y += step) {
    for (var x = 0; x < img.width; x += step) {
      final i = (y * img.width + x) * 3;
      sum += _luma(d[i], d[i + 1], d[i + 2]);
      n++;
    }
  }
  return n == 0 ? 0 : sum / n;
}

/// Variance of the 4-neighbour Laplacian of [img]'s luma, over the interior.
double laplacianVariance(RgbImage img) {
  final w = img.width;
  final h = img.height;
  final d = img.data;
  final g = List<double>.generate(
    w * h,
    (i) => _luma(d[3 * i], d[3 * i + 1], d[3 * i + 2]),
  );
  var sum = 0.0;
  var sumSq = 0.0;
  var n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final c = y * w + x;
      final lap = g[c - w] + g[c + w] + g[c - 1] + g[c + 1] - 4 * g[c];
      sum += lap;
      sumSq += lap * lap;
      n++;
    }
  }
  if (n == 0) return 0;
  final mean = sum / n;
  return math.max(0, sumSq / n - mean * mean);
}

/// Measures [face] in [frame] given its aligned crop.
FaceQuality measureQuality(
  RgbImage frame,
  DetectedFace face,
  RgbImage aligned,
) => FaceQuality(
  interOcularFraction: face.interOcular / math.max(frame.width, frame.height),
  yaw: face.yaw,
  faceLuma: meanLuma(aligned),
  frameLuma: meanLuma(frame, step: 8),
  sharpness: laplacianVariance(aligned),
);
