import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_platform/sg_platform.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/app/routes.dart';

@immutable
class UnlockState {
  const new({
    this.role = Role.owner,
    this.digits = '',
    this.shakeKey = 0,
    this.attemptsLeft,
    this.lockedFor,
    this.checking = false,
  });

  final Role role;
  final String digits;
  final int shakeKey;

  /// Set after a wrong PIN while tries remain.
  final int? attemptsLeft;

  /// Set while the user is locked out.
  final Duration? lockedFor;
  final bool checking;

  bool get locked => lockedFor != null && lockedFor! > Duration.zero;

  UnlockState copyWith({
    Role? role,
    String? digits,
    int? shakeKey,
    int? attemptsLeft,
    Duration? lockedFor,
    bool? checking,
    bool clearError = false,
  }) => UnlockState(
    role: role ?? this.role,
    digits: digits ?? this.digits,
    shakeKey: shakeKey ?? this.shakeKey,
    attemptsLeft: clearError ? null : attemptsLeft ?? this.attemptsLeft,
    lockedFor: clearError ? null : lockedFor ?? this.lockedFor,
    checking: checking ?? this.checking,
  );
}

/// PIN entry (design 09): auto-submits at six digits, shakes on a wrong PIN
/// and locks out with a back-off countdown (ADR-0004 §2).
class UnlockController extends Notifier<UnlockState> {
  Timer? _countdown;

  @override
  UnlockState build() {
    ref.onDispose(() => _countdown?.cancel());
    return const UnlockState();
  }

  void selectRole(Role role) {
    state = state.copyWith(role: role, digits: '', clearError: true);
  }

  void digit(int d) {
    if (state.locked || state.checking) return;
    if (state.digits.length >= PinPolicy.length) return;
    state = state.copyWith(digits: '${state.digits}$d');
    if (state.digits.length == PinPolicy.length) unawaited(_submit());
  }

  void backspace() {
    if (state.digits.isEmpty) return;
    state = state.copyWith(
      digits: state.digits.substring(0, state.digits.length - 1),
    );
  }

  Future<void> _submit() async {
    final role = state.role;
    final pin = state.digits;
    state = state.copyWith(checking: true);
    final result = await ref.read(userRepositoryProvider).verifyPin(role, pin);
    switch (result) {
      case Ok(:final value):
        state = state.copyWith(checking: false, digits: '');
        await ref.read(appModeProvider.notifier).enterAdmin(value);
      case Err(:final failure):
        unawaited(HapticFeedback.heavyImpact());
        final locked = switch (failure) {
          WrongPin(:final lockedFor) => lockedFor,
          LockedOut(:final remaining) => remaining,
          _ => null,
        };
        state = UnlockState(
          role: role,
          shakeKey: state.shakeKey + 1,
          attemptsLeft: failure is WrongPin ? failure.attemptsLeft : null,
          lockedFor: locked,
        );
        if (locked != null && locked > Duration.zero) _startCountdown();
    }
  }

  void _startCountdown() {
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left =
          (state.lockedFor ?? Duration.zero) - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        timer.cancel();
        state = state.copyWith(clearError: true);
      } else {
        state = state.copyWith(lockedFor: left);
      }
    });
  }

  /// Signs in with the OS fingerprint / Face ID for the selected role.
  Future<void> unlockWithBiometrics(String reason) async {
    if (state.locked || state.checking) return;
    final ok = await ref.read(biometricProvider).authenticate(reason: reason);
    if (!ok) return;
    final users = await ref.read(userRepositoryProvider).users();
    final user = users.firstWhere((u) => u.role == state.role);
    await ref.read(appModeProvider.notifier).enterAdmin(user);
  }
}

final NotifierProvider<UnlockController, UnlockState> unlockControllerProvider =
    NotifierProvider.autoDispose<UnlockController, UnlockState>(
      UnlockController.new,
    );

final FutureProvider<BiometricKind> biometricKindProvider =
    FutureProvider.autoDispose<BiometricKind>((ref) {
      return ref.watch(biometricProvider).availableKind();
    });

