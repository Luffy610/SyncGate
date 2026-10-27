import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/app/routes.dart';
import 'package:syncgate/src/application/attendance_use_cases.dart';
import 'package:syncgate/src/features/gate/gate_controller.dart';
import 'package:syncgate/src/features/gate/gate_copy.dart';
import 'package:syncgate/src/features/gate/gate_screen.dart';

typedef ManualCandidate = ({Worker worker, Direction direction});

/// Workers the guard can pick right now, sorted by name.
final manualCandidatesProvider = Provider<List<ManualCandidate>>((ref) {
  final workers = ref.watch(workersProvider).value ?? const <Worker>[];
  final events = ref.watch(todayEventsProvider).value ?? const [];
  final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
  return TodayCalculator.manualCandidates(
    workers: workers,
    events: events,
    shifts: shifts,
    now: ref.watch(nowProvider),
    shiftId: ref.watch(currentShiftProvider)?.id,
  );
});

@immutable
class ManualEntryState {
  const new({
    this.query = '',
    this.selectedWorkerId,
    this.reason,
    this.saving = false,
    this.limitReachedFor,
  });

  final String query;
  final String? selectedWorkerId;
  final ManualReason? reason;
  final bool saving;

  /// Set when the daily limit blocked the save.
  final String? limitReachedFor;

  bool get canSave => selectedWorkerId != null && reason != null && !saving;

  ManualEntryState copyWith({
    String? query,
    String? selectedWorkerId,
    ManualReason? reason,
    bool? saving,
    String? limitReachedFor,
    bool clearLimit = false,
  }) => ManualEntryState(
    query: query ?? this.query,
    selectedWorkerId: selectedWorkerId ?? this.selectedWorkerId,
    reason: reason ?? this.reason,
    saving: saving ?? this.saving,
    limitReachedFor: clearLimit
        ? null
        : limitReachedFor ?? this.limitReachedFor,
  );
}

class ManualEntryController extends Notifier<ManualEntryState> {
  @override
  ManualEntryState build() => const ManualEntryState();

  void search(String query) => state = state.copyWith(query: query);

  void select(String workerId) =>
      state = state.copyWith(selectedWorkerId: workerId, clearLimit: true);

  void setReason(ManualReason reason) =>
      state = state.copyWith(reason: reason, clearLimit: true);

  /// Saves the mark. Returns the stored mark, or `null` if it failed (the
  /// state then carries the reason).
  Future<Marked?> save() async {
    if (!state.canSave) return null;
    final id = state.selectedWorkerId!;
    state = state.copyWith(saving: true);
    final session = ref.read(adminSessionProvider);
    final actor =
        session?.user.name ??
        (await ref.read(settingsRepositoryProvider).load()).gateOperatorId;
    final result = await ref
        .read(markManualAttendanceProvider)
        .call(workerId: id, reason: state.reason!, actor: actor);
    switch (result) {
      case Ok(:final value):
        state = state.copyWith(saving: false);
        return value;
      case Err(failure: ManualLimitReached()):
        state = state.copyWith(saving: false, limitReachedFor: id);
      case Err():
        state = state.copyWith(saving: false);
    }
    return null;
  }
}

final NotifierProvider<ManualEntryController, ManualEntryState>
manualEntryProvider =
    NotifierProvider.autoDispose<ManualEntryController, ManualEntryState>(
      ManualEntryController.new,
    );

