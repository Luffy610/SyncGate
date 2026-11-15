import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:sg_vision/sg_vision.dart';

/// The shipped models, read straight from this package's assets.
const modelsDir = 'assets/models';

/// Where `ml/scripts/make_e2e_fixtures.py` wrote the LFW-based gate frames:
/// `$SG_VISION_FIXTURES`, else `<repo>/.cache/ml/e2e`. `null` if absent.
String? fixturesDir() {
  final dir =
      Platform.environment['SG_VISION_FIXTURES'] ??
      '${Directory.current.path}/../../.cache/ml/e2e';
  return File('$dir/e2e.json').existsSync() ? dir : null;
}

const missingFixtures =
    'Face fixtures not found. Generate them with:\n'
    '  ml/scripts/fetch_lfw.sh && '
    'python -I ml/scripts/make_e2e_fixtures.py --data .cache/ml '
    '--out .cache/ml/e2e';

/// Decodes a JPEG/PNG fixture to RGB.
RgbImage loadRgb(String path) {
  final decoded = img.decodeImage(File(path).readAsBytesSync())!;
  final bytes = decoded.getBytes(order: img.ChannelOrder.rgb);
  return RgbImage(decoded.width, decoded.height, bytes);
}

Object? readJson(String path) => jsonDecode(File(path).readAsStringSync());
