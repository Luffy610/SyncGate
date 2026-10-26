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
import 'package:syncgate/src/application/exception_use_cases.dart';
import 'package:syncgate/src/features/exceptions/correct_record_sheet.dart';
import 'package:syncgate/src/features/gate/gate_copy.dart';

enum ExceptionFilter { all, manual, missingOut, clock, other }

class ExceptionFilterController extends Notifier<ExceptionFilter> {
  @override
  ExceptionFilter build() => ExceptionFilter.all;

  // ignore: use_setters_to_change_properties, a Notifier method is clearer.
  void select(ExceptionFilter filter) => state = filter;
}

final NotifierProvider<ExceptionFilterController, ExceptionFilter>
exceptionFilterProvider =
    NotifierProvider.autoDispose<ExceptionFilterController, ExceptionFilter>(
      ExceptionFilterController.new,
    );

ExceptionFilter filterOf(ExceptionKind kind) => switch (kind) {
  ExceptionKind.manual => ExceptionFilter.manual,
  ExceptionKind.missingOut => ExceptionFilter.missingOut,
  ExceptionKind.clock => ExceptionFilter.clock,
  _ => ExceptionFilter.other,
};

typedef ExceptionEntry = ({ExceptionRecord record, Worker? worker});

/// Open exceptions with their worker, in the order of the design: missing
/// OUT, manual, clock, then the rest; newest first inside each.
final Provider<List<ExceptionEntry>> exceptionEntriesProvider =
    Provider.autoDispose<List<ExceptionEntry>>((ref) {
      final records = ref.watch(openExceptionsProvider);
      final workers = ref.watch(workersProvider).value ?? const <Worker>[];
      int rank(ExceptionKind k) => switch (k) {
        ExceptionKind.missingOut => 0,
        ExceptionKind.manual => 1,
        ExceptionKind.clock => 2,
        _ => 3,
      };
      final entries =
          [
            for (final r in records)
              (
                record: r,
                worker: workers.where((w) => w.id == r.workerId).firstOrNull,
              ),
          ]..sort((a, b) {
            final byKind = rank(a.record.kind) - rank(b.record.kind);
            return byKind != 0 ? byKind : b.record.at.compareTo(a.record.at);
          });
      return entries;
    });

String exceptionTag(AppLocalizations l10n, ExceptionKind kind) =>
    switch (kind) {
      ExceptionKind.missingOut => l10n.exception_tag_missingOut,
      ExceptionKind.manual => l10n.exception_tag_manual,
      ExceptionKind.clock => l10n.exception_tag_clock,
      ExceptionKind.lowMargin => l10n.exception_tag_lowMargin,
      ExceptionKind.duplicate => l10n.exception_tag_duplicate,
      ExceptionKind.spoofSuspect => l10n.exception_tag_spoofSuspect,
      ExceptionKind.livenessActive => l10n.exception_tag_livenessActive,
    };

({Color background, Color foreground}) tagColors(ExceptionKind kind) =>
    switch (kind) {
      ExceptionKind.missingOut => (
        background: SgColors.warningBg,
        foreground: SgColors.warningText,
      ),
      ExceptionKind.manual => (
        background: SgColors.infoBg,
        foreground: SgColors.infoText,
      ),
      ExceptionKind.clock => (
        background: SgColors.dangerTint,
        foreground: SgColors.danger,
      ),
      _ => (background: SgColors.dangerTint, foreground: SgColors.danger),
    };

String exceptionDetail(AppLocalizations l10n, ExceptionRecord r) =>
    switch (r.kind) {
      ExceptionKind.missingOut => l10n.exception_detail_missingOut(
        r.inAt == null ? '' : formatHm(r.inAt!),
      ),
      ExceptionKind.manual => l10n.exception_detail_manual(
        r.actor ?? '',
        r.reason == null
            ? ''
            : manualReasonLabel(l10n, r.reason!).toLowerCase(),
      ),
      ExceptionKind.clock => l10n.exception_clock_detail(r.count ?? 0),
      _ => l10n.exception_detail_other,
    };

