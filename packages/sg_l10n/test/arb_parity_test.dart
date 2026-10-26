import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _load(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _keys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  final en = _load('en');
  final hi = _load('hi');

  test('Hindi has every English key and nothing extra', () {
    expect(_keys(hi).difference(_keys(en)), isEmpty, reason: 'extra in hi');
    expect(_keys(en).difference(_keys(hi)), isEmpty, reason: 'missing in hi');
  });

  test('every placeholder declared in English is used in Hindi', () {
    for (final key in _keys(en)) {
      final meta = en['@$key'] as Map<String, dynamic>?;
      final placeholders =
          (meta?['placeholders'] as Map<String, dynamic>?)?.keys ?? <String>[];
      for (final name in placeholders) {
        expect(
          RegExp('[{]$name[,}]').hasMatch(hi[key] as String),
          isTrue,
          reason: '$key is missing {$name} in hi',
        );
      }
    }
  });

  test('no translation is empty', () {
    for (final key in _keys(hi)) {
      expect((hi[key] as String).trim(), isNotEmpty, reason: key);
    }
  });

  test('keys follow the <feature>_<screen>_<element> naming', () {
    final pattern = RegExp(r'^[a-z][A-Za-z]*(_[A-Za-z0-9]+)+$');
    final bad = _keys(en).where((k) => !pattern.hasMatch(k));
    expect(bad, isEmpty);
  });
}
