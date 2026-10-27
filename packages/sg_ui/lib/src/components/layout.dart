import 'package:flutter/material.dart';
import 'package:sg_ui/src/components/basics.dart';
import 'package:sg_ui/src/components/buttons.dart';
import 'package:sg_ui/src/components/inputs.dart';
import 'package:sg_ui/src/text.dart';
import 'package:sg_ui/src/theme.dart';
import 'package:sg_ui/src/tokens.dart';

enum SgLeading { none, back, close }

/// An action in the top bar. iOS shows text for [textAction] and an icon
/// otherwise; Android shows a pill for [textAction] and an icon otherwise.
class SgBarAction {
  const new({
    required this.icon,
    required this.label,
    required this.onTap,
    this.textAction = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool textAction;
}

/// Top bar: large title on iOS tab roots, centred 17 pt title on pushed iOS
/// screens, left-aligned 22 sp title on Android (frontend plan §4.4).
class SgTopBar extends StatelessWidget {
  const new({
    required this.title,
    this.subtitle,
    this.leading = SgLeading.none,
    this.leadingLabel,
    this.onLeading,
    this.actions = const [],
    this.largeTitle = false,
    this.dark = false,
    this.trailingText,
    super.key,
  });

  final String title;
  final String? subtitle;
  final SgLeading leading;

  /// iOS text for the leading control ("Cancel", "Back", "Today"). Also the
  /// semantic label on Android.
  final String? leadingLabel;
  final VoidCallback? onLeading;
  final List<SgBarAction> actions;

  /// iOS only: large title under the action row (tab roots).
  final bool largeTitle;
  final bool dark;

  /// Small muted text on the right (e.g. "Step 3 of 3").
  final String? trailingText;

  SgTopBar withAction(SgBarAction action) => SgTopBar(
    title: title,
    subtitle: subtitle,
    leading: leading,
    leadingLabel: leadingLabel,
    onLeading: onLeading,
    actions: [...actions, action],
    largeTitle: largeTitle,
    dark: dark,
    trailingText: trailingText,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.sg;
    final fg = dark ? Colors.white : SgColors.ink;
    final muted = dark ? SgColors.gateMuted : SgColors.muted;
    return tokens.isIos
        ? _ios(context, tokens, fg, muted)
        : _android(context, tokens, fg, muted);
  }

  Widget _android(BuildContext context, SgTokens t, Color fg, Color muted) {
    return Padding(
      padding: EdgeInsets.fromLTRB(t.gutter - 8, 8, t.gutter - 8, 8),
      child: Row(
        children: [
          if (leading != SgLeading.none)
            SgIconButton(
              icon: leading == SgLeading.close ? SgIcons.close : SgIcons.back,
              label: leadingLabel ?? '',
              onPressed: onLeading,
              color: fg,
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SgText.title.copyWith(color: fg),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(subtitle!, style: SgText.caption.copyWith(color: muted)),
              ],
            ),
          ),
          if (trailingText != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                trailingText!,
                style: SgText.body.copyWith(color: muted),
              ),
            ),
          for (final a in actions) _androidAction(a, fg),
        ],
      ),
    );
  }

  Widget _androidAction(SgBarAction a, Color fg) {
    if (a.textAction) {
      return Padding(
        padding: const EdgeInsets.only(left: 8, right: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: SgColors.ink,
            borderRadius: BorderRadius.circular(24),
          ),
          child: SgTap(
            onTap: a.onTap,
            radius: 24,
            semanticLabel: a.label,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: Text(
                a.label,
                style: SgText.bodyStrong.copyWith(color: Colors.white),
              ),
            ),
          ),
        ),
      );
    }
    return SgIconButton(
      icon: a.icon,
      label: a.label,
      onPressed: a.onTap,
      color: fg,
    );
  }

  Widget _ios(BuildContext context, SgTokens t, Color fg, Color muted) {
    final leadingWidget = leading == SgLeading.none
        ? const SizedBox(width: 48)
        : SgTap(
            onTap: onLeading,
            semanticLabel: leadingLabel,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading == SgLeading.back)
                    Icon(SgIcons.backIos, color: fg, size: 28),
                  Text(
                    leadingLabel ?? '',
                    style: SgText.body.copyWith(color: fg, fontSize: 17),
                  ),
                ],
              ),
            ),
          );

    Widget actionWidget(SgBarAction a) => SgTap(
      onTap: a.onTap,
      semanticLabel: a.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: a.textAction
            ? Text(
                a.label,
                style: SgText.bodyStrong.copyWith(color: fg, fontSize: 17),
              )
            : Icon(a.icon, color: fg, size: 28),
      ),
    );

    final actionRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final a in actions) actionWidget(a)],
    );

    if (largeTitle) {
      return Padding(
        padding: EdgeInsets.fromLTRB(t.gutter, 8, t.gutter, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (leading == SgLeading.none)
                  const SizedBox(height: 48)
                else
                  leadingWidget,
                actionRow,
              ],
            ),
            Text(title, style: SgText.titleLarge.copyWith(color: fg)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitle!,
                  style: SgText.body.copyWith(color: muted),
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(t.gutter, 8, t.gutter, 8),
      child: Row(
        children: [
          leadingWidget,
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SgText.bodyStrong.copyWith(color: fg, fontSize: 17),
            ),
          ),
          if (trailingText != null && actions.isEmpty)
            Text(trailingText!, style: SgText.body.copyWith(color: muted))
          else if (actions.isEmpty)
            const SizedBox(width: 48)
          else
            actionRow,
        ],
      ),
    );
  }
}

