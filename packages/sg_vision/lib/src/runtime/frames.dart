import 'dart:typed_data';

import 'package:sg_vision/src/pipeline/rgb_image.dart';

/// One camera frame as delivered, before colour conversion. Only plain typed
/// data, so it can be sent to the vision isolate without native handles.
/// Converted lazily: frames dropped by back-pressure are never converted.
sealed class RawFrame {
  const new(this.at);

  /// When the frame was captured.
  final DateTime at;

  /// Upright RGB.
  RgbImage toRgb();

  /// Zeroes the pixel buffers (ADR-0006 §3).
  void wipe();
}

/// An already-converted RGB frame (tests, recorded clips).
final class RgbFrame extends RawFrame {
  const new(this.image, DateTime at) : super(at);

  final RgbImage image;

  @override
  RgbImage toRgb() => image;

  @override
  void wipe() => image.wipe();
}

/// Android YUV 4:2:0 (NV21 / NV12 / I420 planes from CameraX).
final class Yuv420Frame extends RawFrame {
  const new({
    required DateTime at,
    required this.width,
    required this.height,
    required this.y,
    required this.yRowStride,
    required this.u,
    required this.v,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.rotation,
  }) : super(at);

  final int width;
  final int height;
  final Uint8List y;
  final int yRowStride;
  final Uint8List u;
  final Uint8List v;
  final int uvRowStride;
  final int uvPixelStride;
  final FrameRotation rotation;

  @override
  RgbImage toRgb() => rgbFromYuv420(
    width: width,
    height: height,
    y: y,
    yRowStride: yRowStride,
    u: u,
    v: v,
    uvRowStride: uvRowStride,
    uvPixelStride: uvPixelStride,
    rotation: rotation,
  );

  @override
  void wipe() {
    y.fillRange(0, y.length, 0);
    u.fillRange(0, u.length, 0);
    v.fillRange(0, v.length, 0);
  }
}

/// Single-buffer NV21 (Y plane then interleaved V/U).
final class Nv21Frame extends RawFrame {
  const new({
    required DateTime at,
    required this.bytes,
    required this.width,
    required this.height,
    required this.rowStride,
    required this.rotation,
  }) : super(at);

  final Uint8List bytes;
  final int width;
  final int height;
  final int rowStride;
  final FrameRotation rotation;

  @override
  RgbImage toRgb() => rgbFromNv21(
    bytes,
    width: width,
    height: height,
    rowStride: rowStride,
    rotation: rotation,
  );

  @override
  void wipe() => bytes.fillRange(0, bytes.length, 0);
}

/// iOS BGRA8888.
final class Bgra8888Frame extends RawFrame {
  const new({
    required DateTime at,
    required this.bytes,
    required this.width,
    required this.height,
    required this.rowStride,
    required this.rotation,
  }) : super(at);

  final Uint8List bytes;
  final int width;
  final int height;
  final int rowStride;
  final FrameRotation rotation;

  @override
  RgbImage toRgb() => rgbFromBgra8888(
    bytes,
    width: width,
    height: height,
    rowStride: rowStride,
    rotation: rotation,
  );

  @override
  void wipe() => bytes.fillRange(0, bytes.length, 0);
}

/// Where frames come from: the front camera in the app, scripted frames in
/// tests and demos.
abstract interface class FrameSource {
  /// Starts delivering frames. Returns the preview texture ID (negative when
  /// there is no live preview).
  Future<int> start();

  /// Frames while started. Consumers drop frames they cannot keep up with.
  Stream<RawFrame> get frames;

  Future<void> stop();
}
