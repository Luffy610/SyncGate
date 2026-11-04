import 'dart:async';
import 'dart:isolate';

import 'package:sg_vision/src/pipeline/enrolment_engine.dart';
import 'package:sg_vision/src/pipeline/face_pipeline.dart';
import 'package:sg_vision/src/pipeline/quality.dart';
import 'package:sg_vision/src/runtime/frames.dart';
import 'package:sg_vision/src/runtime/model_assets.dart';

/// Which quality gate a frame goes through.
enum AnalysisMode {
  /// Gate mode: frontal-ish faces only.
  gate,

  /// Guided capture: any yaw (the engine judges pose per angle).
  enrolment,
}

QualityPolicy _policyFor(AnalysisMode mode) => switch (mode) {
  AnalysisMode.gate => const QualityPolicy(),
  AnalysisMode.enrolment => const EnrolmentPolicy().quality,
};

/// Runs the [FacePipeline] somewhere: inline, or on a background isolate.
abstract interface class VisionRunner {
  /// Loads the models. Safe to call again; later calls do nothing.
  Future<void> load(ModelAssets assets);

  /// Analyses [frame] and wipes it.
  Future<FrameAnalysis> analyse(RawFrame frame, AnalysisMode mode);

  Future<void> close();
}

FrameAnalysis _analyse(FacePipeline p, RawFrame frame, AnalysisMode mode) {
  final rgb = frame.toRgb();
  try {
    return p.analyse(rgb, policy: _policyFor(mode));
  } finally {
    rgb.wipe();
    frame.wipe();
  }
}

/// Runs on the calling isolate. For tests and tools.
final class InlineVisionRunner implements VisionRunner {
  FacePipeline? _pipeline;

  @override
  Future<void> load(ModelAssets assets) async {
    _pipeline ??= FacePipeline.fromBytes(
      manifest: assets.manifest,
      detectorBytes: assets.detector,
      embedderBytes: assets.embedder,
    );
  }

  @override
  Future<FrameAnalysis> analyse(RawFrame frame, AnalysisMode mode) async {
    final p = _pipeline ?? (throw StateError('models not loaded'));
    return _analyse(p, frame, mode);
  }

  @override
  Future<void> close() async {
    _pipeline?.detector.close();
    _pipeline?.embedder.close();
    _pipeline = null;
  }
}

/// Runs on a long-lived background isolate, so inference never janks the
/// UI. Frames are copied to the isolate and wiped on both sides.
final class IsolateVisionRunner implements VisionRunner {
  Isolate? _isolate;
  SendPort? _send;
  ReceivePort? _recv;
  Future<void>? _loading;
  var _nextId = 0;
  final _pending = <int, Completer<FrameAnalysis>>{};

  @override
  Future<void> load(ModelAssets assets) => _loading ??= _spawn(assets);

  Future<void> _spawn(ModelAssets assets) async {
    final recv = ReceivePort();
    _recv = recv;
    final ready = Completer<void>();
    recv.listen((msg) {
      switch (msg) {
        case SendPort():
          _send = msg;
        case _Loaded():
          ready.complete();
        case _LoadFailed(:final error):
          ready.completeError(StateError(error));
        case _Result(:final id, :final analysis):
          _pending.remove(id)?.complete(analysis);
        case _Failed(:final id, :final error):
          _pending.remove(id)?.completeError(StateError(error));
      }
    });
    _isolate = await Isolate.spawn(
      _visionMain,
      _Init(recv.sendPort, assets),
      debugName: 'sg_vision',
    );
    await ready.future;
  }

  @override
  Future<FrameAnalysis> analyse(RawFrame frame, AnalysisMode mode) {
    final send = _send ?? (throw StateError('models not loaded'));
    final id = _nextId++;
    final c = Completer<FrameAnalysis>();
    _pending[id] = c;
    send.send(_Analyse(id, frame, mode));
    // The isolate received a copy; wipe ours.
    frame.wipe();
    return c.future;
  }

  @override
  Future<void> close() async {
    _send?.send(const _Close());
    _isolate?.kill();
    _recv?.close();
    for (final c in _pending.values) {
      c.completeError(StateError('vision runner closed'));
    }
    _pending.clear();
    _isolate = null;
    _send = null;
    _loading = null;
  }
}

final class _Init {
  const new(this.reply, this.assets);
  final SendPort reply;
  final ModelAssets assets;
}

final class _Analyse {
  const new(this.id, this.frame, this.mode);
  final int id;
  final RawFrame frame;
  final AnalysisMode mode;
}

final class _Close {
  const new();
}

final class _Loaded {
  const new();
}

final class _LoadFailed {
  const new(this.error);
  final String error;
}

final class _Result {
  const new(this.id, this.analysis);
  final int id;
  final FrameAnalysis analysis;
}

final class _Failed {
  const new(this.id, this.error);
  final int id;
  final String error;
}

void _visionMain(_Init init) {
  final port = ReceivePort();
  init.reply.send(port.sendPort);
  FacePipeline pipeline;
  try {
    pipeline = FacePipeline.fromBytes(
      manifest: init.assets.manifest,
      detectorBytes: init.assets.detector,
      embedderBytes: init.assets.embedder,
    );
  } on Object catch (e) {
    init.reply.send(_LoadFailed('$e'));
    return;
  }
  init.reply.send(const _Loaded());
  port.listen((msg) {
    switch (msg) {
      case _Analyse(:final id, :final frame, :final mode):
        try {
          init.reply.send(_Result(id, _analyse(pipeline, frame, mode)));
        } on Object catch (e) {
          init.reply.send(_Failed(id, '$e'));
        }
      case _Close():
        pipeline.detector.close();
        pipeline.embedder.close();
        port.close();
    }
  });
}
