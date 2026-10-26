import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:syncgate/src/app/providers.dart';

/// The notice shown before enrolment is versioned content, not UI strings
/// (frontend plan §5).
const noticeVersion = 'v0-draft';

/// Placeholder until legal confirms the basis (TBD-L1).
const legalBasisPlaceholder = '[CONSENT OR LEGITIMATE USE — TBD]';

/// Formats a date as `DD-MM-YYYY` while typing: digits only, hyphens inserted
/// after the day and month.
class DateInputFormatter extends TextInputFormatter {
  const new();

  static String format(String text) {
    final digits = text.replaceAll(RegExp('[^0-9]'), '');
    final capped = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buffer = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i == 2 || i == 4) buffer.write('-');
      buffer.write(capped[i]);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = format(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

@immutable
class EnrolmentForm {
  const new({
    this.workerId,
    this.name = '',
    this.code = '',
    this.dob = '',
    this.department,
    this.designation = '',
    this.shiftId,
    this.contractor,
    this.phone = '',
    this.language = AppLanguage.hi,
    this.showErrors = false,
    this.codeTaken = false,
  });

  /// Set once the worker has been created (after the details step).
  final String? workerId;
  final String name;
  final String code;
  final String dob;
  final String? department;
  final String designation;
  final String? shiftId;
  final String? contractor;
  final String phone;
  final AppLanguage language;
  final bool showErrors;
  final bool codeTaken;

  DateTime? get dateOfBirth => AttendanceRules.parseDate(dob);

  bool get dobComplete => dob.length == 10;

  EnrolmentForm copyWith({
    String? workerId,
    String? name,
    String? code,
    String? dob,
    String? department,
    String? designation,
    String? shiftId,
    String? contractor,
    bool clearContractor = false,
    String? phone,
    AppLanguage? language,
    bool? showErrors,
    bool? codeTaken,
  }) => EnrolmentForm(
    workerId: workerId ?? this.workerId,
    name: name ?? this.name,
    code: code ?? this.code,
    dob: dob ?? this.dob,
    department: department ?? this.department,
    designation: designation ?? this.designation,
    shiftId: shiftId ?? this.shiftId,
    contractor: clearContractor ? null : contractor ?? this.contractor,
    phone: phone ?? this.phone,
    language: language ?? this.language,
    showErrors: showErrors ?? this.showErrors,
    codeTaken: codeTaken ?? this.codeTaken,
  );
}

/// The enrolment form and the worker it creates, shared by the three screens
/// of the flow (details, notice, face).
class EnrolmentController extends Notifier<EnrolmentForm> {
  @override
  EnrolmentForm build() => const EnrolmentForm();

  /// Starts a new enrolment with an auto-assigned ID and the current shift.
  Future<void> startNew() async {
    final code = await ref.read(workerRepositoryProvider).nextCode();
    // Read from the repository: the shift stream may not have loaded yet.
    final shifts = await ref.read(shiftRepositoryProvider).all();
    final now = ref.read(clockProvider).now();
    final shift =
        shifts.where((s) => s.isRunningAt(now)).firstOrNull ??
        shifts.firstOrNull;
    state = EnrolmentForm(code: code, shiftId: shift?.id);
  }

  /// Continues enrolment for a worker who already exists (needs a face).
  Future<void> startFor(Worker worker) async {
    state = EnrolmentForm(
      workerId: worker.id,
      name: worker.name,
      code: worker.code,
      department: worker.department,
      designation: worker.designation,
      shiftId: worker.shiftId,
      contractor: worker.contractor,
      phone: worker.phone ?? '',
      language: worker.language,
    );
  }

  void update(EnrolmentForm Function(EnrolmentForm) change) {
    state = change(state).copyWith(codeTaken: false);
  }

  /// Why the form can't be submitted yet, or `null` if it can.
  bool get isValid {
    final form = state;
    final dob = form.dateOfBirth;
    return form.name.trim().isNotEmpty &&
        form.code.trim().isNotEmpty &&
        dob != null &&
        AttendanceRules.isAdult(dob, ref.read(clockProvider).now()) &&
        form.department != null &&
        form.designation.trim().isNotEmpty &&
        form.shiftId != null;
  }

  /// Creates the worker (needing a face) or updates the one already made.
  /// Returns `false` if the form is invalid or the ID is taken.
  Future<bool> submitDetails() async {
    state = state.copyWith(showErrors: true);
    if (!isValid) return false;
    final repo = ref.read(workerRepositoryProvider);
    final form = state;
    final unique = await repo.isCodeUnique(
      form.code,
      exceptWorkerId: form.workerId,
    );
    if (!unique) {
      state = state.copyWith(codeTaken: true);
      return false;
    }
    final phone = form.phone.trim().isEmpty ? null : form.phone.trim();
    if (form.workerId == null) {
      final created = await repo.add(
        NewWorker(
          code: form.code.trim(),
          name: form.name.trim(),
          dateOfBirth: form.dateOfBirth!,
          department: form.department!,
          designation: form.designation.trim(),
          shiftId: form.shiftId!,
          language: form.language,
          contractor: form.contractor,
          phone: phone,
        ),
      );
      state = state.copyWith(workerId: created.id);
      await ref
          .read(auditLogProvider)
          .append(
            AuditEntry(
              at: ref.read(clockProvider).now(),
              actor: 'admin',
              action: 'worker.created',
              detail: created.code,
            ),
          );
    } else {
      final existing = await repo.byId(form.workerId!);
      if (existing != null) {
        await repo.update(
          existing.copyWith(
            code: form.code.trim(),
            name: form.name.trim(),
            dateOfBirth: form.dateOfBirth,
            department: form.department,
            designation: form.designation.trim(),
            shiftId: form.shiftId,
            contractor: form.contractor,
            phone: phone,
            language: form.language,
          ),
        );
      }
    }
    return true;
  }
}

final enrolmentProvider = NotifierProvider<EnrolmentController, EnrolmentForm>(
  EnrolmentController.new,
);

final FutureProvider<List<String>> departmentsProvider =
    FutureProvider.autoDispose<List<String>>((ref) {
      return ref.watch(workerRepositoryProvider).departments();
    });

final FutureProvider<List<String>> contractorsProvider =
    FutureProvider.autoDispose<List<String>>((ref) {
      return ref.watch(workerRepositoryProvider).contractors();
    });
