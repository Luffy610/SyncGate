import 'dart:async';
import 'dart:math' as math;

import 'package:sg_vision/src/enrolment.dart';
import 'package:sg_vision/src/gate_vision_service.dart';
import 'package:sg_vision/src/pipeline/enrolment_engine.dart';
import 'package:sg_vision/src/pipeline/face_pipeline.dart';
import 'package:sg_vision/src/pipeline/gate_engine.dart';
import 'package:sg_vision/src/pipeline/matcher.dart';
import 'package:sg_vision/src/pipeline/model_manifest.dart';
import 'package:sg_vision/src/pipeline/templates.dart';
import 'package:sg_vision/src/runtime/frames.dart';
import 'package:sg_vision/src/runtime/model_assets.dart';
import 'package:sg_vision/src/runtime/vision_runner.dart';
import 'package:sg_vision/src/vision_event.dart';

/// Rough scene light from mean frame luma. Phones auto-expose, so this is a
/// relative estimate (dim / fine / bright), not a light-meter reading.
double estimateLux(double frameLuma) => frameLuma * frameLuma / 40;

/// Pieces every real vision service shares: one camera, one runner (one copy
/// of the models) and the template vault.
///
/// The stack owns the camera. Services attach a consumer while they run;
/// the camera runs while anyone is attached, and each frame goes to the most
/// recently attached consumer only (one camera, one user at a time), so a
/// late `stop()` from the gate can never stop the camera under enrolment.
final class VisionStack {
  new({
    required this.source,
    required this.runner,
    required this.vault,
    required this.loadAssets,
    this.clock = DateTime.now,
    this.onError,
  });

  final FrameSource source;
  final VisionRunner runner;
  final TemplateVault vault;
  final DateTime Function() clock;

  /// Called when a frame fails to analyse (the gate carries on with the
  /// next frame). For the diagnostics log (ADR-0022); never sees pixels.
  final void Function(Object error, StackTrace stack)? onError;

  /// Loads (and integrity-checks) the models; called once.
  final Future<ModelAssets> Function() loadAssets;
  Future<ModelAssets>? _assets;

  final _consumers = <_FramePump>[];
  StreamSubscription<RawFrame>? _frames;
  int? _texture;
  Future<void> _camera = Future.value();

  /// Loads and verifies the models once, then starts the runner.
  Future<ModelManifest> ready() async {
    final assets = await (_assets ??= loadAssets());
    await runner.load(assets);
    return assets.manifest;
  }

  /// Runs camera changes one at a time, in call order.
  Future<T> _serially<T>(Future<T> Function() step) {
    final next = _camera.then((_) => step());
    _camera = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<int> _attach(_FramePump pump) => _serially(() async {
    _consumers
      ..remove(pump)
      ..add(pump);
    if (_frames == null) {
      _texture = await source.start();
      _frames = source.frames.listen(_dispatch);
    }
    return _texture!;
  });

  Future<void> _detach(_FramePump pump) => _serially(() async {
    _consumers.remove(pump);
    if (_consumers.isNotEmpty || _frames == null) return;
    // Cancelling takes effect at once; not awaiting it keeps the camera
    // hand-over in one turn of the event loop.
    unawaited(_frames?.cancel());
    _frames = null;
    _texture = null;
    await source.stop();
  });

  void _dispatch(RawFrame frame) {
    if (_consumers.isEmpty) {
      frame.wipe();
    } else {
      unawaited(_consumers.last._onFrame(frame));
    }
  }

  /// Stops the camera and frees the models.
  Future<void> close() async {
    _consumers.clear();
    await _serially(() async {
      unawaited(_frames?.cancel());
      _frames = null;
      await source.stop();
    });
    await runner.close();
  }
}

/// One service's view of the camera: analyses frames one at a time and
/// drops those that arrive while the previous one is still being analysed
/// ("keep only latest", ADR-0006 §3).
final class _FramePump {
  new(this._stack, this._mode, this._onAnalysis);

  final VisionStack _stack;
  final AnalysisMode _mode;
  final FutureOr<void> Function(FrameAnalysis, DateTime) _onAnalysis;
  var _busy = false;
  var _active = false;

  /// Frames skipped because the pipeline was busy.
  int dropped = 0;

  Future<int> start() {
    _active = true;
    return _stack._attach(this);
  }

