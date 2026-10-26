import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/routes.dart';
import 'package:syncgate/src/features/reports/reports_providers.dart';

/// Full muster: one row per worker, one column per day, with a frozen name
/// column and horizontal scrolling for the days.
class MusterGridScreen extends ConsumerWidget {
  const new({super.key});

  static const _cell = 38.0;
  static const _nameWidth = 132.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final muster = ref.watch(musterProvider);
    final filter = ref.watch(reportFilterProvider);

    Color colorFor(String code) => switch (code) {
      'P' => SgColors.successText,
      'A' => SgColors.danger,
      'L' => SgColors.warningText,
      _ => SgColors.muted,
    };

    return SgScaffold(
      topBar: SgTopBar(
        title: l10n.reports_muster_title,
        subtitle: formatMonthYear(filter.month, l10n.localeName),
        leading: SgLeading.back,
        leadingLabel: l10n.reports_title,
        onLeading: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(Routes.reports);
          }
        },
      ),
      body: muster.when(
        loading: () => const Center(child: SgSpinner()),
        error: (e, _) => Center(child: Text(l10n.common_error)),
        data: (rows) {
          if (rows.isEmpty) return Center(child: Text(l10n.reports_empty));
          final days = rows.first.days.length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.reports_muster_legend,
                    style: SgText.caption,
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: _cell),
                          for (final r in rows)
                            SizedBox(
                              width: _nameWidth,
                              height: _cell,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 16),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    r.worker.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: SgText.body.copyWith(fontSize: 15),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  for (var d = 1; d <= days; d++)
                                    SizedBox(
                                      width: _cell,
                                      height: _cell,
                                      child: Center(
                                        child: Text('$d', style: SgText.label),
                                      ),
                                    ),
                                ],
                              ),
                              for (final r in rows)
                                Row(
                                  children: [
                                    for (final code in r.days)
                                      SizedBox(
                                        width: _cell,
                                        height: _cell,
                                        child: Center(
                                          child: Text(
                                            code,
                                            style: SgText.mono.copyWith(
                                              fontSize: 13,
                                              color: colorFor(code),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
