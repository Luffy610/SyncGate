import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/app_config.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/features/common/consent_providers.dart';
import 'package:syncgate/src/features/enrolment/enrolment_draft.dart';
import 'package:syncgate/src/features/settings/settings_hub_screen.dart';

Future<void> _save(
  WidgetRef ref,
  AppSettings Function(AppSettings) change,
) async {
  final repo = ref.read(settingsRepositoryProvider);
  await repo.save(change(await repo.load()));
}

Future<void> _audit(WidgetRef ref, String action, [String? detail]) async {
  final session = ref.read(adminSessionProvider);
  await ref
      .read(auditLogProvider)
      .append(
        AuditEntry(
          at: ref.read(clockProvider).now(),
          actor: session?.user.name ?? 'admin',
          action: action,
          detail: detail,
        ),
      );
}

String weekdayLong(AppLocalizations l10n, int weekday) => switch (weekday) {
  DateTime.monday => l10n.weekday_1,
  DateTime.tuesday => l10n.weekday_2,
  DateTime.wednesday => l10n.weekday_3,
  DateTime.thursday => l10n.weekday_4,
  DateTime.friday => l10n.weekday_5,
  DateTime.saturday => l10n.weekday_6,
  DateTime.sunday => l10n.weekday_7,
  _ => l10n.common_none,
};

