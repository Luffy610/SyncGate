import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:sg_vision/sg_vision.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/app/routes.dart';
import 'package:syncgate/src/features/enrolment/capture_controller.dart';
import 'package:syncgate/src/features/enrolment/enrolment_draft.dart';

String _captureHint(AppLocalizations l10n, QualityIssue issue) =>
    switch (issue) {
      QualityIssue.tooDark => l10n.capture_hint_tooDark,
      QualityIssue.backlight => l10n.capture_hint_backlight,
      QualityIssue.tooFar => l10n.capture_hint_tooFar,
      QualityIssue.turnLess => l10n.capture_hint_turnLess,
      QualityIssue.blurry => l10n.capture_hint_blurry,
      QualityIssue.covered => l10n.capture_hint_covered,
      QualityIssue.dirtyLens => l10n.capture_hint_dirtyLens,
    };

String _angleLabel(AppLocalizations l10n, CaptureAngle angle) =>
    switch (angle) {
      CaptureAngle.front => l10n.capture_angle_front,
      CaptureAngle.left => l10n.capture_angle_left,
      CaptureAngle.right => l10n.capture_angle_right,
      CaptureAngle.mask => l10n.capture_angle_mask,
    };

String _instruction(AppLocalizations l10n, CaptureState state) {
  if (state.phase == CapturePhase.processing ||
      state.phase == CapturePhase.done) {
    return l10n.capture_processing;
  }
  return switch (state.angle) {
    CaptureAngle.front => l10n.capture_turn_front,
    CaptureAngle.left => l10n.capture_turn_left,
    CaptureAngle.right => l10n.capture_turn_right,
    CaptureAngle.mask => l10n.capture_turn_mask,
  };
}

/// Face capture · step 3 of 3 (design 14). Holds the idle timer so Admin does
/// not return to the gate mid-capture.
class EnrolFaceScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<EnrolFaceScreen> createState() => _EnrolFaceScreenState();
}

class _EnrolFaceScreenState extends ConsumerState<EnrolFaceScreen> {
  late final IdleHold _hold;
  CapturePhase _handledPhase = CapturePhase.capturing;

  @override
  void initState() {
    super.initState();
    _hold = ref.read(idleHoldProvider.notifier);
    unawaited(Future.microtask(_hold.hold));
  }

  @override
  void dispose() {
    unawaited(Future.microtask(_hold.release));
    super.dispose();
  }

  Future<void> _close() async {
    final l10n = AppLocalizations.of(context);
    final name = ref.read(enrolmentProvider).name;
    final stop = await showSgConfirm(
      context,
      title: l10n.capture_stop_title(name),
      message: l10n.capture_stop_message,
      confirmLabel: l10n.capture_stop_confirm,
      cancelLabel: l10n.capture_stop_keep,
      destructive: true,
    );
    if (!stop || !mounted) return;
    await ref.read(captureControllerProvider.notifier).cancel();
    if (mounted) context.go(Routes.workers);
  }