/// Exceptions (design 15): everything that needs a look before payroll.
class ExceptionsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entries = ref.watch(exceptionEntriesProvider);
    final filter = ref.watch(exceptionFilterProvider);
    final now = ref.watch(nowProvider);
    final gutter = context.sg.gutter;

    int count(ExceptionFilter f) => f == ExceptionFilter.all
        ? entries.length
        : entries.where((e) => filterOf(e.record.kind) == f).length;

    final chips = <SgOption<ExceptionFilter>>[
      SgOption(
        value: ExceptionFilter.all,
        label: l10n.exceptions_filter_all(count(ExceptionFilter.all)),
      ),
      if (count(ExceptionFilter.manual) > 0)
        SgOption(
          value: ExceptionFilter.manual,
          label: l10n.exceptions_filter_manual(count(ExceptionFilter.manual)),
        ),
      if (count(ExceptionFilter.missingOut) > 0)
        SgOption(
          value: ExceptionFilter.missingOut,
          label: l10n.exceptions_filter_missingOut(
            count(ExceptionFilter.missingOut),
          ),
        ),
      if (count(ExceptionFilter.clock) > 0)
        SgOption(
          value: ExceptionFilter.clock,
          label: l10n.exceptions_filter_clock(count(ExceptionFilter.clock)),
        ),
      if (count(ExceptionFilter.other) > 0)
        SgOption(
          value: ExceptionFilter.other,
          label: l10n.exceptions_filter_other(count(ExceptionFilter.other)),
        ),
    ];
    final shown = entries
        .where(
          (e) =>
              filter == ExceptionFilter.all ||
              filterOf(e.record.kind) == filter,
        )
        .toList();

    return SgScaffold(
      topBar: SgTopBar(
        title: l10n.exceptions_title,
        largeTitle: true,
        leading: SgLeading.back,
        leadingLabel: l10n.today_title,
        onLeading: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(Routes.today);
          }
        },
      ),
      body: entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      SgIcons.checkCircle,
                      size: 72,
                      color: SgColors.successText,
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.exceptions_empty, style: SgText.title),
                    const SizedBox(height: 8),
                    Text(
                      l10n.exceptions_emptySub,
                      style: SgText.body.copyWith(color: SgColors.muted),
                    ),
                  ],
                ),
              ),
            )
          : SgScrollColumn(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 32),
              children: [
                SgChoiceChips<ExceptionFilter>(
                  options: chips,
                  selected: filter,
                  onSelected: ref.read(exceptionFilterProvider.notifier).select,
                ),
                const SizedBox(height: 12),
                for (final e in shown) ...[
                  _ExceptionCard(
                    entry: e,
                    now: now,
                    onTap: () => unawaited(_open(context, ref, e)),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    ExceptionEntry entry,
  ) async {
    final session = ref.read(adminSessionProvider);
    final canCorrect = canDo(session, Capability.corrections);
    if (!canCorrect) return;
    if (entry.record.kind == ExceptionKind.missingOut && entry.worker != null) {
      await showSgSheet<bool>(
        context,
        builder: (_) =>
            CorrectRecordSheet(record: entry.record, worker: entry.worker!),
      );
    } else {
      await showSgSheet<bool>(
        context,
        builder: (_) => ReviewSheet(entry: entry),
      );
    }
  }
}

class _ExceptionCard extends StatelessWidget {
  const new({required this.entry, required this.now, required this.onTap});

  final ExceptionEntry entry;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final r = entry.record;
    final colors = tagColors(r.kind);
    final when = AttendanceRules.isSameDay(r.at, now)
        ? formatHm(r.at)
        : formatDayMonth(r.at);
    final title = r.kind == ExceptionKind.clock
        ? l10n.exception_clock_title(r.minutes ?? 0)
        : '${entry.worker?.name ?? ''} · ${entry.worker?.code ?? ''}';

    return SgCard(
      onTap: onTap,
      semanticLabel: '${exceptionTag(l10n, r.kind)}, $title',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SgStatusTag(
                label: exceptionTag(l10n, r.kind),
                background: colors.background,
                foreground: colors.foreground,
              ),
              Text(when, style: SgText.mono.copyWith(color: SgColors.muted)),
            ],
          ),
          const SizedBox(height: 10),
          Text(title, style: SgText.bodyStrong.copyWith(fontSize: 19)),
          const SizedBox(height: 2),
          Text(
            exceptionDetail(l10n, r),
            style: SgText.caption.copyWith(fontSize: 15),
          ),
        ],
      ),
    );
  }
}

/// Info sheet for exceptions that need no change (manual entries, clock
/// changes): what happened, and "Mark reviewed".
class ReviewSheet extends ConsumerWidget {
  const new({required this.entry, super.key});

  final ExceptionEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final r = entry.record;
    final title = r.kind == ExceptionKind.clock
        ? l10n.exception_clock_title(r.minutes ?? 0)
        : '${entry.worker?.name ?? ''} · ${entry.worker?.code ?? ''}';
    final colors = tagColors(r.kind);

    Future<void> confirm() async {
      final session = ref.read(adminSessionProvider);
      await ref
          .read(reviewExceptionProvider)
          .call(r, actor: session?.user.name ?? 'admin');
      if (context.mounted) {
        Navigator.of(context).pop(true);
        showSgToast(context, l10n.review_reviewed);
      }
    }

    return SgSheetFrame(
      title: l10n.review_title,
      cancelLabel: l10n.common_cancel,
      confirmLabel: l10n.review_markReviewed,
      onCancel: () => Navigator.of(context).pop(false),
      onConfirm: () => unawaited(confirm()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SgStatusTag(
            label: exceptionTag(l10n, r.kind),
            background: colors.background,
            foreground: colors.foreground,
          ),
          const SizedBox(height: 12),
          Text(title, style: SgText.title),
          const SizedBox(height: 4),
          Text(
            exceptionDetail(l10n, r),
            style: SgText.body.copyWith(color: SgColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatDate(r.at)}, ${formatHm(r.at)}',
            style: SgText.mono.copyWith(color: SgColors.muted),
          ),
        ],
      ),
    );
  }
}
