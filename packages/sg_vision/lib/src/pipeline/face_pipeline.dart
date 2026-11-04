import 'dart:typed_data';

import 'package:sg_vision/src/pipeline/face_detector.dart';
import 'package:sg_vision/src/pipeline/face_embedder.dart';
import 'package:sg_vision/src/pipeline/geometry.dart';
import 'package:sg_vision/src/pipeline/model_manifest.dart';
import 'package:sg_vision/src/pipeline/quality.dart';
import 'package:sg_vision/src/pipeline/rgb_image.dart';
import 'package:sg_vision/src/pipeline/tensor_model.dart';
import 'package:sg_vision/src/vision_event.dart';

/// What the pipeline learned from one frame.
final class FrameAnalysis {
  const new({
    required this.frameWidth,
    required this.frameHeight,
    required this.micros,
    required this.frameLuma,
    this.face,
    this.quality,
    this.issue,
    this.embedding,
  });

  final int frameWidth;
  final int frameHeight;

  /// Time spent in the pipeline for this frame.
  final int micros;

  /// Mean luma of the whole frame (subsampled), face or not.
  final double frameLuma;
  final DetectedFace? face;
  final FaceQuality? quality;

  /// Why the face cannot be used, if it cannot.
  final QualityIssue? issue;

  /// Unit face vector; set only for usable faces.
  final Float32List? embedding;

  bool get usable => face != null && issue == null && embedding != null;

  /// Face height as a fraction of the frame height.
  double get faceSizeRatio => face == null ? 0 : face!.height / frameHeight;
}

/// Detect → refine → quality → align → embed (ADR-0006 §2). Pure Dart over
/// LiteRT; runs the same on Android, iOS and the test host.
final class FacePipeline {
  new({
    required this.detector,
    required this.embedder,
    required this.template,
    this.policy = const QualityPolicy(),
  });

  /// Builds the pipeline from the model files' bytes.
  factory fromBytes({
    required ModelManifest manifest,
    required Uint8List detectorBytes,
    required Uint8List embedderBytes,
    int threads = 4,
    QualityPolicy policy = const QualityPolicy(),
  }) => FacePipeline(
    detector: BlazeFaceDetector(
      LiteRtModel.fromBuffer(detectorBytes, threads: threads),
      inputSize: manifest.detectorInput,
      scoreMin: manifest.detectorScoreMin,
      nmsIou: manifest.detectorNmsIou,
      refineCropScale: manifest.refineCropScale,
    ),
    embedder: SFaceEmbedder(
      LiteRtModel.fromBuffer(embedderBytes, threads: threads),
      dims: manifest.dims,
    ),
    template: manifest.template,
    policy: policy,
  );

  final BlazeFaceDetector detector;
  final SFaceEmbedder embedder;
  final List<Point2> template;
  final QualityPolicy policy;

  /// Analyses one upright RGB [frame]. With [embedPoorFaces] the embedding
  /// is computed even when the quality gate fails (camera check, tests).
  FrameAnalysis analyse(
    RgbImage frame, {
    QualityPolicy? policy,
    bool embedPoorFaces = false,
  }) {
    final sw = Stopwatch()..start();
    final face = detector.detect(frame);
    if (face == null) {
      return FrameAnalysis(
        frameWidth: frame.width,
        frameHeight: frame.height,
        micros: sw.elapsedMicroseconds,
        frameLuma: meanLuma(frame, step: 8),
      );
    }
    final aligned = alignFace(frame, face, template);
    try {
      final quality = measureQuality(frame, face, aligned);
      final issue = (policy ?? this.policy).issue(quality);
      final embedding = issue == null || embedPoorFaces
          ? embedder.embed(aligned)
          : null;
      return FrameAnalysis(
        frameWidth: frame.width,
        frameHeight: frame.height,
        micros: sw.elapsedMicroseconds,
        frameLuma: quality.frameLuma,
        face: face,
        quality: quality,
        issue: issue,
        embedding: embedding,
      );
    } finally {
      aligned.wipe();
    }
  }
}
