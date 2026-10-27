import 'package:flutter/widgets.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/features/gate/gate_controller.dart';
import 'package:syncgate/src/features/gate/gate_copy.dart';

/// Camera panel while scanning (design 01): preview, liveness pill, yellow
/// frame brackets and an optional quality hint.
class ScanningPanel extends StatelessWidget {
  const new({required this.state, super.key});

  final GateViewState state;

  @override
  Widget build(BuildContext context) {
    final copy = GateCopy.of(context);
    final texture = state.textureId;
    final hint = state.hint;

    return Column(
      children: [
        Expanded(
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
                  const SgScanFrame(),
                  Positioned(
                    top: 16,
                    left: 16,
                    child: SgDotPill(
                      label: copy.primary.gate_liveness_on,
                      dot: SgColors.successOnDark,
                      background: SgColors.gateBg,
                    ),
                  ),
                  if (hint != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: SgColors.warningBg,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            qualityHintText(copy.primary, hint),
                            textAlign: TextAlign.center,
                            style: SgText.bodyStrong.copyWith(
                              color: SgColors.warningText,
                            ),
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
        _Prompt(copy: copy),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _Prompt extends StatelessWidget {
  const new({required this.copy});

  final GateCopy copy;

  @override
  Widget build(BuildContext context) {
    final primary = copy.primary;
    final english = copy.english;
    final second = copy.bilingual
        ? '${english.gate_scan_prompt} · ${english.gate_scan_hint}'
        : primary.gate_scan_hint;
    return Semantics(
      liveRegion: true,
      label: '${primary.gate_scan_prompt}. $second',
      child: ExcludeSemantics(
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                primary.gate_scan_prompt,
                textAlign: TextAlign.center,
                style: SgText.gatePrompt.copyWith(color: SgColors.white),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                second,
                textAlign: TextAlign.center,
                style: SgText.gatePromptSecondary.copyWith(
                  color: const Color(0xFFD5D8DB),
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Green confirmation panel (design 02).
class MatchedPanel extends StatelessWidget {
  const new({
    required this.worker,
    required this.direction,
    required this.at,
    required this.onTime,
    required this.use24h,
    super.key,
  });

  final Worker worker;
  final Direction direction;
  final DateTime at;
  final bool onTime;
  final bool use24h;

  @override
  Widget build(BuildContext context) {
    final copy = GateCopy.of(context);
    final mine = workerCopy(worker);
    final isIn = direction == Direction.checkIn;
    final label = directionLabel(copy.primary, direction);
    final time = formatTime(at, use24h: use24h, padHour: true);
    final greeting = isIn
        ? mine.gate_matched_greetingIn(worker.firstName)
        : mine.gate_matched_greetingOut(worker.firstName);
    final timing = onTime
        ? copy.primary.gate_matched_onTime
        : copy.primary.gate_matched_late;
    final status = isIn ? ' · $timing' : '';
    final spoken = isIn
        ? mine.gate_voice_in(worker.firstName)
        : mine.gate_voice_out(worker.firstName);

    return Semantics(
      liveRegion: true,
      label: '$label $time, ${worker.name}, $greeting',
      child: ExcludeSemantics(
        child: SgGatePanel(
          color: SgColors.successFill,
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: SgColors.white, width: 5),
                    ),
                    child: const Icon(
                      SgIcons.check,
                      color: SgColors.white,
                      size: 54,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: SgColors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$label · $time',
                      style: SgText.bodyStrong.copyWith(
                        color: const Color(0xFF0B5B33),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      worker.name,
                      textAlign: TextAlign.center,
                      style: SgText.gateName.copyWith(color: SgColors.white),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    greeting,
                    textAlign: TextAlign.center,
                    style: SgText.gatePromptSecondary.copyWith(
                      color: SgColors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${worker.code} · ${worker.department}$status',
                    textAlign: TextAlign.center,
                    style: SgText.body.copyWith(
                      color: const Color(0xFFE3F4EA),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(SgIcons.volume, color: Color(0xFFE3F4EA)),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          copy.primary.gate_voice_caption(spoken),
                          style: SgText.body.copyWith(
                            color: const Color(0xFFE3F4EA),
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Red panel with the retry countdown (design 03).
class NotRecognisedPanel extends StatelessWidget {
  const new({
    required this.state,
    required this.onTryAgain,
    required this.onPickWorker,
    super.key,
  });

  final GateViewState state;
  final VoidCallback onTryAgain;
  final VoidCallback onPickWorker;

  @override
  Widget build(BuildContext context) {
    final copy = GateCopy.of(context);
    final hint = qualityHintText(copy.primary, state.hint);
    final retry = copy.primary.gate_notRecognised_retry(state.retrySeconds);
    return SgGatePanel(
      color: SgColors.danger,
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                liveRegion: true,
                label: '${copy.primary.gate_notRecognised_title}. $hint',
                child: ExcludeSemantics(
                  child: Column(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: SgColors.white, width: 5),
                        ),
                        child: const Icon(
                          SgIcons.close,
                          color: SgColors.white,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          copy.primary.gate_notRecognised_title,
                          textAlign: TextAlign.center,
                          style: SgText.gatePrompt.copyWith(
                            color: SgColors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (copy.bilingual)
                        Text(
                          copy.english.gate_notRecognised_title,
                          textAlign: TextAlign.center,
                          style: SgText.gatePromptSecondary.copyWith(
                            color: SgColors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        '$hint $retry',
                        textAlign: TextAlign.center,
                        style: SgText.body.copyWith(
                          color: const Color(0xFFFBE4E1),
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SgButton(
                label: copy.primary.gate_notRecognised_tryAgain,
                kind: SgButtonKind.onColor,
                large: true,
                foreground: const Color(0xFF7A1A12),
                icon: SgIcons.refresh,
                onPressed: onTryAgain,
              ),
              const SizedBox(height: 12),
              SgButton(
                label: copy.primary.gate_notRecognised_pickWorker,
                kind: SgButtonKind.onColorOutline,
                large: true,
                onPressed: onPickWorker,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Neutral grey panel for a repeat mark inside the cooldown (FR-ATT-05).
class CooldownPanel extends StatelessWidget {
  const new({
    required this.worker,
    required this.direction,
    required this.at,
    required this.use24h,
    super.key,
  });

  final Worker? worker;
  final Direction? direction;
  final DateTime? at;
  final bool use24h;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = directionLabel(l10n, direction ?? Direction.checkIn);
    final time = at == null
        ? ''
        : formatTime(at!, use24h: use24h, padHour: true);
    final title = l10n.gate_cooldown_title(label, time);
    return Semantics(
      liveRegion: true,
      label: '${worker?.name ?? ''}. $title',
      child: ExcludeSemantics(
        child: SgGatePanel(
          color: const Color(0xFF3B4046),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: SgColors.gateMuted, width: 5),
                    ),
                    child: const Icon(
                      SgIcons.clock,
                      color: SgColors.gateMuted,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (worker != null)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        worker!.name,
                        style: SgText.gateName.copyWith(color: SgColors.white),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: SgText.gatePromptSecondary.copyWith(
                      color: SgColors.white,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.gate_cooldown_hint,
                    style: SgText.body.copyWith(color: SgColors.gateMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The gate cannot run (camera problem).
class PausedPanel extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SgGatePanel(
      color: SgColors.gatePanel,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(SgIcons.camera, color: SgColors.gateMuted, size: 56),
            const SizedBox(height: 16),
            Text(
              l10n.gate_paused_title,
              style: SgText.gatePromptSecondary.copyWith(color: SgColors.white),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.gate_paused_camera,
              textAlign: TextAlign.center,
              style: SgText.body.copyWith(color: SgColors.gateMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Clock, shift, progress and the last mark (all gate designs).
class GateFooter extends StatelessWidget {
  const new({
    required this.data,
    required this.use24h,
    required this.highlightLast,
    super.key,
  });

  final GateFooterData data;
  final bool use24h;

  /// Tints the last-mark row green right after a mark (design 02).
  final bool highlightLast;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final now = data.now;
    final hm = use24h
        ? formatHm(now)
        : formatTime(now, padHour: true).split(' ').first;
    final shift = data.shift;
    final markedText = l10n.gate_footer_marked(data.marked, data.expected);
    final markedStr = '${data.marked}';
    final markedAt = markedText.indexOf(markedStr);

    return Container(
      decoration: const BoxDecoration(
        color: SgColors.gatePanel,
        border: Border(top: BorderSide(color: SgColors.gateLine)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Semantics(
                  label: formatTime(now, use24h: use24h),
                  child: ExcludeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          hm,
                          style: SgText.gateClock.copyWith(
                            color: SgColors.white,
                            fontSize: 34,
                          ),
                        ),
                        if (!use24h) ...[
                          const SizedBox(width: 8),
                          Text(
                            meridiem(now),
                            style: SgText.bodyStrong.copyWith(
                              color: SgColors.gateMuted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (shift != null)
                        Text(
                          l10n.gate_footer_shift(
                            shift.name,
                            formatShiftWindow(
                              shift.startMinute,
                              shift.endMinute,
                            ),
                          ),
                          textAlign: TextAlign.end,
                          style: SgText.bodyStrong.copyWith(
                            color: SgColors.white,
                            fontSize: 15,
                          ),
                        ),
                      Text(
                        '${weekdayShort(now, locale)} · ${formatDate(now)}',
                        style: SgText.caption.copyWith(
                          color: SgColors.gateMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: markedAt < 0
                          ? [TextSpan(text: markedText)]
                          : [
                              TextSpan(text: markedText.substring(0, markedAt)),
                              TextSpan(
                                text: markedStr,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              TextSpan(
                                text: markedText.substring(
                                  markedAt + markedStr.length,
                                ),
                              ),
                            ],
                    ),
                    style: SgText.body.copyWith(
                      color: SgColors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  l10n.gate_footer_notYet(data.notYet),
                  style: SgText.body.copyWith(
                    color: SgColors.gateMuted,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SgProgressBar(value: data.progress),
            const SizedBox(height: 12),
            _LastMarkRow(data: data, use24h: use24h, highlight: highlightLast),
          ],
        ),
      ),
    );
  }
}

class _LastMarkRow extends StatelessWidget {
  const new({
    required this.data,
    required this.use24h,
    required this.highlight,
  });

  final GateFooterData data;
  final bool use24h;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final worker = data.lastWorker;
    final event = data.lastEvent;
    if (worker == null || event == null) {
      return SizedBox(
        height: 56,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l10n.gate_footer_noMarks,
            style: SgText.body.copyWith(color: SgColors.gateMuted),
          ),
        ),
      );
    }
    return AnimatedContainer(
      duration: SgMotion.fast,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFF133524) : SgColors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SgAvatarInitials(
            name: worker.name,
            background: highlight
                ? SgColors.successFill
                : const Color(0xFF2B2F36),
            foreground: SgColors.white,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  worker.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SgText.bodyStrong.copyWith(
                    color: SgColors.white,
                    fontSize: 16,
                  ),
                ),
                Text(
                  l10n.gate_footer_lastMark(worker.code, worker.department),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SgText.caption.copyWith(
                    color: SgColors.gateMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${directionLabel(l10n, event.direction)}  ${formatHm(event.at)}',
            style: SgText.mono.copyWith(
              color: SgColors.successOnDark,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
