import 'dart:typed_data';

import 'package:flutter_litert/flutter_litert.dart';

/// One loaded model with a single float32 input. Inputs and outputs are
/// views onto the runtime's own buffers, so nothing is copied per frame.
abstract interface class TensorModel {
  /// The input tensor, NHWC float32. Fill it, then [invoke].
  Float32List get input;

  /// Output tensor [name] after [invoke].
  Float32List output(String name);

  /// Names of the output tensors.
  Iterable<String> get outputNames;

  void invoke();
  void close();
}

/// A LiteRT (TensorFlow Lite) model on the CPU (XNNPACK), ADR-0006 §1.
final class LiteRtModel implements TensorModel {
  new _(this._interpreter) {
    _interpreter.allocateTensors();
    _input = _interpreter.getInputTensor(0).asFloat32View();
    for (final t in _interpreter.getOutputTensors()) {
      _outputs[t.name] = t.asFloat32View();
    }
  }

  /// Loads a `.tflite` file's bytes. [threads] CPU threads (ADR-0006: 4).
  factory fromBuffer(Uint8List bytes, {int threads = 4}) {
    final options = InterpreterOptions()..threads = threads;
    return LiteRtModel._(Interpreter.fromBuffer(bytes, options: options));
  }

  final Interpreter _interpreter;
  late final Float32List _input;
  final _outputs = <String, Float32List>{};

  @override
  Float32List get input => _input;

  @override
  Float32List output(String name) =>
      _outputs[name] ??
      (throw ArgumentError('no output "$name"; has ${_outputs.keys}'));

  @override
  Iterable<String> get outputNames => _outputs.keys;

  @override
  void invoke() => _interpreter.invoke();

  @override
  void close() => _interpreter.close();
}
