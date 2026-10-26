import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/idle_watcher.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/app/router.dart';

/// Root widget: theme, locale, router and the idle watcher for Admin mode.
class SyncGateApp extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final platform = ref.watch(platformProvider);

    // The router needs the saved mode, so wait for settings before building
    // it. This is a few milliseconds on a real phone.
    // Staging and prod have no real back ends yet (plan step F6); say so
    // instead of showing a blank screen.
    if (settings.hasError) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SgTheme.light(platform),
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'This build is not connected to its back end yet '
                '(frontend plan step F6). Use the dev flavour.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }
    if (!settings.hasValue) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SgTheme.light(platform),
        home: const ColoredBox(color: SgColors.groundAndroid),
      );
    }

    final language = settings.requireValue.language;
    final locale = Locale(language.isAvailable ? language.code : 'en');
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).app_name,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: SgTheme.light(platform),
      builder: (context, child) {
        final admin = ref.watch(appModeProvider) is AdminMode;
        return IdleWatcher(
          active: admin,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
