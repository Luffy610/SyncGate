import 'dart:async';

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

/// Restore a backup instead of setting up from scratch: used on a replacement
/// phone, before any setup (ADR-0013). The owner picks the `.sgbackup` file and
/// types the backup passphrase. Workers come back needing a face, because face
/// data is never part of a backup.
class RestoreScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  final _passphrase = TextEditingController();
  PickedFile? _file;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  bool get _ready =>
      _file != null && _passphrase.text.trim().isNotEmpty && !_busy;

  Future<void> _choose() async {
    final picked = await ref.read(filePickProvider).pickFile();
    if (picked == null || !mounted) return;
    setState(() {
      _file = picked;
      _error = null;
    });
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(backupServiceProvider)
        .restore(file: _file!.bytes, passphrase: _passphrase.text.trim());
    if (!mounted) return;
    switch (result) {
      case Ok():
        // The server now holds the restored settings: reload them and let the
        // app pick its mode (gate) from them.
        await ref.read(settingsRepositoryProvider).load();
        ref.invalidate(appModeProvider);
        if (mounted) context.go(Routes.root);
      case Err(:final failure):
        setState(() {
          _busy = false;
          _error = switch (failure) {
            Unexpected(:final message)
                when (message ?? '').contains('passphrase') =>
              l10n.restore_errorPassphrase,
            NoInternet() => l10n.restore_errorOffline,
            Unexpected(:final message)
                when (message ?? '').contains('fresh install') =>
              l10n.restore_errorNotEmpty,
            _ => l10n.restore_errorGeneric,
          };
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gutter = context.sg.gutter;
    return SgScaffold(
      topBar: SgTopBar(
        title: l10n.restore_title,
        leading: SgLeading.back,
        leadingLabel: l10n.setup_language_title,
        onLeading: () => context.go(Routes.setupLanguage),
      ),
      body: SgScrollColumn(
        padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
        children: [
          Text(
            l10n.restore_body,
            style: SgText.body.copyWith(color: SgColors.muted, fontSize: 17),
          ),
          const SizedBox(height: 16),
          SgCard(
            child: Text(
              _file?.name ?? l10n.restore_noFile,
              key: const ValueKey('restore-file'),
              style: SgText.bodyStrong,
            ),
          ),
          const SizedBox(height: 8),
          SgButton(
            label: l10n.restore_choose,
            kind: SgButtonKind.text,
            onPressed: _busy ? null : () => unawaited(_choose()),
          ),
          const SizedBox(height: 8),
          SgTextField(
            label: l10n.restore_passphrase,
            controller: _passphrase,
            obscure: true,
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) SgFieldNote(_error!, color: SgColors.danger),
          const SizedBox(height: 16),
          SgButton(
            label: _busy ? l10n.restore_working : l10n.restore_action,
            onPressed: _ready ? () => unawaited(_restore()) : null,
          ),
        ],
      ),
    );
  }
}
