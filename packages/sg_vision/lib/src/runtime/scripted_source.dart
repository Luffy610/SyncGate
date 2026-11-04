import 'dart:async';

import 'package:sg_vision/src/runtime/frames.dart';

/// A [FrameSource] fed by hand: tests, recorded clips, demos. [push] sends a
/// frame and resolves once the consumer has had a chance to analyse it.
final class ScriptedFrameSource implements FrameSource {
  new({this.textureId = -1});

  final int textureId;
  final _frames = StreamController<RawFrame>.broadcast(sync: true);

  /// Whether [start] was called without a [stop] since.
  bool running = false;

  @override
  Stream<RawFrame> get frames => _frames.stream;

  @override
  Future<int> start() async {
    running = true;
    return textureId;
  }

  @override
  Future<void> stop() async => running = false;

  /// Delivers [frame] if started (otherwise drops it, like a real camera).
  void push(RawFrame frame) {
    if (running) _frames.add(frame);
  }
}
