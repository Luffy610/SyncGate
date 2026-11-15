import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_vision/sg_vision.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart' show modelsDir;

/// Returns a scripted analysis for every frame and records the mode used.
final class _ScriptedRunner implements VisionRunner {
  Float32List? next = unit(0, dims: 128);
  final modes = <AnalysisMode>[];

  @override
  Future<void> load(ModelAssets assets) async {}

  @override
  Future<FrameAnalysis> analyse(RawFrame frame, AnalysisMode mode) async {
    modes.add(mode);
    frame.wipe();
    // A fresh vector per frame, like the real pipeline (consumers wipe it).
    final v = next;
    return analysisOf(v == null ? null : Float32List.fromList(v));
  }

  @override
  Future<void> close() async {}
}

void main() {
  late ScriptedFrameSource source;
  late _ScriptedRunner runner;
  late InMemoryTemplateVault vault;
  late VisionStack stack;
  var t = DateTime(2026, 11, 4, 6);

  Future<void> frame() async {
    t = t.add(const Duration(milliseconds: 200));
    source.push(RgbFrame(RgbImage.blank(4, 4), t));
    await pumpEventQueue();
  }

  setUp(() {
    source = ScriptedFrameSource();
    runner = _ScriptedRunner();
    vault = InMemoryTemplateVault();
    stack = VisionStack(
      source: source,
      runner: runner,
      vault: vault,
      loadAssets: () async => ModelAssets.fromDirectory(modelsDir),
      clock: () => t,
    );
  });

  test('the camera goes to whoever started last, then back', () async {
    final gate = LiteRtGateVisionService(
      stack: stack,
      activeWorkers: () async => {'w1'},
    );
    final enrol = LiteRtEnrolmentCaptureService(
      stack: stack,
      policy: EnrolmentPolicy.frontOnly,
    );
    await gate.start(const GateVisionConfig());
    await frame();
    expect(runner.modes.last, AnalysisMode.gate);

    // Enrolment opens while the gate is still running (its stop is late).
    await enrol.start('w1');
    await frame();
    expect(runner.modes.last, AnalysisMode.enrolment);

    await enrol.cancel();
    await frame();
    expect(runner.modes.last, AnalysisMode.gate);
    expect(source.running, isTrue);

    await gate.stop();
    expect(source.running, isFalse);
  });

  test(
    'a worker enrolled while the gate was stopped matches on restart',
    () async {
      final gate = LiteRtGateVisionService(
        stack: stack,
        activeWorkers: () async => {'w1'},
      );
      final enrol = LiteRtEnrolmentCaptureService(
        stack: stack,
        policy: EnrolmentPolicy.frontOnly,
      );
      final events = <VisionEvent>[];
      gate.events.listen(events.add);

      await gate.start(const GateVisionConfig());
      // The gate goes away (admin mode) without waiting for the stop.
      final stopping = gate.stop();

      await enrol.start('w1');
      for (var i = 0; i < 3; i++) {
        await frame();
      }
      expect(await enrol.finish(), isA<EnrolOk>());
      await stopping;
      expect(await vault.all(), hasLength(1));

      await gate.start(const GateVisionConfig());
      for (var i = 0; i < 3; i++) {
        await frame();
      }
      expect(events.whereType<Match>().single.workerId, 'w1');
    },
  );

  test('diagnostics describe each frame without pixels', () async {
    final lines = <String>[];
    final diagnostics = VisionDiagnostics(log: lines.add);
    final stackWithDiagnostics = VisionStack(
      source: source,
      runner: runner,
      vault: vault,
      loadAssets: () async => ModelAssets.fromDirectory(modelsDir),
      clock: () => t,
      diagnostics: true,
    );
    expect(stackWithDiagnostics.diagnostics, isNotNull);
    expect(stack.diagnostics, isNull);

    diagnostics
      ..record(
        mode: 'gate',
        analysis: analysisOf(unit(0)),
        at: t,
        candidate: const MatchCandidate(
          workerId: 'w1',
          score: 0.71,
          runnerUpId: 'w2',
          runnerUpScore: 0.2,
        ),
        threshold: 0.48,
        margin: 0.08,
        note: 'gallery 2 · last: MATCH w1',
      )
      ..record(
        mode: 'gate',
        analysis: analysisOf(null, face: false),
        at: t.add(const Duration(milliseconds: 200)),
      );
    expect(lines.single, startsWith('[sg_vision] gate 640x480 fix 0°'));
    expect(lines.single, contains('best w1 0.71 (need 0.48) lead 0.51'));
    expect(lines.single, contains('yaw +0.00'));
    expect(VisionDiagnostics.overlay.value, contains('no face'));
    diagnostics.clear();
    expect(VisionDiagnostics.overlay.value, isNull);
  });

  test('camera check reads light, backlight, lens and distance', () {
    final reading = LiteRtCameraCheckService.readingFrom([
      analysisOf(unit(0)),
      analysisOf(unit(0)),
    ]);
    expect(reading.lightOk, isTrue);
    expect(reading.backlight, isFalse);
    expect(reading.lensClean, isTrue);
    // Eye distance 10% of the long side → about 49 cm away.
    expect(reading.faceDistanceCm, closeTo(49, 2));
    expect(reading.faceSizeOk, isTrue);

    final empty = LiteRtCameraCheckService.readingFrom([
      analysisOf(null, face: false),
    ]);
    expect(empty.faceDistanceCm, 0);
    expect(empty.lux, greaterThan(100));
  });
}
