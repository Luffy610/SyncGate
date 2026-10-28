import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/routes.dart';

String roleLabel(AppLocalizations l10n, Role role) => switch (role) {
  Role.owner => l10n.role_owner,
  Role.admin => l10n.role_admin,
  Role.gateOperator => l10n.role_gateOperator,
};

/// Settings hub (no design yet, D-1): entry points to everything else.
class SettingsHubScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(adminSessionProvider);
    final ownerOnly = canDo(session, Capability.backupRestore);
    final gutter = context.sg.gutter;

    Widget row(String title, String route, {String? subtitle}) => SgListRow(
      title: title,
      subtitle: subtitle,
      showChevron: true,
      onTap: () => context.go(route),
    );

    return SgScaffold(
      topBar: SgTopBar(title: l10n.settings_title, largeTitle: true),
      body: SgScrollColumn(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 32),
        children: [
          if (session != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                l10n.settings_signedIn(roleLabel(l10n, session.role)),
                style: SgText.caption.copyWith(fontSize: 14),
              ),
            ),
          if (ownerOnly) ...[
            SgCardList(
              children: [
                row(l10n.settings_backup, Routes.settingsBackup),
                row(l10n.settings_users, Routes.settingsUsers),
              ],
            ),
            const SizedBox(height: 16),
          ],
          SgCardList(
            children: [
              row(l10n.settings_shifts, Routes.settingsShifts),
              row(l10n.settings_gate, Routes.settingsGate),
              row(l10n.settings_tally, Routes.settingsTally),
            ],
          ),
          const SizedBox(height: 16),
          SgCardList(
            children: [
              row(l10n.settings_language, Routes.settingsLanguage),
              row(l10n.settings_privacy, Routes.settingsPrivacy),
              row(l10n.settings_about, Routes.settingsAbout),
            ],
          ),
        ],
      ),
    );
  }
}

/// A settings sub-page: back arrow to Settings, scrolling content.
class SettingsPage extends StatelessWidget {
  const new({
    required this.title,
    required this.children,
    this.actions = const [],
    super.key,
  });

  final String title;
  final List<Widget> children;
  final List<SgBarAction> actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gutter = context.sg.gutter;
    return SgScaffold(
      topBar: SgTopBar(
        title: title,
        leading: SgLeading.back,
        leadingLabel: l10n.settings_title,
        onLeading: () => context.go(Routes.settings),
        actions: actions,
      ),
      body: SgScrollColumn(
        padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
        children: children,
      ),
    );
  }
}
