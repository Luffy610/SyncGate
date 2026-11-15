/// Helpers for tests that run the real models on the development machine
/// (`flutter test`), not on a phone.
library;

import 'dart:io';

import 'package:flutter_litert/flutter_litert.dart';

var _loaded = false;

/// Loads LiteRT's bundled desktop library for host tests.
///
/// `flutter_litert` finds that library through
/// `./.dart_tool/package_config.json`, which in a pub workspace exists only
/// at the workspace root, not in each package. This briefly switches to the
/// nearest directory that has one, forces the library to load, and switches
/// back. Call it from `setUpAll` before building a pipeline.
void prepareLiteRtForHostTests() {
  if (_loaded) return;
  final root = _workspaceRoot();
  if (root == null) return;
  final original = Directory.current;
  Directory.current = root;
  try {
    InterpreterOptions().delete();
    _loaded = true;
  } finally {
    Directory.current = original;
  }
}

/// Runs [body] with the workspace root as the working directory, for code
/// that loads LiteRT in a *new* isolate (each isolate loads it again), such
/// as `IsolateVisionRunner.load`.
Future<T> inWorkspaceRoot<T>(Future<T> Function() body) async {
  final root = _workspaceRoot();
  final original = Directory.current;
  if (root != null) Directory.current = root;
  try {
    return await body();
  } finally {
    Directory.current = original;
  }
}

Directory? _workspaceRoot() {
  var dir = Directory.current.absolute;
  while (!File('${dir.path}/.dart_tool/package_config.json').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
  return dir;
}
