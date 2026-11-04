import 'package:flutter_test/flutter_test.dart';
import 'package:sg_vision/sg_vision.dart';

import 'support/fakes.dart';

void main() {
  EnrolmentEngine engine({EnrolmentPolicy policy = const EnrolmentPolicy()}) =>
      EnrolmentEngine(
        thresholds: testThresholds,
        modelId: 'test',
        modelVersion: '1',
        policy: policy,
      );

  List<CaptureEvent> feed(EnrolmentEngine e, Iterable<FrameAnalysis> frames) =>
      [for (final f in frames) ...e.onFrame(f)];

  List<FrameAnalysis> frames(double yaw, [int n = 3]) => [
    for (var i = 0; i < n; i++)
      analysisOf(withCosine(0, 0.95 - i * 0.01, other: 3), yaw: yaw),
  ];

  test('front, left, right and mask each need 3 good frames', () {
    final e = engine();
    final events = [
      ...feed(e, frames(0)),
      ...feed(e, frames(0.5)),
      ...feed(e, frames(-0.5)),
      ...feed(e, frames(0.05)),
    ];
    expect(events.whereType<AngleDone>().map((d) => d.angle), [
      CaptureAngle.front,
      CaptureAngle.left,
      CaptureAngle.right,
      CaptureAngle.mask,
    ]);
    expect(
      events.whereType<AngleProgress>().first.fraction,
      closeTo(1 / 3, 1e-9),
    );
    expect(e.complete, isTrue);
    final result = e.finish(workerId: 'w1', existing: [], now: DateTime(2026));
    expect(result.outcome, isA<EnrolOk>());
    expect(result.templates.map((t) => t.slot), [
      TemplateSlot.front,
      TemplateSlot.left,
      TemplateSlot.right,
      TemplateSlot.mask,
    ]);
    expect(result.templates.first.modelId, 'test');
  });

  test('frontal frames do not count for a side angle', () {
    final e = engine()..onFrame(frames(0)[0]);
    feed(e, frames(0, 2));
    final events = feed(e, frames(0.05, 5));
    expect(events.whereType<AngleDone>(), isEmpty);
    expect(e.current, CaptureAngle.left);
  });

  test('left and right are mirror-agnostic but must be opposite', () {
    final e = engine();
    feed(e, frames(0));
    // The worker turns one way for "left" (sign depends on mirroring)…
    feed(e, frames(-0.5));
    expect(e.current, CaptureAngle.right);
    // …so the same way again does not count for "right".
    expect(feed(e, frames(-0.5)).whereType<AngleDone>(), isEmpty);
    expect(feed(e, frames(0.5)).whereType<AngleDone>(), hasLength(1));
  });

  test('a different face mid-capture is ignored', () {
    final e = engine();
    feed(e, frames(0));
    final stranger = [
      for (var i = 0; i < 3; i++) analysisOf(unit(5), yaw: 0.5),
    ];
    expect(feed(e, stranger).whereType<AngleProgress>(), isEmpty);
  });

  test('quality problems are shown, then cleared', () {
    final e = engine();
    final events = feed(e, [
      analysisOf(unit(0), issue: QualityIssue.tooDark),
      analysisOf(unit(0)),
    ]);
    final hints = events.whereType<CaptureQuality>().map((q) => q.issue);
    expect(hints, [QualityIssue.tooDark, null]);
  });

  test('the mask sample can be skipped', () {
    final e = engine();
    feed(e, [...frames(0), ...frames(0.5), ...frames(-0.5)]);
    expect(e.current, CaptureAngle.mask);
    e.skipMask();
    expect(e.complete, isTrue);
    final t = e.finish(workerId: 'w1', existing: [], now: DateTime(2026));
    expect(t.templates.map((x) => x.slot), isNot(contains(TemplateSlot.mask)));
  });

  test('a face already enrolled as someone else is a duplicate', () {
    final e = engine(policy: EnrolmentPolicy.frontOnly);
    feed(e, frames(0));
    final existing = [template('ramesh', unit(0))];
    final dup = e.finish(
      workerId: 'w2',
      existing: existing,
      now: DateTime(2026),
    );
    expect((dup.outcome as EnrolDuplicate).workerId, 'ramesh');
    expect(dup.templates, isEmpty);

    final forced = e.finish(
      workerId: 'w2',
      existing: existing,
      now: DateTime(2026),
      overrideDuplicate: true,
    );
    expect(forced.outcome, isA<EnrolOk>());
    expect(forced.templates, hasLength(1));
  });

  test('re-enrolling the same worker is not a duplicate of themself', () {
    final e = engine(policy: EnrolmentPolicy.frontOnly);
    feed(e, frames(0));
    final result = e.finish(
      workerId: 'ramesh',
      existing: [template('ramesh', unit(0))],
      now: DateTime(2026),
    );
    expect(result.outcome, isA<EnrolOk>());
  });

  test('the stills policy accepts any pose for every angle', () {
    final e = engine(policy: EnrolmentPolicy.stills);
    feed(e, [...frames(0), ...frames(0), ...frames(0)]);
    expect(e.current, CaptureAngle.mask);
  });

  test('finishing without a frontal sample is an error', () {
    expect(
      () => engine().finish(workerId: 'w', existing: [], now: DateTime(2026)),
      throwsStateError,
    );
  });
}
