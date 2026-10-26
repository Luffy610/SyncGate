import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/app/routes.dart';
import 'package:syncgate/src/features/settings/settings_hub_screen.dart';
import 'package:syncgate/src/features/today/today_screen.dart';

Future<void> _saveSettings(
  WidgetRef ref,
  AppSettings Function(AppSettings) change,
) async {
  final repo = ref.read(settingsRepositoryProvider);
  await repo.save(change(await repo.load()));
}

/// Backup & device (design 17).
class BackupScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final info = ref.watch(backupInfoProvider).value;
    final licence = ref.watch(licenceStatusProvider).value;
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final now = ref.watch(nowProvider);
    final use24h = settings.use24HourClock;
    final last = info?.lastBackupAt;
    final overdue =
        last == null ||
        TodayCalculator.daysAgo(last, now) >= settings.remindBackupDays;

    final licenceText = switch (licence?.state) {
      LicenceState.active when licence!.expiresOn != null =>
        l10n.backup_licenceActive(formatDate(licence.expiresOn!)),
      LicenceState.trial when licence!.expiresOn != null =>
        l10n.backup_licenceTrial(formatDate(licence.expiresOn!)),
      LicenceState.none || null => l10n.backup_licenceNone,
      _ => l10n.backup_licenceState,
    };

    return SettingsPage(
      title: l10n.backup_title,
      children: [
        SgBanner(
          kind: overdue ? SgBannerKind.warning : SgBannerKind.success,
          title: last == null
              ? l10n.today_backup_never
              : l10n.today_backup_last(backupWhen(l10n, last, now)),
          message: last == null
              ? l10n.backup_hero_none
              : l10n.backup_hero_details(
                  formatDateTime(last, use24h: use24h),
                  info?.destination ?? '',
                ),
          action: SgButton(
            label: l10n.backup_now,
            onPressed: () => unawaited(_backupNow(context, ref, settings)),
          ),
        ),
        const SizedBox(height: 20),
        _Header(l10n.backup_section),
        SgCardList(
          children: [
            SgSwitchRow(
              title: l10n.backup_auto,
              subtitle: l10n.backup_autoSub(l10n.backup_account),
              value: settings.autoBackup,
              onChanged: (v) => unawaited(
                _saveSettings(ref, (s) => s.copyWith(autoBackup: v)),
              ),
            ),
            SgListRow(
              title: l10n.backup_file,
              subtitle: l10n.backup_fileSub,
              onTap: () => unawaited(_shareFile(context, ref, settings)),
            ),
            SgListRow(
              title: l10n.backup_remind,
              subtitle: l10n.backup_remindSub,
              trailingText: l10n.backup_remindValue(settings.remindBackupDays),
              onTap: () => unawaited(_pickRemind(context, ref, settings)),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(SgIcons.shield, color: SgColors.successText),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.backup_privacy,
                  style: SgText.body.copyWith(
                    color: SgColors.muted,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
        _Header(l10n.backup_section_licence),
        SgCardList(
          children: [
            SgListRow(title: l10n.backup_licence, trailingText: licenceText),
            SgListRow(
              title: l10n.backup_move,
              onTap: () => unawaited(_move(context, ref, settings)),
            ),
            SgListRow(
              title: l10n.backup_lost,
              danger: true,
              onTap: () => unawaited(_lost(context, ref)),
            ),
          ],
        ),
      ],
    );
  }

  /// The first backup asks for a passphrase; later ones just run.
  Future<void> _backupNow(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    if (!settings.backupPassphraseSet) {
      unawaited(context.push(Routes.settingsPassphrase));
      return;
    }
    await runBackup(context, ref);
  }

  Future<void> _shareFile(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    if (!settings.backupPassphraseSet) {
      unawaited(context.push(Routes.settingsPassphrase));
      return;
    }
    final hold = ref.read(idleHoldProvider.notifier)..hold();
    try {
      await runBackup(context, ref);
      await ref.read(shareProvider).shareFile('syncgate-backup.sgbackup');
    } finally {
      hold.release();
    }
  }

  Future<void> _pickRemind(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showSgPicker<int>(
      context,
      title: l10n.backup_remind,
      selected: settings.remindBackupDays,
      options: [
        for (final d in const [3, 7, 14, 30])
          SgOption(value: d, label: l10n.backup_remindValue(d)),
      ],
    );
    if (picked != null) {
      await _saveSettings(ref, (s) => s.copyWith(remindBackupDays: picked));
    }
  }

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showSgConfirm(
      context,
      title: l10n.backup_move_title,
      message: l10n.backup_move_message,
      confirmLabel: l10n.backup_move_confirm,
      cancelLabel: l10n.common_cancel,
    );
    if (ok && context.mounted) await _backupNow(context, ref, settings);
  }

  Future<void> _lost(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showSgConfirm(
      context,
      title: l10n.backup_lost_title,
      message: l10n.backup_lost_message,
      confirmLabel: l10n.backup_lost_confirm,
      cancelLabel: l10n.common_cancel,
      destructive: true,
    );
    if (!ok) return;
    final session = ref.read(adminSessionProvider);
    await ref
        .read(auditLogProvider)
        .append(
          AuditEntry(
            at: ref.read(clockProvider).now(),
            actor: session?.user.name ?? 'Owner',
            action: 'device.reportedLost',
          ),
        );
    if (context.mounted) showSgToast(context, l10n.backup_lost_done);
  }
}

class _Header extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text.toUpperCase(), style: SgText.label),
    );
  }
}

