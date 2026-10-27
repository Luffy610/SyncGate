import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/providers.dart';

/// Licence state as an inline banner (ADR-0014 §2). Nothing for an active
/// licence. Export and backup are never disabled by licence state.
class LicenceBanner extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(licenceStatusProvider).value;
    final now = ref.watch(nowProvider);
    if (status == null) return const SizedBox.shrink();

    final (kind, text) = switch (status.state) {
      LicenceState.trial => (
        SgBannerKind.info,
        l10n.licence_banner_trial(
          (status.expiresOn?.difference(now).inDays ?? 0).clamp(0, 365),
        ),
      ),
      LicenceState.graceOverdue => (
        SgBannerKind.warning,
        l10n.licence_banner_overdue,
      ),
      LicenceState.restricted => (
        SgBannerKind.warning,
        l10n.licence_banner_restricted,
      ),
      LicenceState.revoked => (
        SgBannerKind.danger,
        l10n.licence_banner_revoked,
      ),
      LicenceState.none || LicenceState.active => (null, ''),
    };
    if (kind == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SgBanner(kind: kind, title: text),
    );
  }
}
