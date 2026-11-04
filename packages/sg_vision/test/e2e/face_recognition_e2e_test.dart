// End-to-end face recognition on the shipped models, through the same
// services the app uses: camera-format frames (NV21 from a rotated sensor,
// BGRA) → LiteRtEnrolmentCaptureService → template vault →
// LiteRtGateVisionService → Match / NoMatch events.
//
// Data: LFW identities placed in synthetic 640×480 gate frames
// (ml/scripts/make_e2e_fixtures.py). Each worker is enrolled from one photo
// and walks up with a *different* photo of the same person, so this is a
// harder test than a same-day gate. Impostors are people never enrolled.
@Tags(['vision'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_vision/sg_vision.dart';
import 'package:sg_vision/testing.dart';

import '../support/fixtures.dart';
import '../support/frames.dart';

final class _Tally {
  int genuine = 0;
  int correct = 0;
  int wrongWorker = 0;
  int notRecognised = 0;
  int impostors = 0;
  int impostorAccepted = 0;
  int enrolled = 0;
  int enrolFailed = 0;
  int duplicateFlags = 0;
  final latencyMs = <double>[];

  double rate(int n, int of) => of == 0 ? 0 : n / of;
  double get identificationRate => rate(correct, genuine);
  double get falseAcceptRate => rate(impostorAccepted, impostors);
  double get correctDecisions =>
      rate(correct + impostors - impostorAccepted, genuine + impostors);

  String report() {
    String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
    final sorted = [...latencyMs]..sort();
    final p95 = sorted.isEmpty
        ? 0
        : sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)];
    final enrolLine =
        '  enrolled ............ $enrolled (failed $enrolFailed, '
        'duplicate flags $duplicateFlags)';
    return [
      'Face recognition e2e (LFW in gate frames, galleries of 25)',
      enrolLine,
      '  genuine walk-ups .... $genuine',
      '    recognised ........ $correct (${pct(identificationRate)})',
      '    not recognised .... $notRecognised',
      '    wrong worker ...... $wrongWorker',
      '  impostor walk-ups ... $impostors',
      '    accepted .......... $impostorAccepted (${pct(falseAcceptRate)})',
      '  correct decisions ... ${pct(correctDecisions)}',
      '  pipeline p95 ........ ${p95.toStringAsFixed(0)} ms/frame (host CPU)',
    ].join('\n');
  }
}

