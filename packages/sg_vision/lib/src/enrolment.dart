import 'package:sg_vision/src/vision_event.dart';

/// Where the worker is asked to turn during enrolment (design 14).
enum CaptureAngle { front, left, right, mask }

/// Events during enrolment capture. No image or embedding crosses into Dart.
sealed class CaptureEvent {
  const new();
}

/// Progress through the current angle, 0..1.
final class AngleProgress extends CaptureEvent {
  const new({required this.angle, required this.fraction});

  final CaptureAngle angle;
  final double fraction;
}

final class AngleDone extends CaptureEvent {
  const new(this.angle);

  final CaptureAngle angle;
}

final class CaptureQuality extends CaptureEvent {
  const new(this.issue);

  /// `null` clears the hint.
  final QualityIssue? issue;
}

/// Result of the duplicate check after all angles are captured.
sealed class EnrolOutcome {
  const new();
}

final class EnrolOk extends EnrolOutcome {
  const new();
}

/// The face looks like an already enrolled worker.
final class EnrolDuplicate extends EnrolOutcome {
  const new(this.workerId);

  final String workerId;
}

abstract interface class EnrolmentCaptureService {
  /// Starts the camera for [workerId]. Returns the preview texture ID.
  Future<int> start(String workerId);
  Stream<CaptureEvent> get events;

  /// The mask sample is optional.
  Future<void> skipMask();

  /// Runs the duplicate check and stores the face code on the phone.
  Future<EnrolOutcome> finish({bool overrideDuplicate = false});
  Future<void> cancel();
}

/// Light and framing readings from the camera check (design 07).
final class CameraReading {
  const new({
    required this.lux,
    required this.backlight,
    required this.lensClean,
    required this.faceDistanceCm,
  });

  final double lux;
  final bool backlight;
  final bool lensClean;
  final int faceDistanceCm;

  bool get lightOk => lux >= 100;
  bool get faceSizeOk => faceDistanceCm >= 40 && faceDistanceCm <= 90;
}

abstract interface class CameraCheckService {
  /// Starts a live preview and returns its texture ID.
  Future<int> start();
  Future<void> stop();

  /// Takes a fresh reading.
  Future<CameraReading> check();
}
