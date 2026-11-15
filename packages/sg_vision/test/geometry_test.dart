import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_vision/sg_vision.dart';

import 'support/frames.dart';

RgbImage gradient(int w, int h) {
  final img = RgbImage.blank(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      img.data[i] = x * 255 ~/ w;
      img.data[i + 1] = y * 255 ~/ h;
      img.data[i + 2] = 128;
    }
  }
  return img;
}

void main() {
  group('Affine.similarity', () {
    test('recovers rotation, scale and translation', () {
      const angle = 0.3;
      const s = 1.7;
      final truth = Affine(
        s * math.cos(angle),
        -s * math.sin(angle),
        12,
        s * math.sin(angle),
        s * math.cos(angle),
        -7,
      );
      const src = [
        Point2(10, 10),
        Point2(50, 12),
        Point2(30, 40),
        Point2(31, 60),
      ];
      final dst = src.map(truth.apply).toList();
      final fit = Affine.similarity(src, dst);
      for (final p in src) {
        final a = fit.apply(p);
        final b = truth.apply(p);
        expect(a.distanceTo(b), lessThan(1e-9));
      }
      expect(fit.scale, closeTo(s, 1e-9));
    });

    test('inverse undoes the transform', () {
      const t = Affine(1.2, -0.4, 5, 0.4, 1.2, -3);
      const p = Point2(17, -4);
      final back = t.inverse().apply(t.apply(p));
      expect(back.distanceTo(p), lessThan(1e-9));
    });
  });

  group('warpAffine', () {
    test('identity copies the image', () {
      final img = gradient(20, 10);
      final out = warpAffine(img, const Affine(1, 0, 0, 0, 1, 0), 20, 10);
      expect(out.data, img.data);
    });

    test('pixels outside the source are black', () {
      final img = gradient(10, 10)..data.fillRange(0, 300, 200);
      final out = warpAffine(img, Affine.scaleTranslate(1, 20, 0), 10, 10);
      expect(out.data.every((v) => v == 0), isTrue);
    });
  });

  group('camera frame conversion', () {
    test('NV21 converts back to RGB within YUV rounding', () {
      final img = gradient(64, 48);
      final rgb = rgbFromNv21(nv21From(img), width: 64, height: 48);
      var maxErr = 0;
      for (var i = 0; i < img.data.length; i++) {
        maxErr = math.max(maxErr, (img.data[i] - rgb.data[i]).abs());
      }
      // Chroma is shared by 2×2 blocks; a smooth gradient stays close.
      expect(maxErr, lessThanOrEqualTo(8));
    });

    test('rotation 90 makes a sideways sensor frame upright', () {
      final upright = gradient(48, 64);
      final sensor = rotateCcw(upright); // 64×48, like a landscape sensor
      final fixed = rgbFromNv21(
        nv21From(sensor),
        width: sensor.width,
        height: sensor.height,
        rotation: FrameRotation.r90,
      );
      expect((fixed.width, fixed.height), (48, 64));
      var err = 0;
      for (var i = 0; i < upright.data.length; i++) {
        err = math.max(err, (upright.data[i] - fixed.data[i]).abs());
      }
      expect(err, lessThanOrEqualTo(8));
    });

    test('BGRA swaps channels and honours the row stride', () {
      final bytes = Uint8List(2 * 8)..setAll(0, [1, 2, 3, 255, 4, 5, 6, 255]);
      final rgb = rgbFromBgra8888(bytes, width: 2, height: 1, rowStride: 16);
      expect(rgb.data, [3, 2, 1, 6, 5, 4]);
    });

    test('rotations map corners correctly', () {
      final img = RgbImage.blank(3, 2);
      img.data[0] = 9; // top-left red
      final bgra = Uint8List(3 * 2 * 4);
      for (var i = 0; i < 6; i++) {
        bgra[i * 4 + 2] = img.data[i * 3];
      }
      Point2 redAt(FrameRotation r) {
        final out = rgbFromBgra8888(
          bgra,
          width: 3,
          height: 2,
          rowStride: 12,
          rotation: r,
        );
        final i = out.data.indexOf(9) ~/ 3;
        return Point2((i % out.width).toDouble(), (i ~/ out.width).toDouble());
      }

      expect(redAt(FrameRotation.r0).toString(), '(0.0, 0.0)');
      expect(redAt(FrameRotation.r90).toString(), '(1.0, 0.0)');
      expect(redAt(FrameRotation.r180).toString(), '(2.0, 1.0)');
      expect(redAt(FrameRotation.r270).toString(), '(0.0, 2.0)');
    });
  });
}
