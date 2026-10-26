import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/app/routes.dart';
import 'package:syncgate/src/features/common/licence_banner.dart';
import 'package:syncgate/src/features/gate/gate_controller.dart';

/// Which shift the Today numbers are for; an empty string means all shifts.
class TodayShiftFilter extends Notifier<String> {
  @override
  String build() => ref.read(currentShiftProvider)?.id ?? '';

  // ignore: use_setters_to_change_properties, a Notifier method is clearer.
  void select(String shiftId) => state = shiftId;
}

final todayShiftFilterProvider = NotifierProvider<TodayShiftFilter, String>(
  TodayShiftFilter.new,
);

final todaySummaryProvider = Provider<TodaySummary?>((ref) {
  final workers = ref.watch(workersProvider).value;
  final events = ref.watch(todayEventsProvider).value;
  final shifts = ref.watch(shiftsProvider).value;
  if (workers == null || events == null || shifts == null) return null;
  final filter = ref.watch(todayShiftFilterProvider);
  return TodayCalculator.summary(
    workers: workers,
    events: events,
    shifts: shifts,
    now: ref.watch(nowProvider),
    shiftId: filter.isEmpty ? null : filter,
  );
});

String backupWhen(AppLocalizations l10n, DateTime last, DateTime now) =>
    l10n.backup_when(TodayCalculator.daysAgo(last, now));

/// Today (design 10): the running shift, the numbers, what needs review and
/// the backup reminder.
class TodayScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final session = ref.watch(adminSessionProvider);
    final now = ref.watch(nowProvider);
    final settings = ref.watch(settingsProvider).value;
    final use24h = settings?.use24HourClock ?? false;
    final canEnrol = canDo(session, Capability.enrolWorkers);
    final canBackup = canDo(session, Capability.backupRestore);
    final limited = session?.role == Role.gateOperator;

    return SgScaffold(
      topBar: SgTopBar(
        title: l10n.today_title,
        subtitle:
            '${formatDateWithWeekday(now, locale)} · '
            '${formatTime(now, use24h: use24h)}',
        largeTitle: true,
        actions: [
          if (!limited)
            SgBarAction(
              icon: SgIcons.search,
              label: l10n.workers_search,
              onTap: () => context.go(Routes.workers),
            ),
          if (!limited)
            SgBarAction(
              icon: SgIcons.more,
              label: l10n.reports_menu,
              onTap: () => unawaited(_menu(context, ref)),
            ),
        ],
      ),
      primaryAction: canEnrol
          ? SgPrimaryActionSpec(
              label: l10n.today_enrol,
              onTap: () => unawaited(context.push(Routes.enrolDetails)),
            )
          : null,
      body: SgScrollColumn(
        padding: EdgeInsets.fromLTRB(
          context.sg.gutter,
          4,
          context.sg.gutter,
          96,
        ),
        children: [
          const LicenceBanner(),
          const _ShiftCard(),
          const SizedBox(height: 12),
          const _ShiftChips(),
          const SizedBox(height: 12),
          const _Stats(),
          if (!limited) ...[
            const SizedBox(height: 12),
            const _ReviewCard(),
            if (canBackup) ...[const SizedBox(height: 12), const _BackupCard()],
          ],
        ],
      ),
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showSgPicker<String>(
      context,
      title: l10n.reports_menu,
      options: [
        SgOption(value: 'exceptions', label: l10n.exceptions_title),
        SgOption(value: 'gate', label: l10n.settings_gate),
      ],
    );
    if (!context.mounted) return;
    if (choice == 'exceptions') unawaited(context.push(Routes.exceptions));
    if (choice == 'gate') context.go(Routes.settingsGate);
  }
}