void main() {
  setUpAll(prepareLiteRtForHostTests);
  final dir = fixturesDir();

  test(
    'enrol 4 × 25 workers, then genuine and impostor walk-ups',
    () async {
      final spec = readJson('$dir/e2e.json')! as Map<String, Object?>;
      final galleries = (spec['galleries']! as List)
          .cast<Map<String, Object?>>();
      final tally = _Tally();
      var clock = DateTime(2026, 11, 4, 6);
      var useNv21 = true;

      // A camera frame from a fixture file, alternating Android (NV21 from
      // a sensor mounted at 90°) and iOS (BGRA) layouts.
      RawFrame cameraFrame(String file) {
        final rgb = loadRgb('$dir/$file');
        useNv21 = !useNv21;
        if (useNv21) {
          final sensor = rotateCcw(rgb);
          return Nv21Frame(
            at: clock,
            bytes: nv21From(sensor),
            width: sensor.width,
            height: sensor.height,
            rowStride: sensor.width,
            rotation: FrameRotation.r90,
          );
        }
        return Bgra8888Frame(
          at: clock,
          bytes: bgraFrom(rgb, rowStride: rgb.width * 4 + 64),
          width: rgb.width,
          height: rgb.height,
          rowStride: rgb.width * 4 + 64,
          rotation: FrameRotation.r0,
        );
      }

      final empty = RgbImage.blank(640, 480)
        ..data.fillRange(0, 640 * 480 * 3, 90);

      for (final (g, gallery) in galleries.indexed) {
        final source = ScriptedFrameSource();
        final vault = InMemoryTemplateVault();
        final stack = VisionStack(
          source: source,
          runner: InlineVisionRunner(),
          vault: vault,
          loadAssets: () async => ModelAssets.fromDirectory(modelsDir),
          clock: () => clock,
        );
        // Still photos cannot turn their head, so only the frontal sample
        // is captured, with no pose limit (LFW faces are not all frontal).
        final enrol = LiteRtEnrolmentCaptureService(
          stack: stack,
          policy: const EnrolmentPolicy(
            angles: [CaptureAngle.front],
            requirePose: false,
          ),
        );
        final workers = (gallery['workers']! as List)
            .cast<Map<String, Object?>>();
        final ids = {for (final w in workers) w['id']! as String};
        final gate = LiteRtGateVisionService(
          stack: stack,
          activeWorkers: () async => ids,
        );

        // ---- Enrolment --------------------------------------------------
        for (final w in workers) {
          final id = w['id']! as String;
          var done = false;
          final sub = enrol.events.listen((e) {
            if (e is AngleDone) done = true;
          });
          await enrol.start(id);
          final files = (w['enrol']! as List).cast<String>();
          for (var i = 0; i < files.length * 3 && !done; i++) {
            source.push(cameraFrame(files[i % files.length]));
            await pumpEventQueue();
            clock = clock.add(const Duration(milliseconds: 150));
          }
          await sub.cancel();
          if (!done) {
            tally.enrolFailed++;
            await enrol.cancel();
            continue;
          }
          final outcome = await enrol.finish();
          if (outcome is EnrolDuplicate) {
            tally.duplicateFlags++;
            await enrol.start(id);
            for (final f in files) {
              source.push(cameraFrame(f));
              await pumpEventQueue();
            }
            await enrol.finish(overrideDuplicate: true);
          }
          tally.enrolled++;
        }

        // ---- Gate ---------------------------------------------------------
        final events = <VisionEvent>[];
        final sub = gate.events.listen(events.add);
        await gate.start(const GateVisionConfig());

        Future<VisionEvent?> walkUp(List<String> files) async {
          // The previous person leaves: an empty frame for a second.
          for (var i = 0; i < 4; i++) {
            source.push(
              RgbFrame(RgbImage(640, 480, empty.data.sublist(0)), clock),
            );
            await pumpEventQueue();
            clock = clock.add(const Duration(milliseconds: 300));
          }
          events.clear();
          // Then walks up; the camera sees them for up to 2.6 s.
          for (var i = 0; i < 13; i++) {
            final sw = Stopwatch()..start();
            source.push(cameraFrame(files[i % files.length]));
            await pumpEventQueue();
            tally.latencyMs.add(sw.elapsedMicroseconds / 1000);
            clock = clock.add(const Duration(milliseconds: 200));
            final decision = events.where((e) => e is Match || e is NoMatch);
            if (decision.isNotEmpty) return decision.first;
          }
          return null;
        }

        for (final w in workers) {
          tally.genuine++;
          final d = await walkUp((w['gate']! as List).cast<String>());
          switch (d) {
            case Match(:final workerId) when workerId == w['id']:
              tally.correct++;
            case Match():
              tally.wrongWorker++;
            default:
              tally.notRecognised++;
          }
        }
        for (final imp
            in (gallery['impostors']! as List).cast<Map<String, Object?>>()) {
          tally.impostors++;
          final d = await walkUp((imp['gate']! as List).cast<String>());
          if (d is Match) tally.impostorAccepted++;
        }
        await sub.cancel();
        await gate.stop();
        await stack.close();
        // Progress, so a slow CI run shows where it is.
        // ignore: avoid_print
        print('gallery $g done: ${tally.correct}/${tally.genuine} recognised');
      }

      // The report is the point of this test.
      // ignore: avoid_print
      print(tally.report());
      expect(tally.enrolFailed, 0, reason: tally.report());
      expect(tally.wrongWorker, 0, reason: tally.report());
      expect(
        tally.falseAcceptRate,
        lessThanOrEqualTo(0.01),
        reason: tally.report(),
      );
      expect(
        tally.correctDecisions,
        greaterThanOrEqualTo(0.95),
        reason: tally.report(),
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
    skip: dir == null ? missingFixtures : null,
  );
}
