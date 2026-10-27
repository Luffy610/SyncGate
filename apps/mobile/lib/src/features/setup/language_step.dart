import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/features/setup/setup_scaffold.dart';

/// Step 1: choose the app language (design 05). The choice applies at once.
class LanguageStep extends ConsumerWidget {
  const new({super.key});

  static const step = 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final english = lookupAppLocalizations(const Locale('en'));
    final hindi = lookupAppLocalizations(const Locale('hi'));
    final settings = ref.watch(settingsProvider).value;
    final selected = settings?.language ?? AppLanguage.en;
    final isEnglish = l10n.localeName == 'en';

    Future<void> choose(AppLanguage language) async {
      final repo = ref.read(settingsRepositoryProvider);
      await repo.save((await repo.load()).copyWith(language: language));
    }

    final continueLabel = isEnglish
        ? '${english.common_continue} · ${hindi.common_continue}'
        : '${hindi.common_continue} · ${english.common_continue}';

    return SetupScaffold(
      step: step,
      title: l10n.setup_language_title,
      secondaryTitle: isEnglish
          ? hindi.setup_language_title
          : english.setup_language_title,
      body: l10n.setup_language_body,
      actions: [
        SgButton(
          label: continueLabel,
          onPressed: () => unawaited(SetupNav.next(context, ref, step)),
        ),
      ],
      child: Column(
        children: [
          for (final language in AppLanguage.values) ...[
            SgSelectRow(
              title: language.nativeName,
              subtitle: language.isAvailable
                  ? language.englishName
                  : '${language.englishName} · ${l10n.common_comingSoon}',
              selected: language == selected,
              dimmed: !language.isAvailable,
              onTap: language.isAvailable
                  ? () => unawaited(choose(language))
                  : () => showSgToast(context, l10n.common_comingSoon),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
