import 'dart:async';

import 'package:sg_vision/sg_vision.dart';

/// Texture ID the fakes return. The UI shows the grey silhouette from the
/// designs instead of a camera texture for any negative ID.
const fakeTextureId = -1;

/// Scripted fake of the gate camera pipeline. Events come from the debug
/// panel, from tests, or from [startDemoLoop].
class FakeGateVisionService implements GateVisionService {
  final _controller = StreamController<VisionEvent>.broadcast();
  bool running = false;

  /// Simulates a camera that cannot start (permission denied, in use).
  bool failOnStart = false;
  GateVisionConfig? lastConfig;
  Timer? _demo;

  @override
  Future<int> start(GateVisionConfig config) async {
    if (failOnStart) throw StateError('camera unavailable');
    running = true;
    lastConfig = config;
    return fakeTextureId;
  }

  @override
  Future<void> stop() async {
    running = false;
    stopDemoLoop();
  }

  @override
  Stream<VisionEvent> get events => _controller.stream;

  void emit(VisionEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  /// A recognised worker walks up.
  void match(String workerId) {
    emit(const FaceSeen(faceSizeRatio: 0.45));
    emit(Match(workerId: workerId, score: 0.91, margin: 0.22, liveness: 0.97));
  }

  /// A face that is not accepted.
  void noMatch([NoMatchReason reason = NoMatchReason.unknown]) {
    emit(const FaceSeen(faceSizeRatio: 0.4));
    emit(NoMatch(reason));
  }

  /// Plays [workers] one at a time, every [every], then repeats.
  void startDemoLoop(
    List<String> workers, {
    Duration every = const Duration(seconds: 6),
  }) {
    stopDemoLoop();
    var i = 0;
    _demo = Timer.periodic(every, (_) {
      if (workers.isEmpty) return;
      if (i % 4 == 3) {
        emit(const QualityHint(QualityIssue.covered));
        noMatch();
      } else {
        match(workers[i % workers.length]);
      }
      i++;
    });
  }

  void stopDemoLoop() {
    _demo?.cancel();
    _demo = null;
  }

  Future<void> dispose() async {
    stopDemoLoop();
    await _controller.close();
  }
}

/// Fake enrolment capture: moves through front, left, right and (optional)
/// mask on a timer.
class FakeEnrolmentCaptureService implements EnrolmentCaptureService {
  new({
    this.stepEvery = const Duration(milliseconds: 300),
    this.stepsPerAngle = 4,
  });

  Duration stepEvery;
  final int stepsPerAngle;

  /// When set, `finish()` reports a duplicate of this worker unless the
  /// caller overrides.
  String? duplicateOf;
  final cancelled = <String>[];
  final finished = <String>[];

  final _controller = StreamController<CaptureEvent>.broadcast();
  Timer? _timer;
  String? _workerId;
  var _angleIndex = 0;
  var _step = 0;

  static const List<CaptureAngle> _angles = [
    CaptureAngle.front,
    CaptureAngle.left,
    CaptureAngle.right,
    CaptureAngle.mask,
  ];

  @override
  Future<int> start(String workerId) async {
    _workerId = workerId;
    _angleIndex = 0;
    _step = 0;
    _timer?.cancel();
    _timer = Timer.periodic(stepEvery, (_) => _tick());
    return fakeTextureId;
  }

  void _tick() {
    if (_angleIndex >= _angles.length) {
      _timer?.cancel();
      return;
    }
    final angle = _angles[_angleIndex];
    _step++;
    _controller.add(
      AngleProgress(angle: angle, fraction: _step / stepsPerAngle),
    );
    if (_step >= stepsPerAngle) {
      _controller.add(AngleDone(angle));
      _angleIndex++;
      _step = 0;
    }
  }

  @override
  Stream<CaptureEvent> get events => _controller.stream;

  /// Shows (or clears, with `null`) a quality hint over the preview.
  void emitQuality(QualityIssue? issue) =>
      _controller.add(CaptureQuality(issue));

  @override
  Future<void> skipMask() async {
    if (_angleIndex == 3) {
      _angleIndex = _angles.length;
      _timer?.cancel();
    }
  }

  @override
  Future<EnrolOutcome> finish({bool overrideDuplicate = false}) async {
    _timer?.cancel();
    final duplicate = duplicateOf;
    if (duplicate != null && !overrideDuplicate) {
      return EnrolDuplicate(duplicate);
    }
    if (_workerId != null) finished.add(_workerId!);
    return const EnrolOk();
  }

  @override
  Future<void> cancel() async {
    _timer?.cancel();
    if (_workerId != null) cancelled.add(_workerId!);
  }
}

/// Fake camera check: the first reading is dim, later ones are fine.
class FakeCameraCheckService implements CameraCheckService {
  var _checks = 0;
  bool running = false;

  @override
  Future<int> start() async {
    running = true;
    return fakeTextureId;
  }

  @override
  Future<void> stop() async => running = false;

  @override
  Future<CameraReading> check() async {
    _checks++;
    if (_checks == 1) {
      return const CameraReading(
        lux: 42,
        backlight: false,
        lensClean: true,
        faceDistanceCm: 60,
      );
    }
    return const CameraReading(
      lux: 240,
      backlight: false,
      lensClean: true,
      faceDistanceCm: 60,
    );
  }
}
