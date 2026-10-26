import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_vision/sg_vision.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/features/enrolment/enrolment_draft.dart';

enum CapturePhase { capturing, processing, duplicate, done, failed }

@immutable
class CaptureState {
  const new({
    this.phase = CapturePhase.capturing,
    this.angle = CaptureAngle.front,
    this.done = const {},
    this.fraction = 0,
    this.quality,
    this.maskSkipped = false,
    this.duplicateOf,
  });

  final CapturePhase phase;
  final CaptureAngle angle;
  final Set<CaptureAngle> done;

  /// Progress through the current angle, 0..1.
  final double fraction;
  final QualityIssue? quality;
  final bool maskSkipped;

  /// The worker this face looks like (phase [CapturePhase.duplicate]).
  final Worker? duplicateOf;

  int get totalAngles => maskSkipped ? 3 : 4;

  /// Overall ring progress, 0..1.
  double get progress {
    final counted = done.where((a) => !(maskSkipped && a == CaptureAngle.mask));
    return ((counted.length + fraction) / totalAngles).clamp(0, 1);
  }

  CaptureState copyWith({
    CapturePhase? phase,
    CaptureAngle? angle,
    Set<CaptureAngle>? done,
    double? fraction,
    QualityIssue? quality,
    bool clearQuality = false,
    bool? maskSkipped,
    Worker? duplicateOf,
  }) => CaptureState(
    phase: phase ?? this.phase,
    angle: angle ?? this.angle,
    done: done ?? this.done,
    fraction: fraction ?? this.fraction,
    quality: clearQuality ? null : quality ?? this.quality,
    maskSkipped: maskSkipped ?? this.maskSkipped,
    duplicateOf: duplicateOf ?? this.duplicateOf,
  );
}

/// Runs the enrolment capture (design 14): turns capture events into ring
/// progress, finishes with the duplicate check and stores the result.
class CaptureController extends Notifier<CaptureState> {
  late final EnrolmentCaptureService _service;
  StreamSubscription<CaptureEvent>? _events;
  var _finishing = false;
  var _disposed = false;
  var _completed = false;
  late final String _workerId;

  /// The texture to show; `null` until the camera started.
  int? textureId;

  @override
  CaptureState build() {
    _service = ref.read(enrolmentCaptureProvider);
    _workerId = ref.read(enrolmentProvider).workerId ?? '';
    ref.onDispose(() {
      _disposed = true;
      unawaited(_events?.cancel());
      if (!_completed) unawaited(_service.cancel());
    });
    unawaited(_start());
    return const CaptureState();
  }

  Future<void> _start() async {
    _events = _service.events.listen(_onEvent);
    final texture = await _service.start(_workerId);
    if (_disposed) return;
    textureId = texture;
    // Rebuild listeners once the preview is known.
    state = state.copyWith();
  }

  static const List<CaptureAngle> _order = [
    CaptureAngle.front,
    CaptureAngle.left,
    CaptureAngle.right,
    CaptureAngle.mask,
  ];

  void _onEvent(CaptureEvent event) {
    if (_disposed || state.phase != CapturePhase.capturing) return;
    switch (event) {
      case AngleProgress(:final angle, :final fraction):
        state = state.copyWith(angle: angle, fraction: fraction);
      case AngleDone(:final angle):
        final done = {...state.done, angle};
        final index = _order.indexOf(angle);
        final last = angle == CaptureAngle.mask;
        final skipRest = angle == CaptureAngle.right && state.maskSkipped;
        state = state.copyWith(
          done: done,
          angle: last ? angle : _order[index + 1],
          fraction: 0,
        );
        if (last || skipRest) unawaited(_finish());
      case CaptureQuality(:final issue):
        state = issue == null
            ? state.copyWith(clearQuality: true)
            : state.copyWith(quality: issue);
    }
  }

  /// "Skip mask sample".
  Future<void> skipMask() async {
    if (state.done.contains(CaptureAngle.mask)) return;
    state = state.copyWith(maskSkipped: true);
    await _service.skipMask();
    if (state.done.containsAll(const [
      CaptureAngle.front,
      CaptureAngle.left,
      CaptureAngle.right,
    ])) {
      await _finish();
    }
  }

  Future<void> _finish({bool override = false, String? reason}) async {
    if (_finishing && !override) return;
    _finishing = true;
    state = state.copyWith(phase: CapturePhase.processing);
    final outcome = await _service.finish(overrideDuplicate: override);
    if (_disposed) return;
    switch (outcome) {
      case EnrolOk():
        await _complete(overrideReason: reason);
      case EnrolDuplicate(:final workerId):
        final worker = await ref.read(workerRepositoryProvider).byId(workerId);
        if (_disposed) return;
        state = state.copyWith(
          phase: CapturePhase.duplicate,
          duplicateOf: worker,
        );
    }
  }

  Future<void> _complete({String? overrideReason}) async {
    final repo = ref.read(workerRepositoryProvider);
    final worker = await repo.byId(_workerId);
    await repo.setFaceStatus(_workerId, FaceStatus.enrolled);
    final session = ref.read(adminSessionProvider);
    await ref
        .read(auditLogProvider)
        .append(
          AuditEntry(
            at: ref.read(clockProvider).now(),
            actor: session?.user.name ?? 'admin',
            action: overrideReason == null
                ? 'worker.enrolled'
                : 'worker.enrolled.duplicateOverride',
            detail: '${worker?.code ?? _workerId} ${overrideReason ?? ''}'
                .trim(),
          ),
        );
    _completed = true;
    if (_disposed) return;
    state = state.copyWith(phase: CapturePhase.done);
  }

  /// "Override with reason" after a duplicate warning.
  Future<void> overrideDuplicate(String reason) =>
      _finish(override: true, reason: reason);

  /// "Cancel" after a duplicate warning, or the close button.
  Future<void> cancel() async {
    await _service.cancel();
    if (!_disposed) state = state.copyWith(phase: CapturePhase.failed);
  }
}

final NotifierProvider<CaptureController, CaptureState>
captureControllerProvider =
    NotifierProvider.autoDispose<CaptureController, CaptureState>(
      CaptureController.new,
    );
