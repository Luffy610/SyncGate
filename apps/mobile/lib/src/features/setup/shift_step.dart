import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/features/setup/setup_scaffold.dart';

const _graceOptions = [0, 5, 10, 15, 20, 30];

/// Step 3: name, hours, grace time and weekly off of the first shift.
/// Defaults are Day 06:00–14:00 with 10 minutes grace (E05-T05).
class ShiftStep extends ConsumerStatefulWidget {
  const new({super.key});

  static const step = 3;

  @override
  ConsumerState<ShiftStep> createState() => _ShiftStepState();
}

class _ShiftStepState extends ConsumerState<ShiftStep> {
  final _name = TextEditingController();
  Shift? _original;
  int _start = 6 * 60;
  int _end = 14 * 60;
  var _grace = 10;
  int _weeklyOff = DateTime.sunday;
  var _showErrors = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final shifts = await ref.read(shiftRepositoryProvider).all();
    if (!mounted || shifts.isEmpty) return;
    final shift = shifts.first;
    setState(() {
      _original = shift;
      _name.text = shift.name;
      _start = shift.startMinute;
      _end = shift.endMinute;
      _grace = shift.graceMinutes;
      _weeklyOff = shift.weeklyOff;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _error(AppLocalizations l10n) {
    if (_name.text.trim().isEmpty) return l10n.shift_nameRequired;
    if (_start == _end) return l10n.shift_sameTimes;
    return null;
  }

  Future<void> _pickTime({required bool start}) async {
    final l10n = AppLocalizations.of(context);
    final current = start ? _start : _end;
    final picked = await showSgTimePicker(
      context,
      title: start ? l10n.shift_starts : l10n.shift_ends,
      initialMinute: current,
      confirmLabel: l10n.common_save,
      cancelLabel: l10n.common_cancel,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_error(l10n) != null) {
      setState(() => _showErrors = true);
      return;
    }
    final base =
        _original ??
        const Shift(
          id: 'shift-day',
          name: 'Day',
          startMinute: 360,
          endMinute: 840,
        );
    await ref
        .read(shiftRepositoryProvider)
        .save(
          base.copyWith(
            name: _name.text.trim(),
            startMinute: _start,
            endMinute: _end,
            graceMinutes: _grace,
            weeklyOff: _weeklyOff,
          ),
        );
    if (mounted) await SetupNav.next(context, ref, ShiftStep.step);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = _showErrors ? _error(l10n) : null;
    final crosses = _end <= _start;

    return SetupScaffold(
      step: ShiftStep.step,
      title: l10n.setup_shift_title,
      body: l10n.setup_shift_body,
      actions: [
        SgButton(
          label: l10n.common_continue,
          onPressed: () => unawaited(_save()),
        ),
      ],
      child: SgSection(
        children: [
          SgTextField(
            label: l10n.shift_name,
            controller: _name,
            textCapitalization: TextCapitalization.words,
            errorText: error != null && _name.text.trim().isEmpty
                ? error
                : null,
            onChanged: (_) => setState(() {}),
          ),
          SgPickerField(
            label: l10n.shift_starts,
            valueText: formatMinuteOfDay(_start),
            onTap: () => unawaited(_pickTime(start: true)),
          ),
          SgPickerField(
            label: l10n.shift_ends,
            valueText: formatMinuteOfDay(_end),
            onTap: () => unawaited(_pickTime(start: false)),
          ),
          if (crosses && _start != _end) SgFieldNote(l10n.shift_endsNextDay),
          if (error != null && _start == _end)
            SgFieldNote(error, color: SgColors.danger),
          SgSelectField<int>(
            label: l10n.shift_grace,
            value: _grace,
            options: [
              for (final m in _graceOptions)
                SgOption(value: m, label: l10n.shift_graceValue(m)),
            ],
            onChanged: (m) => setState(() => _grace = m),
          ),
          SgFieldNote(l10n.shift_graceHelp),
          SgSelectField<int>(
            label: l10n.shift_weeklyOff,
            value: _weeklyOff,
            options: [
              for (var d = DateTime.sunday; d >= DateTime.monday; d--)
                SgOption(value: d, label: _weekdayName(l10n, d)),
              SgOption(value: 0, label: l10n.common_none),
            ],
            onChanged: (d) => setState(() => _weeklyOff = d),
          ),
        ],
      ),
    );
  }
}

String _weekdayName(AppLocalizations l10n, int weekday) => switch (weekday) {
  DateTime.monday => l10n.weekday_1,
  DateTime.tuesday => l10n.weekday_2,
  DateTime.wednesday => l10n.weekday_3,
  DateTime.thursday => l10n.weekday_4,
  DateTime.friday => l10n.weekday_5,
  DateTime.saturday => l10n.weekday_6,
  _ => l10n.weekday_7,
};
