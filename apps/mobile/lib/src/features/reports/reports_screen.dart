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
import 'package:syncgate/src/features/reports/reports_providers.dart';

/// Reports (design 16): daily list or monthly muster, filters, and the
/// payroll export. Gate operators never get here.
class ReportsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(reportViewProvider);
    final gutter = context.sg.gutter;

    return SgScaffold(
      topBar: SgTopBar(
        title: l10n.reports_title,
        largeTitle: true,
        actions: [
          SgBarAction(
            icon: SgIcons.more,
            label: l10n.reports_menu,
            onTap: () => unawaited(_menu(context)),
          ),
        ],
      ),
      body: SgScrollColumn(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 32),
        children: [
          SgSegmented<ReportView>(
            selected: view,
            onChanged: ref.read(reportViewProvider.notifier).select,
            options: [
              SgOption(value: ReportView.daily, label: l10n.reports_daily),
              SgOption(value: ReportView.monthly, label: l10n.reports_monthly),
            ],
          ),
          const SizedBox(height: 12),
          const _FilterRow(),
          const SizedBox(height: 12),
          if (view == ReportView.monthly)
            const _MusterSummary()
          else
            const _DailyList(),
          const SizedBox(height: 20),
          const ExportSection(),
        ],
      ),
    );
  }

  Future<void> _menu(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showSgPicker<String>(
      context,
      title: l10n.reports_menu,
      options: [
        SgOption(value: 'tally', label: l10n.reports_menu_tally),
        SgOption(value: 'templates', label: l10n.reports_menu_templates),
      ],
    );
    if (!context.mounted) return;
    if (choice == 'tally') context.go(Routes.settingsTally);
    if (choice == 'templates') {
      showSgToast(context, l10n.common_comingSoon);
    }
  }
}

class _FilterRow extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = l10n.localeName;
    final filter = ref.watch(reportFilterProvider);
    final controller = ref.read(reportFilterProvider.notifier);
    final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
    final departments = ref.watch(departmentsForReportsProvider).value ?? [];
    final contractors = ref.watch(contractorsForReportsProvider).value ?? [];
    final today = ref.watch(todayProvider);

    final months = [
      for (var i = 0; i < 12; i++) DateTime(today.year, today.month - i),
    ];

    Future<void> pickMonth() async {
      final picked = await showSgPicker<DateTime>(
        context,
        title: l10n.reports_pickMonth,
        selected: filter.month,
        options: [
          for (final m in months)
            SgOption(value: m, label: formatMonthYear(m, locale)),
        ],
      );
      if (picked != null) controller.set(filter.copyWith(month: picked));
    }

    Future<void> pickDept() async {
      final picked = await showSgPicker<String>(
        context,
        title: l10n.enrol_field_department,
        selected: filter.department ?? '',
        options: [
          SgOption(value: '', label: l10n.common_all),
          for (final d in departments) SgOption(value: d, label: d),
        ],
      );
      if (picked == null) return;
      controller.set(
        picked.isEmpty
            ? filter.copyWith(clearDepartment: true)
            : filter.copyWith(department: picked),
      );
    }

    Future<void> pickShift() async {
      final picked = await showSgPicker<String>(
        context,
        title: l10n.enrol_field_shift,
        selected: filter.shiftId ?? '',
        options: [
          SgOption(value: '', label: l10n.common_all),
          for (final s in shifts) SgOption(value: s.id, label: s.name),
        ],
      );
      if (picked == null) return;
      controller.set(
        picked.isEmpty
            ? filter.copyWith(clearShift: true)
            : filter.copyWith(shiftId: picked),
      );
    }

    Future<void> pickContractor() async {
      final picked = await showSgPicker<String>(
        context,
        title: l10n.enrol_field_contractor,
        selected: filter.contractor ?? '',
        options: [
          SgOption(value: '', label: l10n.common_all),
          for (final c in contractors) SgOption(value: c, label: c),
        ],
      );
      if (picked == null) return;
      controller.set(
        picked.isEmpty
            ? filter.copyWith(clearContractor: true)
            : filter.copyWith(contractor: picked),
      );
    }

    final shiftName =
        shifts.where((s) => s.id == filter.shiftId).firstOrNull?.name ??
        l10n.common_all;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SgChip(
            label: formatMonthYear(filter.month, locale),
            selected: true,
            dropdown: true,
            onTap: () => unawaited(pickMonth()),
          ),
          const SizedBox(width: 8),
          SgChip(
            label: l10n.reports_filter_dept(
              filter.department ?? l10n.common_all,
            ),
            selected: false,
            dropdown: true,
            onTap: () => unawaited(pickDept()),
          ),
          const SizedBox(width: 8),
          SgChip(
            label: l10n.reports_filter_shift(shiftName),
            selected: false,
            dropdown: true,
            onTap: () => unawaited(pickShift()),
          ),
          const SizedBox(width: 8),
          SgChip(
            label: l10n.reports_filter_contractor(
              filter.contractor ?? l10n.common_all,
            ),
            selected: false,
            dropdown: true,
            onTap: () => unawaited(pickContractor()),
          ),
        ],
      ),
    );
  }
}

