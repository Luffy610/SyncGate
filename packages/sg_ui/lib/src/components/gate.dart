import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sg_ui/src/components/basics.dart';
import 'package:sg_ui/src/components/buttons.dart';
import 'package:sg_ui/src/text.dart';
import 'package:sg_ui/src/tokens.dart';

/// The SyncGate mark: a yellow rounded square with an arch ("gate").
class SgLogo extends StatelessWidget {
  const new({this.size = 56, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _LogoPainter()),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.22)),
      Paint()..color = SgColors.brandYellow,
    );
    final stroke = Paint()
      ..color = SgColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.11
      ..strokeCap = StrokeCap.round;
    final arch = Path()
      ..moveTo(s * 0.28, s * 0.74)
      ..lineTo(s * 0.28, s * 0.46)
      ..arcToPoint(
        Offset(s * 0.72, s * 0.46),
        radius: Radius.circular(s * 0.22),
      )
      ..lineTo(s * 0.72, s * 0.74);
    canvas
      ..drawPath(arch, stroke)
      ..drawLine(Offset(s * 0.5, s * 0.5), Offset(s * 0.5, s * 0.72), stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Grey head-and-shoulders placeholder used by the fake camera.
class SgFaceSilhouette extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        painter: _SilhouettePainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = SgColors.silhouette;
    final w = size.width;
    final h = size.height;
    final head = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.40),
      width: w * 0.42,
      height: h * 0.40,
    );
    canvas
      ..drawOval(head, paint)
      ..drawArc(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.98),
          width: w * 0.88,
          height: h * 0.62,
        ),
        math.pi,
        math.pi,
        true,
        paint,
      );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Yellow corner brackets framing the face area.
class SgScanFrame extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        painter: _BracketPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SgColors.brandYellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final left = size.width * 0.20;
    final right = size.width * 0.80;
    final top = size.height * 0.15;
    final bottom = size.height * 0.78;
    const len = 38.0;
    for (final (x, y, dx, dy) in [
      (left, top, 1.0, 1.0),
      (right, top, -1.0, 1.0),
      (left, bottom, 1.0, -1.0),
      (right, bottom, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x + dx * len, y)
          ..lineTo(x, y)
          ..lineTo(x, y + dy * len),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Coloured result panel of the gate (green / red / grey / neutral).
class SgGatePanel extends StatelessWidget {
  const new({
    required this.color,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    super.key,
  });

  final Color color;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: SgMotion.fast,
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(SgRadius.gatePanel),
      ),
      child: child,
    );
  }
}

/// Gate header: logo, product name, offline status, language chip and the
/// lock button that opens admin unlock.
class SgGateHeader extends StatelessWidget {
  const new({
    required this.statusText,
    required this.languageLabel,
    required this.languageSemantic,
    required this.lockSemantic,
    required this.onLanguage,
    required this.onLock,
    this.onLogoLongPress,
    this.warning,
    super.key,
  });

  final String statusText;
  final String languageLabel;
  final String languageSemantic;
  final String lockSemantic;
  final VoidCallback onLanguage;
  final VoidCallback onLock;
  final VoidCallback? onLogoLongPress;

  /// Small chip next to the status, e.g. "Not pinned".
  final String? warning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onLongPress: onLogoLongPress,
            child: const SgLogo(size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SyncGate',
                  style: SgText.bodyStrong.copyWith(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: SgColors.successOnDark,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        statusText,
                        style: SgText.caption.copyWith(
                          color: SgColors.gateMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
                if (warning != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      warning!,
                      style: SgText.caption.copyWith(
                        color: SgColors.brandYellow,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SgColors.gateLine, width: 1.5),
            ),
            child: SgTap(
              onTap: onLanguage,
              radius: 16,
              semanticLabel: languageSemantic,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    languageLabel,
                    style: SgText.bodyStrong.copyWith(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SgIconButton(
            icon: SgIcons.lock,
            label: lockSemantic,
            onPressed: onLock,
            color: Colors.white,
            bordered: true,
          ),
        ],
      ),
    );
  }
}

/// Face-capture progress ring: green for done, a yellow head for the current
/// position, grey for what remains (design 14).
class SgCaptureRing extends StatelessWidget {
  const new({required this.progress, super.key});

  /// 0..1 around the ring.
  final double progress;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        painter: _RingPainter(progress.clamp(0, 1)),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const new(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      size.width * 0.06,
      size.height * 0.10,
      size.width * 0.88,
      size.height * 0.72,
    );
    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    const start = -math.pi / 2;
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      stroke(const Color(0xFF3B4045)),
    );
    if (progress > 0) {
      canvas.drawArc(
        rect,
        start,
        2 * math.pi * progress,
        false,
        stroke(SgColors.successOnDark),
      );
    }
    if (progress < 1) {
      canvas.drawArc(
        rect,
        start + 2 * math.pi * progress + 0.1,
        0.5,
        false,
        stroke(SgColors.brandYellow),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

enum SgAngleStatus { done, now, pending, optional }

/// One of the four capture angles (Front / Left / Right / Mask).
class SgAngleTile extends StatelessWidget {
  const new({
    required this.label,
    required this.caption,
    required this.status,
    super.key,
  });

  final String label;
  final String caption;
  final SgAngleStatus status;

  @override
  Widget build(BuildContext context) {
    final now = status == SgAngleStatus.now;
    final glyph = switch (status) {
      SgAngleStatus.done => Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: SgColors.successOnDark,
          shape: BoxShape.circle,
        ),
        child: const Icon(SgIcons.check, color: SgColors.ink, size: 30),
      ),
      SgAngleStatus.now => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: SgColors.brandYellow, width: 5),
        ),
      ),
      SgAngleStatus.pending || SgAngleStatus.optional => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: SgColors.gateMuted, width: 3),
        ),
      ),
    };
    return Semantics(
      container: true,
      label: '$label, $caption',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: now ? const Color(0xFF2B2310) : SgColors.gatePanel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: now ? SgColors.brandYellow : SgColors.gateLine,
              width: now ? 2 : 1.5,
            ),
          ),
          child: Column(
            children: [
              glyph,
              const SizedBox(height: 10),
              Text(
                label,
                style: SgText.bodyStrong.copyWith(
                  color: now ? SgColors.brandYellow : Colors.white,
                ),
              ),
              Text(
                caption,
                style: SgText.caption.copyWith(color: SgColors.gateMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed white oval used as the face guide in the camera check (design 07).
class SgDashedOval extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        painter: _DashedOvalPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _DashedOvalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.46),
      width: size.height * 0.60,
      height: size.height * 0.78,
    );
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const dashes = 36;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
