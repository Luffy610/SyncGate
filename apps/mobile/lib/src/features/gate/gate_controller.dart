import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_platform/sg_platform.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:sg_vision/sg_vision.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/application/attendance_use_cases.dart';

enum GatePhase { scanning, matched, notRecognised, cooldown, paused }

/// What the gate screen shows (frontend plan §6.1). One route, one state
/// machine, so the camera texture is never rebuilt between marks.
@immutable
class GateViewState {
  const new({
    this.phase = GatePhase.scanning,
    this.textureId,
    this.worker,
    this.direction,
    this.at,
    this.onTime = true,
    this.hint,
    this.retrySeconds = 0,
    this.pausedBecauseCameraFailed = false,
  });

  final GatePhase phase;

  /// Camera preview texture; negative or `null` shows the silhouette.
  final int? textureId;
  final Worker? worker;
  final Direction? direction;
  final DateTime? at;
  final bool onTime;

  /// Last quality hint from the pipeline ("too dark", "covered" …).
  final QualityIssue? hint;
  final int retrySeconds;
  final bool pausedBecauseCameraFailed;

  GateViewState copyWith({
    GatePhase? phase,
    int? textureId,
    Worker? worker,
    Direction? direction,
    DateTime? at,
    bool? onTime,
    QualityIssue? hint,
    bool clearHint = false,
    int? retrySeconds,
    bool? pausedBecauseCameraFailed,
  }) => GateViewState(
    phase: phase ?? this.phase,
    textureId: textureId ?? this.textureId,
    worker: worker ?? this.worker,
    direction: direction ?? this.direction,
    at: at ?? this.at,
    onTime: onTime ?? this.onTime,
    hint: clearHint ? null : hint ?? this.hint,
    retrySeconds: retrySeconds ?? this.retrySeconds,
    pausedBecauseCameraFailed:
        pausedBecauseCameraFailed ?? this.pausedBecauseCameraFailed,
  );
}

/// How long the gate stays dark-and-idle before dimming the screen.
const gateDimAfter = Duration(seconds: 60);

/// Drives the gate: starts the camera, turns [VisionEvent]s into marks and
/// UI state, plays voice, and manages the screen (wake lock, dimming).
class GateController extends Notifier<GateViewState> {
  StreamSubscription<VisionEvent>? _events;
  Timer? _holdTimer;
  Timer? _retryTimer;
  Timer? _dimTimer;
  var _processing = false;
  var _disposed = false;
  late final GateVisionService _vision;
  late final ScreenService _screen;

  @override
  GateViewState build() {
    // Captured here because providers can't be read while disposing.
    _vision = ref.read(gateVisionProvider);
    _screen = ref.read(screenProvider);
    ref.onDispose(_shutdown);
    unawaited(_start());
    return const GateViewState();
  }

  Future<void> _start() async {
    _events = _vision.events.listen(_onEvent);
    try {
      final settings = await ref.read(settingsRepositoryProvider).load();
      final texture = await _vision.start(
        GateVisionConfig(useScreenFillLight: settings.screenFillLight),
      );
      if (_disposed) return;
      state = state.copyWith(textureId: texture);
      await _screen.setKeepAwake(enabled: true);
      _armDim();
    } on Object {
      if (_disposed) return;
      state = state.copyWith(
        phase: GatePhase.paused,
        pausedBecauseCameraFailed: true,
      );
    }
  }

  void _shutdown() {
    _disposed = true;
    _holdTimer?.cancel();
    _retryTimer?.cancel();
    _dimTimer?.cancel();
    unawaited(_events?.cancel());
    unawaited(_vision.stop());
    unawaited(_screen.setKeepAwake(enabled: false));
    unawaited(_screen.setDimmed(dimmed: false));
  }

  void _armDim() {
    _dimTimer?.cancel();
    _dimTimer = Timer(gateDimAfter, () {
      unawaited(_screen.setDimmed(dimmed: true));
    });
  }

  void _wake() {
    unawaited(_screen.setDimmed(dimmed: false));
    _armDim();
  }

  void _onEvent(VisionEvent event) {
    if (_disposed) return;
    switch (event) {
      case FaceSeen():
        _wake();
      case QualityHint(:final issue):
        if (state.phase == GatePhase.scanning) {
          state = state.copyWith(hint: issue);
        }
      case Match(:final workerId):
        if (state.phase == GatePhase.scanning && !_processing) {
          unawaited(_handleMatch(workerId));
        }
      case NoMatch():
        if (state.phase == GatePhase.scanning && !_processing) {
          _showNotRecognised();
        }
      case PipelineStats():
        break;
    }
  }