final FutureProvider<List<String>> departmentsForReportsProvider =
    FutureProvider.autoDispose<List<String>>(
      (ref) => ref.watch(workerRepositoryProvider).departments(),
    );

final FutureProvider<List<String>> contractorsForReportsProvider =
    FutureProvider.autoDispose<List<String>>(
      (ref) => ref.watch(workerRepositoryProvider).contractors(),
    );

class _MusterSummary extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final muster = ref.watch(musterProvider);
    final days = ref.watch(workingDaysProvider);

    return muster.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: SgSpinner()),
      ),
      error: (e, _) => SgBanner(
        kind: SgBannerKind.danger,
        title: l10n.common_error,
        action: SgButton(
          label: l10n.common_retry,
          kind: SgButtonKind.secondary,
          onPressed: () => ref.invalidate(musterProvider),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Text(l10n.reports_empty, style: SgText.title),
                const SizedBox(height: 4),
                Text(
                  l10n.reports_emptySub,
                  style: SgText.body.copyWith(color: SgColors.muted),
                ),
              ],
            ),
          );
        }
        return SgCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.reports_summary(rows.length, days),
                        style: SgText.bodyStrong.copyWith(fontSize: 17),
                      ),
                    ),
                    SgButton(
                      label: l10n.reports_seeAll,
                      kind: SgButtonKind.text,
                      underline: true,
                      expand: false,
                      onPressed: () =>
                          unawaited(context.push(Routes.reportsMuster)),
                    ),
                  ],
                ),
              ),
              const SgDivider(),
              Container(
                color: const Color(0xFFF7F6F2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: _MusterLine(
                  worker: l10n.reports_col_worker,
                  p: l10n.reports_col_present,
                  a: l10n.reports_col_absent,
                  late: l10n.reports_col_late,
                  ot: l10n.reports_col_overtime,
                  header: true,
                ),
              ),
              for (final row in rows.take(5)) ...[
                const SgDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: _MusterLine(
                    worker: row.worker.name,
                    p: '${row.present}',
                    a: '${row.absent}',
                    late: '${row.late}',
                    ot: formatNumber(row.overtimeHours, decimals: 1),
                    flagged: row.hasOpenExceptions,
                    flagLabel: l10n.reports_flagged,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MusterLine extends StatelessWidget {
  const new({
    required this.worker,
    required this.p,
    required this.a,
    required this.late,
    required this.ot,
    this.header = false,
    this.flagged = false,
    this.flagLabel,
  });

  final String worker;
  final String p;
  final String a;
  final String late;
  final String ot;
  final bool header;
  final bool flagged;
  final String? flagLabel;

  @override
  Widget build(BuildContext context) {
    final style = header
        ? SgText.label.copyWith(fontSize: 13)
        : SgText.mono.copyWith(fontSize: 17);
    Widget cell(String text, double width) => SizedBox(
      width: width,
      child: Text(text, textAlign: TextAlign.end, style: style),
    );
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  worker,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: header
                      ? SgText.label
                      : SgText.body.copyWith(fontSize: 17),
                ),
              ),
              if (flagged)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Semantics(
                    label: flagLabel,
                    child: const Icon(
                      SgIcons.flag,
                      size: 18,
                      color: SgColors.warningIcon,
                    ),
                  ),
                ),
            ],
          ),
        ),
        cell(p, 30),
        cell(a, 30),
        cell(late, 52),
        cell(ot, 52),
      ],
    );
  }
}

String _hm(DateTime? time) => time == null ? '--:--' : formatHm(time);

