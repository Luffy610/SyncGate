import 'package:flutter_test/flutter_test.dart';
import 'package:sg_vision/sg_vision.dart';

import 'support/fakes.dart';

void main() {
  final t0 = DateTime(2026, 11, 4, 6);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  GateEngine engine({LivenessEstimator? liveness, Set<String>? active}) {
    return GateEngine(thresholds: testThresholds, liveness: liveness)
      ..setGallery(
        FaceMatcher([
          template('ramesh', unit(0)),
          template('sunita', unit(1)),
          template('sunita', unit(2), slot: TemplateSlot.left),
        ]),
        active: active,
      );
  }

  List<VisionEvent> feed(GateEngine e, List<(int, FrameAnalysis)> frames) => [
    for (final (ms, a) in frames) ...e.onFrame(a, at(ms)).events,
  ];

  group('FaceMatcher', () {
    test("a worker's score is the best of their slots", () {
      final m = FaceMatcher([
        template('a', unit(0)),
        template('a', unit(1), slot: TemplateSlot.left),
        template('b', unit(2)),
      ]);
      final best = m.best(withCosine(1, 0.9, other: 2))!;
      expect(best.workerId, 'a');
      expect(best.score, closeTo(0.9, 1e-6));
      expect(best.runnerUpId, 'b');
      expect(best.margin, closeTo(0.9 - 0.4359, 1e-3));
    });

    test('can be limited to some workers', () {
      final m = FaceMatcher([template('a', unit(0)), template('b', unit(1))]);
      expect(m.best(unit(0), only: {'b'})!.workerId, 'b');
      expect(m.best(unit(0), only: {})?.workerId, isNull);
    });
  });

  group('GateEngine (ADR-0009)', () {
    test('matches when the same worker wins 2 of 3 frames', () {
      final e = engine();
      final events = feed(e, [
        (0, analysisOf(withCosine(0, 0.8))),
        (200, analysisOf(withCosine(0, 0.82))),
      ]);
      final match = events.whereType<Match>().single;
      expect(match.workerId, 'ramesh');
      expect(match.score, closeTo(0.81, 1e-3));
      expect(match.liveness, 1.0);
      expect(events.whereType<FaceSeen>(), hasLength(2));
    });

    test('one good frame is not enough', () {
      final e = engine();
      final events = feed(e, [(0, analysisOf(withCosine(0, 0.9)))]);
      expect(events.whereType<Match>(), isEmpty);
    });

    test('frames further apart than the agreement span do not count', () {
      final e = engine();
      final events = feed(e, [
        (0, analysisOf(withCosine(0, 0.9))),
        (1500, analysisOf(withCosine(0, 0.9))),
      ]);
      expect(events.whereType<Match>(), isEmpty);
    });

    test('a look-alike (small margin) is "not recognised" after 2 s', () {
      final e = engine();
      // Equally close to Ramesh (axis 0) and Sunita (axis 1).
      final between = l2Normalise([1, 1, 0, 0, 0, 0, 0, 0.1]);
      final events = feed(e, [
        for (var ms = 0; ms <= 2000; ms += 250) (ms, analysisOf(between)),
      ]);
      expect(events.whereType<Match>(), isEmpty);
      expect(
        events.whereType<NoMatch>().single.reason,
        NoMatchReason.lowMargin,
      );
    });

    test('a stranger is "not recognised" after 2 s', () {
      final e = engine();
      final events = feed(e, [
        for (var ms = 0; ms <= 2000; ms += 250) (ms, analysisOf(unit(5))),
      ]);
      expect(events.whereType<NoMatch>().single.reason, NoMatchReason.unknown);
    });

    test('poor frames give hints and never match', () {
      final e = engine();
      final events = feed(e, [
        for (var ms = 0; ms <= 3000; ms += 250)
          (ms, analysisOf(unit(0), issue: QualityIssue.tooDark)),
      ]);
      expect(events.whereType<QualityHint>().first.issue, QualityIssue.tooDark);
      expect(events.whereType<Match>(), isEmpty);
      expect(events.whereType<NoMatch>(), isEmpty);
    });

    test('only active workers can match', () {
      final e = engine(active: {'sunita'});
      final events = feed(e, [
        for (var ms = 0; ms <= 2000; ms += 250) (ms, analysisOf(unit(0))),
      ]);
      expect(events.whereType<Match>(), isEmpty);
    });

    test('after a match the next person needs the face to leave first', () {
      final e = engine();
      final first = feed(e, [
        (0, analysisOf(unit(0))),
        (200, analysisOf(unit(0))),
      ]);
      expect(first.whereType<Match>().single.workerId, 'ramesh');
      // Sunita steps in without a gap: held until retryAfter (3 s).
      final held = feed(e, [
        (400, analysisOf(unit(1))),
        (600, analysisOf(unit(1))),
      ]);
      expect(held.whereType<Match>(), isEmpty);
      // The frame empties, then Sunita walks up.
      final next = feed(e, [
        (700, analysisOf(null, face: false)),
        (1600, analysisOf(null, face: false)),
        (1800, analysisOf(unit(1))),
        (2000, analysisOf(unit(1))),
      ]);
      expect(next.whereType<Match>().single.workerId, 'sunita');
    });

    test('the same worker is not re-sent while they linger', () {
      final e = engine();
      final events = feed(e, [
        for (var ms = 0; ms <= 8000; ms += 200) (ms, analysisOf(unit(0))),
      ]);
      expect(events.whereType<Match>(), hasLength(1));
    });

    test('a liveness fail looks like "not recognised"', () {
      final e = engine(liveness: _AlwaysSpoof());
      final events = feed(e, [
        (0, analysisOf(unit(0))),
        (200, analysisOf(unit(0))),
      ]);
      expect(events.whereType<Match>(), isEmpty);
      expect(
        events.whereType<NoMatch>().single.reason,
        NoMatchReason.livenessFail,
      );
    });

    test('a very confident match offers an adaptive template', () {
      final e = engine()..onFrame(analysisOf(unit(0)), at(0));
      final step = e.onFrame(analysisOf(unit(0)), at(200));
      expect(step.adaptive?.workerId, 'ramesh');
    });
  });
}

final class _AlwaysSpoof implements LivenessEstimator {
  @override
  double get threshold => 0.5;

  @override
  double score(List<FrameAnalysis> frames) => 0.1;
}
