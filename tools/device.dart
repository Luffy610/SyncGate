// Helpers for scripts/run-on-device: finds the phone to run on and checks
// the Flutter version. Run from the repo root:
//
//   dart run tools/device.dart pick android|ios [--device <id or name>]
//       Prints the chosen device ID on stdout (messages go to stderr).
//       Exit 0 = found, 3 = no usable device.
//   dart run tools/device.dart check-flutter
//       Warns (stderr) if Flutter is not the version pinned in .fvmrc.
//
// It works the same on macOS, Linux and Windows because it only asks
// `flutter devices --machine` and parses the JSON.

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty) _usage();
  switch (args.first) {
    case 'pick':
      if (args.length < 2 || !const {'android', 'ios'}.contains(args[1])) {
        _usage();
      }
      String? wanted;
      final i = args.indexOf('--device');
      if (i >= 0 && i + 1 < args.length) wanted = args[i + 1];
      exit(await _pick(args[1], wanted));
    case 'check-flutter':
      await _checkFlutter();
    default:
      _usage();
  }
}

Never _usage() {
  stderr.writeln(
    'usage: dart run tools/device.dart pick android|ios [--device <id>]\n'
    '       dart run tools/device.dart check-flutter',
  );
  exit(64);
}

Future<ProcessResult> _flutter(List<String> args) =>
    Process.run('flutter', args, runInShell: Platform.isWindows);

/// One entry of `flutter devices --machine`.
typedef _Device = ({
  String id,
  String name,
  String platform,
  bool emulator,
  bool supported,
});

Future<int> _pick(String platform, String? wanted) async {
  final result = await _flutter([
    'devices',
    '--machine',
    // Wireless and freshly plugged-in iPhones can take a few seconds.
    '--device-timeout=${platform == 'ios' ? 10 : 5}',
  ]);
  if (result.exitCode != 0) {
    stderr.writeln('`flutter devices` failed:\n${result.stderr}');
    return 3;
  }
  final out = result.stdout as String;
  final start = out.indexOf('[');
  final List<Object?> raw;
  try {
    raw = jsonDecode(start < 0 ? '[]' : out.substring(start)) as List<Object?>;
  } on FormatException {
    stderr.writeln('Could not read `flutter devices --machine` output.');
    return 3;
  }
  final all = <_Device>[
    for (final d in raw.cast<Map<String, Object?>>())
      (
        id: d['id']! as String,
        name: d['name']! as String,
        platform: d['targetPlatform']! as String,
        emulator: d['emulator'] == true,
        supported: d['isSupported'] != false,
      ),
  ];
  bool matches(_Device d) => platform == 'ios'
      ? d.platform == 'ios'
      : d.platform.startsWith('android');
  final candidates = all.where(matches).toList();

  if (wanted != null) {
    final hit = candidates
        .where((d) => d.id == wanted || d.name == wanted)
        .firstOrNull;
    if (hit == null) {
      stderr.writeln('No $platform device "$wanted" is connected.');
      _list(candidates);
      return 3;
    }
    stdout.writeln(hit.id);
    return 0;
  }

  final unsupported = candidates.where((d) => !d.supported).toList();
  final phones = candidates.where((d) => d.supported && !d.emulator).toList();
  final emulators = candidates.where((d) => d.supported && d.emulator).toList();

  if (phones.isNotEmpty) {
    final chosen = phones.first;
    if (phones.length > 1) {
      stderr.writeln(
        'Several phones are connected; using ${chosen.name}. '
        'Pick another with --device <id>:',
      );
      _list(phones);
    }
    stdout.writeln(chosen.id);
    return 0;
  }
  // A phone is plugged in but not usable yet: say why rather than quietly
  // falling back to an emulator.
  if (emulators.isNotEmpty && !unsupported.any((d) => !d.emulator)) {
    final chosen = emulators.first;
    final kind = platform == 'ios' ? 'simulator' : 'emulator';
    final camera = platform == 'ios'
        ? 'the iOS simulator has none'
        : 'set the emulator front camera to your webcam (AVD settings)';
    stderr.writeln(
      'No phone found; using the $kind ${chosen.name}. '
      'Face recognition needs a real camera: $camera.',
    );
    stdout.writeln(chosen.id);
    return 0;
  }

  stderr.writeln('No $platform phone found.');
  if (unsupported.isNotEmpty) {
    stderr.writeln('These are connected but not ready:');
    _list(unsupported);
  }
  stderr.writeln(
    platform == 'ios'
        ? '- Unlock the iPhone and tap "Trust This Computer".\n'
              '- iOS 16+: turn on Settings → Privacy & Security → '
              'Developer Mode, then restart the phone.\n'
              '- Check it shows in Xcode → Window → Devices and Simulators.'
        : '- On the phone: Settings → About phone → tap "Build number" 7 '
              'times, then Developer options → USB debugging on.\n'
              '- Unlock the phone and accept "Allow USB debugging?".\n'
              '- Use a data cable (not charge-only); try `adb devices`.',
  );
  return 3;
}

void _list(List<_Device> devices) {
  for (final d in devices) {
    stderr.writeln(
      '  ${d.name}  (id: ${d.id}${d.emulator ? ', emulator' : ''}'
      '${d.supported ? '' : ', not ready'})',
    );
  }
}

Future<void> _checkFlutter() async {
  final pinned = File('.fvmrc').existsSync()
      ? (jsonDecode(File('.fvmrc').readAsStringSync())
                as Map<String, Object?>)['flutter']
            as String?
      : null;
  final result = await _flutter(['--version', '--machine']);
  final out = result.stdout as String;
  final start = out.indexOf('{');
  if (result.exitCode != 0 || start < 0) {
    stderr.writeln('Could not read the Flutter version.');
    return;
  }
  final version =
      (jsonDecode(out.substring(start))
              as Map<String, Object?>)['frameworkVersion']
          as String?;
  if (pinned != null && version != pinned) {
    stderr.writeln(
      'Warning: Flutter $version is installed but the repo pins $pinned '
      '(.fvmrc). If the build fails, install $pinned (see README).',
    );
  } else {
    stderr.writeln('Flutter $version');
  }
}