String _formatRemaining(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Admin unlock (design 09), reached from the lock button on the gate.
class UnlockScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(unlockControllerProvider);
    final controller = ref.read(unlockControllerProvider.notifier);
    final ios = context.isIos;
    final biometric = ref.watch(biometricKindProvider).value;
    final biometricOn =
        (ref.watch(settingsProvider).value?.biometricEnabled ?? false) &&
        biometric != null &&
        biometric != BiometricKind.none;
    final biometricLabel = ios
        ? l10n.unlock_useFaceId
        : l10n.unlock_useFingerprint;

    void leave() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.gate);
      }
    }

    String? message;
    if (state.locked) {
      message = l10n.unlock_lockedOut(_formatRemaining(state.lockedFor!));
    } else if (state.attemptsLeft != null) {
      message = l10n.unlock_wrong(state.attemptsLeft!);
    }

    return SgScaffold(
      topBar: SgTopBar(
        title: '',
        leading: SgLeading.close,
        leadingLabel: ios ? l10n.unlock_backToGate : l10n.common_close,
        onLeading: leave,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: context.sg.gutter + 8),
        child: Column(
          children: [
            const SizedBox(height: 8),
            const SgLogo(size: 48),
            const SizedBox(height: 20),
            Semantics(
              header: true,
              child: Text(
                l10n.unlock_title,
                style: SgText.heading.copyWith(fontSize: 26),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.unlock_prompt,
              style: SgText.body.copyWith(color: SgColors.muted, fontSize: 17),
            ),
            const SizedBox(height: 20),
            SgSegmented<Role>(
              selected: state.role,
              onChanged: controller.selectRole,
              options: [
                SgOption(value: Role.owner, label: l10n.role_owner),
                SgOption(value: Role.admin, label: l10n.role_admin),
                SgOption(
                  value: Role.gateOperator,
                  label: l10n.role_gateOperator,
                ),
              ],
            ),
            const SizedBox(height: 24),
            SgPinDots(
              length: PinPolicy.length,
              filled: state.digits.length,
              shakeKey: state.shakeKey,
              semanticLabel: l10n.unlock_prompt,
            ),
            SizedBox(
              height: 36,
              child: Center(
                child: message == null
                    ? null
                    : Semantics(
                        liveRegion: true,
                        child: Text(
                          message,
                          key: const ValueKey('unlock-message'),
                          style: SgText.bodyStrong.copyWith(
                            color: SgColors.danger,
                            fontSize: 15,
                          ),
                        ),
                      ),
              ),
            ),
            SgPinPad(
              enabled: !state.locked && !state.checking,
              onDigit: controller.digit,
              onBackspace: controller.backspace,
              backspaceLabel: l10n.unlock_delete,
              biometricLabel: biometricLabel,
              onBiometric: biometricOn
                  ? () => unawaited(
                      controller.unlockWithBiometrics(
                        l10n.unlock_biometricReason,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            if (biometricOn)
              SgButton(
                label: biometricLabel,
                kind: SgButtonKind.text,
                underline: true,
                expand: false,
                onPressed: () => unawaited(
                  controller.unlockWithBiometrics(l10n.unlock_biometricReason),
                ),
              ),
            if (state.role == Role.owner)
              SgButton(
                label: l10n.unlock_forgot,
                kind: SgButtonKind.text,
                expand: false,
                onPressed: () => unawaited(_resetPin(context, ref)),
              ),
            const SizedBox(height: 16),
            Text(
              l10n.unlock_footer,
              textAlign: TextAlign.center,
              style: SgText.caption.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _resetPin(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final done = await showSgSheet<bool>(
      context,
      builder: (ctx) => const _ResetPinSheet(),
    );
    if (done ?? false) {
      if (context.mounted) showSgToast(context, l10n.unlock_reset_done);
    }
  }
}

class _ResetPinSheet extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_ResetPinSheet> createState() => _ResetPinSheetState();
}

class _ResetPinSheetState extends ConsumerState<_ResetPinSheet> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  var _failed = false;

  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    super.dispose();
  }

  bool get _valid =>
      _code.text.trim().isNotEmpty &&
      RegExp(r'^\d{6}$').hasMatch(_pin.text.trim());

  Future<void> _reset() async {
    final result = await ref
        .read(userRepositoryProvider)
        .resetOwnerPin(recoveryCode: _code.text, newPin: _pin.text.trim());
    if (!mounted) return;
    if (result.isOk) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SgSheetFrame(
      title: l10n.unlock_reset_title,
      cancelLabel: l10n.common_cancel,
      confirmLabel: l10n.unlock_reset_confirm,
      onCancel: () => Navigator.of(context).pop(false),
      onConfirm: _valid ? () => unawaited(_reset()) : null,
      child: SgSection(
        children: [
          SgTextField(
            label: l10n.unlock_reset_code,
            controller: _code,
            mono: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() => _failed = false),
          ),
          SgTextField(
            label: l10n.unlock_reset_newPin,
            controller: _pin,
            obscure: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(PinPolicy.length),
            ],
            onChanged: (_) => setState(() {}),
          ),
          if (_failed)
            SgFieldNote(l10n.unlock_reset_failed, color: SgColors.danger),
        ],
      ),
    );
  }
}
