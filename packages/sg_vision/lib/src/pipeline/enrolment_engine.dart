import 'dart:typed_data';

import 'package:sg_vision/src/enrolment.dart';
import 'package:sg_vision/src/pipeline/face_embedder.dart';
import 'package:sg_vision/src/pipeline/face_pipeline.dart';
import 'package:sg_vision/src/pipeline/matcher.dart';
import 'package:sg_vision/src/pipeline/model_manifest.dart';
import 'package:sg_vision/src/pipeline/quality.dart';
import 'package:sg_vision/src/pipeline/templates.dart';

/// Rules for guided capture (ADR-0008 §1, design 14).
final class EnrolmentPolicy {
  const new({
    this.angles = const [
      CaptureAngle.front,
      CaptureAngle.left,
      CaptureAngle.right,
      CaptureAngle.mask,
    ],
    this.framesPerAngle = 3,
    this.frontMaxYaw = 0.3,
    this.sideMinYaw = 0.3,
    this.sideMaxYaw = 0.95,
    this.consistency = 0.3,
    this.quality = const QualityPolicy(maxYaw: 1.01),
    this.requirePose = true,
  });

  /// Capture only a frontal sample: for still-photo evaluation and tests.
  static const frontOnly = EnrolmentPolicy(angles: [CaptureAngle.front]);

  /// Every angle accepts any pose: for driving the guided flow with still
  /// photos (tests, demos). Never for real enrolment.
  static const stills = EnrolmentPolicy(requirePose: false);

  /// In order. [CaptureAngle.mask] is optional and can be skipped.
  final List<CaptureAngle> angles;

  /// Good frames needed per angle (ADR-0008: ≥ 3).
  final int framesPerAngle;
  final double frontMaxYaw;
  final double sideMinYaw;
  final double sideMaxYaw;

  /// Frames that do not resemble the front sample at least this much are
  /// ignored, so a passer-by cannot slip into someone's enrolment.
  final double consistency;

  /// Yaw is judged per angle, so the generic yaw limit is off.
  final QualityPolicy quality;

  /// Whether each angle checks the head pose (off only for [stills]).
  final bool requirePose;
}

/// What [EnrolmentEngine.finish] decided.
final class EnrolmentResult {
  const new(this.outcome, this.templates);

  final EnrolOutcome outcome;

  /// The templates to store (empty for a duplicate that was not overridden).
  final List<FaceTemplate> templates;
}

/// Guided multi-angle capture → one mean template per angle, then the
/// duplicate check against everyone already enrolled.
final class EnrolmentEngine {
  new({
    required this.thresholds,
    required this.modelId,
    required this.modelVersion,
    this.policy = const EnrolmentPolicy(),
  });

  final MatchThresholds thresholds;
  final String modelId;
  final String modelVersion;
  final EnrolmentPolicy policy;

  var _index = 0;
  final _frames = <CaptureAngle, List<Float32List>>{};
  final _quality = <CaptureAngle, List<double>>{};
  double? _firstSideSign;
  var _maskSkipped = false;
  bool? _lastHadIssue;

  CaptureAngle? get current =>
      _index < policy.angles.length ? policy.angles[_index] : null;

  /// All required angles captured (mask counts only if not skipped).
  bool get complete => current == null;

  /// Feeds one analysed frame (use [EnrolmentPolicy.quality] in the
  /// pipeline). Returns the events for the capture screen.
  List<CaptureEvent> onFrame(FrameAnalysis a) {
    final angle = current;
    if (angle == null) return const [];
    final events = <CaptureEvent>[];
    final face = a.face;
    if (face == null) return events;
    if (a.issue != null || a.embedding == null) {
      if (_lastHadIssue != true || a.issue != null) {
        events.add(CaptureQuality(a.issue));
      }
      _lastHadIssue = true;
      return events;
    }
    if (_lastHadIssue ?? true) events.add(const CaptureQuality(null));
    _lastHadIssue = false;

    if (!_poseFits(angle, face.yaw)) return events;
    final front = _frames[CaptureAngle.front];
    if (front != null &&
        front.isNotEmpty &&
        cosine(meanEmbedding(front), a.embedding!) < policy.consistency) {
      return events;
    }
    if (angle == CaptureAngle.left || angle == CaptureAngle.right) {
      _firstSideSign ??= face.yaw.sign;
    }
    final list = _frames.putIfAbsent(angle, () => [])..add(a.embedding!);
    _quality.putIfAbsent(angle, () => []).add(a.quality?.score ?? 0);
    events.add(
      AngleProgress(
        angle: angle,
        fraction: list.length / policy.framesPerAngle,
      ),
    );
    if (list.length >= policy.framesPerAngle) {
      events.add(AngleDone(angle));
      _index++;
      if (current == CaptureAngle.mask && _maskSkipped) _index++;
    }
    return events;
  }

  bool _poseFits(CaptureAngle angle, double yaw) {
    if (!policy.requirePose) return true;
    final a = yaw.abs();
    switch (angle) {
      case CaptureAngle.front:
      case CaptureAngle.mask:
        return a <= policy.frontMaxYaw;
      case CaptureAngle.left:
      case CaptureAngle.right:
        if (a < policy.sideMinYaw || a > policy.sideMaxYaw) return false;
        // Which sign is "left" depends on mirroring, so the first side
        // fixes it and the second must be the other way.
        final first = _firstSideSign;
        if (first == null) return true;
        final isFirstSide =
            angle ==
            policy.angles.firstWhere(
              (x) => x == CaptureAngle.left || x == CaptureAngle.right,
            );
        return isFirstSide ? yaw.sign == first : yaw.sign == -first;
    }
  }

  /// The mask sample is optional.
  void skipMask() {
    _maskSkipped = true;
    if (current == CaptureAngle.mask) _index++;
  }

  /// Builds the templates and runs the duplicate check against [existing]
  /// (everyone else's templates).
  EnrolmentResult finish({
    required String workerId,
    required List<FaceTemplate> existing,
    required DateTime now,
    bool overrideDuplicate = false,
  }) {
    if (!(_frames[CaptureAngle.front]?.isNotEmpty ?? false)) {
      throw StateError('no frontal sample captured');
    }
    final templates = <FaceTemplate>[
      for (final MapEntry(key: angle, value: vs) in _frames.entries)
        if (vs.length >= policy.framesPerAngle)
          FaceTemplate(
            workerId: workerId,
            slot: TemplateSlot.values.byName(angle.name),
            vector: meanEmbedding(vs),
            modelId: modelId,
            modelVersion: modelVersion,
            quality: _quality[angle]!.reduce((a, b) => a + b) / vs.length,
            createdAt: now,
          ),
    ];
    if (!overrideDuplicate) {
      final others = FaceMatcher(existing.where((t) => t.workerId != workerId));
      for (final t in templates) {
        final best = others.best(t.vector);
        if (best != null && best.score >= thresholds.duplicate) {
          return EnrolmentResult(EnrolDuplicate(best.workerId), const []);
        }
      }
    }
    return EnrolmentResult(const EnrolOk(), templates);
  }

  /// Drops captured samples (cancel).
  void clear() {
    for (final vs in _frames.values) {
      for (final v in vs) {
        v.fillRange(0, v.length, 0);
      }
    }
    _frames.clear();
    _quality.clear();
    _index = 0;
    _firstSideSign = null;
    _maskSkipped = false;
  }
}