  Future<void> _onPhase(CapturePhase phase) async {
    if (phase == _handledPhase) return;
    _handledPhase = phase;
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(captureControllerProvider.notifier);
    if (phase == CapturePhase.done) {
      final name = ref.read(enrolmentProvider).name;
      showSgToast(context, l10n.capture_enrolled(name));
      context.go(Routes.workers);
    } else if (phase == CapturePhase.duplicate) {
      final other = ref.read(captureControllerProvider).duplicateOf;
      final override = await showSgConfirm(
        context,
        title: l10n.capture_duplicate_title(
          other?.name ?? '',
          other?.code ?? '',
        ),
        message: l10n.capture_duplicate_body,
        confirmLabel: l10n.capture_duplicate_override,
        cancelLabel: l10n.capture_duplicate_cancel,
        destructive: true,
      );
      if (!mounted) return;
      if (!override) {
        await controller.cancel();
        if (mounted) context.go(Routes.workers);
        return;
      }
      final reason = await showSgTextPrompt(
        context,
        title: l10n.capture_duplicate_reasonTitle,
        label: l10n.capture_duplicate_reasonLabel,
        confirmLabel: l10n.common_continue,
        cancelLabel: l10n.common_cancel,
      );
      if (!mounted) return;
      if (reason == null) {
        await controller.cancel();
        if (mounted) context.go(Routes.workers);
        return;
      }
      _handledPhase = CapturePhase.capturing;
      await controller.overrideDuplicate(reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final platform = ref.watch(platformProvider);
    final form = ref.watch(enrolmentProvider);
    final state = ref.watch(captureControllerProvider);
    final controller = ref.read(captureControllerProvider.notifier);
    ref.listen(captureControllerProvider.select((s) => s.phase), (_, phase) {
      unawaited(_onPhase(phase));
    });

    final mine = lookupAppLocalizations(
      Locale(form.language.isAvailable ? form.language.code : 'en'),
    );
    final texture = controller.textureId;
    final quality = state.quality;

    SgAngleStatus statusOf(CaptureAngle angle) {
      if (state.done.contains(angle)) return SgAngleStatus.done;
      if (angle == CaptureAngle.mask) {
        return state.angle == CaptureAngle.mask
            ? SgAngleStatus.now
            : SgAngleStatus.optional;
      }
      return angle == state.angle ? SgAngleStatus.now : SgAngleStatus.pending;
    }

    String captionOf(CaptureAngle angle) => switch (statusOf(angle)) {
      SgAngleStatus.done => l10n.capture_status_done,
      SgAngleStatus.now => l10n.capture_status_now,
      SgAngleStatus.pending => l10n.capture_status_next,
      SgAngleStatus.optional => l10n.common_optional,
    };

    final secondary = mine.localeName == l10n.localeName
        ? null
        : _instruction(mine, state);

    return SgGateScope(
      platform: platform,
      child: SgScaffold(
        dark: true,
        topBar: SgTopBar(
          title: form.name,
          dark: true,
          leading: SgLeading.close,
          leadingLabel: l10n.common_cancel,
          onLeading: () => unawaited(_close()),
          trailingText: l10n.capture_step,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 0.86,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(SgRadius.gatePanel),
                  child: ColoredBox(
                    color: SgColors.gatePanel,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (texture != null && texture >= 0)
                          Texture(textureId: texture)
                        else
                          const SgFaceSilhouette(),
                        SgCaptureRing(progress: state.progress),
                        if (quality != null)
                          Positioned(
                            top: 12,
                            left: 12,
                            right: 12,
                            child: Semantics(
                              liveRegion: true,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: SgColors.warningBg,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      SgIcons.sun,
                                      color: SgColors.warningText,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _captureHint(l10n, quality),
                                        style: SgText.bodyStrong.copyWith(
                                          color: SgColors.warningText,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Column(
                  children: [
                    Text(
                      _instruction(l10n, state),
                      textAlign: TextAlign.center,
                      style: SgText.title.copyWith(
                        color: SgColors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 24,
                      ),
                    ),
                    if (secondary != null)
                      Text(
                        secondary,
                        textAlign: TextAlign.center,
                        style: SgText.body.copyWith(
                          color: SgColors.gateMuted,
                          fontSize: 17,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final angle in CaptureAngle.values) ...[
                    if (angle != CaptureAngle.front) const SizedBox(width: 8),
                    Expanded(
                      child: SgAngleTile(
                        label: _angleLabel(l10n, angle),
                        caption: captionOf(angle),
                        status: statusOf(angle),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    SgIcons.shield,
                    color: SgColors.successOnDark,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.capture_privacy,
                      style: SgText.body.copyWith(
                        color: SgColors.gateMuted,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SgButton(
                label: l10n.capture_skipMask,
                kind: SgButtonKind.gateOutline,
                expand: false,
                onPressed:
                    state.phase == CapturePhase.capturing && !state.maskSkipped
                    ? () => unawaited(controller.skipMask())
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
