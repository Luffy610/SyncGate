import 'package:flutter/material.dart';
import 'package:sg_ui/src/components/basics.dart';
import 'package:sg_ui/src/text.dart';
import 'package:sg_ui/src/theme.dart';
import 'package:sg_ui/src/tokens.dart';

enum SgButtonKind {
  /// Ink fill, white text.
  primary,

  /// Brand yellow fill, ink text (gate actions).
  brand,

  /// White fill with a hairline border.
  secondary,

  /// Transparent with a visible border.
  outline,

  /// Text only; underlined when [SgButton.underline] is set.
  text,

  /// Red text only.
  danger,

  /// White fill, for use on a coloured panel.
  onColor,

  /// White outline, for use on a coloured panel.
  onColorOutline,

  /// Outline on the dark gate (light border and text).
  gateOutline,
}

/// The one button. Radius and height follow the platform (ADR-0005).
class SgButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    this.kind = SgButtonKind.primary,
    this.icon,
    this.expand = true,
    this.large = false,
    this.underline = false,
    this.foreground,
    this.semanticLabel,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final SgButtonKind kind;
  final IconData? icon;
  final bool expand;

  /// 56 dp tall, for the gate where buttons are pressed in a hurry.
  final bool large;
  final bool underline;

  /// Overrides the text colour (used by [SgButtonKind.onColor]).
  final Color? foreground;
  final String? semanticLabel;

  static const _outlineBorder = Color(0xFFA9ABA8);

  @override
  Widget build(BuildContext context) {
    final tokens = context.sg;
    final enabled = onPressed != null;
    final textOnly = kind == SgButtonKind.text || kind == SgButtonKind.danger;

    final (Color fill, Color text, Color? border) = switch (kind) {
      SgButtonKind.primary => (SgColors.ink, Colors.white, null),
      SgButtonKind.brand => (SgColors.brandYellow, SgColors.ink, null),
      SgButtonKind.secondary => (
        SgColors.surface,
        SgColors.ink,
        _outlineBorder,
      ),
      SgButtonKind.outline => (
        Colors.transparent,
        SgColors.ink,
        _outlineBorder,
      ),
      SgButtonKind.text => (Colors.transparent, SgColors.ink, null),
      SgButtonKind.danger => (Colors.transparent, SgColors.danger, null),
      SgButtonKind.onColor => (Colors.white, SgColors.ink, null),
      SgButtonKind.onColorOutline => (
        Colors.transparent,
        Colors.white,
        Colors.white,
      ),
      SgButtonKind.gateOutline => (
        Colors.transparent,
        Colors.white,
        SgColors.gateLine,
      ),
    };
    final textColor = foreground ?? text;

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 22, color: textColor),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: SgText.bodyStrong.copyWith(
              color: textColor,
              fontSize: 17,
              decoration: underline ? TextDecoration.underline : null,
            ),
          ),
        ),
      ],
    );

    final radius = tokens.buttonRadius;
    final minHeight = textOnly
        ? sgMinTouch
        : large
        ? 56.0
        : tokens.buttonHeight;

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(radius),
          border: border == null ? null : Border.all(color: border, width: 1.5),
        ),
        child: SgTap(
          onTap: onPressed,
          radius: radius,
          semanticLabel: semanticLabel ?? label,
          minSize: minHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Icon-only button with a 48 dp target and a required semantic label.
class SgIconButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color = SgColors.ink,
    this.background,
    this.bordered = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color? background;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: bordered
            ? Border.all(color: SgColors.gateLine, width: 1.5)
            : null,
      ),
      child: SgTap(
        onTap: onPressed,
        semanticLabel: label,
        radius: 16,
        child: SizedBox(
          width: sgMinTouch,
          height: sgMinTouch,
          child: Icon(icon, color: color, size: 26),
        ),
      ),
    );
  }
}