class _DailyList extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final day = ref.watch(reportDayProvider);
    final daily = ref.watch(dailyReportProvider);
    final controller = ref.read(reportDayProvider.notifier);
    final today = ref.watch(todayProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SgIconButton(
              icon: SgIcons.back,
              label: l10n.common_back,
              onPressed: () =>
                  controller.set(day.subtract(const Duration(days: 1))),
            ),
            Text(
              l10n.reports_daily_title(
                formatDateWithWeekday(day, l10n.localeName),
              ),
              style: SgText.bodyStrong,
            ),
            SgIconButton(
              icon: SgIcons.chevron,
              label: l10n.common_next,
              onPressed: day.isBefore(today)
                  ? () => controller.set(day.add(const Duration(days: 1)))
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        daily.when(
          loading: () => const Center(child: SgSpinner()),
          error: (e, _) => Text(l10n.common_error),
          data: (rows) => SgCardList(
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    r.worker.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: SgText.bodyStrong,
                                  ),
                                ),
                                if (r.flagged)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Icon(
                                      SgIcons.flag,
                                      size: 18,
                                      color: SgColors.warningIcon,
                                    ),
                                  ),
                              ],
                            ),
                            Text(
                              '${l10n.reports_daily_in} ${_hm(r.inAt)}'
                              ' · ${l10n.reports_daily_out} ${_hm(r.outAt)}',
                              style: SgText.mono.copyWith(
                                color: SgColors.muted,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        switch (r.status) {
                          'P' => l10n.reports_status_P,
                          'L' => l10n.reports_status_L,
                          _ => l10n.reports_status_A,
                        },
                        style: SgText.bodyStrong.copyWith(
                          color: r.status == 'A'
                              ? SgColors.muted
                              : r.status == 'L'
                              ? SgColors.warningText
                              : SgColors.successText,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "EXPORT FOR PAYROLL": pick Excel or Tally and share the file (design 16).
class ExportSection extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final format = ref.watch(exportFormatProvider);
    final tally = ref.watch(tallyMatchProvider).value;
    final ios = context.isIos;

    final tallySub = tally == null
        ? ''
        : tally.toMap == 0
        ? l10n.reports_export_tallyAllMatched(tally.total)
        : l10n.reports_export_tallySub(tally.matched, tally.total, tally.toMap);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            l10n.reports_export_header.toUpperCase(),
            style: SgText.label,
          ),
        ),
        SgSelectRow(
          title: l10n.reports_export_excel,
          subtitle: l10n.reports_export_excelSub,
          titleStyle: SgText.bodyStrong.copyWith(fontSize: 19),
          leading: const _FormatBadge(
            'XLSX',
            SgColors.successTint,
            SgColors.successText,
          ),
          selected: format == ExportFormat.excel,
          onTap: () => ref
              .read(exportFormatProvider.notifier)
              .select(ExportFormat.excel),
        ),
        const SizedBox(height: 10),
        SgSelectRow(
          title: l10n.reports_export_tally,
          subtitle: tallySub,
          titleStyle: SgText.bodyStrong.copyWith(fontSize: 19),
          leading: const _FormatBadge(
            'XML',
            SgColors.infoBg,
            SgColors.infoText,
          ),
          selected: format == ExportFormat.tally,
          onTap: () => ref
              .read(exportFormatProvider.notifier)
              .select(ExportFormat.tally),
        ),
        const SizedBox(height: 14),
        SgButton(
          label: l10n.reports_export_action,
          icon: ios ? SgIcons.shareIos : SgIcons.share,
          onPressed: () => unawaited(_export(context, ref)),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final open = ref.read(openExceptionsProvider).length;
    if (open > 0) {
      final go = await showSgConfirm(
        context,
        title: l10n.reports_export_confirmTitle(open),
        message: l10n.reports_export_confirmMessage,
        confirmLabel: l10n.reports_export_confirmGo,
        cancelLabel: l10n.reports_export_confirmReview,
      );
      if (!go || !context.mounted) {
        if (!go && context.mounted) unawaited(context.push(Routes.exceptions));
        return;
      }
    }

    final hold = ref.read(idleHoldProvider.notifier)..hold();
    try {
      final format = ref.read(exportFormatProvider);
      final filter = ref.read(reportFilterProvider);
      final result = await showSgBusy(
        context,
        message: l10n.reports_export_progress,
        task: ref.read(exportServiceProvider).export(format, filter),
      );
      if (!context.mounted) return;
      switch (result) {
        case Ok(:final value):
          await ref.read(shareProvider).shareFile(value.path);
          final session = ref.read(adminSessionProvider);
          await ref
              .read(auditLogProvider)
              .append(
                AuditEntry(
                  at: ref.read(clockProvider).now(),
                  actor: session?.user.name ?? 'admin',
                  action: 'report.exported',
                  detail: '${format.name} ${value.path}',
                ),
              );
          if (context.mounted) {
            showSgToast(context, l10n.reports_export_shared(value.path));
          }
        case Err():
          showSgToast(context, l10n.common_error);
      }
    } finally {
      hold.release();
    }
  }
}

class _FormatBadge extends StatelessWidget {
  const new(this.label, this.background, this.foreground);

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: SgText.bodyStrong.copyWith(color: foreground, fontSize: 13),
      ),
    );
  }
}
