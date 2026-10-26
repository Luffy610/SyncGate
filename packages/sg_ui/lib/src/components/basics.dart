import 'package:flutter/material.dart';
import 'package:sg_ui/src/text.dart';
import 'package:sg_ui/src/theme.dart';
import 'package:sg_ui/src/tokens.dart';

/// Stroke icons used across the app. The designs use one outline set on both
/// platforms; the export format (font vs SVG) is open item D-3.
abstract final class SgIcons {
  static const IconData lock = Icons.lock_outline;
  static const IconData back = Icons.arrow_back;
  static const IconData backIos = Icons.chevron_left;
  static const IconData close = Icons.close;
  static const IconData more = Icons.more_vert;
  static const IconData search = Icons.search;
  static const IconData home = Icons.home_outlined;
  static const IconData homeActive = Icons.home;
  static const IconData people = Icons.people_outline;
  static const IconData peopleActive = Icons.people;
  static const IconData reports = Icons.insert_chart_outlined;
  static const IconData reportsActive = Icons.insert_chart;
  static const IconData settings = Icons.tune;
  static const IconData add = Icons.add;
  static const IconData faceScan = Icons.center_focus_strong_outlined;
  static const IconData backup = Icons.cloud_upload_outlined;
  static const IconData flag = Icons.flag_outlined;
  static const IconData check = Icons.check;
  static const IconData checkCircle = Icons.check_circle_outline;
  static const IconData chevron = Icons.chevron_right;
  static const IconData expand = Icons.keyboard_arrow_down;
  static const IconData dropdown = Icons.arrow_drop_down;
  static const IconData volume = Icons.volume_up_outlined;
  static const IconData warning = Icons.warning_amber_rounded;
  static const IconData sun = Icons.wb_sunny_outlined;
  static const IconData qr = Icons.qr_code_scanner;
  static const IconData offline = Icons.wifi_off;
  static const IconData fingerprint = Icons.fingerprint;
  static const IconData faceId = Icons.face_unlock_outlined;
  static const IconData backspace = Icons.backspace_outlined;
  static const IconData share = Icons.share_outlined;
  static const IconData shareIos = Icons.ios_share;
  static const IconData shield = Icons.verified_user_outlined;
  static const IconData document = Icons.description_outlined;
  static const IconData refresh = Icons.refresh;
  static const IconData clock = Icons.access_time;
  static const IconData person = Icons.person_outline;
  static const IconData phone = Icons.smartphone;
  static const IconData camera = Icons.photo_camera_outlined;
  static const IconData info = Icons.info_outline;
  static const IconData edit = Icons.edit_outlined;
  static const IconData keyboardUp = Icons.keyboard_arrow_up;
  static const IconData globe = Icons.language;
}

/// A tappable area with a ripple, a button role for screen readers and a
/// minimum 48 dp touch target.
class SgTap extends StatelessWidget {
  const new({
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.radius = 12,
    this.minSize = sgMinTouch,
    this.selected,
    this.toggled,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double radius;
  final double minSize;
  final bool? selected;

  /// For switch-like rows: announced as on / off.
  final bool? toggled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      toggled: toggled,
      label: semanticLabel,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minSize, minWidth: minSize),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// White card with the platform card radius and a hairline border.
class SgCard extends StatelessWidget {
  const new({
    required this.child,
    this.padding = const EdgeInsets.all(SgSpace.s4),
    this.color = SgColors.surface,
    this.borderColor = SgColors.line,
    this.selected = false,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final bool selected;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final radius = context.sg.cardRadius;
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected ? SgColors.ink : borderColor,
          width: selected ? 2 : 1,
        ),
      ),
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : SgTap(
              onTap: onTap,
              radius: radius,
              semanticLabel: semanticLabel,
              selected: selected,
              minSize: 0,
              child: Padding(padding: padding, child: child),
            ),
    );
    return box;
  }
}

/// Centres content and caps its width on tablets.
class SgMaxWidth extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: sgMaxContentWidth),
        child: child,
      ),
    );
  }
}

/// Progress spinner in the brand colour.
class SgSpinner extends StatelessWidget {
  const new({this.size = 24, this.color = SgColors.ink, super.key});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
    );
  }
}

/// Initials in a circle; never a photo (ADR-0005 §4).
class SgAvatarInitials extends StatelessWidget {
  const new({
    required this.name,
    this.size = 48,
    this.background = const Color(0xFFE9E7E1),
    this.foreground = SgColors.ink,
    super.key,
  });

  final String name;
  final double size;
  final Color background;
  final Color foreground;

  static String initialsOf(String name) {
    final parts = name
        .split(RegExp(r'[\s.]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Text(
          initialsOf(name),
          style: SgText.bodyStrong.copyWith(
            color: foreground,
            fontSize: size * 0.33,
          ),
        ),
      ),
    );
  }
}

/// Small coloured label, e.g. MISSING OUT / MANUAL / CLOCK.
class SgStatusTag extends StatelessWidget {
  const new({
    required this.label,
    required this.background,
    required this.foreground,
    super.key,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: SgText.label.copyWith(color: foreground, fontSize: 12),
      ),
    );
  }
}

/// Pill with a status dot, e.g. "● Live preview" or "● App pinning off".
class SgDotPill extends StatelessWidget {
  const new({
    required this.label,
    required this.dot,
    this.background = SgColors.gatePanel,
    this.foreground = Colors.white,
    super.key,
  });

  final String label;
  final Color dot;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: SgText.bodyStrong.copyWith(
                color: foreground,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A flat progress bar: yellow fill on a track (gate footer, design 01).
class SgProgressBar extends StatelessWidget {
  const new({
    required this.value,
    this.track = SgColors.gateLine,
    this.height = 8,
    super.key,
  });

  /// 0..1.
  final double value;
  final Color track;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      value: '${(value.clamp(0, 1) * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                ColoredBox(color: track, child: const SizedBox.expand()),
                AnimatedContainer(
                  duration: SgMotion.normal,
                  width: box.maxWidth * value.clamp(0, 1),
                  color: SgColors.brandYellow,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hairline separator.
class SgDivider extends StatelessWidget {
  const new({this.color = SgColors.line, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: const SizedBox(height: 1, width: double.infinity),
  );
}

/// A scrolling column that builds every child. Use it for pages of a few
/// dozen items; long lists should be lazy.
class SgScrollColumn extends StatelessWidget {
  const new({
    required this.children,
    this.padding = EdgeInsets.zero,
    this.controller,
    super.key,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