/// Shifts & rules: list, edit and add shifts (E08 holds the full engine).
class ShiftsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
    return SettingsPage(
      title: l10n.shifts_title,
      children: [
        SgCardList(
          children: [
            for (final s in shifts)
              SgListRow(
                title: s.name,
                subtitle: l10n.shifts_row_sub(
                  formatShiftWindow(s.startMinute, s.endMinute),
                  s.graceMinutes,
                ),
                showChevron: true,
                onTap: () => unawaited(_edit(context, ref, s)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SgButton(
          label: l10n.shifts_add,
          kind: SgButtonKind.secondary,
          icon: SgIcons.add,
          onPressed: () => unawaited(_edit(context, ref, null)),
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Shift? shift) async {
    await showSgSheet<bool>(context, builder: (_) => _ShiftSheet(shift: shift));
  }
}

class _ShiftSheet extends ConsumerStatefulWidget {
  const new({required this.shift});

  final Shift? shift;

  @override
  ConsumerState<_ShiftSheet> createState() => _ShiftSheetState();
}

class _ShiftSheetState extends ConsumerState<_ShiftSheet> {
  late final _name = TextEditingController(text: widget.shift?.name ?? '');
  late int _start = widget.shift?.startMinute ?? 14 * 60;
  late int _end = widget.shift?.endMinute ?? 22 * 60;
  late int _grace = widget.shift?.graceMinutes ?? 10;
  late int _weeklyOff = widget.shift?.weeklyOff ?? DateTime.sunday;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && _start != _end;

  Future<void> _time({required bool start}) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showSgTimePicker(
      context,
      title: start ? l10n.shift_starts : l10n.shift_ends,
      initialMinute: start ? _start : _end,
      confirmLabel: l10n.common_save,
      cancelLabel: l10n.common_cancel,
    );
    if (picked == null) return;
    setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _submit() async {
    final base =
        widget.shift ??
        Shift(
          id: newShiftId(),
          name: _name.text,
          startMinute: _start,
          endMinute: _end,
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
    await _audit(ref, 'shift.saved', _name.text.trim());
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SgSheetFrame(
      title: widget.shift == null ? l10n.shifts_new : l10n.shifts_edit,
      cancelLabel: l10n.common_cancel,
      confirmLabel: l10n.common_save,
      onCancel: () => Navigator.of(context).pop(false),
      onConfirm: _valid ? () => unawaited(_submit()) : null,
      child: SgSection(
        children: [
          SgTextField(
            label: l10n.shift_name,
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          SgPickerField(
            label: l10n.shift_starts,
            valueText: formatMinuteOfDay(_start),
            onTap: () => unawaited(_time(start: true)),
          ),
          SgPickerField(
            label: l10n.shift_ends,
            valueText: formatMinuteOfDay(_end),
            onTap: () => unawaited(_time(start: false)),
          ),
          if (_end <= _start && _start != _end)
            SgFieldNote(l10n.shift_endsNextDay),
          SgSelectField<int>(
            label: l10n.shift_grace,
            value: _grace,
            options: [
              for (final m in const [0, 5, 10, 15, 20, 30])
                SgOption(value: m, label: l10n.shift_graceValue(m)),
            ],
            onChanged: (m) => setState(() => _grace = m),
          ),
          SgSelectField<int>(
            label: l10n.shift_weeklyOff,
            value: _weeklyOff,
            options: [
              for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                SgOption(value: d, label: weekdayLong(l10n, d)),
              SgOption(value: 0, label: l10n.common_none),
            ],
            onChanged: (d) => setState(() => _weeklyOff = d),
          ),
        ],
      ),
    );
  }
}

var _shiftCounter = 0;

/// An ID for a shift created in the app (the data layer issues real ones).
String newShiftId() => 'shift-custom-${_shiftCounter++}';

/// Users & PINs (owner only): change the PIN of any role.
class UsersScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final users = ref.watch(usersProvider).value ?? const <AppUser>[];
    return SettingsPage(
      title: l10n.users_title,
      children: [
        SgCardList(
          children: [
            for (final u in users)
              SgListRow(
                title: roleLabel(l10n, u.role),
                subtitle: l10n.users_changePin,
                showChevron: true,
                onTap: () => unawaited(
                  showSgSheet<bool>(
                    context,
                    builder: (_) => _PinSheet(user: u),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(l10n.users_note, style: SgText.caption.copyWith(fontSize: 14)),
      ],
    );
  }
}

final FutureProvider<List<AppUser>> usersProvider =
    FutureProvider.autoDispose<List<AppUser>>((ref) {
      return ref.watch(userRepositoryProvider).users();
    });

class _PinSheet extends ConsumerStatefulWidget {
  const new({required this.user});

  final AppUser user;

  @override
  ConsumerState<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends ConsumerState<_PinSheet> {
  final _pin = TextEditingController();
  final _again = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    _again.dispose();
    super.dispose();
  }

  bool get _complete => RegExp(r'^\d{6}$').hasMatch(_pin.text);
  bool get _same => _pin.text == _again.text;

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    await ref.read(userRepositoryProvider).setPin(widget.user.id, _pin.text);
    await _audit(ref, 'user.pinChanged', widget.user.role.name);
    if (!mounted) return;
    Navigator.of(context).pop(true);
    showSgToast(context, l10n.users_saved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(PinPolicy.length),
    ];
    return SgSheetFrame(
      title: '${l10n.users_changePin} · ${roleLabel(l10n, widget.user.role)}',
      cancelLabel: l10n.common_cancel,
      confirmLabel: l10n.common_save,
      onCancel: () => Navigator.of(context).pop(false),
      onConfirm: _complete && _same ? () => unawaited(_submit()) : null,
      child: SgSection(
        children: [
          SgTextField(
            label: l10n.users_newPin,
            controller: _pin,
            obscure: true,
            keyboardType: TextInputType.number,
            inputFormatters: formatters,
            onChanged: (_) => setState(() {}),
          ),
          SgTextField(
            label: l10n.users_confirmPin,
            controller: _again,
            obscure: true,
            keyboardType: TextInputType.number,
            inputFormatters: formatters,
            onChanged: (_) => setState(() {}),
          ),
          if (_again.text.isNotEmpty && !_same)
            SgFieldNote(l10n.users_mismatch, color: SgColors.danger),
        ],
      ),
    );
  }
}

final StreamProvider<Map<String, String>> tallyMapProvider =
    StreamProvider.autoDispose<Map<String, String>>((ref) {
      return ref.watch(tallyMappingProvider).watch();
    });

/// Tally mapping: match each enrolled worker to their Tally employee.
class TallyScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final workers =
        (ref.watch(workersProvider).value ?? const <Worker>[])
            .where((w) => w.active && w.faceStatus == FaceStatus.enrolled)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final map = ref.watch(tallyMapProvider).value ?? const {};
    final matched = workers.where((w) => map.containsKey(w.id)).length;

    return SettingsPage(
      title: l10n.tally_title,
      children: [
        Text(
          l10n.tally_body,
          style: SgText.body.copyWith(color: SgColors.muted, fontSize: 17),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.tally_summary(matched, workers.length),
          style: SgText.bodyStrong,
        ),
        const SizedBox(height: 12),
        SgCardList(
          children: [
            for (final w in workers)
              SgListRow(
                title: w.name,
                subtitle: map[w.id] ?? w.code,
                trailing: Text(
                  map.containsKey(w.id) ? l10n.tally_matched : l10n.tally_toMap,
                  style: SgText.bodyStrong.copyWith(
                    color: map.containsKey(w.id)
                        ? SgColors.successText
                        : SgColors.warningText,
                  ),
                ),
                onTap: () => unawaited(_map(context, ref, w, map[w.id])),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _map(
    BuildContext context,
    WidgetRef ref,
    Worker worker,
    String? current,
  ) async {
    final l10n = AppLocalizations.of(context);
    final name = await showSgTextPrompt(
      context,
      title: worker.name,
      label: l10n.tally_enter,
      confirmLabel: l10n.common_save,
      cancelLabel: l10n.common_cancel,
    );
    if (name == null) return;
    await ref.read(tallyMappingProvider).set(worker.id, name);
    await _audit(ref, 'tally.mapped', worker.code);
  }
}

/// Language: the gate / default admin language.
class LanguageSettingsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected =
        ref.watch(settingsProvider).value?.language ?? AppLanguage.en;
    return SettingsPage(
      title: l10n.language_settings_title,
      children: [
        Text(
          l10n.language_settings_body,
          style: SgText.body.copyWith(color: SgColors.muted, fontSize: 17),
        ),
        const SizedBox(height: 16),
        for (final language in AppLanguage.values) ...[
          SgSelectRow(
            title: language.nativeName,
            subtitle: language.isAvailable
                ? language.englishName
                : '${language.englishName} · ${l10n.common_comingSoon}',
            selected: language == selected,
            dimmed: !language.isAvailable,
            onTap: language.isAvailable
                ? () => unawaited(
                    _save(ref, (s) => s.copyWith(language: language)),
                  )
                : () => showSgToast(context, l10n.common_comingSoon),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Gate settings: auto-return, cooldown, voice, fill light, clock format.
class GateSettingsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider).value ?? const AppSettings();

    Future<void> pickMinutes({
      required String title,
      required List<int> choices,
      required int current,
      required AppSettings Function(AppSettings, int) apply,
      int unit = 1,
    }) async {
      final picked = await showSgPicker<int>(
        context,
        title: title,
        selected: current,
        options: [
          for (final c in choices)
            SgOption(
              value: c,
              label: l10n.gateSettings_minutes((c / unit).round()),
            ),
        ],
      );
      if (picked != null) await _save(ref, (x) => apply(x, picked));
    }

    final volume = s.voiceVolume < 0.5
        ? 0
        : s.voiceVolume < 0.9
        ? 1
        : 2;

    return SettingsPage(
      title: l10n.gateSettings_title,
      children: [
        SgCardList(
          children: [
            SgListRow(
              title: l10n.gateSettings_autoReturn,
              subtitle: l10n.gateSettings_autoReturnSub,
              trailingText: l10n.gateSettings_minutes(s.idleMinutes),
              onTap: () => unawaited(
                pickMinutes(
                  title: l10n.gateSettings_autoReturn,
                  choices: const [1, 2, 5, 10],
                  current: s.idleMinutes,
                  apply: (x, v) => x.copyWith(idleMinutes: v),
                ),
              ),
            ),
            SgListRow(
              title: l10n.gateSettings_cooldown,
              subtitle: l10n.gateSettings_cooldownSub,
              trailingText: l10n.gateSettings_minutes(
                (s.cooldownSeconds / 60).round(),
              ),
              onTap: () => unawaited(
                pickMinutes(
                  title: l10n.gateSettings_cooldown,
                  choices: const [60, 120, 300],
                  current: s.cooldownSeconds,
                  unit: 60,
                  apply: (x, v) => x.copyWith(cooldownSeconds: v),
                ),
              ),
            ),
            SgListRow(
              title: l10n.gateSettings_volume,
              trailingText: [
                l10n.gateSettings_volumeLow,
                l10n.gateSettings_volumeMedium,
                l10n.gateSettings_volumeHigh,
              ][volume],
              onTap: () => unawaited(() async {
                final picked = await showSgPicker<int>(
                  context,
                  title: l10n.gateSettings_volume,
                  selected: volume,
                  options: [
                    SgOption(value: 0, label: l10n.gateSettings_volumeLow),
                    SgOption(value: 1, label: l10n.gateSettings_volumeMedium),
                    SgOption(value: 2, label: l10n.gateSettings_volumeHigh),
                  ],
                );
                if (picked != null) {
                  await _save(
                    ref,
                    (x) => x.copyWith(voiceVolume: [0.3, 0.7, 1.0][picked]),
                  );
                }
              }()),
            ),
            SgSwitchRow(
              title: l10n.gateSettings_fillLight,
              value: s.screenFillLight,
              onChanged: (v) =>
                  unawaited(_save(ref, (x) => x.copyWith(screenFillLight: v))),
            ),
            SgSwitchRow(
              title: l10n.gateSettings_clock24,
              value: s.use24HourClock,
              onChanged: (v) =>
                  unawaited(_save(ref, (x) => x.copyWith(use24HourClock: v))),
            ),
            SgSwitchRow(
              title: l10n.gateSettings_biometric,
              value: s.biometricEnabled,
              onChanged: (v) =>
                  unawaited(_save(ref, (x) => x.copyWith(biometricEnabled: v))),
            ),
          ],
        ),
      ],
    );
  }
}

/// Privacy & DPDP pack: notice version, consent coverage, face code count.
class PrivacyScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final workers = ref.watch(workersProvider).value ?? const <Worker>[];
    final agreed = ref.watch(consentedWorkersProvider).value?.length ?? 0;
    final faces = workers
        .where((w) => w.faceStatus == FaceStatus.enrolled)
        .length;
    return SettingsPage(
      title: l10n.privacy_title,
      children: [
        SgCardList(
          children: [
            SgListRow(
              title: l10n.privacy_notice,
              subtitle: l10n.privacy_noticeSub(noticeVersion),
            ),
            SgListRow(
              title: l10n.privacy_consents,
              trailingText: l10n.privacy_consentsValue(agreed, workers.length),
            ),
            SgListRow(
              title: l10n.privacy_faceStored,
              trailingText: l10n.privacy_faceStoredValue(faces),
            ),
            SgListRow(
              title: l10n.privacy_grievance,
              subtitle: l10n.privacy_grievanceValue,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(l10n.privacy_erase, style: SgText.caption.copyWith(fontSize: 14)),
      ],
    );
  }
}

/// About: version, build and where data lives.
class AboutScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(appConfigProvider);
    return SettingsPage(
      title: l10n.about_title,
      children: [
        const Center(child: SgLogo(size: 72)),
        const SizedBox(height: 12),
        Center(child: Text(l10n.app_name, style: SgText.title)),
        const SizedBox(height: 20),
        SgCardList(
          children: [
            SgListRow(title: l10n.about_version, trailingText: '0.1.0 (1)'),
            SgListRow(
              title: l10n.about_build,
              trailingText: config.flavour.name,
            ),
            SgListRow(
              title: l10n.about_data,
              trailingText: l10n.about_dataValue,
            ),
          ],
        ),
      ],
    );
  }
}
