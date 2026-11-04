import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sg_vision/src/pipeline/rgb_image.dart';

/// A point in pixels.
final class Point2 {
  const new(this.x, this.y);

  final double x;
  final double y;

  double distanceTo(Point2 o) => math.sqrt(_sq(x - o.x) + _sq(y - o.y));

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

double _sq(double v) => v * v;

/// A 2-D affine transform `p' = [a b; c d] p + [tx; ty]`.
final class Affine {
  const new(this.a, this.b, this.tx, this.c, this.d, this.ty);

  /// Scale by [s], then translate.
  new scaleTranslate(double s, double dx, double dy)
    : a = s,
      b = 0,
      tx = dx,
      c = 0,
      d = s,
      ty = dy;

  /// The least-squares similarity (rotation, uniform scale, translation; no
  /// reflection) mapping [src] onto [dst]. Same result as Umeyama's method,
  /// solved in closed form with complex numbers.
  factory similarity(List<Point2> src, List<Point2> dst) {
    if (src.length != dst.length || src.length < 2) {
      throw ArgumentError('need >= 2 matching points');
    }
    final n = src.length;
    var msx = 0.0;
    var msy = 0.0;
    var mdx = 0.0;
    var mdy = 0.0;
    for (var i = 0; i < n; i++) {
      msx += src[i].x;
      msy += src[i].y;
      mdx += dst[i].x;
      mdy += dst[i].y;
    }
    msx /= n;
    msy /= n;
    mdx /= n;
    mdy /= n;
    // a = sum(conj(s) * d) / sum(|s|^2) over centred points.
    var re = 0.0;
    var im = 0.0;
    var norm = 0.0;
    for (var i = 0; i < n; i++) {
      final sx = src[i].x - msx;
      final sy = src[i].y - msy;
      final dx = dst[i].x - mdx;
      final dy = dst[i].y - mdy;
      re += sx * dx + sy * dy;
      im += sx * dy - sy * dx;
      norm += sx * sx + sy * sy;
    }
    if (norm < 1e-12) throw ArgumentError('degenerate points');
    re /= norm;
    im /= norm;
    return Affine(
      re,
      -im,
      mdx - (re * msx - im * msy),
      im,
      re,
      mdy - (im * msx + re * msy),
    );
  }
  final double a;
  final double b;
  final double tx;
  final double c;
  final double d;
  final double ty;

  Point2 apply(Point2 p) =>
      Point2(a * p.x + b * p.y + tx, c * p.x + d * p.y + ty);

  Affine inverse() {
    final det = a * d - b * c;
    if (det.abs() < 1e-12) throw StateError('singular transform');
    final ia = d / det;
    final ib = -b / det;
    final ic = -c / det;
    final id = a / det;
    return Affine(ia, ib, -(ia * tx + ib * ty), ic, id, -(ic * tx + id * ty));
  }

  /// Uniform scale of a similarity transform.
  double get scale => math.sqrt((a * d - b * c).abs());
}

/// Warps [src] into an [outW] x [outH] image: output pixel (u, v) samples
/// [srcToDst]⁻¹(u, v) bilinearly; outside the source is black. Matches
/// OpenCV's `warpAffine(..., INTER_LINEAR, BORDER_CONSTANT)` pixel convention.
RgbImage warpAffine(RgbImage src, Affine srcToDst, int outW, int outH) {
  final inv = srcToDst.inverse();
  final out = RgbImage.blank(outW, outH);
  final s = src.data;
  final o = out.data;
  final w = src.width;
  final h = src.height;
  var k = 0;
  for (var v = 0; v < outH; v++) {
    var x = inv.b * v + inv.tx;
    var y = inv.d * v + inv.ty;
    for (var u = 0; u < outW; u++, x += inv.a, y += inv.c, k += 3) {
      final x0 = x.floor();
      final y0 = y.floor();
      if (x0 < -1 || y0 < -1 || x0 >= w || y0 >= h) continue;
      final fx = x - x0;
      final fy = y - y0;
      final x1 = x0 + 1;
      final y1 = y0 + 1;
      final inX0 = x0 >= 0;
      final inX1 = x1 < w;
      final inY0 = y0 >= 0;
      final inY1 = y1 < h;
      final i00 = inX0 && inY0 ? (y0 * w + x0) * 3 : -1;
      final i10 = inX1 && inY0 ? (y0 * w + x1) * 3 : -1;
      final i01 = inX0 && inY1 ? (y1 * w + x0) * 3 : -1;
      final i11 = inX1 && inY1 ? (y1 * w + x1) * 3 : -1;
      final w00 = (1 - fx) * (1 - fy);
      final w10 = fx * (1 - fy);
      final w01 = (1 - fx) * fy;
      final w11 = fx * fy;
      for (var ch = 0; ch < 3; ch++) {
        final val =
            (i00 < 0 ? 0 : s[i00 + ch] * w00) +
            (i10 < 0 ? 0 : s[i10 + ch] * w10) +
            (i01 < 0 ? 0 : s[i01 + ch] * w01) +
            (i11 < 0 ? 0 : s[i11 + ch] * w11);
        o[k + ch] = val > 255 ? 255 : val.round();
      }
    }
  }
  return out;
}

/// RGB bytes to a float tensor: `value * scale + offset`, optionally
/// mirrored left-right.
Float32List toFloatTensor(
  RgbImage img, {
  double scale = 1,
  double offset = 0,
  bool mirror = false,
  Float32List? into,
}) {
  final out = into ?? Float32List(img.width * img.height * 3);
  final d = img.data;
  final w = img.width;
  var k = 0;
  for (var y = 0; y < img.height; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + (mirror ? w - 1 - x : x)) * 3;
      out[k++] = d[i] * scale + offset;
      out[k++] = d[i + 1] * scale + offset;
      out[k++] = d[i + 2] * scale + offset;
    }
  }
  return out;
}
