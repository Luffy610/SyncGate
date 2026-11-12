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
import 'package:syncgate/src/features/setup/setup_scaffold.dart';

/// Step 6b: enrol the first worker now, or go straight to the gate.
class FirstWorkerStep extends ConsumerWidget {
  const new({super.key});

  static const step = 7;

  Future<void> _enrolNow(BuildContext context, WidgetRef ref) async {
    // Finishing setup moves the app to the gate, which removes this screen
    // while the calls below are still running (they are network calls with a
    // real back end). So everything needed is taken before the first await.
    final controller = ref.read(appModeProvider.notifier);
    final users = ref.read(userRepositoryProvider);
    final router = GoRouter.of(context);
    // The owner signed in when the PIN was created, so look them up first.
    final owner = (await users.users()).firstWhere((u) => u.role == Role.owner);
    await controller.completeSetupAndEnterAdmin(owner);
    router.go(Routes.enrolDetails);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SetupScaffold(
      step: step,
      title: l10n.setup_firstWorker_title,
      body: l10n.setup_firstWorker_body,
      actions: [
        SgButton(
          label: l10n.setup_firstWorker_enrol,
          onPressed: () => unawaited(_enrolNow(context, ref)),
        ),
        SgButton(
          label: l10n.setup_firstWorker_later,
          kind: SgButtonKind.text,
          onPressed: () =>
              unawaited(ref.read(appModeProvider.notifier).completeSetup()),
        ),
      ],
      child: const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Icon(SgIcons.faceScan, size: 96, color: SgColors.muted),
        ),
      ),
    );
  }
}
