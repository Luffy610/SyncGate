import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncgate/src/dev/catalogue_page.dart';

import 'support/test_app.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('catalogue renders on ${platform.name}', (tester) async {
      final app = await pumpApp(tester, platform: platform, textScale: 1.3);
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const CataloguePage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Catalogue'), findsOneWidget);
      expect(app.mode, isNotNull);
    });
  }
}
