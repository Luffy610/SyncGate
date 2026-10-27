import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart' show AppSettings;
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/providers.dart';

/// Wraps Admin mode. Returns to the gate after [AppSettings.idleMinutes]
/// without a touch, and when the app comes back from the background
/// (ADR-0004 §1). Face capture and sharing hold the timer via
/// [idleHoldProvider].
class IdleWatcher extends ConsumerStatefulWidget {
  const new({required this.active, required this.child, super.key});

  /// Only Admin mode runs the timer. The widget stays in the tree in every
  /// mode so the navigator below it is never rebuilt.
  final bool active;
  final Widget child;

  @override
  ConsumerState<IdleWatcher> createState() => _IdleWatcherState();
}

class _IdleWatcherState extends ConsumerState<IdleWatcher> {
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;
  var _wasBackgrounded = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    _restart();
  }

  @override
  void didUpdateWidget(IdleWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _wasBackgrounded = true;
    if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      if (widget.active && ref.read(idleHoldProvider) == 0) {
        _returnToGate('resume');
      }
    }
  }

  void _restart() {
    _timer?.cancel();
    if (!widget.active) return;
    final minutes = ref.read(settingsProvider).value?.idleMinutes ?? 2;
    _timer = Timer(Duration(minutes: minutes), () {
      if (ref.read(idleHoldProvider) > 0) {
        _restart();
      } else {
        _returnToGate('idle');
      }
    });
  }

  void _returnToGate(String reason) {
    if (ref.read(appModeProvider) is AdminMode) {
      unawaited(ref.read(appModeProvider.notifier).enterGate(reason: reason));
    }
  }

  @override
  Widget build(BuildContext context) {
    // A changed timeout applies at once, not after the next touch.
    ref.listen(
      settingsProvider.select((s) => s.value?.idleMinutes),
      (_, _) => _restart(),
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _restart(),
      onPointerMove: (_) => _restart(),
      onPointerUp: (_) => _restart(),
      child: widget.child,
    );
  }
}
