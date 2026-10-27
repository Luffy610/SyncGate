import 'package:flutter/widgets.dart';
import 'package:sg_domain/sg_domain.dart';
import 'package:sg_l10n/sg_l10n.dart';
import 'package:sg_vision/sg_vision.dart';

/// Gate copy is bilingual: the device language first, English second
/// (frontend plan §5). Both come from the same ARB keys.
class GateCopy {
  const new(this.primary, this.english);

  factory of(BuildContext context) => GateCopy(
    AppLocalizations.of(context),
    lookupAppLocalizations(const Locale('en')),
  );

  final AppLocalizations primary;
  final AppLocalizations english;

  /// False when the device language is already English.
  bool get bilingual => primary.localeName != english.localeName;
}

/// Strings in a worker's own language, falling back to English for languages
/// that have no translations yet.
AppLocalizations workerCopy(Worker worker) {
  final language = worker.language;
  return lookupAppLocalizations(
    Locale(language.isAvailable ? language.code : 'en'),
  );
}

String directionLabel(AppLocalizations l10n, Direction direction) =>
    direction == Direction.checkIn ? l10n.attendance_in : l10n.attendance_out;

String qualityHintText(AppLocalizations l10n, QualityIssue? issue) =>
    switch (issue) {
      null => l10n.gate_hint_default,
      QualityIssue.tooDark => l10n.gate_hint_tooDark,
      QualityIssue.backlight => l10n.gate_hint_backlight,
      QualityIssue.tooFar => l10n.gate_hint_tooFar,
      QualityIssue.turnLess => l10n.gate_hint_turnLess,
      QualityIssue.blurry => l10n.gate_hint_blurry,
      QualityIssue.covered => l10n.gate_hint_covered,
      QualityIssue.dirtyLens => l10n.gate_hint_dirtyLens,
    };

String manualReasonLabel(AppLocalizations l10n, ManualReason reason) =>
    switch (reason) {
      ManualReason.notRecognised => l10n.reason_notRecognised,
      ManualReason.maskHelmet => l10n.reason_maskHelmet,
      ManualReason.injury => l10n.reason_injury,
      ManualReason.cameraIssue => l10n.reason_cameraIssue,
      ManualReason.newWorker => l10n.reason_newWorker,
    };
