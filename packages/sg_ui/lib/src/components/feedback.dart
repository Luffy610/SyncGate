import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sg_ui/src/components/basics.dart';
import 'package:sg_ui/src/components/buttons.dart';
import 'package:sg_ui/src/components/inputs.dart';
import 'package:sg_ui/src/text.dart';
import 'package:sg_ui/src/theme.dart';
import 'package:sg_ui/src/tokens.dart';

const _sheetColor = Color(0xFFF3F2EE);

/// Opens a modal bottom sheet with the SyncGate shape (28 top radius, drag
/// handle). Put [SgSheetFrame] inside for the platform header / actions.
Future<T?> showSgSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: _sheetColor,
    constraints: const BoxConstraints(maxWidth: sgMaxContentWidth),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(SgRadius.sheetTop),
      ),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: builder(ctx),
    ),
  );
}

/// Sheet content: drag handle, title and Cancel / confirm actions. iOS puts
/// the actions in the header, Android at the bottom (design 15).
class SgSheetFrame extends StatelessWidget {
  const new({
    required this.title,
    required this.child,
    required this.cancelLabel,
    required this.onCancel,
    this.confirmLabel,
    this.onConfirm,
    super.key,
  });

  final String title;
  final Widget child;
  final String cancelLabel;
  final VoidCallback onCancel;
  final String? confirmLabel;

  /// `null` disables the confirm action.
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final ios = context.isIos;
    final handle = Center(
      child: Container(
        width: 44,
        height: 5,
        margin: const EdgeInsets.only(top: 12, bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFBDBDB8),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
    Widget content;
    if (ios) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          handle,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SgButton(
                      label: cancelLabel,
                      kind: SgButtonKind.text,
                      expand: false,
                      onPressed: onCancel,
                    ),
                  ),
                ),
                Flexible(
                  flex: 2,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: SgText.bodyStrong.copyWith(fontSize: 17),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: confirmLabel == null
                        ? const SizedBox.shrink()
                        : SgButton(
                            label: confirmLabel!,
                            kind: SgButtonKind.text,
                            expand: false,
                            onPressed: onConfirm,
                          ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: child,
            ),
          ),
        ],
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          handle,
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Text(title, style: SgText.title.copyWith(fontSize: 26)),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: child,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 24, 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SgButton(
                  label: cancelLabel,
                  kind: SgButtonKind.text,
                  expand: false,
                  onPressed: onCancel,
                ),
                if (confirmLabel != null) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: SgButton(
                      label: confirmLabel!,
                      expand: false,
                      onPressed: onConfirm,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }
    return SafeArea(top: false, child: content);
  }
}

/// A trailing action in a picker (e.g. "Add new department").
class SgPickerAction<T> {
  const new({required this.label, required this.run});

  final String label;
  final Future<T?> Function(BuildContext context) run;
}

/// Pick one option from a sheet list.
Future<T?> showSgPicker<T>(
  BuildContext context, {
  required String title,
  required List<SgOption<T>> options,
  T? selected,
  SgPickerAction<T>? extraAction,
}) {
  return showSgSheet<T>(
    context,
    builder: (ctx) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFBDBDB8),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Text(title, style: SgText.title),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                for (final o in options)
                  SgTap(
                    onTap: () => Navigator.of(ctx).pop(o.value),
                    selected: o.value == selected,
                    semanticLabel: o.label,
                    minSize: 56,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  o.label,
                                  style: SgText.body.copyWith(
                                    fontSize: 17,
                                    fontWeight: o.value == selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                if (o.subtitle != null)
                                  Text(o.subtitle!, style: SgText.caption),
                              ],
                            ),
                          ),
                          if (o.value == selected)
                            const Icon(SgIcons.check, color: SgColors.ink),
                        ],
                      ),
                    ),
                  ),
                if (extraAction != null)
                  SgTap(
                    onTap: () async {
                      final value = await extraAction.run(ctx);
                      if (value != null && ctx.mounted) {
                        Navigator.of(ctx).pop(value);
                      }
                    },
                    minSize: 56,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          const Icon(SgIcons.add, color: SgColors.ink),
                          const SizedBox(width: 12),
                          Text(
                            extraAction.label,
                            style: SgText.bodyStrong.copyWith(fontSize: 17),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Confirm dialog. Returns `true` when confirmed.
Future<bool> showSgConfirm(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required String cancelLabel,
  String? message,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: SgColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ctx.sg.cardRadius + 8),
      ),
      title: Text(title, style: SgText.title.copyWith(fontSize: 20)),
      content: message == null ? null : Text(message, style: SgText.body),
      actions: [
        SgButton(
          label: cancelLabel,
          kind: SgButtonKind.text,
          expand: false,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        SgButton(
          label: confirmLabel,
          kind: destructive ? SgButtonKind.danger : SgButtonKind.primary,
          expand: false,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for one line of text (e.g. a new department name).
Future<String?> showSgTextPrompt(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  required String cancelLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _TextPrompt(
      title: title,
      label: label,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
}

class _TextPrompt extends StatefulWidget {
  const new({
    required this.title,
    required this.label,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String cancelLabel;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SgColors.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(widget.title, style: SgText.title.copyWith(fontSize: 20)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
      ),
      actions: [
        SgButton(
          label: widget.cancelLabel,
          kind: SgButtonKind.text,
          expand: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
        SgButton(
          label: widget.confirmLabel,
          expand: false,
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.of(context).pop(text.isEmpty ? null : text);
          },
        ),
      ],
    );
  }
}

/// Short message at the bottom of the screen.
void showSgToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: SgText.body.copyWith(color: Colors.white),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: SgColors.ink,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.sg.cardRadius),
        ),
      ),
    );
}

