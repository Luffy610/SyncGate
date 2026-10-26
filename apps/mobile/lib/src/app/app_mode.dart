import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:syncgate/src/app/providers.dart';

/// Number of setup steps (frontend plan §6.2): language, licence, shift,
/// camera, kiosk, owner PIN, first worker.
const setupStepCount = 7;

/// The app is always in exactly one mode (ADR-0004 §1).
@immutable
sealed class AppMode {
  const new();
}

/// First launch or after restore. [step] is 1-based.
final class SetupMode extends AppMode {
  const new(this.step);

  final int step;

  @override
  bool operator ==(Object other) => other is SetupMode && other.step == step;

  @override
  int get hashCode => Object.hash(SetupMode, step);
}

final class GateMode extends AppMode {
  const new();

  @override
  bool operator ==(Object other) => other is GateMode;

  @override
  int get hashCode => (GateMode).hashCode;
}

final class AdminMode extends AppMode {
  const new(this.session);

  final AdminSession session;

  Role get role => session.role;
}

/// Single source of truth for the mode (frontend plan §3.1). Every change is
/// written to settings, and every admin entry or exit to the audit log.
class AppModeController extends Notifier<AppMode> {
  @override
  AppMode build() {
    final settings = ref.read(settingsProvider).requireValue;
    return switch (settings.mode) {
      AppModeKind.setup => SetupMode(
        settings.setupStep.clamp(1, setupStepCount),
      ),
      // Admin never survives a restart: the app opens on the gate.
      AppModeKind.gate || AppModeKind.admin => const GateMode(),
    };
  }

  Future<void> _save(AppSettings Function(AppSettings) change) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.save(change(await repo.load()));
  }

  /// Moves to setup step [step] and remembers it.
  Future<void> goToSetupStep(int step) async {
    final next = step.clamp(1, setupStepCount);
    state = SetupMode(next);
    await _save((s) => s.copyWith(mode: AppModeKind.setup, setupStep: next));
  }

  Future<void> completeSetup() async {
    state = const GateMode();
    await _save((s) => s.copyWith(mode: AppModeKind.gate));
    await ref
        .read(auditLogProvider)
        .append(
          AuditEntry(
            at: ref.read(clockProvider).now(),
            actor: 'Owner',
            action: 'setup.completed',
          ),
        );
  }

  Future<void> enterAdmin(AppUser user) async {
    final now = ref.read(clockProvider).now();
    state = AdminMode(AdminSession(user: user, startedAt: now));
    await _save((s) => s.copyWith(mode: AppModeKind.admin));
    await ref
        .read(auditLogProvider)
        .append(
          AuditEntry(
            at: now,
            actor: user.name,
            action: 'mode.admin',
            detail: user.role.name,
          ),
        );
  }

  Future<void> enterGate({String reason = 'manual'}) async {
    final previous = state;
    state = const GateMode();
    await _save((s) => s.copyWith(mode: AppModeKind.gate));
    if (previous is AdminMode) {
      await ref
          .read(auditLogProvider)
          .append(
            AuditEntry(
              at: ref.read(clockProvider).now(),
              actor: previous.session.user.name,
              action: 'mode.gate',
              detail: reason,
            ),
          );
    }
  }

  /// Dev only (debug panel): back to a fresh install.
  Future<void> resetToFreshInstall() async {
    state = const SetupMode(1);
    await _save((s) => const AppSettings().copyWith(language: s.language));
  }
}

final appModeProvider = NotifierProvider<AppModeController, AppMode>(
  AppModeController.new,
);

/// The signed-in admin session, or `null` outside Admin mode.
final adminSessionProvider = Provider<AdminSession?>((ref) {
  final mode = ref.watch(appModeProvider);
  return mode is AdminMode ? mode.session : null;
});

/// Whether the current session may do [capability]. Outside Admin mode
/// nothing is allowed.
bool canDo(AdminSession? session, Capability capability) =>
    session?.can(capability) ?? false;
