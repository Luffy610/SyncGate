import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sg_ui/src/components/basics.dart';
import 'package:sg_ui/src/components/feedback.dart';
import 'package:sg_ui/src/text.dart';
import 'package:sg_ui/src/theme.dart';
import 'package:sg_ui/src/tokens.dart';

/// A note under a field ("✓ Age 28 …"). Inside an iOS grouped section it is
/// drawn below the card, like the designs.
class SgFieldNote extends StatelessWidget {
  const new(this.text, {this.color = SgColors.muted, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Text(text, style: SgText.caption.copyWith(color: color)),
    );
  }
}

/// Text input: outlined with a floating label on Android, a label/value row
/// on iOS (to be placed in an `SgSection`).
class SgTextField extends StatelessWidget {
  const new({
    required this.label,
    this.controller,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.mono = false,
    this.onChanged,
    this.obscure = false,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.errorText,
    this.focusNode,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool mono;
  final ValueChanged<String>? onChanged;
  final bool obscure;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final String? errorText;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final style = (mono ? SgText.mono : SgText.body).copyWith(
      fontSize: mono ? 18 : 17,
    );
    if (context.isIos) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: [
              Text(label, style: SgText.body.copyWith(fontSize: 17)),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  onChanged: onChanged,
                  obscureText: obscure,
                  autofocus: autofocus,
                  textCapitalization: textCapitalization,
                  textAlign: TextAlign.right,
                  style: style,
                  cursorColor: SgColors.ink,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: hint,
                    hintStyle: style.copyWith(color: const Color(0xFF9A9C99)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    errorText: errorText,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      obscureText: obscure,
      autofocus: autofocus,
      textCapitalization: textCapitalization,
      style: style,
      cursorColor: SgColors.ink,
      decoration: _outlined(label, hint, errorText),
    );
  }
}

InputDecoration _outlined(String label, String? hint, String? error) {
  OutlineInputBorder border(Color color, [double width = 1.5]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    errorText: error,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    labelStyle: SgText.body.copyWith(color: SgColors.muted, fontSize: 15),
    floatingLabelStyle: SgText.body.copyWith(
      color: SgColors.muted,
      fontSize: 15,
    ),
    hintStyle: SgText.body.copyWith(color: const Color(0xFF8B8D8A)),
    contentPadding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
    enabledBorder: border(const Color(0xFF8E908D), 1.2),
    focusedBorder: border(SgColors.ink, 2),
    errorBorder: border(SgColors.danger),
    focusedErrorBorder: border(SgColors.danger, 2),
  );
}

/// One choice in a picker.
class SgOption<T> {
  const new({required this.value, required this.label, this.subtitle});

  final T value;
  final String label;
  final String? subtitle;
}

/// A tappable field that shows a value and opens something (a picker sheet,
/// a time picker): a value + chevron row on iOS, an outlined dropdown on
/// Android.
class SgPickerField extends StatelessWidget {
  const new({
    required this.label,
    required this.valueText,
    required this.onTap,
    this.placeholder,
    super.key,
  });

  final String label;

  /// `null` shows [placeholder] in the muted colour.
  final String? valueText;
  final String? placeholder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = valueText ?? placeholder ?? '';
    final valueStyle = SgText.body.copyWith(
      fontSize: 17,
      color: valueText == null ? const Color(0xFF8B8D8A) : SgColors.ink,
    );
    if (context.isIos) {
      return SgTap(
        onTap: onTap,
        radius: 0,
        minSize: 52,
        semanticLabel: '$label, $text',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Text(label, style: SgText.body.copyWith(fontSize: 17)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  text,
                  textAlign: TextAlign.right,
                  style: valueStyle,
                ),
              ),
              const Icon(SgIcons.chevron, color: SgColors.muted),
            ],
          ),
        ),
      );
    }
    return SgTap(
      onTap: onTap,
      radius: 8,
      minSize: 0,
      semanticLabel: '$label, $text',
      child: InputDecorator(
        decoration: _outlined(label, null, null).copyWith(
          suffixIcon: const Icon(SgIcons.dropdown, color: SgColors.ink),
        ),
        child: Text(text, style: valueStyle),
      ),
    );
  }
}

/// Picks one value from a list in a sheet.
class SgSelectField<T> extends StatelessWidget {
  const new({
    required this.label,
    required this.options,
    required this.onChanged,
    this.value,
    this.placeholder,
    this.pickerTitle,
    this.extraAction,
    super.key,
  });