/// Shows a progress dialog while [task] runs, then returns its result.
Future<T> showSgBusy<T>(
  BuildContext context, {
  required String message,
  required Future<T> task,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: SgColors.surface,
          surfaceTintColor: Colors.transparent,
          content: Row(
            children: [
              const SgSpinner(),
              const SizedBox(width: 20),
              Expanded(child: Text(message, style: SgText.body)),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await task;
  } finally {
    if (navigator.mounted) navigator.pop();
  }
}

/// Hour / minute stepper sheet. Times are minutes since midnight.
Future<int?> showSgTimePicker(
  BuildContext context, {
  required String title,
  required int initialMinute,
  required String confirmLabel,
  required String cancelLabel,
}) {
  return showSgSheet<int>(
    context,
    builder: (ctx) => _TimeSheet(
      title: title,
      initialMinute: initialMinute,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
}

class _TimeSheet extends StatefulWidget {
  const new({
    required this.title,
    required this.initialMinute,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final String title;
  final int initialMinute;
  final String confirmLabel;
  final String cancelLabel;

  @override
  State<_TimeSheet> createState() => _TimeSheetState();
}

class _TimeSheetState extends State<_TimeSheet> {
  late int _hour = widget.initialMinute ~/ 60;
  late int _minute = widget.initialMinute % 60;

  @override
  Widget build(BuildContext context) {
    return SgSheetFrame(
      title: widget.title,
      cancelLabel: widget.cancelLabel,
      confirmLabel: widget.confirmLabel,
      onCancel: () => Navigator.of(context).pop(),
      onConfirm: () => Navigator.of(context).pop(_hour * 60 + _minute),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _column(
            key: 'hour',
            value: _hour,
            onUp: () => setState(() => _hour = (_hour + 1) % 24),
            onDown: () => setState(() => _hour = (_hour + 23) % 24),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(':', style: SgText.mono.copyWith(fontSize: 40)),
          ),
          _column(
            key: 'minute',
            value: _minute,
            onUp: () => setState(() => _minute = (_minute + 1) % 60),
            onDown: () => setState(() => _minute = (_minute + 59) % 60),
          ),
        ],
      ),
    );
  }

  Widget _column({
    required String key,
    required int value,
    required VoidCallback onUp,
    required VoidCallback onDown,
  }) {
    return Column(
      children: [
        SgIconButton(
          icon: SgIcons.keyboardUp,
          label: '$key up',
          onPressed: onUp,
        ),
        Text(
          value.toString().padLeft(2, '0'),
          key: ValueKey('time-$key'),
          style: SgText.mono.copyWith(
            fontSize: 44,
            fontWeight: FontWeight.w600,
          ),
        ),
        SgIconButton(
          icon: SgIcons.expand,
          label: '$key down',
          onPressed: onDown,
        ),
      ],
    );
  }
}
