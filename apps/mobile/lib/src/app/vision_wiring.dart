import 'package:flutter/foundation.dart';
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
/// (degrees clockwise) overrides the frame rotation, though the pipeline
/// normally works the orientation out by itself. [diagnostics] shows live
/// pipeline numbers over the camera preview and logs them: for testing on
/// a phone only, never in a customer build.
VisionStack deviceVisionStack({
  TemplateVault? vault,
  int? cameraRotation,
  bool diagnostics = false,
}) => VisionStack(
  source: CameraFrameSource(rotationOverride: cameraRotation),
  runner: IsolateVisionRunner(),
  vault: vault ?? InMemoryTemplateVault(),
  loadAssets: ModelAssets.fromBundle,
  diagnostics: diagnostics,
  onError: diagnostics
      ? (error, _) => debugPrint('[sg_vision] frame failed: $error')
      : null,
);
