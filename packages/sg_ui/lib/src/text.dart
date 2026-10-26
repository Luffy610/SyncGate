import 'package:flutter/painting.dart';
import 'package:sg_ui/src/tokens.dart';

/// Type scale from the frontend plan §4.2. Gate sizes were re-measured from
/// the design PNGs (2x exports): the plan's prompt and clock sizes are in
/// export pixels, so they are halved here.
///
/// Fonts: IBM Plex Sans is not bundled yet (needs the OFL font files), so
/// text uses the platform font; Indic scripts fall back to the system's Noto
/// fonts. Only sizes and weights are fixed here.
abstract final class SgText {
  static const _mono = <String>['monospace', 'Courier'];
  static const _tabular = [FontFeature.tabularFigures()];

  static const gatePrompt = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    height: 1.15,
  );
  static const gatePromptSecondary = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );
  static const gateName = TextStyle(
    fontSize: 38,
    fontWeight: FontWeight.w700,
    height: 1.1,
  );
  static const gateClock = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w600,
    fontFamilyFallback: _mono,
    fontFeatures: _tabular,
    height: 1,
  );
  static const titleLarge = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: SgColors.ink,
  );
  static const titleAndroid = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: SgColors.ink,
  );
  static const title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: SgColors.ink,
  );
  static const heading = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: SgColors.ink,
    height: 1.15,
  );
  static const body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: SgColors.ink,
  );
  static const bodyStrong = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: SgColors.ink,
  );
  static const label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: SgColors.muted,
  );
  static const caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: SgColors.muted,
  );
  static const mono = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    fontFamilyFallback: _mono,
    fontFeatures: _tabular,
    color: SgColors.ink,
  );
}
