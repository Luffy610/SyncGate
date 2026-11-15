import 'package:sg_vision/src/pipeline/face_detector.dart';
import 'package:sg_vision/src/pipeline/rgb_image.dart';

/// Works out which way up camera frames really are, instead of trusting
/// the orientation a phone or camera plugin reports.
///
/// The recogniser needs upright faces. On frames turned 90° it rejects most
/// enrolled people (83% in `ml/` measurements, against 8% upright) and its
/// head-turn estimate is meaningless; a wrong reported orientation is
/// exactly what broke the first iPhone test.
///
/// While **calibrating**, the caller runs the detector on each frame in all
/// four orientations and passes the faces to [vote]. An orientation scores
/// the detector's confidence when the face it finds there looks upright
/// (the detector also "finds" faces in turned frames, but less confidently
/// or visibly tilted). After [framesNeeded] frames with a face, the
/// orientation with the highest total wins: in `ml/` measurements five
/// frames chose correctly every time (one frame: 98%).
///
/// Once **settled** there is no extra work. If faces then keep showing up
/// tilted ([recheckAfter] in a row), calibration starts again.
final class UprightGuard {
  new({this.framesNeeded = 5, this.maxRoll = 45, this.recheckAfter = 30});

  final int framesNeeded;

  /// A face tilted further than this (degrees) does not look upright.
  final double maxRoll;
  final int recheckAfter;

  /// Clockwise turn applied to every frame after its own rotation: the
  /// settled orientation, or the current leader while calibrating.
  FrameRotation correction = FrameRotation.r0;

  final _scores = <FrameRotation, double>{};
  var _frames = 0;
  var _settled = false;
  var _tilted = 0;

  /// Calibration is done; frames are upright with [correction].
  bool get settled => _settled;

  bool _looksUpright(DetectedFace face) => face.roll.abs() < maxRoll;

  /// Calibrating: [faces] holds the detector's best face for each extra
  /// rotation of one frame (`null` where it found none).
  void vote(Map<FrameRotation, DetectedFace?> faces) {
    if (_settled) return;
    var counted = false;
    for (final MapEntry(key: rotation, value: face) in faces.entries) {
      if (face == null || !_looksUpright(face)) continue;
      _scores[rotation] = (_scores[rotation] ?? 0) + face.score;
      counted = true;
    }
    if (!counted) return;
    _frames++;
    correction = _scores.entries
        .reduce((a, b) => b.value > a.value ? b : a)
        .key;
    if (_frames >= framesNeeded) _settled = true;
  }

  /// Settled: call with the face found in each corrected frame (or `null`).
  /// A long run of tilted faces means the orientation changed.
  void observe(DetectedFace? face) {
    if (!_settled || face == null) return;
    if (_looksUpright(face)) {
      _tilted = 0;
      return;
    }
    if (++_tilted < recheckAfter) return;
    _settled = false;
    _tilted = 0;
    _frames = 0;
    _scores.clear();
  }
}
