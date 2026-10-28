import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:syncgate/src/app/providers.dart';

enum ReportView { daily, monthly }

class ReportViewController extends Notifier<ReportView> {
  @override
  ReportView build() => ReportView.monthly;

  // ignore: use_setters_to_change_properties, a Notifier method is clearer.
  void select(ReportView view) => state = view;
}

final reportViewProvider = NotifierProvider<ReportViewController, ReportView>(
  ReportViewController.new,
);

class ReportFilterController extends Notifier<ReportFilter> {
  @override
  ReportFilter build() {
    final today = ref.read(todayProvider);
    return ReportFilter(month: DateTime(today.year, today.month));
  }

  // ignore: use_setters_to_change_properties, a Notifier method is clearer.
  void set(ReportFilter filter) => state = filter;
}

final reportFilterProvider =
    NotifierProvider<ReportFilterController, ReportFilter>(
      ReportFilterController.new,
    );

class ReportDayController extends Notifier<DateTime> {
  @override
  DateTime build() => ref.read(todayProvider);

  // ignore: use_setters_to_change_properties, a Notifier method is clearer.
  void set(DateTime day) => state = day;
}

final reportDayProvider = NotifierProvider<ReportDayController, DateTime>(
  ReportDayController.new,
);

/// Which export format is selected.
class ExportFormatController extends Notifier<ExportFormat> {
  @override
  ExportFormat build() => ExportFormat.excel;

  // ignore: use_setters_to_change_properties, a Notifier method is clearer.
  void select(ExportFormat format) => state = format;
}

final exportFormatProvider =
    NotifierProvider<ExportFormatController, ExportFormat>(
      ExportFormatController.new,
    );

/// The monthly muster for the current filter. Recomputed when today's marks
/// or the exceptions change.
final FutureProvider<List<MusterRow>> musterProvider =
    FutureProvider.autoDispose<List<MusterRow>>((ref) {
      final filter = ref.watch(reportFilterProvider);
      ref
        ..watch(todayEventsProvider)
        ..watch(exceptionsProvider)
        ..watch(workersProvider);
      return ref.watch(reportServiceProvider).monthly(filter);
    });

final FutureProvider<List<DailyRow>> dailyReportProvider =
    FutureProvider.autoDispose<List<DailyRow>>((ref) {
      final day = ref.watch(reportDayProvider);
      ref
        ..watch(todayEventsProvider)
        ..watch(exceptionsProvider);
      return ref.watch(reportServiceProvider).daily(day);
    });

final Provider<int> workingDaysProvider = Provider.autoDispose<int>((ref) {
  final filter = ref.watch(reportFilterProvider);
  ref.watch(nowProvider.select((n) => n.day));
  return ref.watch(reportServiceProvider).workingDays(filter.month);
});

@immutable
class TallyMatch {
  const new(this.matched, this.total);

  final int matched;
  final int total;

  int get toMap => total - matched;
}

final FutureProvider<TallyMatch> tallyMatchProvider =
    FutureProvider.autoDispose<TallyMatch>((ref) async {
      ref.watch(workersProvider);
      final match = await ref.watch(exportServiceProvider).tallyMatch();
      return TallyMatch(match.matched, match.total);
    });
