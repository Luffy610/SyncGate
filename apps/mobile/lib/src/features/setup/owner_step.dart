import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/features/setup/setup_scaffold.dart';

enum _Phase { create, confirm, recovery }

/// Step 6a: create the owner PIN, confirm it, and show the one-time recovery
/// code (ADR-0004 §2).
class OwnerStep extends ConsumerStatefulWidget {
  const new({super.key});

  static const step = 6;

  @override
  ConsumerState<OwnerStep> createState() => _OwnerStepState();
}

class _OwnerStepState extends ConsumerState<OwnerStep> {
  _Phase _phase = _Phase.create;
  var _entry = '';
  var _first = '';
  var _mismatch = false;
  var _shake = 0;
  var _written = false;
  String? _recoveryCode;

  void _digit(int d) {
    if (_entry.length >= PinPolicy.length) return;
    setState(() {
      _mismatch = false;
      _entry += '$d';
    });
    if (_entry.length == PinPolicy.length) unawaited(_complete());
  }

  void _backspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _complete() async {
    if (_phase == _Phase.create) {
      setState(() {
        _first = _entry;
        _entry = '';
        _phase = _Phase.confirm;
      });
    } else if (_entry == _first) {
      final code = await ref.read(userRepositoryProvider).createOwner(_first);
      if (!mounted) return;
      setState(() {
        _recoveryCode = code;
        _phase = _Phase.recovery;
      });
    } else {
      unawaited(HapticFeedback.heavyImpact());
      setState(() {
        _entry = '';
        _first = '';
        _phase = _Phase.create;
        _mismatch = true;
        _shake++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_phase == _Phase.recovery) {
      return SetupScaffold(
        step: OwnerStep.step,
        title: l10n.setup_owner_recoveryTitle,
        body: l10n.setup_owner_recoveryBody,
        actions: [
          SgButton(
            label: l10n.common_continue,
            onPressed: _written
                ? () => unawaited(SetupNav.next(context, ref, OwnerStep.step))
                : null,
          ),
        ],
        child: Column(
          children: [
            SgCard(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  _recoveryCode ?? '',
                  key: const ValueKey('recovery-code'),
                  style: SgText.mono.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SgCheckRow(
              value: _written,
              onChanged: (v) => setState(() => _written = v),
              title: l10n.setup_owner_recoveryCheck,
              subtitle: l10n.setup_owner_recoveryCheckSub,
            ),
          ],
        ),
      );
    }

    final confirming = _phase == _Phase.confirm;
    return SetupScaffold(
      step: OwnerStep.step,
      title: confirming
          ? l10n.setup_owner_confirmTitle
          : l10n.setup_owner_createTitle,
      body: confirming
          ? l10n.setup_owner_confirmBody
          : l10n.setup_owner_createBody,
      child: Column(
        children: [
          if (_mismatch) ...[
            SgBanner(
              kind: SgBannerKind.danger,
              title: l10n.setup_owner_mismatch,
            ),
            const SizedBox(height: 16),
          ],
          SgPinDots(
            length: PinPolicy.length,
            filled: _entry.length,
            shakeKey: _shake,
            semanticLabel: l10n.unlock_prompt,
          ),
          const SizedBox(height: 24),
          SgPinPad(
            onDigit: _digit,
            onBackspace: _backspace,
            backspaceLabel: l10n.unlock_delete,
          ),
        ],
      ),
    );
  }
}
