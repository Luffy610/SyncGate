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
import 'package:syncgate/src/features/enrolment/enrolment_draft.dart';

/// The notice text in one language, as plain sections (also read aloud).
List<(String title, String body)> noticeSections(AppLocalizations l10n) => [
  (l10n.notice_s1_title, l10n.notice_s1_body),
  (l10n.notice_s2_title, l10n.notice_s2_body),
  (l10n.notice_s3_title, l10n.notice_s3_body),
  (l10n.notice_s4_title, l10n.notice_s4_body),
];

/// Privacy notice and consent · step 2 of 3 (design 13). The notice is shown
/// in the worker's language and nothing proceeds until it is agreed.
class EnrolNoticeScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<EnrolNoticeScreen> createState() => _EnrolNoticeScreenState();
}

class _EnrolNoticeScreenState extends ConsumerState<EnrolNoticeScreen> {
  var _agreed = false;
  var _saving = false;

  Future<void> _agree() async {
    final form = ref.read(enrolmentProvider);
    final workerId = form.workerId;
    if (workerId == null) return;
    setState(() => _saving = true);
    final session = ref.read(adminSessionProvider);
    await ref
        .read(consentRepositoryProvider)
        .record(
          workerId: workerId,
          noticeVersion: noticeVersion,
          language: form.language,
          adminId: session?.user.id ?? 'unknown',
        );
    await ref
        .read(auditLogProvider)
        .append(
          AuditEntry(
            at: ref.read(clockProvider).now(),
            actor: session?.user.name ?? 'admin',
            action: 'consent.recorded',
            detail: '${form.code} $noticeVersion ${form.language.code}',
          ),
        );
    if (mounted) {
      setState(() => _saving = false);
      unawaited(context.push(Routes.enrolFace));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final form = ref.watch(enrolmentProvider);
    final mine = lookupAppLocalizations(
      Locale(form.language.isAvailable ? form.language.code : 'en'),
    );
    final gutter = context.sg.gutter;
    final showTo = l10n.notice_showTo(form.name);
    final nameAt = showTo.indexOf(form.name);

    return SgScaffold(
      topBar: SgTopBar(
        title: l10n.notice_title,
        leading: SgLeading.back,
        leadingLabel: l10n.common_back,
        onLeading: () => context.pop(),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: SgFlowSteps(
              current: 2,
              labels: [
                l10n.enrol_step_details,
                l10n.enrol_step_notice,
                l10n.enrol_step_face,
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: nameAt < 0
                          ? [TextSpan(text: showTo)]
                          : [
                              TextSpan(text: showTo.substring(0, nameAt)),
                              TextSpan(
                                text: form.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: SgColors.ink,
                                ),
                              ),
                              TextSpan(
                                text: showTo.substring(
                                  nameAt + form.name.length,
                                ),
                              ),
                            ],
                    ),
                    style: SgText.body.copyWith(color: SgColors.muted),
                  ),
                ),
                const SizedBox(width: 8),
                SgButton(
                  label: mine.notice_listen,
                  kind: SgButtonKind.outline,
                  icon: SgIcons.volume,
                  expand: false,
                  semanticLabel: mine.notice_listen,
                  onPressed: () => unawaited(
                    ref
                        .read(voiceProvider)
                        .readNotice(
                          [
                            mine.notice_content_title,
                            for (final (t, b) in noticeSections(mine)) '$t. $b',
                          ].join('\n'),
                          mine.localeName,
                        ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: Column(
                children: [
                  SgCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mine.notice_content_title,
                          key: const ValueKey('notice-title'),
                          style: SgText.title.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        for (final (title, body) in noticeSections(mine)) ...[
                          const SizedBox(height: 18),
                          Text(
                            title,
                            style: SgText.bodyStrong.copyWith(fontSize: 18),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            body,
                            style: SgText.body.copyWith(
                              color: const Color(0xFF3A3D3B),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SgCheckRow(
                    value: _agreed,
                    onChanged: (v) => setState(() => _agreed = v),
                    title: mine.notice_agree,
                    subtitle: l10n.notice_agreeSub,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          SgIcons.clock,
                          color: SgColors.muted,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.notice_saved(legalBasisPlaceholder),
                            style: SgText.caption.copyWith(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 16),
            child: SgButton(
              label: l10n.notice_continue,
              onPressed: _agreed && !_saving ? () => unawaited(_agree()) : null,
            ),
          ),
        ],
      ),
    );
  }
}