class _ShiftCard extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shift = ref.watch(currentShiftProvider);
    final summary = ref.watch(todaySummaryProvider);
    final now = ref.watch(nowProvider);
    final session = ref.watch(adminSessionProvider);
    final limited = session?.role == Role.gateOperator;
    final running = shift?.isRunningAt(now) ?? false;

    final title = shift == null
        ? l10n.today_title
        : running
        ? l10n.today_shift_running(shift.name)
        : l10n.today_shift_upcoming(
            shift.name,
            formatMinuteOfDay(shift.startMinute),
          );
    final window = shift == null
        ? ''
        : l10n.today_shift_expected(
            formatShiftWindow(shift.startMinute, shift.endMinute),
            summary?.expected ?? 0,
          );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SgColors.ink,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: SgText.title.copyWith(
                    color: SgColors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: SgColors.successOnDark,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.today_offlineOk,
                    style: SgText.caption.copyWith(
                      color: SgColors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            window,
            style: SgText.body.copyWith(color: const Color(0xFFD5D8DB)),
          ),
          const SizedBox(height: 14),
          SgButton(
            label: l10n.today_startGate,
            kind: SgButtonKind.brand,
            icon: SgIcons.faceScan,
            large: true,
            onPressed: () => unawaited(
              ref.read(appModeProvider.notifier).enterGate(reason: 'start'),
            ),
          ),
          if (limited) ...[
            const SizedBox(height: 8),
            SgButton(
              label: l10n.today_operator_manual,
              kind: SgButtonKind.gateOutline,
              onPressed: () => unawaited(context.push(Routes.manual)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShiftChips extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
    final selected = ref.watch(todayShiftFilterProvider);
    return SgChoiceChips<String>(
      selected: selected,
      onSelected: ref.read(todayShiftFilterProvider.notifier).select,
      options: [
        SgOption(value: '', label: l10n.common_all),
        for (final s in shifts) SgOption(value: s.id, label: s.name),
      ],
    );
  }
}

class _Stats extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(todaySummaryProvider);
    if (s == null) {
      return const Center(child: SgSpinner());
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SgStatCard(
                dot: SgColors.successFill,
                label: l10n.today_stat_present,
                value: '${s.present}',
                caption: l10n.today_stat_presentOf(s.expected),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SgStatCard(
                dot: const Color(0xFF6E706D),
                label: l10n.today_stat_absent,
                value: '${s.absent}',
                caption: l10n.today_stat_onLeave(s.onLeave),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SgStatCard(
                dot: SgColors.warningIcon,
                label: l10n.today_stat_late,
                value: '${s.late}',
                caption: l10n.today_stat_after(s.lateAfterLabel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SgStatCard(
                dot: SgColors.infoText,
                label: l10n.today_stat_onPremises,
                value: '${s.onPremises}',
                caption: l10n.today_stat_wentOut(s.wentOut),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final open = ref.watch(openExceptionsProvider);
    final manual = open.where((e) => e.kind == ExceptionKind.manual).length;
    final missing = open
        .where((e) => e.kind == ExceptionKind.missingOut)
        .length;
    final clock = open.where((e) => e.kind == ExceptionKind.clock).length;
    final other = open.length - manual - missing - clock;
    final parts = [
      if (manual > 0) l10n.today_review_manual(manual),
      if (missing > 0) l10n.today_review_missingOut(missing),
      if (clock > 0) l10n.today_review_clock(clock),
      if (other > 0) l10n.today_review_other(other),
    ];
    final clear = open.isEmpty;

    return SgCard(
      onTap: () => unawaited(context.push(Routes.exceptions)),
      semanticLabel: clear
          ? l10n.today_review_clear
          : l10n.today_review_title(open.length),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: clear ? SgColors.successTint : SgColors.dangerTint,
              shape: BoxShape.circle,
            ),
            child: Icon(
              clear ? SgIcons.check : SgIcons.flag,
              color: clear ? SgColors.successText : SgColors.danger,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clear
                      ? l10n.today_review_clear
                      : l10n.today_review_title(open.length),
                  style: SgText.bodyStrong.copyWith(fontSize: 18),
                ),
                Text(
                  clear ? l10n.today_review_clearSub : parts.join(' · '),
                  style: SgText.caption.copyWith(fontSize: 15),
                ),
              ],
            ),
          ),
          const Icon(SgIcons.chevron, color: SgColors.muted),
        ],
      ),
    );
  }
}

class _BackupCard extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final info = ref.watch(backupInfoProvider).value;
    final remind = ref.watch(settingsProvider).value?.remindBackupDays ?? 7;
    final now = ref.watch(nowProvider);
    if (info == null) return const SizedBox.shrink();
    final last = info.lastBackupAt;
    final overdue =
        last == null || TodayCalculator.daysAgo(last, now) >= remind;
    if (!overdue) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: SgColors.warningBg,
        borderRadius: BorderRadius.circular(context.sg.cardRadius + 4),
      ),
      child: Row(
        children: [
          const Icon(SgIcons.backup, color: SgColors.warningIcon, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              last == null
                  ? l10n.today_backup_never
                  : l10n.today_backup_last(backupWhen(l10n, last, now)),
              style: SgText.bodyStrong.copyWith(
                color: SgColors.warningText,
                fontSize: 17,
              ),
            ),
          ),
          SgButton(
            label: l10n.today_backup_action,
            expand: false,
            onPressed: () => unawaited(runBackup(context, ref)),
          ),
        ],
      ),
    );
  }
}

/// Runs a backup with a progress dialog and a confirmation toast.
Future<void> runBackup(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final session = ref.read(adminSessionProvider);
  final result = await showSgBusy(
    context,
    message: l10n.backup_inProgress,
    task: ref.read(backupServiceProvider).backupNow(),
  );
  if (!context.mounted) return;
  if (result.isOk) {
    unawaited(
      ref
          .read(auditLogProvider)
          .append(
            AuditEntry(
              at: ref.read(clockProvider).now(),
              actor: session?.user.name ?? 'Owner',
              action: 'backup.manual',
            ),
          ),
    );
    showSgToast(context, l10n.backup_done);
  } else {
    showSgToast(context, l10n.common_error);
  }
}
