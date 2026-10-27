import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncgate/src/app/app_config.dart';
import 'package:syncgate/src/app/syncgate_app.dart';

void main() {
  testWidgets('staging and prod say they are not wired yet', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              flavour: Flavour.prod,
              licenceBaseUrl: '',
              sentryDsn: '',
            ),
          ),
        ],
        child: const SyncGateApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('not connected to its back end'),
      findsOneWidget,
    );
  });
}
