import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/routes.dart';

/// Steps shown to the user: owner PIN and first worker share step 6.
const setupDisplaySteps = 6;

int displayStep(int step) =>
    step > setupDisplaySteps ? setupDisplaySteps : step;

/// Moves the wizard between steps. The mode remembers the furthest step, so
/// the wizard resumes there after a restart.
class SetupNav {
  const new _();

  /// Goes forward from [step] (1-based) to the next one.
  static Future<void> next(
    BuildContext context,
    WidgetRef ref,
    int step,
  ) async {
    final mode = ref.read(appModeProvider);
    final furthest = mode is SetupMode ? mode.step : step;
    final target = step + 1;
    if (target > furthest) {
      await ref.read(appModeProvider.notifier).goToSetupStep(target);
    }
    if (context.mounted) context.go(Routes.setupSteps[target - 1]);
  }

  static void back(BuildContext context, int step) {
    if (step > 1) context.go(Routes.setupSteps[step - 2]);
  }
}

/// Shared frame of the setup wizard (designs 05–08): logo or back control,
/// "Step n of 6", progress bar, title, scrolling content and pinned actions.
class SetupScaffold extends ConsumerWidget {
  const new({
    required this.step,
    required this.title,
    required this.child,
    this.secondaryTitle,
    this.body,
    this.actions = const [],
    this.titleKey,
    super.key,
  });

  /// Internal step, 1..7.
  final int step;
  final String title;

  /// Second-language title shown under [title] (design 05).
  final String? secondaryTitle;
  final String? body;
  final Widget child;
  final List<Widget> actions;
  final Key? titleKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final gutter = context.sg.gutter;
    final ios = context.isIos;

    final leading = step == 1
        ? Row(
            children: [
              const SgLogo(size: 28),
              const SizedBox(width: 12),
              Text(
                l10n.app_name,
                style: SgText.title.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          )
        : SgTap(
            onTap: () => SetupNav.back(context, step),
            semanticLabel: l10n.common_back,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(ios ? SgIcons.backIos : SgIcons.back, size: 28),
                  if (ios)
                    Text(
                      l10n.common_back,
                      style: SgText.body.copyWith(fontSize: 17),
                    ),
                ],
              ),
            ),
          );

    return SgScaffold(
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                leading,
                Text(
                  l10n.setup_stepOf(displayStep(step), setupDisplaySteps),
                  style: SgText.body.copyWith(
                    color: SgColors.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: SgStepper(
              current: displayStep(step),
              total: setupDisplaySteps,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(gutter, 24, gutter, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(title, key: titleKey, style: SgText.heading),
                  ),
                  if (secondaryTitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        secondaryTitle!,
                        style: SgText.title.copyWith(color: SgColors.muted),
                      ),
                    ),
                  if (body != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        body!,
                        style: SgText.body.copyWith(
                          color: SgColors.muted,
                          fontSize: 17,
                          height: 1.4,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  child,
                ],
              ),
            ),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    actions[i],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Used by steps that start a future from a button.
void run(Future<void> future) => unawaited(future);