class SgNavItem {
  const new({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Bottom navigation: iOS tab bar, Android M3 navigation bar with a yellow
/// pill indicator.
class SgNavBar extends StatelessWidget {
  const new({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<SgNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.sg;
    final bar = Row(
      children: [
        for (var i = 0; i < items.length; i++)
          Expanded(child: _item(i, items[i], i == selectedIndex, t.isIos)),
      ],
    );
    return Container(
      constraints: BoxConstraints(minHeight: t.navHeight),
      decoration: BoxDecoration(
        color: t.isIos ? t.ground : const Color(0xFFF0EFEA),
        border: t.isIos
            ? const Border(top: BorderSide(color: SgColors.line))
            : null,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: bar,
        ),
      ),
    );
  }

  Widget _item(int index, SgNavItem item, bool active, bool ios) {
    final label = Text(
      item.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: SgText.caption.copyWith(
        color: active ? SgColors.ink : SgColors.muted,
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        fontSize: 13,
      ),
    );
    final icon = Icon(
      active ? item.activeIcon : item.icon,
      color: active ? SgColors.ink : SgColors.muted,
      size: 26,
    );
    return Semantics(
      selected: active,
      child: SgTap(
        onTap: () => onSelected(index),
        semanticLabel: item.label,
        minSize: 56,
        radius: 16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ios)
              Padding(padding: const EdgeInsets.only(bottom: 4), child: icon)
            else
              AnimatedContainer(
                duration: SgMotion.fast,
                width: 64,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? SgColors.brandYellow : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: icon,
              ),
            if (!ios) const SizedBox(height: 4),
            label,
          ],
        ),
      ),
    );
  }
}

/// The main action of a tab root: an extended FAB on Android, a "+" in the
/// top bar on iOS.
class SgPrimaryActionSpec {
  const new({
    required this.label,
    required this.onTap,
    this.icon = SgIcons.add,
  });

  final String label;
  final VoidCallback onTap;
  final IconData icon;
}

/// Page scaffold: ground colour, safe area, top bar, optional bottom bar and
/// primary action; content is capped at [sgMaxContentWidth].
class SgScaffold extends StatelessWidget {
  const new({
    required this.body,
    this.topBar,
    this.bottom,
    this.primaryAction,
    this.dark = false,
    this.resizeForKeyboard = true,
    super.key,
  });

  final Widget body;
  final SgTopBar? topBar;
  final Widget? bottom;
  final SgPrimaryActionSpec? primaryAction;
  final bool dark;
  final bool resizeForKeyboard;

  @override
  Widget build(BuildContext context) {
    final t = context.sg;
    var bar = topBar;
    final action = primaryAction;
    if (bar != null && action != null && t.isIos) {
      bar = bar.withAction(
        SgBarAction(
          icon: action.icon,
          label: action.label,
          onTap: action.onTap,
        ),
      );
    }
    final background = dark ? SgColors.gateBg : t.ground;

    return Scaffold(
      backgroundColor: background,
      resizeToAvoidBottomInset: resizeForKeyboard,
      floatingActionButton: action != null && !t.isIos
          ? FloatingActionButton.extended(
              // Tabs keep their pages alive, so several FABs can exist at once.
              heroTag: null,
              onPressed: action.onTap,
              backgroundColor: SgColors.brandYellow,
              foregroundColor: SgColors.ink,
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              icon: Icon(action.icon),
              label: Text(
                action.label,
                style: SgText.bodyStrong.copyWith(fontSize: 17),
              ),
            )
          : null,
      bottomNavigationBar: bottom,
      body: SafeArea(
        bottom: bottom == null,
        child: SgMaxWidth(
          child: Column(
            children: [
              ?bar,
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section with a caps header. iOS groups the children in one inset card;
/// Android stacks standalone fields (forms) with a gap.
class SgSection extends StatelessWidget {
  const new({
    required this.children,
    this.header,
    this.footer,
    this.androidHeader = true,
    super.key,
  });

  final String? header;
  final String? footer;
  final List<Widget> children;

  /// Android forms in the designs have no section headers.
  final bool androidHeader;

  @override
  Widget build(BuildContext context) {
    final t = context.sg;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null && (t.isIos || androidHeader))
            Padding(
              padding: EdgeInsets.fromLTRB(t.isIos ? 16 : 4, 12, 0, 8),
              child: Text(
                header!.toUpperCase(),
                style: t.isIos
                    ? SgText.caption.copyWith(letterSpacing: 0.4, fontSize: 14)
                    : SgText.label,
              ),
            ),
          if (t.isIos) ...[
            SgCardList(
              children: [
                for (final c in children)
                  if (c is! SgFieldNote) c,
              ],
            ),
            for (final c in children)
              if (c is SgFieldNote) c,
          ] else
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: SgSpace.s3),
              children[i],
            ],
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(footer!, style: SgText.caption),
            ),
        ],
      ),
    );
  }
}

