import 'package:flutter/material.dart';
import 'package:sg_ui/src/tokens.dart';

/// Everything about the look that is not in `ThemeData`, resolved once per
/// platform (frontend plan §4.3).
@immutable
class SgTokens extends ThemeExtension<SgTokens> {
  const new({
    required this.isIos,
    required this.ground,
    required this.gutter,
    required this.cardRadius,
    required this.chipRadius,
    required this.buttonRadius,
    required this.buttonHeight,
    required this.navHeight,
  });

  factory forPlatform(TargetPlatform platform) {
    final ios = platform == TargetPlatform.iOS;
    return SgTokens(
      isIos: ios,
      ground: ios ? SgColors.groundIos : SgColors.groundAndroid,
      gutter: ios ? 20 : 16,
      cardRadius: ios ? 12 : 16,
      chipRadius: ios ? 18 : 8,
      buttonRadius: ios ? 12 : 24,
      buttonHeight: ios ? 50 : 48,
      navHeight: ios ? 83 : 80,
    );
  }

  final bool isIos;
  final Color ground;
  final double gutter;
  final double cardRadius;
  final double chipRadius;
  final double buttonRadius;
  final double buttonHeight;
  final double navHeight;

  @override
  SgTokens copyWith({bool? isIos}) => isIos == null
      ? this
      : SgTokens.forPlatform(
          isIos ? TargetPlatform.iOS : TargetPlatform.android,
        );

  @override
  SgTokens lerp(ThemeExtension<SgTokens>? other, double t) => this;
}

/// Looks up the active tokens: `context.sg.isIos`, `context.sg.gutter`.
extension SgContext on BuildContext {
  SgTokens get sg =>
      Theme.of(this).extension<SgTokens>() ??
      SgTokens.forPlatform(Theme.of(this).platform);

  bool get isIos => sg.isIos;
}

/// App themes. The platform decides the chrome; the brand is the same.
abstract final class SgTheme {
  static ThemeData light(TargetPlatform platform) {
    final tokens = SgTokens.forPlatform(platform);
    final scheme = ColorScheme.fromSeed(seedColor: SgColors.brandYellow)
        .copyWith(
          primary: SgColors.ink,
          onPrimary: Colors.white,
          surface: tokens.ground,
          onSurface: SgColors.ink,
          secondary: SgColors.brandYellow,
          onSecondary: SgColors.ink,
          error: SgColors.danger,
        );
    return ThemeData(
      useMaterial3: true,
      platform: platform,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.ground,
      canvasColor: tokens.ground,
      splashFactory: InkRipple.splashFactory,
      dividerColor: SgColors.line,
      extensions: [tokens],
    );
  }

  /// Dark theme for the gate and face capture.
  static ThemeData gate(TargetPlatform platform) {
    final tokens = SgTokens.forPlatform(platform);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: SgColors.brandYellow,
          brightness: Brightness.dark,
        ).copyWith(
          primary: SgColors.brandYellow,
          onPrimary: SgColors.ink,
          surface: SgColors.gateBg,
          onSurface: Colors.white,
          error: SgColors.danger,
        );
    return ThemeData(
      useMaterial3: true,
      platform: platform,
      colorScheme: scheme,
      scaffoldBackgroundColor: SgColors.gateBg,
      canvasColor: SgColors.gateBg,
      brightness: Brightness.dark,
      extensions: [tokens],
    );
  }
}

/// Applies the dark gate theme to everything below it (gate, manual entry,
/// face capture).
class SgGateScope extends StatelessWidget {
  const new({required this.platform, required this.child, super.key});

  final TargetPlatform platform;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: SgTheme.gate(platform), child: child);
}
