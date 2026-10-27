/// Events emitted by the gate pipeline (mirrors the Pigeon v0 contract,
/// delivery plan E02-T02).
sealed class VisionEvent {
  const new();
}

/// A face is in view. [faceSizeRatio] is face height / frame height.
final class FaceSeen extends VisionEvent {
  const new({required this.faceSizeRatio});

  final double faceSizeRatio;
}

/// The current frame is not good enough; the UI shows a fix-it hint.
final class QualityHint extends VisionEvent {
  const new(this.issue);

  final QualityIssue issue;
}

/// A worker was recognised and passed liveness.
final class Match extends VisionEvent {
  const new({
    required this.workerId,
    required this.score,
    required this.margin,
    required this.liveness,
  });

  final String workerId;
  final double score;
  final double margin;
  final double liveness;
}

/// A face was seen but not accepted.
final class NoMatch extends VisionEvent {
  const new(this.reason);

  final NoMatchReason reason;
}

/// Periodic pipeline health, used by debug overlays and the camera check.
final class PipelineStats extends VisionEvent {
  const new({required this.fps, required this.p95Ms, required this.lux});

  final double fps;
  final int p95Ms;
  final double lux;
}

enum QualityIssue {
  tooDark,
  backlight,
  tooFar,
  turnLess,
  blurry,
  covered,
  dirtyLens,
}

enum NoMatchReason { unknown, lowMargin, livenessFail }
