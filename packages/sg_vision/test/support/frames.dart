import 'dart:typed_data';

import 'package:sg_vision/sg_vision.dart';

/// RGB → NV21 (BT.601 full range), the inverse of `rgbFromNv21`.
Uint8List nv21From(RgbImage img) {
  final w = img.width;
  final h = img.height;
  final out = Uint8List(w * h + w * h ~/ 2);
  final d = img.data;
  int c(double v) => v.round().clamp(0, 255);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      final r = d[i].toDouble();
      final g = d[i + 1].toDouble();
      final b = d[i + 2].toDouble();
      out[y * w + x] = c(0.299 * r + 0.587 * g + 0.114 * b);
      if (y.isEven && x.isEven) {
        final o = w * h + (y >> 1) * w + x;
        out[o] = c(0.5 * r - 0.418688 * g - 0.081312 * b + 128); // V
        out[o + 1] = c(-0.168736 * r - 0.331264 * g + 0.5 * b + 128); // U
      }
    }
  }
  return out;
}

/// [img] rotated 90° counter-clockwise (what a sensor mounted at 90° gives).
RgbImage rotateCcw(RgbImage img) {
  final out = RgbImage.blank(img.height, img.width);
  for (var y = 0; y < img.height; y++) {
    for (var x = 0; x < img.width; x++) {
      final s = (y * img.width + x) * 3;
      final ox = y;
      final oy = img.width - 1 - x;
      final o = (oy * out.width + ox) * 3;
      out.data.setRange(o, o + 3, img.data, s);
    }
  }
  return out;
}

/// RGB → BGRA8888 rows padded to [rowStride] bytes (iOS camera layout).
Uint8List bgraFrom(RgbImage img, {int? rowStride}) {
  final stride = rowStride ?? img.width * 4;
  final out = Uint8List(stride * img.height);
  for (var y = 0; y < img.height; y++) {
    for (var x = 0; x < img.width; x++) {
      final s = (y * img.width + x) * 3;
      final o = y * stride + x * 4;
      out[o] = img.data[s + 2];
      out[o + 1] = img.data[s + 1];
      out[o + 2] = img.data[s];
      out[o + 3] = 255;
    }
  }
  return out;
}
