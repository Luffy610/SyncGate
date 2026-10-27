import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_ui/sg_ui.dart';

const List<TargetPlatform> platforms = [
  TargetPlatform.android,
  TargetPlatform.iOS,
];

/// Pumps [child] inside a themed app for [platform] at [textScale].
Future<void> pumpSg(
  WidgetTester tester,
  Widget child, {
  TargetPlatform platform = TargetPlatform.android,
  double textScale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? SgTheme.gate(platform) : SgTheme.light(platform),
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
      home: child,
    ),
  );
  await tester.pump();
}
