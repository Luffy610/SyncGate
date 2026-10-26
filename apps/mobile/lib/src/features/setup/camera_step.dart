import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:sg_vision/sg_vision.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/features/setup/setup_scaffold.dart';

/// Step 4: live preview and light check (design 07). Continue is allowed
/// even with warnings.
class CameraStep extends ConsumerStatefulWidget {
  const new({super.key});

  static const step = 4;

  @override
  ConsumerState<CameraStep> createState() => _CameraStepState();
}

class _CameraStepState extends ConsumerState<CameraStep> {
  late final CameraCheckService _camera;
  int? _texture;
  CameraReading? _reading;
  var _checking = false;

  @override
  void initState() {
    super.initState();
    _camera = ref.read(cameraCheckProvider);
    unawaited(_start());
  }

  Future<void> _start() async {
    final texture = await _camera.start();
    if (!mounted) return;
    setState(() => _texture = texture);
    await _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final reading = await _camera.check();
    if (!mounted) return;
    setState(() {
      _reading = reading;
      _checking = false;
    });
  }

  @override
  void dispose() {
    unawaited(_camera.stop());
    super.dispose();
  }

  Future<void> _setFillLight({required bool on}) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.save((await repo.load()).copyWith(screenFillLight: on));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reading = _reading;
    final fillLight =
        ref.watch(settingsProvider).value?.screenFillLight ?? true;
    final texture = _texture;

    return SetupScaffold(
      step: CameraStep.step,
      title: l10n.setup_camera_title,
      body: l10n.setup_camera_body,
      actions: [
        Row(
          children: [
            Expanded(
              child: SgButton(
                label: _checking
                    ? l10n.setup_camera_checking
                    : l10n.setup_camera_checkAgain,
                kind: SgButtonKind.secondary,
                onPressed: _checking ? null : () => unawaited(_check()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SgButton(
                label: l10n.common_continue,
                onPressed: () =>
                    unawaited(SetupNav.next(context, ref, CameraStep.step)),
              ),
            ),
          ],
        ),
      ],
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1.72,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: ColoredBox(
                color: SgColors.gatePanel,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (texture != null && texture >= 0)
                      Texture(textureId: texture)
                    else
                      const SgFaceSilhouette(),
                    const SgDashedOval(),
                    Positioned(
                      top: 14,
                      left: 14,
                      child: SgDotPill(
                        label: l10n.setup_camera_live,
                        dot: SgColors.successOnDark,
                        background: SgColors.gateBg,
                      ),
                    ),
                    if (reading != null)
                      Positioned(
                        bottom: 14,
                        left: 14,
                        child: _LightChip(reading: reading),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (reading != null) _CheckCard(reading: reading),
          const SizedBox(height: 16),
          SgCard(
            padding: EdgeInsets.zero,
            child: SgSwitchRow(
              title: l10n.setup_camera_fillLight,
              subtitle: l10n.setup_camera_fillLightHelp,
              value: fillLight,
              onChanged: (on) => unawaited(_setFillLight(on: on)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LightChip extends StatelessWidget {
  const new({required this.reading});

  final CameraReading reading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ok = reading.lightOk;
    final lux = reading.lux.round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: ok ? SgColors.successTint : SgColors.warningBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            SgIcons.sun,
            size: 20,
            color: ok ? SgColors.successText : SgColors.warningIcon,
          ),
          const SizedBox(width: 8),
          Text(
            ok
                ? l10n.setup_camera_lightChipOk(lux)
                : l10n.setup_camera_lightChipLow(lux),
            style: SgText.bodyStrong.copyWith(
              color: ok ? SgColors.successText : SgColors.warningText,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckCard extends StatelessWidget {
  const new({required this.reading});

  final CameraReading reading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget statusRow(String label, String value, {required bool ok}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(
              ok ? SgIcons.checkCircle : SgIcons.warning,
              color: ok ? SgColors.successText : SgColors.warningIcon,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: SgText.bodyStrong.copyWith(fontSize: 18),
              ),
            ),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: SgText.body.copyWith(
                  color: SgColors.muted,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final lightOk = reading.lightOk;
    return SgCard(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      lightOk ? SgIcons.checkCircle : SgIcons.warning,
                      color: lightOk
                          ? SgColors.successText
                          : SgColors.warningIcon,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        l10n.setup_camera_light,
                        style: SgText.bodyStrong.copyWith(fontSize: 18),
                      ),
                    ),
                    Text(
                      lightOk
                          ? l10n.setup_camera_lightGood
                          : l10n.setup_camera_lightLow,
                      style: SgText.bodyStrong.copyWith(
                        color: lightOk
                            ? SgColors.successText
                            : SgColors.warningIcon,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 38),
                  child: SgProgressBar(
                    value: (reading.lux / 200).clamp(0, 1),
                    track: const Color(0xFFE9E7E1),
                  ),
                ),
                if (!lightOk)
                  Padding(
                    padding: const EdgeInsets.only(left: 38, top: 8),
                    child: Text(
                      l10n.setup_camera_lightAdvice,
                      style: SgText.body.copyWith(
                        color: SgColors.muted,
                        fontSize: 15,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SgDivider(),
          statusRow(
            l10n.setup_camera_backlight,
            reading.backlight
                ? l10n.setup_camera_backlightYes
                : l10n.setup_camera_backlightNone,
            ok: !reading.backlight,
          ),
          const SgDivider(),
          statusRow(
            l10n.setup_camera_lens,
            reading.lensClean
                ? l10n.setup_camera_lensClean
                : l10n.setup_camera_lensDirty,
            ok: reading.lensClean,
          ),
          const SgDivider(),
          statusRow(
            l10n.setup_camera_faceSize,
            reading.faceSizeOk
                ? l10n.setup_camera_faceSizeGood(reading.faceDistanceCm)
                : l10n.setup_camera_faceSizeBad,
            ok: reading.faceSizeOk,
          ),
        ],
      ),
    );
  }
}
