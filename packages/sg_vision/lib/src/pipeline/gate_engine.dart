import 'dart:typed_data';

import 'package:sg_vision/src/pipeline/face_pipeline.dart';
import 'package:sg_vision/src/pipeline/matcher.dart';
import 'package:sg_vision/src/pipeline/model_manifest.dart';
import 'package:sg_vision/src/vision_event.dart';

/// Presentation-attack check (ADR-0007). Returns a calibrated 0..1 score for
/// the frames of one walk-up; the gate rejects below [threshold].
abstract interface class LivenessEstimator {
  double get threshold;
  double score(List<FrameAnalysis> frames);
}

/// Timing and agreement rules for the gate decision (ADR-0009 §2).
final class GateRules {
  const new({
    this.preset = MatchPreset.standard,
    this.window = 3,
    this.agree = 2,
    this.span = const Duration(seconds: 1),
    this.decideWithin = const Duration(seconds: 2),
    this.rearmAfterAbsence = const Duration(milliseconds: 800),
    this.retryAfter = const Duration(seconds: 3),
    this.sameWorkerCooldown = const Duration(seconds: 10),
  });

  final MatchPreset preset;

  /// The same worker must win in [agree] of the last [window] analysed
  /// frames, all within [span].
  final int window;
  final int agree;
  final Duration span;

  /// Keep scanning ("Hold still…") this long before "Not recognised".
  final Duration decideWithin;

  /// A new attempt starts once no face has been seen for this long…
  final Duration rearmAfterAbsence;

  /// …or this long after the last decision, if someone is still in view.
  final Duration retryAfter;

  /// A second match of the same worker within this time is not re-sent.
  final Duration sameWorkerCooldown;
}

/// A confident gate capture that may refresh a worker's adaptive slot
/// (ADR-0008 §4). The service decides whether to store it.
final class AdaptiveCandidate {
  const new({
    required this.workerId,
    required this.embedding,
    required this.score,
    required this.quality,
  });

  final String workerId;
  final Float32List embedding;
  final double score;
  final double quality;
}

/// The result of feeding one frame to [GateEngine].
final class GateStep {
  const new(this.events, {this.adaptive});

  final List<VisionEvent> events;
  final AdaptiveCandidate? adaptive;
}

final class _Vote {
  const new(this.at, this.frame, this.candidate, {required this.passes});

  final DateTime at;
  final FrameAnalysis frame;
  final MatchCandidate? candidate;
  final bool passes;
}

/// Turns frame analyses into gate events with the ADR-0009 rule: a match
/// needs `score ≥ T_match`, a `margin` over the next worker, agreement over
/// several frames and (when configured) liveness.
final class GateEngine {
  new({
    required this.thresholds,
    this.rules = const GateRules(),
    this.liveness,
  });

  final MatchThresholds thresholds;
  final GateRules rules;
  final LivenessEstimator? liveness;

  FaceMatcher _matcher = FaceMatcher(const []);
  Set<String>? _active;
  final _votes = <_Vote>[];
  DateTime? _attemptStart;
  DateTime? _lastFaceAt;
  DateTime? _decidedAt;
  var _sawLowMargin = false;
  String? _lastMatched;
  DateTime? _lastMatchedAt;

  /// Replaces the gallery. [active] limits matching to those workers (only
  /// active, enrolled workers may mark attendance).
  void setGallery(FaceMatcher matcher, {Set<String>? active}) {
    _matcher = matcher;
    _active = active;
  }

  double get _tMatch => thresholds.match(rules.preset);

  void _resetAttempt() {
    _votes.clear();
    _attemptStart = null;
    _decidedAt = null;
    _sawLowMargin = false;
  }

  GateStep onFrame(FrameAnalysis a, DateTime at) {
    final face = a.face;
    if (face == null) {
      final last = _lastFaceAt;
      if (last != null && at.difference(last) >= rules.rearmAfterAbsence) {
        _resetAttempt();
        _lastFaceAt = null;
      }
      return const GateStep([]);
    }
    _lastFaceAt = at;
    final events = <VisionEvent>[FaceSeen(faceSizeRatio: a.faceSizeRatio)];

    final decided = _decidedAt;
    if (decided != null) {
      if (at.difference(decided) < rules.retryAfter) return GateStep(events);
      _resetAttempt();
    }

    final issue = a.issue;
    if (issue != null || a.embedding == null) {
      if (issue != null) events.add(QualityHint(issue));
      return GateStep(events);
    }

    _attemptStart ??= at;
    final cand = _matcher.best(a.embedding!, only: _active);
    final overThreshold = cand != null && cand.score >= _tMatch;
    final passes = overThreshold && cand.margin >= thresholds.margin;
    if (overThreshold && !passes) _sawLowMargin = true;
    _votes
      ..add(_Vote(at, a, cand, passes: passes))
      ..removeWhere((v) => at.difference(v.at) > rules.span);
    while (_votes.length > rules.window) {
      _votes.removeAt(0);
    }

    final winner = _winner();
    if (winner != null) {
      final mine = _votes
          .where((v) => v.passes && v.candidate!.workerId == winner)
          .toList();
      final live = liveness;
      final liveScore = live == null
          ? 1.0
          : live.score([for (final v in _votes) v.frame]);
      _decidedAt = at;
      if (live != null && liveScore < live.threshold) {
        // Same UI as no match: attackers learn nothing (ADR-0007).
        events.add(const NoMatch(NoMatchReason.livenessFail));
        return GateStep(events);
      }
      final repeat =
          winner == _lastMatched &&
          _lastMatchedAt != null &&
          at.difference(_lastMatchedAt!) < rules.sameWorkerCooldown;
      if (repeat) return GateStep(events);
      _lastMatched = winner;
      _lastMatchedAt = at;
      final score =
          mine.map((v) => v.candidate!.score).reduce((x, y) => x + y) /
          mine.length;
      final margin = mine
          .map((v) => v.candidate!.margin)
          .reduce((x, y) => x < y ? x : y);
      events.add(
        Match(
          workerId: winner,
          score: score,
          margin: margin,
          liveness: liveScore,
        ),
      );
      final best = mine.reduce(
        (x, y) => y.candidate!.score > x.candidate!.score ? y : x,
      );
      final quality = best.frame.quality?.score ?? 0;
      final adaptive =
          best.candidate!.score >= thresholds.adapt && quality >= 0.8
          ? AdaptiveCandidate(
              workerId: winner,
              embedding: best.frame.embedding!,
              score: best.candidate!.score,
              quality: quality,
            )
          : null;
      return GateStep(events, adaptive: adaptive);
    }

    if (at.difference(_attemptStart!) >= rules.decideWithin) {
      _decidedAt = at;
      events.add(
        NoMatch(
          _sawLowMargin ? NoMatchReason.lowMargin : NoMatchReason.unknown,
        ),
      );
    }
    return GateStep(events);
  }

  String? _winner() {
    final counts = <String, int>{};
    for (final v in _votes) {
      if (!v.passes) continue;
      final id = v.candidate!.workerId;
      final n = (counts[id] ?? 0) + 1;
      if (n >= rules.agree) return id;
      counts[id] = n;
    }
    return null;
  }
}