  Future<void> _onFrame(RawFrame frame) async {
    if (_busy || !_active) {
      dropped++;
      frame.wipe();
      return;
    }
    _busy = true;
    try {
      final a = await _stack.runner.analyse(frame, _mode);
      if (_active) await _onAnalysis(a, frame.at);
    } on Object catch (e, st) {
      // One bad frame must not stop the gate; the next frame retries.
      _stack.onError?.call(e, st);
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() {
    _active = false;
    return _stack._detach(this);
  }
}

/// Serialises a service's start/stop calls so a stop that is still running
/// cannot interleave with the next start.
final class _Serial {
  Future<void> _last = Future.value();

  Future<T> run<T>(Future<T> Function() step) {
    final next = _last.then((_) => step());
    _last = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }
}

/// The real gate pipeline: camera → LiteRT → [GateEngine] → events.
final class LiteRtGateVisionService implements GateVisionService {
  new({
    required this.stack,
    required this.activeWorkers,
    this.rules = const GateRules(),
    this.preset,
    this.liveness,
    this.statsEvery = const Duration(seconds: 2),
    this.adaptEvery = const Duration(days: 14),
  });

  final VisionStack stack;

  /// IDs of workers who may mark now (active and enrolled).
  final Future<Set<String>> Function() activeWorkers;
  final GateRules rules;

  /// The owner's strictness setting, read at each start.
  final Future<MatchPreset> Function()? preset;
  final LivenessEstimator? liveness;
  final Duration statsEvery;

  /// The adaptive slot refreshes at most this often (ADR-0008 §4).
  final Duration adaptEvery;

  final _events = StreamController<VisionEvent>.broadcast();
  final _serial = _Serial();
  _FramePump? _pump;
  GateEngine? _engine;
  ModelManifest? _manifest;
  StreamSubscription<void>? _vaultSub;
  final _micros = <int>[];
  DateTime? _statsFrom;
  var _lastLuma = 0.0;

  @override
  Stream<VisionEvent> get events => _events.stream;

  @override
  Future<int> start(GateVisionConfig config) => _serial.run(() async {
    await _stop();
    final manifest = _manifest = await stack.ready();
    final chosen = await preset?.call() ?? rules.preset;
    _engine = GateEngine(
      thresholds: manifest.thresholds,
      rules: GateRules(
        preset: chosen,
        window: rules.window,
        agree: rules.agree,
        span: rules.span,
        decideWithin: rules.decideWithin,
        rearmAfterAbsence: rules.rearmAfterAbsence,
        retryAfter: rules.retryAfter,
        sameWorkerCooldown: rules.sameWorkerCooldown,
      ),
      liveness: liveness,
    );
    await _reloadGallery();
    _vaultSub = stack.vault.changes.listen((_) => unawaited(_reloadGallery()));
    final pump = _pump = _FramePump(stack, AnalysisMode.gate, _onAnalysis);
    return await pump.start();
  });

  Future<void> _reloadGallery() async {
    final m = _manifest;
    final engine = _engine;
    if (m == null || engine == null) return;
    final templates = await stack.vault.all(
      modelId: m.modelId,
      modelVersion: m.modelVersion,
    );
    engine.setGallery(FaceMatcher(templates), active: await activeWorkers());
  }

  Future<void> _onAnalysis(FrameAnalysis a, DateTime at) async {
    final engine = _engine;
    if (engine == null) return;
    final step = engine.onFrame(a, at);
    step.events.forEach(_events.add);
    final adaptive = step.adaptive;
    if (adaptive != null) await _maybeAdapt(adaptive);
    _stats(a, at);
  }

  Future<void> _maybeAdapt(AdaptiveCandidate c) async {
    final m = _manifest!;
    final now = stack.clock();
    final mine = (await stack.vault.all(
      modelId: m.modelId,
      modelVersion: m.modelVersion,
    )).where((t) => t.workerId == c.workerId);
    final last = mine.where((t) => t.slot == TemplateSlot.adaptive);
    if (last.isNotEmpty && now.difference(last.first.createdAt) < adaptEvery) {
      return;
    }
    await stack.vault.put(
      FaceTemplate(
        workerId: c.workerId,
        slot: TemplateSlot.adaptive,
        vector: c.embedding,
        modelId: m.modelId,
        modelVersion: m.modelVersion,
        quality: c.quality,
        createdAt: now,
      ),
    );
  }

  void _stats(FrameAnalysis a, DateTime at) {
    _micros.add(a.micros);
    if (a.quality != null) _lastLuma = a.quality!.frameLuma;
    final from = _statsFrom ??= at;
    final span = at.difference(from);
    if (span < statsEvery) return;
    final sorted = [..._micros]..sort();
    final p95 =
        sorted[math.min(sorted.length - 1, (sorted.length * 0.95).floor())];
    _events.add(
      PipelineStats(
        fps: _micros.length / (span.inMilliseconds / 1000),
        p95Ms: (p95 / 1000).round(),
        lux: estimateLux(_lastLuma),
      ),
    );
    _micros.clear();
    _statsFrom = at;
  }

  @override
  Future<void> stop() => _serial.run(_stop);

  Future<void> _stop() async {
    unawaited(_vaultSub?.cancel());
    _vaultSub = null;
    final pump = _pump;
    _pump = null;
    _engine = null;
    _micros.clear();
    _statsFrom = null;
    await pump?.stop();
  }
}

/// Guided enrolment capture on the real pipeline (ADR-0008).
final class LiteRtEnrolmentCaptureService implements EnrolmentCaptureService {
  new({required this.stack, this.policy = const EnrolmentPolicy()});

  final VisionStack stack;
  final EnrolmentPolicy policy;

  final _events = StreamController<CaptureEvent>.broadcast();
  final _serial = _Serial();
  _FramePump? _pump;
  EnrolmentEngine? _engine;
  late String _workerId;

  @override
  Stream<CaptureEvent> get events => _events.stream;

  @override
  Future<int> start(String workerId) => _serial.run(() async {
    await _stopCamera();
    final m = await stack.ready();
    _workerId = workerId;
    _engine = EnrolmentEngine(
      thresholds: m.thresholds,
      modelId: m.modelId,
      modelVersion: m.modelVersion,
      policy: policy,
    );
    final pump = _pump = _FramePump(stack, AnalysisMode.enrolment, (a, _) {
      _engine?.onFrame(a).forEach(_events.add);
    });
    return await pump.start();
  });

  @override
  Future<void> skipMask() async => _engine?.skipMask();

  @override
  Future<EnrolOutcome> finish({bool overrideDuplicate = false}) =>
      _serial.run(() => _finish(overrideDuplicate: overrideDuplicate));

  Future<EnrolOutcome> _finish({required bool overrideDuplicate}) async {
    await _stopCamera();
    final engine = _engine ?? (throw StateError('capture not started'));
    final workerId = _workerId;
    final m = await stack.ready();
    final result = engine.finish(
      workerId: workerId,
      existing: await stack.vault.all(
        modelId: m.modelId,
        modelVersion: m.modelVersion,
      ),
      now: stack.clock(),
      overrideDuplicate: overrideDuplicate,
    );
    if (result.outcome is EnrolOk) {
      await stack.vault.replaceWorker(workerId, result.templates);
      engine.clear();
      _engine = null;
    }
    return result.outcome;
  }

  @override
  Future<void> cancel() => _serial.run(() async {
    await _stopCamera();
    _engine?.clear();
    _engine = null;
  });

  Future<void> _stopCamera() async {
    final pump = _pump;
    _pump = null;
    await pump?.stop();
  }
}

/// The setup wizard's camera and light check (design 07) on the real camera.
final class LiteRtCameraCheckService implements CameraCheckService {
  new({required this.stack, this.window = 8});

  final VisionStack stack;

  /// Readings are summarised over the last [window] analysed frames.
  final int window;
  final _serial = _Serial();
  _FramePump? _pump;
  final _recent = <FrameAnalysis>[];

  @override
  Future<int> start() => _serial.run(() async {
    await _stop();
    await stack.ready();
    final pump = _pump = _FramePump(stack, AnalysisMode.gate, (a, _) {
      _recent.add(a);
      if (_recent.length > window) _recent.removeAt(0);
    });
    return await pump.start();
  });

  @override
  Future<void> stop() => _serial.run(_stop);

  Future<void> _stop() async {
    final pump = _pump;
    _pump = null;
    _recent.clear();
    await pump?.stop();
  }

  @override
  Future<CameraReading> check() async => readingFrom(_recent);

  /// A reading from analysed frames (exposed for tests).
  static CameraReading readingFrom(List<FrameAnalysis> frames) {
    double median(Iterable<double> xs) {
      final s = xs.toList()..sort();
      return s.isEmpty ? 0 : s[s.length ~/ 2];
    }

    final withQuality = frames.where((f) => f.quality != null).toList();
    if (withQuality.isEmpty) {
      // No face in view: judge the light from the whole frame.
      return CameraReading(
        lux: estimateLux(median(frames.map((f) => f.frameLuma))),
        backlight: false,
        lensClean: true,
        faceDistanceCm: 0,
      );
    }

    final q = withQuality.map((f) => f.quality!);
    final frameLuma = median(q.map((x) => x.frameLuma));
    final faceLuma = median(q.map((x) => x.faceLuma));
    final sharp = median(q.map((x) => x.sharpness));
    final iodFraction = median(q.map((x) => x.interOcularFraction));
    // Pinhole model: focal length ≈ 0.785 × long side for a ~65° front
    // camera; adult inter-pupil distance ≈ 6.3 cm.
    final distanceCm = iodFraction <= 0 ? 0 : 6.3 * 0.785 / iodFraction;
    return CameraReading(
      lux: estimateLux(faceLuma),
      backlight: frameLuma - faceLuma > 60 && faceLuma < 80,
      lensClean: sharp >= 20,
      faceDistanceCm: distanceCm.round(),
    );
  }
}
