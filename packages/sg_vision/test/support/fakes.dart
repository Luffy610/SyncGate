import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sg_vision/sg_vision.dart';

/// A unit vector along axis [i] of a [dims]-d space, nudged by [noise] on
/// axis [j]. Distinct axes are orthogonal (cosine 0).
Float32List unit(int i, {int dims = 8, double noise = 0, int j = 0}) {
  final v = List<double>.filled(dims, 0);
  v[i] = 1;
  v[j] += noise;
  return l2Normalise(v);
}

/// A vector with cosine [cos] to axis [i] (the rest on axis [other]).
Float32List withCosine(int i, double cos, {int other = 7, int dims = 8}) {
  final v = List<double>.filled(dims, 0);
  v[i] = cos;
  v[other] = math.sqrt(1 - cos * cos);
  return Float32List.fromList(v);
}

/// A face whose nose sits at [yaw] between the ears.
DetectedFace faceWithYaw(double yaw, {double size = 200}) {
  const cx = 320.0;
  const cy = 240.0;
  final half = size / 2;
  final noseX = cx + yaw * half;
  return DetectedFace(
    score: 0.99,
    left: cx - half,
    top: cy - half,
    right: cx + half,
    bottom: cy + half,
    keypoints: [
      Point2(cx - size * 0.18, cy - size * 0.1),
      Point2(cx + size * 0.18, cy - size * 0.1),
      Point2(noseX, cy + size * 0.05),
      Point2(cx, cy + size * 0.25),
      Point2(cx - half, cy),
      Point2(cx + half, cy),
    ],
  );
}

const goodQuality = FaceQuality(
  interOcularFraction: 0.1,
  yaw: 0,
  faceLuma: 120,
  frameLuma: 120,
  sharpness: 150,
);

FrameAnalysis analysisOf(
  Float32List? embedding, {
  double yaw = 0,
  QualityIssue? issue,
  bool face = true,
}) => FrameAnalysis(
  frameWidth: 640,
  frameHeight: 480,
  micros: 1000,
  frameLuma: 120,
  face: face ? faceWithYaw(yaw) : null,
  quality: face ? goodQuality : null,
  issue: issue,
  embedding: issue == null ? embedding : null,
);

FaceTemplate template(String worker, Float32List v, {TemplateSlot? slot}) =>
    FaceTemplate(
      workerId: worker,
      slot: slot ?? TemplateSlot.front,
      vector: v,
      modelId: 'test',
      modelVersion: '1',
      quality: 1,
      createdAt: DateTime(2026, 11),
    );

const testThresholds = MatchThresholds(
  presets: {
    MatchPreset.strict: 0.7,
    MatchPreset.standard: 0.6,
    MatchPreset.relaxed: 0.5,
  },
  margin: 0.08,
  duplicate: 0.65,
  adapt: 0.9,
);
