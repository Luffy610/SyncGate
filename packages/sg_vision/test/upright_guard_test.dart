import 'package:flutter_test/flutter_test.dart';
import 'package:sg_vision/sg_vision.dart';

import 'support/fakes.dart';

/// An upright frontal face as it appears in a frame that was turned
/// clockwise by [turned].
DetectedFace faceInFrameTurned(FrameRotation turned, {double score = 0.9}) {
  final up = faceWithYaw(0);
  Point2 turn(Point2 p) => switch (turned) {
    FrameRotation.r0 => p,
    FrameRotation.r90 => Point2(-p.y, p.x),
    FrameRotation.r180 => Point2(-p.x, -p.y),
    FrameRotation.r270 => Point2(p.y, -p.x),
  };
  return DetectedFace(
    score: score,
    left: 0,
    top: 0,
    right: 1,
    bottom: 1,
    keypoints: up.keypoints.map(turn).toList(),
  );
}

/// What the detector reports for a frame that needs [needed] to be upright:
/// a confident upright face at [needed], a tilted one a quarter-turn away,
/// and a weaker "upright" ghost at the opposite orientation (as measured).
Map<FrameRotation, DetectedFace?> detections(FrameRotation needed) => {
  needed: faceInFrameTurned(FrameRotation.r0),
  needed + FrameRotation.r90: faceInFrameTurned(FrameRotation.r90, score: 0.75),
  needed + FrameRotation.r180: faceInFrameTurned(FrameRotation.r0, score: 0.65),
  needed + FrameRotation.r270: null,
};

void main() {
  test('roll is 0 for an upright face and ±90/180 for turned frames', () {
    expect(faceInFrameTurned(FrameRotation.r0).roll, closeTo(0, 1));
    expect(faceInFrameTurned(FrameRotation.r90).roll, closeTo(-90, 1));
    expect(faceInFrameTurned(FrameRotation.r270).roll, closeTo(90, 1));
    expect(faceInFrameTurned(FrameRotation.r180).roll.abs(), closeTo(180, 1));
  });

  for (final needed in FrameRotation.values) {
    test('settles on ${needed.degrees}° after five frames with a face', () {
      final guard = UprightGuard();
      for (var i = 0; i < 4; i++) {
        guard.vote(detections(needed));
        expect(guard.settled, isFalse);
      }
      guard.vote(detections(needed));
      expect(guard.settled, isTrue);
      expect(guard.correction, needed);
    });
  }

  test('frames without an upright-looking face do not count', () {
    final guard = UprightGuard();
    for (var i = 0; i < 20; i++) {
      guard.vote({
        FrameRotation.r0: null,
        FrameRotation.r90: faceInFrameTurned(FrameRotation.r90),
      });
    }
    expect(guard.settled, isFalse);
    expect(guard.correction, FrameRotation.r0);
  });

  test('a couple of misleading frames are outvoted', () {
    final guard = UprightGuard()
      ..vote(detections(FrameRotation.r180))
      ..vote(detections(FrameRotation.r0))
      ..vote(detections(FrameRotation.r0))
      ..vote(detections(FrameRotation.r0))
      ..vote(detections(FrameRotation.r0));
    expect(guard.settled, isTrue);
    expect(guard.correction, FrameRotation.r0);
  });

  test('once settled, a long run of tilted faces recalibrates', () {
    final guard = UprightGuard();
    for (var i = 0; i < 5; i++) {
      guard.vote(detections(FrameRotation.r0));
    }
    // A worker tilting their head for a moment changes nothing.
    for (var i = 0; i < 10; i++) {
      guard.observe(faceInFrameTurned(FrameRotation.r90));
    }
    guard.observe(faceInFrameTurned(FrameRotation.r0));
    expect(guard.settled, isTrue);
    // The phone was turned: every face is sideways from now on.
    for (var i = 0; i < 30; i++) {
      guard.observe(faceInFrameTurned(FrameRotation.r90));
    }
    expect(guard.settled, isFalse);
    for (var i = 0; i < 5; i++) {
      guard.vote(detections(FrameRotation.r270));
    }
    expect(guard.correction, FrameRotation.r270);
  });

  test('rotateRgb turns the pixels and four quarter-turns restore them', () {
    final img = RgbImage.blank(3, 2);
    for (var i = 0; i < img.data.length; i++) {
      img.data[i] = i;
    }
    final once = rotateRgb(img, FrameRotation.r90);
    expect((once.width, once.height), (2, 3));
    // Top-left goes to top-right.
    expect(once.data.sublist(3, 6), img.data.sublist(0, 3));
    var back = img;
    for (var i = 0; i < 4; i++) {
      back = rotateRgb(back, FrameRotation.r90);
    }
    expect(back.data, img.data);
    expect(
      rotateRgb(rotateRgb(img, FrameRotation.r90), FrameRotation.r270).data,
      img.data,
    );
  });

  test('a face tilted past 45° is not used', () {
    const tilted = FaceQuality(
      interOcularFraction: 0.1,
      yaw: 0,
      faceLuma: 120,
      frameLuma: 120,
      sharpness: 150,
      roll: -88,
    );
    expect(const QualityPolicy().issue(tilted), QualityIssue.turnLess);
    expect(const QualityPolicy().issue(goodQuality), isNull);
  });
}
