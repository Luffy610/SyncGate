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

/// A worker and where they stand today.
typedef WorkerEntry = ({Worker worker, WorkerDayStatus status});

/// Every worker with today's status, needs-face first, then by name.
final workerEntriesProvider = Provider<List<WorkerEntry>>((ref) {
  final workers = ref.watch(workersProvider).value ?? const <Worker>[];
  final events = ref.watch(todayEventsProvider).value ?? const [];
  final entries =
      [
        for (final w in workers)
          (worker: w, status: TodayCalculator.statusOf(w, events)),
      ]..sort((a, b) {
        final aNeeds = a.status is StatusNeedsFace ? 0 : 1;
        final bNeeds = b.status is StatusNeedsFace ? 0 : 1;
        if (aNeeds != bNeeds) return aNeeds - bNeeds;
        return a.worker.name.compareTo(b.worker.name);
      });
  return entries;
});

enum WorkersFilter { all, notIn, needsFace }

class WorkersFilterController extends Notifier<WorkersFilter> {
  @override
  WorkersFilter build() => WorkersFilter.all;

  // ignore: use_setters_to_change_properties, a Notifier method is clearer.
  void select(WorkersFilter filter) => state = filter;
}

final workersFilterProvider =
    NotifierProvider<WorkersFilterController, WorkersFilter>(
      WorkersFilterController.new,
    );

/// Status text and colour for a row, shared with the worker profile.
({String text, Color color}) statusLabel(
  AppLocalizations l10n,
  WorkerEntry entry, {
  required bool use24h,
}) {
  if (!entry.worker.active) {
    return (text: l10n.workers_status_inactive, color: SgColors.muted);
  }
  return switch (entry.status) {
    StatusNeedsFace() => (
      text: l10n.workers_status_needsFace,
      color: SgColors.warningText,
    ),
    StatusIn(:final at) => (
      text: l10n.workers_status_in(formatHm(at)),
      color: SgColors.successText,
    ),
    StatusOut(:final at) => (
      text: l10n.workers_status_out(formatHm(at)),
      color: SgColors.infoText,
    ),
    StatusOnLeave() => (
      text: l10n.workers_status_onLeave,
      color: SgColors.muted,
    ),
    StatusNotIn() => (text: l10n.workers_status_notIn, color: SgColors.muted),
  };
}

/// Workers tab (design 11).
class WorkersScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends ConsumerState<WorkersScreen> {
  final _search = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(adminSessionProvider);
    final entries = ref.watch(workerEntriesProvider);
    final filter = ref.watch(workersFilterProvider);
    final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
    final use24h = ref.watch(settingsProvider).value?.use24HourClock ?? false;
    final gutter = context.sg.gutter;

    final notIn = entries.where((e) => e.status is StatusNotIn).length;
    final needsFace = entries.where((e) => e.status is StatusNeedsFace).length;

    final query = _query.trim().toLowerCase();
    final shown = entries.where((e) {
      final matchesFilter = switch (filter) {
        WorkersFilter.all => true,
        WorkersFilter.notIn => e.status is StatusNotIn,
        WorkersFilter.needsFace => e.status is StatusNeedsFace,
      };
      final matchesQuery =
          query.isEmpty ||
          e.worker.name.toLowerCase().contains(query) ||
          e.worker.code.toLowerCase().contains(query);
      return matchesFilter && matchesQuery;
    }).toList();

    String shiftName(String id) =>
        shifts.where((s) => s.id == id).firstOrNull?.name ?? '';

    return SgScaffold(
      topBar: SgTopBar(title: l10n.workers_title, largeTitle: true),
      primaryAction: canDo(session, Capability.enrolWorkers)
          ? SgPrimaryActionSpec(
              label: l10n.today_enrol,
              onTap: () => unawaited(context.push(Routes.enrolDetails)),
            )
          : null,
      body: entries.isEmpty
          ? _Empty(
              title: l10n.workers_empty,
              subtitle: l10n.workers_emptySub,
              action: canDo(session, Capability.enrolWorkers)
                  ? SgButton(
                      label: l10n.today_enrol,
                      expand: false,
                      onPressed: () =>
                          unawaited(context.push(Routes.enrolDetails)),
                    )
                  : null,
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 96),
              children: [
                SgSearchField(
                  hint: l10n.workers_search,
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 12),
                SgChoiceChips<WorkersFilter>(
                  selected: filter,
                  onSelected: ref.read(workersFilterProvider.notifier).select,
                  options: [
                    SgOption(
                      value: WorkersFilter.all,
                      label: l10n.workers_filter_all(entries.length),
                    ),
                    SgOption(
                      value: WorkersFilter.notIn,
                      label: l10n.workers_filter_notIn(notIn),
                    ),
                    SgOption(
                      value: WorkersFilter.needsFace,
                      label: l10n.workers_filter_needsFace(needsFace),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        l10n.workers_noMatch,
                        style: SgText.body.copyWith(color: SgColors.muted),
                      ),
                    ),
                  )
                else
                  SgCardList(
                    children: [
                      for (final e in shown)
                        _WorkerRow(
                          entry: e,
                          shift: shiftName(e.worker.shiftId),
                          use24h: use24h,
                          onTap: () => context.go(Routes.worker(e.worker.id)),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }
}

class _WorkerRow extends StatelessWidget {
  const new({
    required this.entry,
    required this.shift,
    required this.use24h,
    required this.onTap,
  });

  final WorkerEntry entry;
  final String shift;
  final bool use24h;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final w = entry.worker;
    final status = statusLabel(l10n, entry, use24h: use24h);
    return SgTap(
      onTap: onTap,
      radius: 0,
      minSize: 64,
      semanticLabel:
          '${w.name}, ${l10n.workers_row_sub(w.code, w.department, shift)}, '
          '${status.text}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SgAvatarInitials(name: w.name),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SgText.bodyStrong.copyWith(fontSize: 18),
                  ),
                  Text(
                    l10n.workers_row_sub(w.code, w.department, shift),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SgText.caption.copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              status.text,
              style: SgText.bodyStrong.copyWith(
                color: status.color,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const new({required this.title, required this.subtitle, this.action});

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(SgIcons.people, size: 72, color: SgColors.muted),
            const SizedBox(height: 16),
            Text(title, style: SgText.title),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: SgText.body.copyWith(color: SgColors.muted),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
