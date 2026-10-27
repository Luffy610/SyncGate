import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_platform/sg_platform.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:sg_vision/sg_vision.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/dev/catalogue_page.dart';
import 'package:syncgate/src/dev/dev_overrides.dart';
import 'package:syncgate/src/dev/fakes/fake_services.dart';
import 'package:syncgate/src/dev/seed.dart';

final devEnvironmentProvider = Provider<DevEnvironment>(
  (ref) => throw UnimplementedError('devEnvironmentProvider not overridden'),
);

/// Dev-only panel (frontend plan §6.1): long-press the logo on the gate.
/// Scripts the fake camera, moves the clock, flips the OS kiosk state and
/// switches the iOS / Android look.
class DebugPanel extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends ConsumerState<DebugPanel> {
  var _demoRunning = false;

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(devEnvironmentProvider);
    final workers = ref.watch(workersProvider).value ?? const <Worker>[];
    final look = ref.watch(lookProvider);
    // The sheet is light, but it opens over the dark gate theme.
    final theme = SgTheme.light(Theme.of(context).platform);

    Widget header(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: theme.textTheme.titleSmall),
    );

    return Theme(
      data: theme,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: ListView(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            children: [
              Text('Debug panel (dev only)', style: theme.textTheme.titleLarge),
              header('Camera'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final w
                      in workers
                          .where((w) => w.faceStatus == FaceStatus.enrolled)
                          .take(6))
                    ActionChip(
                      label: Text('Match ${w.firstName}'),
                      onPressed: () => env.gateVision.match(w.id),
                    ),
                  ActionChip(
                    label: const Text('No match'),
                    onPressed: env.gateVision.noMatch,
                  ),
                  ActionChip(
                    label: const Text('Unknown face'),
                    onPressed: () => env.gateVision.match('w-unknown'),
                  ),
                  for (final issue in QualityIssue.values)
                    ActionChip(
                      label: Text(issue.name),
                      onPressed: () => env.gateVision.emit(QualityHint(issue)),
                    ),
                ],
              ),
              SwitchListTile(
                title: const Text('Demo loop (a worker every 6 s)'),
                value: _demoRunning,
                onChanged: (on) {
                  if (on) {
                    env.gateVision.startDemoLoop([
                      for (final w in workers.where(
                        (w) => w.faceStatus == FaceStatus.enrolled,
                      ))
                        w.id,
                    ]);
                  } else {
                    env.gateVision.stopDemoLoop();
                  }
                  setState(() => _demoRunning = on);
                },
              ),
              SwitchListTile(
                title: const Text('Next enrolment finds a duplicate'),
                value: env.enrolment.duplicateOf != null,
                onChanged: (on) {
                  setState(() {
                    env.enrolment.duplicateOf = on
                        ? DemoSeed.workerId(112)
                        : null;
                  });
                },
              ),
              header('Clock'),
              Wrap(
                spacing: 8,
                children: [
                  for (final (label, by) in [
                    ('+10 min', const Duration(minutes: 10)),
                    ('+1 h', const Duration(hours: 1)),
                    ('+8 h', const Duration(hours: 8)),
                  ])
                    ActionChip(
                      label: Text(label),
                      onPressed: () {
                        final clock = env.backend.clock;
                        if (clock is DemoClock) clock.advance(by);
                      },
                    ),
                ],
              ),
              header('Phone'),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Pinned'),
                    onPressed: () => env.kiosk.set(KioskState.locked),
                  ),
                  ActionChip(
                    label: const Text('Not pinned'),
                    onPressed: () => env.kiosk.set(KioskState.unlocked),
                  ),
                ],
              ),
              header('Look'),
              SegmentedButton<TargetPlatform?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('Device')),
                  ButtonSegment(
                    value: TargetPlatform.android,
                    label: Text('Android'),
                  ),
                  ButtonSegment(value: TargetPlatform.iOS, label: Text('iOS')),
                ],
                selected: {look},
                onSelectionChanged: (s) =>
                    ref.read(lookProvider.notifier).set(s.first),
              ),
              header('App'),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Component catalogue'),
                    onPressed: () {
                      Navigator.of(context)
                        ..pop()
                        ..push(
                          MaterialPageRoute<void>(
                            builder: (_) => const CataloguePage(),
                          ),
                        );
                    },
                  ),
                  ActionChip(
                    label: const Text('Reset to fresh install'),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await ref
                          .read(appModeProvider.notifier)
                          .resetToFreshInstall();
                    },
                  ),
                ],
              ),
              header('Dev PINs'),
              const Text(
                'Owner ${DemoSeed.ownerPin} · Admin ${DemoSeed.adminPin} · '
                'Gate operator ${DemoSeed.operatorPin}\n'
                'Licence key: SGT-4F7K-2Q9M-A1B2 (NONET in the key simulates '
                'no internet, e.g. SGT-NONE-T123-4567)',
              ),
              if (kDebugMode) const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
