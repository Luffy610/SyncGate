import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_vision/sg_vision.dart';
import 'package:syncgate/src/app/providers.dart';

/// The real face pipeline (BlazeFace + SFace on LiteRT, `sg_vision`) behind
/// the three vision interfaces the UI uses. Any flavour can use it; the
/// screens do not change (frontend plan §3.2).
///
/// Only active workers with an enrolled face can match at the gate.
List<Override> realVisionOverrides(
  VisionStack stack, {
  EnrolmentPolicy enrolment = const EnrolmentPolicy(),
}) => [
  gateVisionProvider.overrideWith(
    (ref) => LiteRtGateVisionService(
      stack: stack,
      activeWorkers: () async => {
        for (final w in await ref.read(workerRepositoryProvider).all())
          if (w.active && w.faceStatus == FaceStatus.enrolled) w.id,
      },
    ),
  ),
  enrolmentCaptureProvider.overrideWith(
    (ref) => LiteRtEnrolmentCaptureService(stack: stack, policy: enrolment),
  ),
  cameraCheckProvider.overrideWith(
    (ref) => LiteRtCameraCheckService(stack: stack),
  ),
];

/// The production stack: front camera, models on a background isolate,
/// models loaded from the app bundle. [vault] is in-memory until the
/// encrypted native vault lands (ADR-0010, epic E10). [cameraRotation]
/// (degrees clockwise) overrides the sensor orientation the phone reports,
/// for devices whose frames come out sideways.
VisionStack deviceVisionStack({TemplateVault? vault, int? cameraRotation}) =>
    VisionStack(
      source: CameraFrameSource(rotationOverride: cameraRotation),
      runner: IsolateVisionRunner(),
      vault: vault ?? InMemoryTemplateVault(),
      loadAssets: ModelAssets.fromBundle,
    );
