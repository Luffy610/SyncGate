import 'package:flutter/painting.dart';

/// Colour tokens from ADR-0005 §2. A change here is a design review item.
///
/// Values marked "≈" in the frontend plan §4.1 were read from the PNG exports
/// and are pending confirmation against the canvas (D-2).
abstract final class SgColors {
  static const white = Color(0xFFFFFFFF);
  static const transparent = Color(0x00000000);

  // Light surfaces.
  static const ink = Color(0xFF15171A);
  static const groundIos = Color(0xFFF2F1ED);
  static const groundAndroid = Color(0xFFF7F6F2);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFE6E4DD);
  static const muted = Color(0xFF5E615F);

  /// Fill only, never as text on light backgrounds.
  static const brandYellow = Color(0xFFFFC21A);

  /// Selected row / card fill (≈).
  static const brandYellowTint = Color(0xFFFFF3CC);

  /// Selected chip / segment fill on Android (≈).
  static const brandYellowSoft = Color(0xFFFFE6A3);

  // Gate (dark).
  static const gateBg = Color(0xFF101214);
  static const gatePanel = Color(0xFF16191C);
  static const gateCard = Color(0xFF1C1F23);
  static const gateText = Color(0xFFFFFFFF);
  static const gateMuted = Color(0xFF9AA0A6);
  static const gateLine = Color(0xFF2A2E33);
  static const silhouette = Color(0xFF2B2F36);

  // Status.
  static const successFill = Color(0xFF0E7A45);
  static const successText = Color(0xFF0B7A43);
  static const successOnDark = Color(0xFF3DDC84);
  static const successTint = Color(0xFFE5F3EB);
  static const danger = Color(0xFFA8261C);
  static const dangerTint = Color(0xFFFBE4E1);
  static const warningBg = Color(0xFFFDF0D2);
  static const warningText = Color(0xFF6B4100);
  static const warningIcon = Color(0xFFB26A00);
  static const infoBg = Color(0xFFE7ECF8);
  static const infoText = Color(0xFF1F3F8F);
}

/// 4-pt spacing scale.
abstract final class SgSpace {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
}

/// Radii that differ per platform are resolved in `SgTokens`; these are the
/// ones shared by both.
abstract final class SgRadius {
  static const double gatePanel = 28;
  static const double sheetTop = 28;
}

/// Motion durations and gate timings.
abstract final class SgMotion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const gateConfirmHold = Duration(milliseconds: 1500);
  static const notRecognisedRetry = Duration(seconds: 3);
}

/// Minimum touch target (accessibility, plan §8).
const double sgMinTouch = 48;

/// Widest layout; tablets get the phone layout centred (ADR-0001).
const double sgMaxContentWidth = 600;
