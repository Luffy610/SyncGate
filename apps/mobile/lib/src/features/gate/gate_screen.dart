import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_platform/sg_platform.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/app/routes.dart';
import 'package:syncgate/src/features/gate/gate_controller.dart';
import 'package:syncgate/src/features/gate/gate_widgets.dart';

/// Gate mode (designs 01–04): one screen driven by [GateController].
class GateScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(platformProvider);
    return SgGateScope(platform: platform, child: const _GateView());
  }
}

class _GateView extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gateControllerProvider);
    final controller = ref.read(gateControllerProvider.notifier);
    final footer = ref.watch(gateFooterProvider);
    final settings = ref.watch(settingsProvider).value;
    final use24h = settings?.use24HourClock ?? false;

    final body = switch (state.phase) {
      GatePhase.scanning => ScanningPanel(state: state),
      GatePhase.matched => Column(
        children: [
          Expanded(
            child: MatchedPanel(
              worker: state.worker!,
              direction: state.direction!,
              at: state.at!,
              onTime: state.onTime,
              use24h: use24h,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      GatePhase.notRecognised => Column(
        children: [
          Expanded(
            child: NotRecognisedPanel(
              state: state,
              onTryAgain: controller.retryNow,
              onPickWorker: () => unawaited(context.push(Routes.manual)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      GatePhase.cooldown => Column(
        children: [
          Expanded(
            child: CooldownPanel(
              worker: state.worker,
              direction: state.direction,
              at: state.at,
              use24h: use24h,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      GatePhase.paused => const Column(
        children: [
          Expanded(child: PausedPanel()),
          SizedBox(height: 16),
        ],
      ),
    };

    return SgScaffold(
      dark: true,
      body: Column(
        children: [
          const GateHeaderBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: AnimatedSwitcher(
                duration: SgMotion.fast,
                child: KeyedSubtree(key: ValueKey(state.phase), child: body),
              ),
            ),
          ),
          if (footer != null)
            GateFooter(
              data: footer,
              use24h: use24h,
              highlightLast: state.phase == GatePhase.matched,
            ),
        ],
      ),
    );
  }
}

/// The header shared by the gate and manual entry: logo, offline status,
/// language chip, lock. Long-pressing the logo opens the debug panel in dev.
class GateHeaderBar extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider).value;
    final kiosk = ref.watch(kioskStateProvider).value;
    final platform = ref.watch(platformProvider);
    final language = settings?.language ?? AppLanguage.en;
    final other = language == AppLanguage.hi ? AppLanguage.en : AppLanguage.hi;

    String? warning;
    if (kiosk == KioskState.unlocked) {
      warning = platform == TargetPlatform.iOS
          ? l10n.gate_kiosk_warningIos
          : l10n.gate_kiosk_warning;
    }

    return SgGateHeader(
      statusText: l10n.gate_status_offline,
      languageLabel: other.nativeName,
      languageSemantic: l10n.gate_header_languageSemantic,
      lockSemantic: l10n.gate_header_lock,
      warning: warning,
      onLanguage: () => unawaited(_toggleLanguage(ref)),
      onLock: () => unawaited(context.push(Routes.unlock)),
      onLogoLongPress: () {
        final builder = ref.read(debugPanelBuilderProvider);
        if (builder != null) {
          unawaited(showSgSheet<void>(context, builder: builder));
        }
      },
    );
  }
}

/// Switches the gate language between English and Hindi.
Future<void> _toggleLanguage(WidgetRef ref) async {
  final repo = ref.read(settingsRepositoryProvider);
  final settings = await repo.load();
  final next = settings.language == AppLanguage.hi
      ? AppLanguage.en
      : AppLanguage.hi;
  await repo.save(settings.copyWith(language: next));
}
