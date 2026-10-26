import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/application/exception_use_cases.dart';

enum _Reason { forgotOut, faceFailed, wrongDirection, other }

/// "Correct record" sheet (design 15): set the missing OUT time, give a
/// reason, and see exactly what the audit log will record.
class CorrectRecordSheet extends ConsumerStatefulWidget {
  const new({required this.record, required this.worker, super.key});

  final ExceptionRecord record;
  final Worker worker;

  @override
  ConsumerState<CorrectRecordSheet> createState() => _CorrectRecordSheetState();
}

class _CorrectRecordSheetState extends ConsumerState<CorrectRecordSheet> {
  late int _outMinute;
  _Reason? _reason;
  String? _otherText;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final shifts = ref.read(shiftsProvider).value ?? const <Shift>[];
    final shift = shifts
        .where((s) => s.id == widget.worker.shiftId)
        .firstOrNull;
    _outMinute = shift?.endMinute ?? 14 * 60;
  }

  DateTime get _day => AttendanceRules.startOfDay(widget.record.at);

  DateTime get _outAt => _day.add(Duration(minutes: _outMinute));

  bool get _timeOk => _outAt.isAfter(widget.record.inAt ?? _day);

  String _reasonText(AppLocalizations l10n) => switch (_reason) {
    _Reason.forgotOut => l10n.correct_reason_forgotOut,
    _Reason.faceFailed => l10n.correct_reason_faceFailed,
    _Reason.wrongDirection => l10n.correct_reason_wrongDirection,
    _Reason.other => _otherText ?? '',
    null => '',
  };

  Future<void> _pickTime() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showSgTimePicker(
      context,
      title: l10n.correct_outTime,
      initialMinute: _outMinute,
      confirmLabel: l10n.common_save,
      cancelLabel: l10n.common_cancel,
    );
    if (picked != null) setState(() => _outMinute = picked);
  }

  Future<void> _pickReason(AppLocalizations l10n) async {
    final picked = await showSgPicker<_Reason>(
      context,
      title: l10n.correct_reason,
      selected: _reason,
      options: [
        SgOption(
          value: _Reason.forgotOut,
          label: l10n.correct_reason_forgotOut,
        ),
        SgOption(
          value: _Reason.faceFailed,
          label: l10n.correct_reason_faceFailed,
        ),
        SgOption(
          value: _Reason.wrongDirection,
          label: l10n.correct_reason_wrongDirection,
        ),
        SgOption(value: _Reason.other, label: l10n.correct_reason_other),
      ],
    );
    if (picked == null || !mounted) return;
    if (picked == _Reason.other) {
      final text = await showSgTextPrompt(
        context,
        title: l10n.correct_reason_otherTitle,
        label: l10n.correct_reason,
        confirmLabel: l10n.common_save,
        cancelLabel: l10n.common_cancel,
      );
      if (text == null) return;
      setState(() {
        _reason = picked;
        _otherText = text;
      });
    } else {
      setState(() => _reason = picked);
    }
  }

  Future<void> _save(AppLocalizations l10n) async {
    setState(() => _saving = true);
    final session = ref.read(adminSessionProvider);
    final result = await ref
        .read(correctRecordProvider)
        .call(
          exception: widget.record,
          outAt: _outAt,
          reason: _reasonText(l10n),
          actor: session?.user.name ?? 'admin',
        );
    if (!mounted) return;
    if (result.isOk) {
      Navigator.of(context).pop(true);
      showSgToast(context, l10n.correct_saved);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = l10n.localeName;
    final worker = widget.worker;
    final record = widget.record;
    final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
    final shiftName =
        shifts.where((s) => s.id == worker.shiftId).firstOrNull?.name ?? '';
    final session = ref.watch(adminSessionProvider);
    final now = ref.watch(nowProvider);
    final use24h = ref.watch(settingsProvider).value?.use24HourClock ?? false;
    final outText = formatHm(_outAt);
    final audit = l10n.correct_audit(
      l10n.correct_none,
      outText,
      session?.user.name ?? 'admin',
      formatDateTime(now, use24h: use24h),
    );

    return SgSheetFrame(
      title: l10n.correct_title,
      cancelLabel: l10n.common_cancel,
      confirmLabel: l10n.correct_save,
      onCancel: () => Navigator.of(context).pop(false),
      onConfirm: _reason != null && _timeOk && !_saving
          ? () => unawaited(_save(l10n))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SgAvatarInitials(name: worker.name, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${worker.name} · ${worker.code}',
                      style: SgText.bodyStrong.copyWith(fontSize: 18),
                    ),
                    Text(
                      l10n.correct_dateLine(
                        formatDateWithWeekday(record.at, locale),
                        shiftName,
                        worker.department,
                      ),
                      style: SgText.caption.copyWith(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TimeTile(
                  label: l10n.correct_inFace,
                  time: record.inAt == null ? '--:--' : formatHm(record.inAt!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeTile(
                  label: l10n.correct_outNew,
                  time: outText,
                  active: true,
                  error: !_timeOk,
                  onTap: () => unawaited(_pickTime()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SgPickerField(
            label: l10n.correct_reason,
            valueText: _reason == null ? null : _reasonText(l10n),
            placeholder: l10n.correct_reason_pick,
            onTap: () => unawaited(_pickReason(l10n)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE9E7E1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(SgIcons.document, color: SgColors.muted, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    audit,
                    key: const ValueKey('audit-preview'),
                    style: SgText.body.copyWith(
                      color: SgColors.muted,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const new({
    required this.label,
    required this.time,
    this.active = false,
    this.error = false,
    this.onTap,
  });

  final String label;
  final String time;
  final bool active;
  final bool error;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SgCard(
      selected: active && !error,
      borderColor: error ? SgColors.danger : SgColors.line,
      onTap: onTap,
      semanticLabel: '$label $time',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: SgText.label),
          const SizedBox(height: 4),
          Text(
            time,
            style: SgText.mono.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: error ? SgColors.danger : SgColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