/// Guard fallback (design 04): pick the worker, give a reason, save.
class ManualEntryScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.homeFor(ref.read(appModeProvider)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = ref.watch(platformProvider);
    return SgGateScope(
      platform: platform,
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(manualEntryProvider);
    final controller = ref.read(manualEntryProvider.notifier);
    final all = ref.watch(manualCandidatesProvider);
    final settings = ref.watch(settingsProvider).value;
    final session = ref.watch(adminSessionProvider);
    final operator = session?.user.name ?? settings?.gateOperatorId ?? 'G-02';

    final query = state.query.trim().toLowerCase();
    final shown = all
        .where(
          (c) =>
              query.isEmpty ||
              c.worker.name.toLowerCase().contains(query) ||
              c.worker.code.toLowerCase().contains(query),
        )
        .toList();
    final selected = all
        .where((c) => c.worker.id == state.selectedWorkerId)
        .firstOrNull;

    final saveLabel = selected == null
        ? l10n.gate_manual_saveEmpty
        : l10n.gate_manual_save(
            directionLabel(l10n, selected.direction),
            selected.worker.firstName,
          );

    return SgScaffold(
      dark: true,
      body: Column(
        children: [
          const GateHeaderBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.gate_manual_title,
                        style: SgText.heading.copyWith(
                          color: SgColors.white,
                          fontSize: 26,
                        ),
                      ),
                      Text(
                        l10n.gate_manual_subtitle(operator),
                        style: SgText.caption.copyWith(
                          color: SgColors.gateMuted,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A2E10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF5A4818)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        SgIcons.flag,
                        size: 18,
                        color: SgColors.brandYellow,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.gate_manual_flagged,
                        style: SgText.bodyStrong.copyWith(
                          color: SgColors.brandYellow,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SgSearchField(
              hint: l10n.gate_manual_search,
              controller: _search,
              onChanged: controller.search,
              dark: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.gate_manual_notMarked(all.length).toUpperCase(),
                style: SgText.label.copyWith(color: SgColors.gateMuted),
              ),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      l10n.gate_manual_empty,
                      style: SgText.body.copyWith(color: SgColors.gateMuted),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (final c in shown) ...[
                          _WorkerRow(
                            worker: c.worker,
                            selected: c.worker.id == state.selectedWorkerId,
                            onTap: () => controller.select(c.worker.id),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ],
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.gate_manual_reasonHeader.toUpperCase(),
                style: SgText.label.copyWith(color: SgColors.gateMuted),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SgChoiceChips<ManualReason>(
              dark: true,
              selected: state.reason,
              onSelected: controller.setReason,
              options: [
                for (final r in ManualReason.values)
                  SgOption(value: r, label: manualReasonLabel(l10n, r)),
              ],
            ),
          ),
          if (state.limitReachedFor != null && selected != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SgBanner(
                kind: SgBannerKind.danger,
                title: l10n.gate_manual_limit(selected.worker.name),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SgButton(
                  label: l10n.common_cancel,
                  kind: SgButtonKind.gateOutline,
                  large: true,
                  expand: false,
                  onPressed: _leave,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SgButton(
                    label: saveLabel,
                    kind: SgButtonKind.brand,
                    large: true,
                    onPressed: state.canSave
                        ? () async {
                            final marked = await controller.save();
                            if (marked != null && context.mounted) {
                              showSgToast(
                                context,
                                l10n.gate_manual_saved(
                                  marked.worker.name,
                                  directionLabel(l10n, marked.event.direction),
                                ),
                              );
                              _leave();
                            }
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerRow extends StatelessWidget {
  const new({
    required this.worker,
    required this.selected,
    required this.onTap,
  });

  final Worker worker;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF2B2310) : SgColors.gateCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? SgColors.brandYellow : SgColors.gateLine,
          width: selected ? 2 : 1,
        ),
      ),
      child: SgTap(
        onTap: onTap,
        selected: selected,
        radius: 16,
        semanticLabel: '${worker.name}, ${worker.code}, ${worker.department}',
        minSize: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              SgAvatarInitials(
                name: worker.name,
                size: 36,
                background: const Color(0xFF2B2F36),
                foreground: SgColors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      worker.name,
                      style: SgText.bodyStrong.copyWith(
                        color: SgColors.white,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${worker.code} · ${worker.department}',
                      style: SgText.caption.copyWith(
                        color: SgColors.gateMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(SgIcons.check, color: SgColors.brandYellow),
            ],
          ),
        ),
      ),
    );
  }
}