const _words = [
  'river',
  'mango',
  'lantern',
  'copper',
  'monsoon',
  'saffron',
  'anchor',
  'meadow',
  'tiger',
  'orchid',
  'harbor',
  'jasmine',
  'falcon',
  'marble',
  'cotton',
  'sunrise',
  'bamboo',
  'velvet',
  'compass',
  'pepper',
  'silver',
  'thunder',
  'willow',
  'turmeric',
];

/// Four words to remember, picked from a small list.
String suggestPassphrase(Random random) =>
    [for (var i = 0; i < 4; i++) _words[random.nextInt(_words.length)]]
        .join(' ');

/// First-backup passphrase (undesigned, D-1): suggest four words, confirm,
/// and acknowledge that it cannot be recovered.
class PassphraseScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<PassphraseScreen> createState() => _PassphraseScreenState();
}

class _PassphraseScreenState extends ConsumerState<PassphraseScreen> {
  final _random = Random();
  final _confirm = TextEditingController();
  late String _suggestion = suggestPassphrase(_random);
  var _acknowledged = false;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  bool get _matches => _confirm.text.trim().toLowerCase() == _suggestion;

  Future<void> _save() async {
    await _saveSettings(ref, (s) => s.copyWith(backupPassphraseSet: true));
    if (!mounted) return;
    await runBackup(context, ref);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final typed = _confirm.text.trim().isNotEmpty;
    return SettingsPage(
      title: l10n.passphrase_title,
      children: [
        Text(
          l10n.passphrase_body,
          style: SgText.body.copyWith(color: SgColors.muted, fontSize: 17),
        ),
        const SizedBox(height: 16),
        _Header(l10n.passphrase_suggest),
        SgCard(
          padding: const EdgeInsets.all(20),
          child: Text(
            _suggestion,
            key: const ValueKey('passphrase-suggestion'),
            textAlign: TextAlign.center,
            style: SgText.mono.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SgButton(
          label: l10n.passphrase_another,
          kind: SgButtonKind.text,
          onPressed: () => setState(() {
            _suggestion = suggestPassphrase(_random);
            _confirm.clear();
          }),
        ),
        const SizedBox(height: 8),
        SgTextField(
          label: l10n.passphrase_confirm,
          controller: _confirm,
          mono: true,
          onChanged: (_) => setState(() {}),
        ),
        if (typed && !_matches)
          SgFieldNote(l10n.passphrase_mismatch, color: SgColors.danger),
        const SizedBox(height: 12),
        SgCheckRow(
          value: _acknowledged,
          onChanged: (v) => setState(() => _acknowledged = v),
          title: l10n.passphrase_ack,
        ),
        const SizedBox(height: 16),
        SgButton(
          label: l10n.passphrase_save,
          onPressed: _matches && _acknowledged
              ? () => unawaited(_save())
              : null,
        ),
      ],
    );
  }
}
