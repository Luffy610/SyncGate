import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_platform/sg_platform.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/features/setup/setup_scaffold.dart';

/// Step 5: lock the phone into SyncGate (design 08): Android app pinning, or
/// iOS Guided Access (ADR-0004 §4).
class KioskStep extends ConsumerWidget {
  const new({super.key});

  static const step = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ios = ref.watch(platformProvider) == TargetPlatform.iOS;
    final locked = ref.watch(kioskStateProvider).value == KioskState.locked;
    final kiosk = ref.read(kioskProvider);

    final steps = ios
        ? [
            (l10n.setup_kiosk_iosStep1, l10n.setup_kiosk_iosStep1Sub),
            (l10n.setup_kiosk_iosStep2, l10n.setup_kiosk_iosStep2Sub),
            (l10n.setup_kiosk_iosStep3, l10n.setup_kiosk_iosStep3Sub),
          ]
        : [
            (l10n.setup_kiosk_step1, l10n.setup_kiosk_step1Sub),
            (l10n.setup_kiosk_step2, l10n.setup_kiosk_step2Sub),
            (l10n.setup_kiosk_step3, l10n.setup_kiosk_step3Sub),
          ];

    final status = locked
        ? (ios ? l10n.setup_kiosk_statusOnIos : l10n.setup_kiosk_statusOn)
        : (ios ? l10n.setup_kiosk_statusOffIos : l10n.setup_kiosk_statusOff);

    VoidCallback goNext() =>
        () => unawaited(SetupNav.next(context, ref, step));

    final actions = <Widget>[
      if (locked)
        SgButton(label: l10n.common_continue, onPressed: goNext())
      else if (ios)
        SgButton(
          label: l10n.setup_kiosk_openSettings,
          onPressed: () => unawaited(kiosk.openSettings()),
        )
      else
        SgButton(
          label: l10n.setup_kiosk_pinNow,
          onPressed: () => unawaited(kiosk.startPinning()),
        ),
      if (!locked && !ios)
        SgButton(
          label: l10n.setup_kiosk_openSettings,
          kind: SgButtonKind.text,
          onPressed: () => unawaited(kiosk.openSettings()),
        ),
      if (!locked)
        SgButton(
          label: l10n.setup_kiosk_skip,
          kind: SgButtonKind.text,
          onPressed: goNext(),
        ),
    ];

    return SetupScaffold(
      step: step,
      title: l10n.setup_kiosk_title,
      body: l10n.setup_kiosk_body,
      actions: actions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PhoneIllustration(),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.setup_kiosk_howTo.toUpperCase(), style: SgText.label),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: locked ? SgColors.successTint : SgColors.warningBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: locked
                            ? SgColors.successText
                            : SgColors.warningIcon,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      status,
                      style: SgText.bodyStrong.copyWith(
                        color: locked
                            ? SgColors.successText
                            : SgColors.warningText,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SgCardList(
            children: [
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: SgColors.ink,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: SgText.bodyStrong.copyWith(
                            color: SgColors.white,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              steps[i].$1,
                              style: SgText.bodyStrong.copyWith(fontSize: 17),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              steps[i].$2,
                              style: SgText.body.copyWith(
                                color: SgColors.muted,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhoneIllustration extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        height: 104,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFE9E7E1),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 80,
                decoration: BoxDecoration(
                  color: SgColors.ink,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(child: SgLogo(size: 24)),
              ),
              Positioned(
                top: -6,
                right: -10,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: SgColors.brandYellow,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    SgIcons.lock,
                    size: 14,
                    color: SgColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
