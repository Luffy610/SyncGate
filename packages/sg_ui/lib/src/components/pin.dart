import 'package:flutter/material.dart';
import 'package:sg_ui/src/components/basics.dart';
import 'package:sg_ui/src/text.dart';
import 'package:sg_ui/src/theme.dart';
import 'package:sg_ui/src/tokens.dart';

/// PIN progress: filled dots for entered digits, rings for the rest. Shakes
/// when [shakeKey] changes (wrong PIN).
class SgPinDots extends StatefulWidget {
  const new({
    required this.length,
    required this.filled,
    this.shakeKey = 0,
    this.semanticLabel,
    super.key,
  });

  final int length;
  final int filled;

  /// Bump to trigger the shake animation.
  final int shakeKey;
  final String? semanticLabel;

  @override
  State<SgPinDots> createState() => _SgPinDotsState();
}

class _SgPinDotsState extends State<SgPinDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );

  @override
  void didUpdateWidget(SgPinDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shakeKey != widget.shakeKey) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      value: '${widget.filled}/${widget.length}',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final dx =
              (1 - _controller.value) *
              14 *
              (_controller.value * 6 * 3.1416).remainder(6.2832).sign;
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < widget.filled
                        ? SgColors.ink
                        : Colors.transparent,
                    border: Border.all(
                      color: i < widget.filled ? SgColors.ink : SgColors.muted,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Number pad: pill keys on Android, round keys on iOS. The bottom-left key
/// is the biometric button (or blank), the bottom-right is backspace.
class SgPinPad extends StatelessWidget {
  const new({
    required this.onDigit,
    required this.onBackspace,
    required this.backspaceLabel,
    this.onBiometric,
    this.biometricLabel,
    this.enabled = true,
    super.key,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final String backspaceLabel;
  final VoidCallback? onBiometric;
  final String? biometricLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ios = context.isIos;
    Widget digit(int d) => _Key(
      ios: ios,
      semantic: '$d',
      onTap: enabled ? () => onDigit(d) : null,
      child: Text(
        '$d',
        style: SgText.body.copyWith(fontSize: 34, fontWeight: FontWeight.w400),
      ),
    );
    Widget icon(IconData data, String label, VoidCallback? onTap) => _Key(
      ios: ios,
      plain: true,
      semantic: label,
      onTap: enabled ? onTap : null,
      child: Icon(data, size: 32, color: SgColors.ink),
    );
    final bio = onBiometric == null
        ? const _Key(ios: false, plain: true, semantic: '', child: SizedBox())
        : icon(
            ios ? SgIcons.faceId : SgIcons.fingerprint,
            biometricLabel ?? '',
            onBiometric,
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9],
        ])
          Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.sizeOf(context).height < 720 ? 8 : 14,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [for (final d in row) digit(d)],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            bio,
            digit(0),
            icon(SgIcons.backspace, backspaceLabel, onBackspace),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const new({
    required this.ios,
    required this.semantic,
    required this.child,
    this.onTap,
    this.plain = false,
  });

  final bool ios;
  final String semantic;
  final Widget child;
  final VoidCallback? onTap;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final compactKeys = MediaQuery.sizeOf(context).height < 720;
    final width = compactKeys ? 88.0 : (ios ? 76.0 : 100.0);
    // Short phones (about 640 dp) get smaller keys so the pad still fits.
    final compact = MediaQuery.sizeOf(context).height < 720;
    final height = compact ? 52.0 : (ios ? 76.0 : 64.0);
    final radius = compact ? 26.0 : (ios ? 38.0 : 32.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: SizedBox(
        width: width,
        height: height,
        child: plain
            ? SgTap(
                onTap: onTap,
                semanticLabel: semantic,
                radius: radius,
                minSize: 0,
                child: Center(child: child),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFECEBE6),
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: SgTap(
                  onTap: onTap,
                  semanticLabel: semantic,
                  radius: radius,
                  minSize: 0,
                  child: Center(child: child),
                ),
              ),
      ),
    );
  }
}
