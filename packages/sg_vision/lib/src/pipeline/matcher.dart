import 'dart:typed_data';

import 'package:sg_vision/src/pipeline/face_embedder.dart';
import 'package:sg_vision/src/pipeline/templates.dart';

/// The best and runner-up workers for one probe (ADR-0009 §1).
final class MatchCandidate {
  const new({
    required this.workerId,
    required this.score,
    required this.runnerUpId,
    required this.runnerUpScore,
  });

  final String workerId;
  final double score;
  final String? runnerUpId;

  /// Best score of any *other* worker; -1 when the gallery has one worker.
  final double runnerUpScore;

  double get margin => score - runnerUpScore;
}

/// Exact brute-force cosine search over every template (≤ 150 vectors).
/// A worker's score is the max over their slots.
final class FaceMatcher {
  new(Iterable<FaceTemplate> templates) {
    for (final t in templates) {
      (_byWorker[t.workerId] ??= []).add(t.vector);
    }
  }

  final _byWorker = <String, List<Float32List>>{};

  bool get isEmpty => _byWorker.isEmpty;
  int get workers => _byWorker.length;

  /// Per-worker best scores for [probe], restricted to [only] if given.
  Map<String, double> scores(Float32List probe, {Set<String>? only}) => {
    for (final MapEntry(key: id, value: vs) in _byWorker.entries)
      if (only == null || only.contains(id))
        id: vs.map((v) => cosine(v, probe)).reduce((a, b) => a > b ? a : b),
  };

  /// Top-1 and top-2 workers, or `null` for an empty gallery.
  MatchCandidate? best(Float32List probe, {Set<String>? only}) {
    String? bestId;
    String? secondId;
    var best = -2.0;
    var second = -1.0;
    for (final MapEntry(key: id, value: s) in scores(
      probe,
      only: only,
    ).entries) {
      if (s > best) {
        secondId = bestId;
        second = bestId == null ? -1 : best;
        bestId = id;
        best = s;
      } else if (s > second) {
        secondId = id;
        second = s;
      }
    }
    if (bestId == null) return null;
    return MatchCandidate(
      workerId: bestId,
      score: best,
      runnerUpId: secondId,
      runnerUpScore: second,
    );
  }
}
