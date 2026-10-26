import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/providers.dart';
import 'package:syncgate/src/app/routes.dart';
import 'package:syncgate/src/features/enrolment/enrolment_draft.dart';

String _window(Shift s) => formatShiftWindow(s.startMinute, s.endMinute);

/// New worker · step 1 of 3 (design 12).
class EnrolDetailsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<EnrolDetailsScreen> createState() => _EnrolDetailsScreenState();
}

class _EnrolDetailsScreenState extends ConsumerState<EnrolDetailsScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _dob = TextEditingController();
  final _designation = TextEditingController();
  final _phone = TextEditingController();
  var _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final controller = ref.read(enrolmentProvider.notifier);
    // Coming back from the notice step keeps what was typed.
    if (ref.read(enrolmentProvider).workerId == null) {
      await controller.startNew();
    }
    if (!mounted) return;
    final form = ref.read(enrolmentProvider);
    setState(() {
      _name.text = form.name;
      _code.text = form.code;
      _dob.text = form.dob;
      _designation.text = form.designation;
      _phone.text = form.phone;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _dob.dispose();
    _designation.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.workers);
    }
  }

  Future<void> _next() async {
    final ok = await ref.read(enrolmentProvider.notifier).submitDetails();
    if (ok && mounted) unawaited(context.push(Routes.enrolNotice));
  }

  Future<String?> _addDepartment(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final name = await showSgTextPrompt(
      context,
      title: l10n.enrol_department_newTitle,
      label: l10n.enrol_department_newLabel,
      confirmLabel: l10n.common_add,
      cancelLabel: l10n.common_cancel,
    );
    if (name == null) return null;
    await ref.read(workerRepositoryProvider).addDepartment(name);
    ref.invalidate(departmentsProvider);
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final form = ref.watch(enrolmentProvider);
    final controller = ref.read(enrolmentProvider.notifier);
    final departments = ref.watch(departmentsProvider).value ?? const [];
    final contractors = ref.watch(contractorsProvider).value ?? const [];
    final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
    final now = ref.watch(nowProvider);
    final gutter = context.sg.gutter;

    final dob = form.dateOfBirth;
    String? dobNote;
    var dobOk = true;
    if (form.dobComplete) {
      if (dob == null) {
        dobNote = l10n.enrol_dob_invalid;
        dobOk = false;
      } else {
        final age = AttendanceRules.ageOn(dob, now);
        dobOk = age >= AttendanceRules.minimumAge;
        dobNote = dobOk ? l10n.enrol_age_ok(age) : l10n.enrol_age_under(age);
      }
    }
    final showErrors = form.showErrors;
    String? required(String value) =>
        showErrors && value.trim().isEmpty ? l10n.enrol_required : null;

    return SgScaffold(
      topBar: SgTopBar(
        title: l10n.enrol_title,
        leading: SgLeading.close,
        leadingLabel: l10n.common_cancel,
        onLeading: _leave,
        actions: [
          SgBarAction(
            icon: SgIcons.check,
            label: l10n.common_next,
            textAction: true,
            onTap: _ready ? () => unawaited(_next()) : null,
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: SgSpinner())
          : SgScrollColumn(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 32),
              children: [
                SgFlowSteps(
                  current: 1,
                  labels: [
                    l10n.enrol_step_details,
                    l10n.enrol_step_notice,
                    l10n.enrol_step_face,
                  ],
                ),
                const SizedBox(height: 12),
                SgSection(
                  header: l10n.enrol_section_worker,
                  androidHeader: false,
                  children: [
                    SgTextField(
                      label: l10n.enrol_field_name,
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      errorText: required(form.name),
                      onChanged: (v) =>
                          controller.update((f) => f.copyWith(name: v)),
                    ),
                    SgTextField(
                      label: l10n.enrol_field_code,
                      controller: _code,
                      mono: true,
                      errorText: form.codeTaken
                          ? l10n.enrol_code_taken
                          : required(form.code),
                      onChanged: (v) =>
                          controller.update((f) => f.copyWith(code: v)),
                    ),
                    SgFieldNote(l10n.enrol_field_codeHelp),
                    SgTextField(
                      label: l10n.enrol_field_dob,
                      controller: _dob,
                      keyboardType: TextInputType.number,
                      hint: l10n.enrol_field_dobHint,
                      inputFormatters: const [DateInputFormatter()],
                      errorText: showErrors && form.dob.isEmpty
                          ? l10n.enrol_required
                          : null,
                      onChanged: (v) =>
                          controller.update((f) => f.copyWith(dob: v)),
                    ),
                    if (dobNote != null)
                      SgFieldNote(
                        dobNote,
                        color: dobOk ? SgColors.successText : SgColors.danger,
                      ),
                  ],
                ),
                SgSection(
                  header: l10n.enrol_section_work,
                  androidHeader: false,
                  children: [
                    SgSelectField<String>(
                      label: l10n.enrol_field_department,
                      value: form.department,
                      placeholder: showErrors && form.department == null
                          ? l10n.enrol_required
                          : null,
                      options: [
                        for (final d in departments)
                          SgOption(value: d, label: d),
                      ],
                      extraAction: SgPickerAction<String>(
                        label: l10n.enrol_department_add,
                        run: _addDepartment,
                      ),
                      onChanged: (v) =>
                          controller.update((f) => f.copyWith(department: v)),
                    ),
                    SgTextField(
                      label: l10n.enrol_field_designation,
                      controller: _designation,
                      textCapitalization: TextCapitalization.sentences,
                      errorText: required(form.designation),
                      onChanged: (v) =>
                          controller.update((f) => f.copyWith(designation: v)),
                    ),
                    SgSelectField<String>(
                      label: l10n.enrol_field_shift,
                      value: form.shiftId,
                      options: [
                        for (final s in shifts)
                          SgOption(
                            value: s.id,
                            label: '${s.name} · ${_window(s)}',
                          ),
                      ],
                      onChanged: (v) =>
                          controller.update((f) => f.copyWith(shiftId: v)),
                    ),
                    SgSelectField<String>(
                      label: l10n.enrol_field_contractor,
                      value: form.contractor ?? '',
                      options: [
                        SgOption(
                          value: '',
                          label: l10n.enrol_field_contractorNone,
                        ),
                        for (final c in contractors)
                          SgOption(value: c, label: c),
                      ],
                      onChanged: (v) => controller.update(
                        (f) => v.isEmpty
                            ? f.copyWith(clearContractor: true)
                            : f.copyWith(contractor: v),
                      ),
                    ),
                  ],
                ),
                SgSection(
                  header: l10n.enrol_section_contact,
                  androidHeader: false,
                  children: [
                    SgTextField(
                      label: l10n.enrol_field_phone,
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      hint: l10n.enrol_field_phoneHint,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp('[0-9+ ]')),
                      ],
                      onChanged: (v) =>
                          controller.update((f) => f.copyWith(phone: v)),
                    ),
                    SgSelectField<AppLanguage>(
                      label: l10n.enrol_field_language,
                      value: form.language,
                      options: [
                        for (final lang in AppLanguage.values)
                          SgOption(
                            value: lang,
                            label: '${lang.nativeName} · ${lang.englishName}',
                          ),
                      ],
                      onChanged: (v) =>
                          controller.update((f) => f.copyWith(language: v)),
                    ),
                    SgFieldNote(l10n.enrol_field_languageHelp),
                  ],
                ),
              ],
            ),
    );
  }
}
