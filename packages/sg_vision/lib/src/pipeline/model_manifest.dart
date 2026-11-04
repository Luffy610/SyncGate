import 'dart:convert';

import 'package:sg_vision/src/pipeline/geometry.dart';

/// Owner-facing match strictness (ADR-0009 §4). Each moves `T_match` within
/// bounds that keep system FAR at N = 25 under 0.1%.
enum MatchPreset { strict, standard, relaxed }

/// Thresholds calibrated for one embedding-model version (ADR-0009). They
/// come from `ml/eval/evaluate.py` and ship in `manifest.json`.
final class MatchThresholds {
  const new({
    required this.presets,
    required this.margin,
    required this.duplicate,
    required this.adapt,
  });

  /// Minimum cosine score for a match, per preset.
  final Map<MatchPreset, double> presets;

  /// Minimum lead of the best worker over the next worker.
  final double margin;

  /// Enrolment duplicate check (stricter than the gate, ADR-0008 §3).
  final double duplicate;

  /// Score needed to refresh the adaptive slot (ADR-0008 §4).
  final double adapt;

  double match(MatchPreset preset) => presets[preset]!;
}

/// Describes the models that ship in `assets/models/` and how to run them.
final class ModelManifest {
  const new({
    required this.detectorFile,
    required this.detectorSha256,
    required this.detectorInput,
    required this.detectorScoreMin,
    required this.detectorNmsIou,
    required this.refineCropScale,
    required this.embedderFile,
    required this.embedderSha256,
    required this.modelId,
    required this.modelVersion,
    required this.dims,
    required this.template,
    required this.thresholds,
  });

  factory parse(String json) =>
      ModelManifest.fromJson(jsonDecode(json) as Map<String, Object?>);

  factory fromJson(Map<String, Object?> j) {
    final det = j['detector']! as Map<String, Object?>;
    final emb = j['embedder']! as Map<String, Object?>;
    final th = j['thresholds']! as Map<String, Object?>;
    final presets = th['presets']! as Map<String, Object?>;
    double n(Object? v) => (v! as num).toDouble();
    return ModelManifest(
      detectorFile: det['file']! as String,
      detectorSha256: det['sha256']! as String,
      detectorInput: (det['input']! as num).toInt(),
      detectorScoreMin: n(det['score_min']),
      detectorNmsIou: n(det['nms_iou']),
      refineCropScale: n(det['refine_crop_scale']),
      embedderFile: emb['file']! as String,
      embedderSha256: emb['sha256']! as String,
      modelId: emb['model_id']! as String,
      modelVersion: emb['model_version']! as String,
      dims: (emb['dims']! as num).toInt(),
      template: [
        for (final p in (j['template']! as List<Object?>).cast<List<Object?>>())
          Point2(n(p[0]), n(p[1])),
      ],
      thresholds: MatchThresholds(
        presets: {
          for (final preset in MatchPreset.values)
            preset: n(presets[preset.name]),
        },
        margin: n(th['margin']),
        duplicate: n(th['duplicate']),
        adapt: n(th['adapt']),
      ),
    );
  }

  /// Asset path prefix inside this package.
  static const assetDir = 'packages/sg_vision/assets/models';
  static const assetPath = '$assetDir/manifest.json';

  final String detectorFile;
  final String detectorSha256;
  final int detectorInput;
  final double detectorScoreMin;
  final double detectorNmsIou;
  final double refineCropScale;
  final String embedderFile;
  final String embedderSha256;

  /// Stamped on every template so a model change triggers re-enrolment
  /// (ADR-0006 §6).
  final String modelId;
  final String modelVersion;
  final int dims;

  /// Where the 4 detector keypoints (eyes, nose tip, mouth centre) land in
  /// the 112×112 aligned crop.
  final List<Point2> template;
  final MatchThresholds thresholds;
}
