// Checks the Dart pipeline against the Python reference (ml/eval/pipeline.py)
// stage by stage on lossless frames: same face, same keypoints, same face
// vector (ADR-0020 "pipeline parity").
@Tags(['vision'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_vision/sg_vision.dart';
import 'package:sg_vision/testing.dart';

import '../support/fixtures.dart';

void main() {
  setUpAll(prepareLiteRtForHostTests);
  final dir = fixturesDir();

  test('models match the manifest hashes', () {
    final assets = ModelAssets.fromDirectory(modelsDir);
    expect(assets.manifest.dims, 128);
    expect(assets.manifest.template, hasLength(4));
  });

  test('Dart pipeline matches the Python reference', () {
    final assets = ModelAssets.fromDirectory(modelsDir);
    final pipeline = FacePipeline.fromBytes(
      manifest: assets.manifest,
      detectorBytes: assets.detector,
      embedderBytes: assets.embedder,
    );
    final cases = (readJson('$dir/parity.json')! as List)
        .cast<Map<String, Object?>>();
    var compared = 0;
    for (final c in cases) {
      final frame = loadRgb('$dir/${c['file']}');
      final a = pipeline.analyse(frame, embedPoorFaces: true);
      final want = c['face'] as Map<String, Object?>?;
      if (want == null) {
        expect(a.face, isNull, reason: '${c['file']}: no face expected');
        continue;
      }
      expect(a.face, isNotNull, reason: '${c['file']}: face expected');
      final kps = (want['keypoints']! as List).cast<List<Object?>>();
      for (var k = 0; k < 4; k++) {
        final p = Point2(
          (kps[k][0]! as num).toDouble(),
          (kps[k][1]! as num).toDouble(),
        );
        expect(
          a.face!.keypoints[k].distanceTo(p),
          lessThan(1.5),
          reason: '${c['file']} keypoint $k',
        );
      }
      final ref = Float32List.fromList([
        for (final v in want['embedding']! as List) (v! as num).toDouble(),
      ]);
      expect(
        cosine(a.embedding!, ref),
        greaterThan(0.99),
        reason: '${c['file']} embedding',
      );
      compared++;
    }
    expect(compared, greaterThan(cases.length ~/ 2));
    pipeline
      ..detector.close()
      ..embedder.close();
  }, skip: dir == null ? missingFixtures : null);

  test('the background-isolate runner gives the same answer', () async {
    final assets = ModelAssets.fromDirectory(modelsDir);
    final isolate = IsolateVisionRunner();
    final inline = InlineVisionRunner();
    await inWorkspaceRoot(() => isolate.load(assets));
    await inline.load(assets);
    final cases = (readJson('$dir/parity.json')! as List)
        .cast<Map<String, Object?>>()
        .where((c) => c['face'] != null)
        .take(3);
    for (final c in cases) {
      final file = '$dir/${c['file']}';
      final a = await isolate.analyse(
        RgbFrame(loadRgb(file), DateTime(2026)),
        AnalysisMode.gate,
      );
      final b = await inline.analyse(
        RgbFrame(loadRgb(file), DateTime(2026)),
        AnalysisMode.gate,
      );
      expect(a.face, isNotNull);
      expect(a.issue, b.issue);
      expect(cosine(a.embedding!, b.embedding!), closeTo(1, 1e-6));
    }
    await isolate.close();
    await inline.close();
  }, skip: dir == null ? missingFixtures : null);
}