/// White card with hairline dividers between rows.
class SgCardList extends StatelessWidget {
  const new({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final radius = context.sg.cardRadius;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SgColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: SgColors.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: SgColors.line),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// A row for [SgCardList]: title, optional subtitle and trailing widget.
class SgListRow extends StatelessWidget {
  const new({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.trailingText,
    this.onTap,
    this.danger = false,
    this.showChevron = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final String? trailingText;
  final VoidCallback? onTap;
  final bool danger;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 14)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SgText.body.copyWith(
                    fontSize: 17,
                    color: danger ? SgColors.danger : SgColors.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: SgText.caption),
                  ),
              ],
            ),
          ),
          if (trailingText != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                trailingText!,
                style: SgText.body.copyWith(color: SgColors.muted),
              ),
            ),
          ?trailing,
          if (showChevron) const Icon(SgIcons.chevron, color: SgColors.muted),
        ],
      ),
    );
    if (onTap == null) return row;
    return SgTap(onTap: onTap, radius: 0, minSize: 56, child: row);
  }
}

enum SgBannerKind { warning, info, success, danger }

/// Inline message with an icon (status is never colour only).
class SgBanner extends StatelessWidget {
  const new({
    required this.kind,
    required this.title,
    this.message,
    this.action,
    this.icon,
    super.key,
  });

  final SgBannerKind kind;
  final String title;
  final String? message;
  final Widget? action;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, iconColor, defaultIcon) = switch (kind) {
      SgBannerKind.warning => (
        SgColors.warningBg,
        SgColors.warningText,
        SgColors.warningIcon,
        SgIcons.warning,
      ),
      SgBannerKind.info => (
        SgColors.infoBg,
        SgColors.infoText,
        SgColors.infoText,
        SgIcons.info,
      ),
      SgBannerKind.success => (
        SgColors.successTint,
        SgColors.successText,
        SgColors.successText,
        SgIcons.checkCircle,
      ),
      SgBannerKind.danger => (
        SgColors.dangerTint,
        SgColors.danger,
        SgColors.danger,
        SgIcons.warning,
      ),
    };
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(SgSpace.s4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(context.sg.cardRadius + 4),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon ?? defaultIcon, color: iconColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SgText.bodyStrong.copyWith(color: fg, fontSize: 18),
                  ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        message!,
                        style: SgText.body.copyWith(color: fg),
                      ),
                    ),
                  if (action != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: action,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Number card for the Today screen.
class SgStatCard extends StatelessWidget {
  const new({
    required this.dot,
    required this.label,
    required this.value,
    required this.caption,
    super.key,
  });

  final Color dot;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label $value, $caption',
      child: ExcludeSemantics(
        child: SgCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: dot,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      style: SgText.bodyStrong.copyWith(
                        color: SgColors.muted,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(value, style: SgText.heading.copyWith(fontSize: 40)),
              Text(caption, style: SgText.caption.copyWith(fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wizard progress bar: "Step n of total".
class SgStepper extends StatelessWidget {
  const new({required this.current, required this.total, super.key});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= total; i++) ...[
          if (i > 1) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: SgMotion.normal,
              height: 4,
              decoration: BoxDecoration(
                color: i <= current ? SgColors.ink : const Color(0xFFDAD8D0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Enrolment flow header: 1 Details — 2 Notice — 3 Face.
class SgFlowSteps extends StatelessWidget {
  const new({required this.labels, required this.current, super.key});

  final List<String> labels;

  /// 1-based index of the active step.
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: i < current ? SgColors.ink : const Color(0xFFDAD8D0),
              ),
            ),
          // Labels get four times the room of a connector, or "Details" is
          // clipped to "De…" next to the two connector lines.
          Flexible(flex: 4, child: _step(i + 1, labels[i])),
        ],
      ],
    );
  }

  Widget _step(int number, String label) {
    final done = number < current;
    final active = number == current;
    return Semantics(
      label: '$number, $label',
      selected: active,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? SgColors.successFill
                    : active
                    ? SgColors.ink
                    : Colors.transparent,
                border: done || active
                    ? null
                    : Border.all(color: SgColors.muted, width: 1.5),
              ),
              child: done
                  ? const Icon(SgIcons.check, size: 18, color: Colors.white)
                  : Text(
                      '$number',
                      style: SgText.bodyStrong.copyWith(
                        fontSize: 14,
                        color: active ? Colors.white : SgColors.muted,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SgText.bodyStrong.copyWith(
                  color: active || done ? SgColors.ink : SgColors.muted,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
