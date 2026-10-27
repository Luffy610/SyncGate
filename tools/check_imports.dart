// Enforces the layer rules from ADR-0003 and the frontend plan §2.2.
// Run from the repo root: `dart run tools/check_imports.dart`
// (part of `melos run analyze`). Exits 1 if any rule is broken.

import 'dart:io';

final _importPattern = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

class _Rule {
  const new({
    required this.description,
    required this.appliesTo,
    required this.forbids,
  });

  final String description;
  final bool Function(String path) appliesTo;
  final bool Function(String uri) forbids;
}

final _rules = <_Rule>[
  _Rule(
    description: 'sg_domain is pure Dart: no Flutter, dart:ui or other sg_*',
    appliesTo: (p) => p.startsWith('packages/sg_domain/'),
    forbids: (uri) =>
        uri.startsWith('package:flutter') ||
        uri == 'dart:ui' ||
        (uri.startsWith('package:sg_') &&
            !uri.startsWith('package:sg_domain/')),
  ),
  _Rule(
    description: 'only main_dev.dart and src/dev/ may import dev-only code',
    appliesTo: (p) =>
        p.startsWith('apps/mobile/lib/') &&
        p != 'apps/mobile/lib/main_dev.dart' &&
        p != 'apps/mobile/lib/main.dart' &&
        !p.startsWith('apps/mobile/lib/src/dev/'),
    forbids: (uri) => uri.contains('src/dev/'),
  ),
  _Rule(
    description:
        'screens use sg_ui components, not raw Material/Cupertino (ADR-0005)',
    appliesTo: (p) => p.startsWith('apps/mobile/lib/src/features/'),
    forbids: (uri) =>
        uri == 'package:flutter/material.dart' ||
        uri == 'package:flutter/cupertino.dart',
  ),
];

void main() {
  final root = Directory.current;
  final violations = <String>[];
  var checked = 0;

  for (final dir in ['apps', 'packages']) {
    final base = Directory('${root.path}/$dir');
    if (!base.existsSync()) continue;

    for (final entity in base.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path
          .substring(root.path.length + 1)
          .replaceAll(r'\', '/');
      if (path.contains('/build/') || path.contains('/.dart_tool/')) continue;

      final rules = _rules.where((r) => r.appliesTo(path)).toList();
      if (rules.isEmpty) continue;
      checked++;

      final source = entity.readAsStringSync();
      for (final match in _importPattern.allMatches(source)) {
        final uri = match.group(1)!;
        for (final rule in rules) {
          if (rule.forbids(uri)) {
            violations.add('$path imports $uri\n    rule: ${rule.description}');
          }
        }
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('Import boundaries OK ($checked files checked).');
    return;
  }
  stderr
    ..writeln('Import boundary violations:')
    ..writeAll(violations.map((v) => '  $v'), '\n')
    ..writeln();
  exitCode = 1;
}
