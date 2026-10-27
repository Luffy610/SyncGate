import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/app_mode.dart';

/// Admin mode chrome: the "Gate is paused" banner on top and the four tabs at
/// the bottom (frontend plan §3.1). Gate operators get no tabs.
class AdminShell extends ConsumerWidget {
  const new({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(adminSessionProvider);
    final limited = session?.role == Role.gateOperator;

    return Scaffold(
      backgroundColor: context.sg.ground,
      bottomNavigationBar: limited
          ? null
          : SgNavBar(
              selectedIndex: shell.currentIndex,
              onSelected: (i) =>
                  shell.goBranch(i, initialLocation: i == shell.currentIndex),
              items: [
                SgNavItem(
                  icon: SgIcons.home,
                  activeIcon: SgIcons.homeActive,
                  label: l10n.nav_today,
                ),
                SgNavItem(
                  icon: SgIcons.people,
                  activeIcon: SgIcons.peopleActive,
                  label: l10n.nav_workers,
                ),
                SgNavItem(
                  icon: SgIcons.reports,
                  activeIcon: SgIcons.reportsActive,
                  label: l10n.nav_reports,
                ),
                SgNavItem(
                  icon: SgIcons.settings,
                  activeIcon: SgIcons.settings,
                  label: l10n.nav_settings,
                ),
              ],
            ),
      body: Column(
        children: [
          const GatePausedBanner(),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: shell,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Gate is paused — workers can't mark attendance · Back to gate", pinned to
/// the top of every admin screen (ADR-0004 §1).
class GatePausedBanner extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ColoredBox(
      color: SgColors.ink,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              const Icon(
                SgIcons.warning,
                color: SgColors.brandYellow,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.shell_gatePaused_message,
                  style: SgText.caption.copyWith(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
              SgTap(
                onTap: () => ref
                    .read(appModeProvider.notifier)
                    .enterGate(reason: 'banner'),
                semanticLabel: l10n.shell_gatePaused_action,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      l10n.shell_gatePaused_action,
                      style: SgText.bodyStrong.copyWith(
                        color: SgColors.brandYellow,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
