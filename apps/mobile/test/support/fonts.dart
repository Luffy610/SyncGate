import 'dart:io';

import 'package:flutter/services.dart';

var _loaded = false;

/// Widget tests draw text with the Ahem font (every glyph one em wide), which
/// makes layouts look about twice as wide as on a phone. Loading the real
/// Roboto from the Flutter SDK makes overflow checks meaningful.
///
/// Devanagari has no font here, so Hindi text still uses the test fallback.
Future<void> loadTestFonts() async {
  if (_loaded) return;
  _loaded = true;
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;

  // iOS typography asks for the system fonts, which tests don't have, so
  // Roboto stands in for those too.
  for (final family in [
    'Roboto',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
    '.SF UI Text',
    '.SF UI Display',
  ]) {
    final loader = FontLoader(family);
    for (final name in [
      'roboto-regular',
      'roboto-medium',
      'roboto-bold',
      'roboto-light',
      'roboto-black',
    ]) {
      final file = File('${dir.path}/$name.ttf');
      if (file.existsSync()) {
        loader.addFont(
          Future.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      }
    }
    await loader.load();
  }
}
