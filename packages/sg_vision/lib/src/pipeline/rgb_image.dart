import 'dart:typed_data';

/// An 8-bit RGB image, row-major, 3 bytes per pixel.
///
/// Frames live only in memory. Call [wipe] when done so face pixels do not
/// linger in the heap (ADR-0006 §3).
final class RgbImage {
  new(this.width, this.height, this.data)
    : assert(data.length == width * height * 3, 'data must be w*h*3 bytes');

  /// A black image.
  new blank(this.width, this.height) : data = Uint8List(width * height * 3);

  final int width;
  final int height;
  final Uint8List data;

  /// Zeroes the pixels.
  void wipe() => data.fillRange(0, data.length, 0);
}

/// Clockwise rotation that makes a camera frame upright.
enum FrameRotation {
  r0(0),
  r90(90),
  r180(180),
  r270(270);

  new(this.degrees);

  factory fromDegrees(int degrees) => switch (degrees % 360) {
    90 => r90,
    180 => r180,
    270 => r270,
    _ => r0,
  };

  final int degrees;
}

int _clamp255(double v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

/// Output size and the source pixel for each output pixel of a rotation.
final class _Rotator {
  new(this.srcW, this.srcH, this.rotation, this.step);

  final int srcW;
  final int srcH;
  final FrameRotation rotation;
  final int step;

  bool get _swap =>
      rotation == FrameRotation.r90 || rotation == FrameRotation.r270;
  int get outW => (_swap ? srcH : srcW) ~/ step;
  int get outH => (_swap ? srcW : srcH) ~/ step;

  /// Source x for output (ox, oy), at full resolution.
  int sx(int ox, int oy) => switch (rotation) {
    FrameRotation.r0 => ox * step,
    FrameRotation.r90 => oy * step,
    FrameRotation.r180 => srcW - 1 - ox * step,
    FrameRotation.r270 => srcW - 1 - oy * step,
  };

  int sy(int ox, int oy) => switch (rotation) {
    FrameRotation.r0 => oy * step,
    FrameRotation.r90 => srcH - 1 - ox * step,
    FrameRotation.r180 => srcH - 1 - oy * step,
    FrameRotation.r270 => ox * step,
  };
}

/// Converts a YUV 4:2:0 camera frame (Android: NV21, NV12 or I420 planes) to
/// upright RGB. [step] subsamples (2 = half size). BT.601 full range, as
/// Android cameras deliver.
RgbImage rgbFromYuv420({
  required int width,
  required int height,
  required Uint8List y,
  required int yRowStride,
  required Uint8List u,
  required Uint8List v,
  required int uvRowStride,
  required int uvPixelStride,
  FrameRotation rotation = FrameRotation.r0,
  int step = 1,
}) {
  final r = _Rotator(width, height, rotation, step);
  final out = RgbImage.blank(r.outW, r.outH);
  final d = out.data;
  var o = 0;
  for (var oy = 0; oy < r.outH; oy++) {
    for (var ox = 0; ox < r.outW; ox++) {
      final sx = r.sx(ox, oy);
      final sy = r.sy(ox, oy);
      final yy = y[sy * yRowStride + sx].toDouble();
      final uvi = (sy >> 1) * uvRowStride + (sx >> 1) * uvPixelStride;
      final uu = u[uvi] - 128.0;
      final vv = v[uvi] - 128.0;
      d[o++] = _clamp255(yy + 1.402 * vv);
      d[o++] = _clamp255(yy - 0.344136 * uu - 0.714136 * vv);
      d[o++] = _clamp255(yy + 1.772 * uu);
    }
  }
  return out;
}

/// Converts a single-buffer NV21 frame (Y plane, then interleaved V/U).
RgbImage rgbFromNv21(
  Uint8List bytes, {
  required int width,
  required int height,
  int? rowStride,
  FrameRotation rotation = FrameRotation.r0,
  int step = 1,
}) {
  final stride = rowStride ?? width;
  final ySize = stride * height;
  final vu = Uint8List.sublistView(bytes, ySize);
  return rgbFromYuv420(
    width: width,
    height: height,
    y: bytes,
    yRowStride: stride,
    // NV21 interleaves V first; U is the byte after.
    u: Uint8List.sublistView(vu, 1),
    v: vu,
    uvRowStride: stride,
    uvPixelStride: 2,
    rotation: rotation,
    step: step,
  );
}

/// Converts an iOS BGRA8888 frame to upright RGB.
RgbImage rgbFromBgra8888(
  Uint8List bytes, {
  required int width,
  required int height,
  required int rowStride,
  FrameRotation rotation = FrameRotation.r0,
  int step = 1,
}) {
  final r = _Rotator(width, height, rotation, step);
  final out = RgbImage.blank(r.outW, r.outH);
  final d = out.data;
  var o = 0;
  for (var oy = 0; oy < r.outH; oy++) {
    for (var ox = 0; ox < r.outW; ox++) {
      final i = r.sy(ox, oy) * rowStride + r.sx(ox, oy) * 4;
      d[o++] = bytes[i + 2];
      d[o++] = bytes[i + 1];
      d[o++] = bytes[i];
    }
  }
  return out;
}