  final String label;
  final List<SgOption<T>> options;
  final T? value;
  final String? placeholder;
  final String? pickerTitle;
  final ValueChanged<T> onChanged;

  /// Optional last row in the picker, e.g. "Add new department".
  final SgPickerAction<T>? extraAction;

  String? get _valueLabel {
    for (final o in options) {
      if (o.value == value) return o.label;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showSgPicker<T>(
      context,
      title: pickerTitle ?? label,
      options: options,
      selected: value,
      extraAction: extraAction,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return SgPickerField(
      label: label,
      valueText: _valueLabel,
      placeholder: placeholder,
      onTap: () => unawaited(_open(context)),
    );
  }
}

/// Search box (grey pill on light screens, dark pill on the gate).
class SgSearchField extends StatelessWidget {
  const new({
    required this.hint,
    this.controller,
    this.onChanged,
    this.dark = false,
    super.key,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : SgColors.ink;
    final hintColor = dark ? SgColors.gateMuted : const Color(0xFF777977);
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: dark ? SgColors.gatePanel : const Color(0xFFEBEAE5),
        borderRadius: BorderRadius.circular(999),
        border: dark ? Border.all(color: SgColors.gateLine, width: 1.5) : null,
      ),
      child: Row(
        children: [
          Icon(SgIcons.search, color: hintColor),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: SgText.body.copyWith(color: fg, fontSize: 17),
              cursorColor: fg,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle: SgText.body.copyWith(color: hintColor, fontSize: 17),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Switch: iOS green 51×31, Android ink track with a yellow ✓ thumb.
class SgSwitch extends StatelessWidget {
  const new({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ios = context.isIos;
    final w = ios ? 51.0 : 52.0;
    final h = ios ? 31.0 : 32.0;
    final trackOn = ios ? const Color(0xFF34C759) : SgColors.ink;
    final trackOff = ios ? const Color(0xFFD9D8D3) : const Color(0xFFE2E0D9);
    final thumb = h - 8;
    return Semantics(
      toggled: value,
      label: semanticLabel,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: SizedBox(
            width: sgMinTouch + 8,
            height: sgMinTouch,
            child: Center(
              child: AnimatedContainer(
                duration: SgMotion.fast,
                width: w,
                height: h,
                padding: const EdgeInsets.all(4),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: value ? trackOn : trackOff,
                  borderRadius: BorderRadius.circular(h),
                  border: !ios && !value
                      ? Border.all(color: SgColors.muted, width: 1.5)
                      : null,
                ),
                child: Container(
                  width: ios ? thumb : (value ? thumb : thumb - 8),
                  height: ios ? thumb : (value ? thumb : thumb - 8),
                  decoration: BoxDecoration(
                    color: ios
                        ? Colors.white
                        : value
                        ? SgColors.brandYellow
                        : SgColors.muted,
                    shape: BoxShape.circle,
                  ),
                  child: !ios && value
                      ? const Icon(SgIcons.check, size: 16, color: SgColors.ink)
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A title/subtitle row with a switch, for settings cards. The whole row
/// toggles it.
class SgSwitchRow extends StatelessWidget {
  const new({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SgTap(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      radius: 0,
      minSize: 56,
      toggled: value,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SgText.bodyStrong.copyWith(fontSize: 17)),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: SgText.caption.copyWith(fontSize: 14),
                    ),
                ],
              ),
            ),
            ExcludeSemantics(
              child: IgnorePointer(
                child: SgSwitch(
                  value: value,
                  onChanged: onChanged,
                  semanticLabel: title,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented control: Material segmented buttons on Android (yellow fill with
/// a ✓), a grey track with a white thumb on iOS.
class SgSegmented<T> extends StatelessWidget {
  const new({
    required this.options,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<SgOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final ios = context.isIos;
    return Container(
      padding: ios ? const EdgeInsets.all(3) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: ios ? const Color(0xFFE4E2DC) : Colors.transparent,
        borderRadius: BorderRadius.circular(ios ? 12 : 28),
        border: ios ? null : Border.all(color: const Color(0xFF8E908D)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ios ? 10 : 27),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (!ios && i > 0)
                  const VerticalDivider(width: 1, color: Color(0xFF8E908D)),
                Expanded(child: _segment(options[i], ios)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment(SgOption<T> option, bool ios) {
    final active = option.value == selected;
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!ios && active) ...[
          const Icon(SgIcons.check, size: 20, color: SgColors.ink),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            option.label,
            textAlign: TextAlign.center,
            style: SgText.bodyStrong.copyWith(
              fontSize: 16,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
    return AnimatedContainer(
      duration: SgMotion.fast,
      decoration: BoxDecoration(
        color: active
            ? (ios ? Colors.white : SgColors.brandYellowSoft)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(ios ? 10 : 0),
      ),
      child: SgTap(
        onTap: () => onChanged(option.value),
        radius: ios ? 10 : 0,
        selected: active,
        semanticLabel: option.label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Center(child: content),
        ),
      ),
    );
  }
}

/// One filter chip.
class SgChip extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot,
    this.dropdown = false,
    this.dark = false,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? dot;
  final bool dropdown;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final t = context.sg;
    final ios = t.isIos;
    final Color fill;
    final Color text;
    final Color border;
    if (dark) {
      fill = selected ? SgColors.brandYellow : Colors.transparent;
      text = selected ? SgColors.ink : Colors.white;
      border = selected ? SgColors.brandYellow : SgColors.gateLine;
    } else if (ios) {
      fill = selected ? SgColors.ink : SgColors.surface;
      text = selected ? Colors.white : SgColors.ink;
      border = selected ? SgColors.ink : SgColors.line;
    } else {
      fill = selected ? SgColors.brandYellowSoft : Colors.transparent;
      text = SgColors.ink;
      border = selected ? SgColors.brandYellowSoft : const Color(0xFF8E908D);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(t.chipRadius),
        border: Border.all(color: border, width: 1.5),
      ),
      child: SgTap(
        onTap: onTap,
        radius: t.chipRadius,
        selected: selected,
        semanticLabel: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!ios && selected && !dark) ...[
                Icon(SgIcons.check, size: 20, color: text),
                const SizedBox(width: 8),
              ],
              if (dot != null) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  style: SgText.bodyStrong.copyWith(
                    color: text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (dropdown) ...[
                const SizedBox(width: 4),
                Icon(SgIcons.expand, size: 22, color: text),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Wrapping row of single-select chips.
class SgChoiceChips<T> extends StatelessWidget {
  const new({
    required this.options,
    required this.selected,
    required this.onSelected,
    this.dark = false,
    this.scrollable = false,
    super.key,
  });

  final List<SgOption<T>> options;
  final T? selected;
  final ValueChanged<T> onSelected;
  final bool dark;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final o in options)
        SgChip(
          label: o.label,
          selected: o.value == selected,
          dark: dark,
          onTap: () => onSelected(o.value),
        ),
    ];
    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              chips[i],
            ],
          ],
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

/// Selectable card row (language, template choice): radio on Android, a
/// check on iOS; the selected card gets a yellow tint and ink border.
class SgSelectRow extends StatelessWidget {
  const new({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.titleStyle,
    this.leading,
    this.dimmed = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final TextStyle? titleStyle;
  final Widget? leading;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final ios = context.isIos;
    final control = ios
        ? (selected
              ? const Icon(SgIcons.check, color: SgColors.ink, size: 28)
              : const SizedBox(width: 28))
        : _Radio(selected: selected);
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: SgCard(
        color: selected ? SgColors.brandYellowTint : SgColors.surface,
        selected: selected,
        onTap: onTap,
        semanticLabel: subtitle == null ? title : '$title, $subtitle',
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:
                        titleStyle ?? SgText.bodyStrong.copyWith(fontSize: 20),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: SgText.caption.copyWith(fontSize: 15),
                    ),
                ],
              ),
            ),
            control,
          ],
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const new({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? SgColors.ink : SgColors.muted,
          width: selected ? 2.5 : 2,
        ),
      ),
      child: selected
          ? Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                color: SgColors.ink,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}

/// Large consent checkbox row (design 13).
class SgCheckRow extends StatelessWidget {
  const new({
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: value,
      child: SgCard(
        selected: value,
        onTap: () => onChanged(!value),
        semanticLabel: title,
        child: Row(
          children: [
            AnimatedContainer(
              duration: SgMotion.fast,
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: value ? SgColors.ink : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SgColors.ink, width: 2),
              ),
              child: value
                  ? const Icon(SgIcons.check, color: Colors.white, size: 22)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SgText.bodyStrong.copyWith(fontSize: 18)),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: SgText.caption.copyWith(fontSize: 15),
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