  Future<void> _handleMatch(String workerId) async {
    _processing = true;
    try {
      final result = await ref.read(markAttendanceProvider).call(workerId);
      if (_disposed) return;
      final voice = ref.read(voiceProvider);
      switch (result) {
        case Ok(:final value):
          final worker = value.worker;
          final event = value.event;
          final lang = worker.language.code;
          unawaited(voice.playEarcon(Earcon.success));
          unawaited(
            voice.playPhrase(
              event.direction == Direction.checkIn
                  ? Phrase.markedIn
                  : Phrase.markedOut,
              lang,
            ),
          );
          unawaited(voice.speakName(worker.firstName, lang));
          state = GateViewState(
            phase: GatePhase.matched,
            textureId: state.textureId,
            worker: worker,
            direction: event.direction,
            at: event.at,
            onTime: event.onTime,
          );
          _holdThenScan(SgMotion.gateConfirmHold);
        case Err(failure: AlreadyMarked(:final at, :final direction)):
          final worker = await ref
              .read(workerRepositoryProvider)
              .byId(workerId);
          if (_disposed) return;
          unawaited(ref.read(voiceProvider).playEarcon(Earcon.failure));
          state = GateViewState(
            phase: GatePhase.cooldown,
            textureId: state.textureId,
            worker: worker,
            direction: direction,
            at: at,
          );
          _holdThenScan(const Duration(seconds: 2));
        case Err():
          _showNotRecognised();
      }
    } finally {
      _processing = false;
    }
  }

  void _holdThenScan(Duration hold) {
    _holdTimer?.cancel();
    _holdTimer = Timer(hold, _backToScanning);
  }

  void _showNotRecognised() {
    final voice = ref.read(voiceProvider);
    unawaited(voice.playEarcon(Earcon.failure));
    unawaited(voice.playPhrase(Phrase.notRecognised, _deviceLanguage()));
    final seconds = SgMotion.notRecognisedRetry.inSeconds;
    state = GateViewState(
      phase: GatePhase.notRecognised,
      textureId: state.textureId,
      hint: state.hint,
      retrySeconds: seconds,
    );
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = state.retrySeconds - 1;
      if (left <= 0) {
        timer.cancel();
        _backToScanning();
      } else {
        state = state.copyWith(retrySeconds: left);
      }
    });
  }

  String _deviceLanguage() =>
      ref.read(settingsProvider).value?.language.code ?? 'en';

  void _backToScanning() {
    _holdTimer?.cancel();
    _retryTimer?.cancel();
    if (_disposed) return;
    state = GateViewState(textureId: state.textureId);
  }

  /// "Try again" button.
  void retryNow() => _backToScanning();
}

final NotifierProvider<GateController, GateViewState> gateControllerProvider =
    NotifierProvider.autoDispose<GateController, GateViewState>(
      GateController.new,
    );

/// Data for the gate footer: shift, progress and the last mark.
@immutable
class GateFooterData {
  const new({
    required this.now,
    required this.shift,
    required this.marked,
    required this.expected,
    required this.lastWorker,
    required this.lastEvent,
  });

  final DateTime now;
  final Shift? shift;
  final int marked;
  final int expected;
  final Worker? lastWorker;
  final AttendanceEvent? lastEvent;

  int get notYet => expected - marked;
  double get progress => expected == 0 ? 0 : marked / expected;
}

/// The shift running now (or the next one to start).
final currentShiftProvider = Provider<Shift?>((ref) {
  final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
  if (shifts.isEmpty) return null;
  final now = ref.watch(nowProvider);
  for (final shift in shifts) {
    if (shift.isRunningAt(now)) return shift;
  }
  return shifts.first;
});

final gateFooterProvider = Provider<GateFooterData?>((ref) {
  final workers = ref.watch(workersProvider).value;
  final events = ref.watch(todayEventsProvider).value;
  if (workers == null || events == null) return null;
  final shift = ref.watch(currentShiftProvider);
  final progress = TodayCalculator.gateProgress(
    workers: workers,
    events: events,
    shiftId: shift?.id,
  );
  final last = TodayCalculator.lastMark(events);
  final lastWorker = last == null
      ? null
      : workers.where((w) => w.id == last.workerId).firstOrNull;
  return GateFooterData(
    now: ref.watch(nowProvider),
    shift: shift,
    marked: progress.marked,
    expected: progress.expected,
    lastWorker: lastWorker,
    lastEvent: last,
  );
});
