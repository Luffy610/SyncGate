import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_platform/sg_platform.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/features/setup/licence_key_format.dart';
import 'package:syncgate/src/features/setup/setup_scaffold.dart';

final deviceInfoProvider = FutureProvider<DeviceInfo>((ref) {
  return ref.watch(deviceCheckProvider).check();
});

/// Step 2: licence key or free trial (design 06).
class LicenceStep extends ConsumerStatefulWidget {
  const new({super.key});

  static const step = 2;

  @override
  ConsumerState<LicenceStep> createState() => _LicenceStepState();
}

class _LicenceStepState extends ConsumerState<LicenceStep> {
  final _controller = TextEditingController();
  var _busy = false;
  Failure? _failure;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await ref
        .read(licenceServiceProvider)
        .activate(_controller.text);
    if (!mounted) return;
    switch (result) {
      case Ok():
        await SetupNav.next(context, ref, LicenceStep.step);
      case Err(:final failure):
        setState(() => _failure = failure);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _startTrial() async {
    setState(() => _busy = true);
    await ref.read(licenceServiceProvider).startTrial();
    if (!mounted) return;
    await SetupNav.next(context, ref, LicenceStep.step);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _scan() async {
    final l10n = AppLocalizations.of(context);
    final text = await ref.read(qrScanProvider).scan();
    if (text == null || !mounted) return;
    setState(() {
      _controller.text = LicenceKeyFormatter.format(text, trailingDash: false);
      _failure = null;
    });
    showSgToast(context, l10n.setup_licence_scanned);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final complete = LicenceKeyFormatter.isComplete(_controller.text);
    final failure = _failure;

    return SetupScaffold(
      step: LicenceStep.step,
      title: l10n.setup_licence_title,
      body: l10n.setup_licence_body,
      actions: [
        SgButton(
          label: l10n.setup_licence_activate,
          onPressed: complete && !_busy ? () => unawaited(_activate()) : null,
        ),
        SgButton(
          label: l10n.setup_licence_trial,
          kind: SgButtonKind.text,
          underline: true,
          onPressed: _busy ? null : () => unawaited(_startTrial()),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SgTextField(
            label: l10n.setup_licence_keyLabel,
            controller: _controller,
            hint: 'SGT-XXXX-XXXX-XXXX',
            mono: true,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [LicenceKeyFormatter()],
            onChanged: (_) => setState(() => _failure = null),
          ),
          SgFieldNote(l10n.setup_licence_keyHelper),
          const SizedBox(height: 12),
          SgButton(
            label: l10n.setup_licence_scanQr,
            kind: SgButtonKind.outline,
            icon: SgIcons.qr,
            onPressed: () => unawaited(_scan()),
          ),
          if (failure != null) ...[
            const SizedBox(height: 16),
            SgBanner(
              kind: SgBannerKind.danger,
              title: failure is NoInternet
                  ? l10n.setup_licence_noInternet
                  : l10n.setup_licence_invalid,
              action: failure is NoInternet
                  ? SgButton(
                      label: l10n.setup_licence_trialInstead,
                      kind: SgButtonKind.secondary,
                      onPressed: () => unawaited(_startTrial()),
                    )
                  : null,
            ),
          ],
          const SizedBox(height: 20),
          const _DeviceCard(),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(SgIcons.offline, color: SgColors.muted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.setup_licence_offline,
                  style: SgText.body.copyWith(
                    color: SgColors.muted,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final info = ref.watch(deviceInfoProvider).value;
    if (info == null) return const SizedBox.shrink();

    Widget row(String label, String value, {required bool ok}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(
            ok ? SgIcons.checkCircle : SgIcons.warning,
            color: ok ? SgColors.successText : SgColors.warningIcon,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: SgText.body.copyWith(fontSize: 18)),
          ),
          Text(
            value,
            style: SgText.body.copyWith(color: SgColors.muted, fontSize: 18),
          ),
        ],
      ),
    );

    return SgCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.setup_device_title.toUpperCase(), style: SgText.label),
              Text(
                info.ready ? l10n.setup_device_ready : l10n.setup_device_limits,
                style: SgText.bodyStrong.copyWith(
                  color: info.ready
                      ? SgColors.successText
                      : SgColors.warningIcon,
                ),
              ),
            ],
          ),
          const SgDivider(),
          row(
            l10n.setup_device_camera,
            l10n.setup_device_cameraValue(info.cameraMegapixels),
            ok: info.cameraOk,
          ),
          const SgDivider(),
          row(
            l10n.setup_device_memory,
            l10n.setup_device_memoryValue(info.memoryGb),
            ok: info.memoryOk,
          ),
          const SgDivider(),
          row(l10n.setup_device_system, info.systemName, ok: true),
        ],
      ),
    );
  }
}
