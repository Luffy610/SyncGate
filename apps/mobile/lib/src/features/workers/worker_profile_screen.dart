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
import 'package:syncgate/src/features/common/consent_providers.dart';
import 'package:syncgate/src/features/enrolment/enrolment_draft.dart';
import 'package:syncgate/src/features/workers/workers_screen.dart';

/// Worker profile: details, face status, data held, and the actions the
/// current role may take (deactivate, delete, re-enrol). No design yet (D-1).
class WorkerProfileScreen extends ConsumerWidget {
  const new({required this.workerId, super.key});

  final String workerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final workers = ref.watch(workersProvider).value ?? const <Worker>[];
    final worker = workers.where((w) => w.id == workerId).firstOrNull;
    final session = ref.watch(adminSessionProvider);
    final now = ref.watch(nowProvider);
    final use24h = ref.watch(settingsProvider).value?.use24HourClock ?? false;
    final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
    final entries = ref.watch(workerEntriesProvider);
    final consent =
        ref.watch(consentedWorkersProvider).value?.contains(workerId) ?? false;
    final gutter = context.sg.gutter;

    void back() => context.go(Routes.workers);

    if (worker == null) {
      return SgScaffold(
        topBar: SgTopBar(
          title: l10n.workers_title,
          leading: SgLeading.back,
          leadingLabel: l10n.workers_title,
          onLeading: back,
        ),
        body: Center(child: Text(l10n.profile_notFound)),
      );
    }

    final entry = entries.where((e) => e.worker.id == workerId).firstOrNull;
    final status = entry == null
        ? null
        : statusLabel(l10n, entry, use24h: use24h);
    final shiftName =
        shifts.where((s) => s.id == worker.shiftId).firstOrNull?.name ?? '';
    final age = AttendanceRules.ageOn(worker.dateOfBirth, now);
    final canEnrol = canDo(session, Capability.enrolWorkers);
    final canDelete = canDo(session, Capability.deleteWorker);

    return SgScaffold(
      topBar: SgTopBar(
        title: worker.name,
        leading: SgLeading.back,
        leadingLabel: l10n.workers_title,
        onLeading: back,
      ),
      body: SgScrollColumn(
        padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
        children: [
          Row(
            children: [
              SgAvatarInitials(name: worker.name, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      worker.code,
                      style: SgText.mono.copyWith(fontSize: 18),
                    ),
                    if (status != null)
                      Text(
                        status.text,
                        style: SgText.bodyStrong.copyWith(color: status.color),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Header(l10n.profile_section_details),
          SgCardList(
            children: [
              SgListRow(
                title: l10n.enrol_field_department,
                trailingText: worker.department,
              ),
              SgListRow(
                title: l10n.enrol_field_designation,
                trailingText: worker.designation,
              ),
              SgListRow(title: l10n.enrol_field_shift, trailingText: shiftName),
              SgListRow(
                title: l10n.enrol_field_contractor,
                trailingText: worker.contractor ?? l10n.common_none,
              ),
              SgListRow(
                title: l10n.enrol_field_phone,
                trailingText: worker.phone ?? l10n.common_none,
              ),
              SgListRow(
                title: l10n.enrol_field_language,
                trailingText: worker.language.nativeName,
              ),
              SgListRow(
                title: l10n.enrol_field_dob,
                trailingText:
                    '${formatDate(worker.dateOfBirth)} · '
                    '${l10n.profile_age(age)}',
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Header(l10n.profile_section_face),
          SgCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      worker.faceStatus == FaceStatus.enrolled
                          ? SgIcons.checkCircle
                          : SgIcons.warning,
                      color: worker.faceStatus == FaceStatus.enrolled
                          ? SgColors.successText
                          : SgColors.warningIcon,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        worker.faceStatus == FaceStatus.enrolled
                            ? l10n.profile_face_enrolled
                            : l10n.profile_face_needs,
                        style: SgText.bodyStrong,
                      ),
                    ),
                  ],
                ),
                if (canEnrol) ...[
                  const SizedBox(height: 12),
                  SgButton(
                    label: worker.faceStatus == FaceStatus.enrolled
                        ? l10n.profile_reenrol
                        : l10n.profile_captureFace,
                    kind: SgButtonKind.secondary,
                    onPressed: () =>
                        unawaited(_enrolFace(context, ref, worker, consent)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          _Header(l10n.profile_section_data),
          SgCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.profile_dataSummary,
                  style: SgText.body.copyWith(color: SgColors.muted),
                ),
                const SizedBox(height: 8),
                Text(
                  consent ? l10n.profile_consent : l10n.profile_noConsent,
                  style: SgText.bodyStrong,
                ),
              ],
            ),
          ),
          if (canEnrol) ...[
            const SizedBox(height: 20),
            SgCardList(
              children: [
                SgListRow(
                  title: worker.active
                      ? l10n.profile_deactivate
                      : l10n.profile_reactivate,
                  onTap: () => unawaited(_toggleActive(context, ref, worker)),
                ),
                if (canDelete)
                  SgListRow(
                    title: l10n.profile_delete,
                    danger: true,
                    onTap: () => unawaited(_delete(context, ref, worker)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _enrolFace(
    BuildContext context,
    WidgetRef ref,
    Worker worker,
    bool consent,
  ) async {
    await ref.read(enrolmentProvider.notifier).startFor(worker);
    if (!context.mounted) return;
    unawaited(context.push(consent ? Routes.enrolFace : Routes.enrolNotice));
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    Worker worker,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (worker.active) {
      final ok = await showSgConfirm(
        context,
        title: l10n.profile_deactivate_title(worker.name),
        message: l10n.profile_deactivate_message,
        confirmLabel: l10n.profile_deactivate,
        cancelLabel: l10n.common_cancel,
        destructive: true,
      );
      if (!ok) return;
    }
    await ref
        .read(workerRepositoryProvider)
        .setActive(worker.id, active: !worker.active);
    await _audit(
      ref,
      worker.active ? 'worker.deactivated' : 'worker.reactivated',
      worker,
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Worker worker,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showSgConfirm(
      context,
      title: l10n.profile_delete_title(worker.name),
      message: l10n.profile_delete_message,
      confirmLabel: l10n.profile_delete_confirm,
      cancelLabel: l10n.common_cancel,
      destructive: true,
    );
    if (!ok) return;
    await ref.read(workerRepositoryProvider).delete(worker.id);
    await _audit(ref, 'worker.deleted', worker);
    if (context.mounted) context.go(Routes.workers);
  }

  Future<void> _audit(WidgetRef ref, String action, Worker worker) async {
    final session = ref.read(adminSessionProvider);
    await ref
        .read(auditLogProvider)
        .append(
          AuditEntry(
            at: ref.read(clockProvider).now(),
            actor: session?.user.name ?? 'admin',
            action: action,
            detail: worker.code,
          ),
        );
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
