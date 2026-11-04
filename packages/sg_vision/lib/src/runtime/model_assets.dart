import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:sg_vision/src/pipeline/model_manifest.dart';

/// The manifest and model bytes, checked against the manifest's SHA-256 so
/// a damaged or swapped model never runs.
final class ModelAssets {
  new({
    required this.manifest,
    required this.detector,
    required this.embedder,
  }) {
    _check(manifest.detectorFile, detector, manifest.detectorSha256);
    _check(manifest.embedderFile, embedder, manifest.embedderSha256);
  }

  /// From a directory holding `manifest.json` and the models (tests, tools).
  factory fromDirectory(String dir) {
    final manifest = ModelManifest.parse(
      File('$dir/manifest.json').readAsStringSync(),
    );
    return ModelAssets(
      manifest: manifest,
      detector: File('$dir/${manifest.detectorFile}').readAsBytesSync(),
      embedder: File('$dir/${manifest.embedderFile}').readAsBytesSync(),
    );
  }

  final ModelManifest manifest;
  final Uint8List detector;
  final Uint8List embedder;

  static void _check(String name, Uint8List bytes, String expected) {
    final actual = sha256.convert(bytes).toString();
    if (actual != expected) {
      throw StateError('model $name failed its integrity check');
    }
  }

  /// From the app bundle (the models ship as `sg_vision` assets).
  static Future<ModelAssets> fromBundle([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    final manifest = ModelManifest.parse(
      await b.loadString(ModelManifest.assetPath),
    );
    Future<Uint8List> load(String file) async =>
        (await b.load('${ModelManifest.assetDir}/$file')).buffer.asUint8List();
    return ModelAssets(
      manifest: manifest,
      detector: await load(manifest.detectorFile),
      embedder: await load(manifest.embedderFile),
    );
  }
}
