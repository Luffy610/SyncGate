// The app end to end on the *real* face pipeline (sg_vision: BlazeFace +
// SFace on LiteRT): the owner enrols a new worker through the UI, the worker
// walks up to the gate and is marked IN by face, and a stranger is "Not
// recognised". Only the camera is replaced: frames come from fixture photos
// (ml/scripts/make_e2e_fixtures.py) instead of the lens.
@Tags(['vision'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_vision/sg_vision.dart';
import 'package:sg_vision/testing.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/routes.dart';

import 'enrolment_test.dart' show agreeAndCapture, fillDetails, nextStep;
import 'support/test_app.dart';

const _models = '../../packages/sg_vision/assets/models';

String? _fixtures() {
  final dir =
      Platform.environment['SG_VISION_FIXTURES'] ??
      '${Directory.current.path}/../../.cache/ml/e2e';
  return File('$dir/e2e.json').existsSync() ? dir : null;
}

void main() {
  setUpAll(prepareLiteRtForHostTests);
  final dir = _fixtures();

  testWidgets('enrol by face, mark IN at the gate, reject a stranger', (
    tester,
  ) async {
    final spec = jsonDecode(
      File('$dir/e2e.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final gallery = (spec['galleries']! as List).first as Map<String, Object?>;
    final worker = (gallery['workers']! as List).first as Map<String, Object?>;
    final stranger =
        (gallery['impostors']! as List).first as Map<String, Object?>;

    final decoded = <String, RgbImage>{};
    var frameTime = DateTime(2026, 10, 24, 5, 52);
    final source = ScriptedFrameSource();

    // One camera frame; the pipeline wipes it, so each push is a copy.
    Future<void> show(String? file) async {
      final RgbImage rgb;
      if (file == null) {
        rgb = RgbImage.blank(640, 480)..data.fillRange(0, 640 * 480 * 3, 90);
      } else {
        final cached = decoded[file] ??= () {
          final d = img.decodeImage(File('$dir/$file').readAsBytesSync())!;
          return RgbImage(
            d.width,
            d.height,
            d.getBytes(order: img.ChannelOrder.rgb),
          );
        }();
        rgb = RgbImage(
          cached.width,
          cached.height,
          Uint8List.fromList(cached.data),
        );
      }
      frameTime = frameTime.add(const Duration(milliseconds: 200));
      source.push(RgbFrame(rgb, frameTime));
      await tester.pump();
    }

    final app = await pumpApp(
      tester,
      realVision: VisionStack(
        source: source,
        runner: InlineVisionRunner(),
        vault: InMemoryTemplateVault(),
        loadAssets: () async => ModelAssets.fromDirectory(_models),
      ),
      // Photos cannot turn their head for the left/right samples.
      realEnrolment: EnrolmentPolicy.stills,
    );

    // ---- The owner enrols Geeta through the normal screens -----------
    await app.signIn(Role.owner);
    await tester.tap(find.text('Enrol worker'));
    await tester.pumpAndSettle();
    await fillDetails(tester);
    await nextStep(tester);
    await agreeAndCapture(tester);
    expect(app.location, Routes.enrolFace);

    // Front, left and right: 3 good frames each; then no mask sample.
    final enrolFrames = (worker['enrol']! as List).cast<String>();
    for (var i = 0; i < 9; i++) {
      await show(enrolFrames[i % enrolFrames.length]);
    }
    // The longer mask instruction pushes the button below the fold.
    await tester.ensureVisible(find.text('Skip mask sample'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip mask sample'));
    await tester.pumpAndSettle();
    expect(app.location, Routes.workers);
    expect(find.text('Geeta Rani enrolled'), findsOneWidget);
    final geeta = (await app.env.backend.workers.all()).firstWhere(
      (w) => w.name == 'Geeta Rani',
    );
    expect(geeta.faceStatus, FaceStatus.enrolled);

    // ---- Geeta walks up to the gate (a different photo of her) -----------
    await tester.tap(find.text('Back to gate'));
    await tester.pumpAndSettle();
    expect(app.mode, isA<GateMode>());
    for (var i = 0; i < 4; i++) {
      await show(null);
    }
    final gateFrames = (worker['gate']! as List).cast<String>();
    for (
      var i = 0;
      i < 6 && find.text('IN · 05:52 AM').evaluate().isEmpty;
      i++
    ) {
      await show(gateFrames[i % gateFrames.length]);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('IN · 05:52 AM'), findsOneWidget);
    expect(find.text('Geeta Rani'), findsWidgets);
    final mark = await app.env.backend.attendance.lastEvent(geeta.id);
    expect(mark?.direction, Direction.checkIn);

    // ---- A stranger tries: not recognised ------------------------------
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await show(null);
    }
    final strangerFrames = (stranger['gate']! as List).cast<String>();
    for (
      var i = 0;
      i < 14 && find.text('Not recognised').evaluate().isEmpty;
      i++
    ) {
      await show(strangerFrames[i % strangerFrames.length]);
    }
    expect(find.text('Not recognised'), findsOneWidget);
    // Nobody else was marked.
    final todays = await app.env.backend.attendance.eventsBetween(
      DateTime(2026, 10, 24),
      DateTime(2026, 10, 25),
    );
    expect(
      todays.where((e) => e.at.isAfter(DateTime(2026, 10, 24, 5, 51))),
      hasLength(1),
    );

    // Leave the gate so the camera stops cleanly.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  }, skip: dir == null);
}
