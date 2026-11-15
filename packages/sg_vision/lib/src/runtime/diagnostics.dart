import 'package:flutter/foundation.dart';
import 'package:sg_vision/src/pipeline/face_pipeline.dart';
import 'package:sg_vision/src/pipeline/matcher.dart';

/// Live numbers from the face pipeline for someone testing on a phone:
/// what the camera delivers, how fast frames are analysed, what the
/// detector and matcher think. Shown over the camera preview and printed to
/// the console once a second.
///
/// Numbers and worker IDs only; never pixels or face vectors. Off unless a
/// `VisionStack` is created with `diagnostics: true` (the dev flavour's
/// `--dart-define=VISION_DIAGNOSTICS=true`); never on in staging or prod.
final class VisionDiagnostics {
  new({this.logEvery = const Duration(seconds: 1), void Function(String)? log})
    : log = log ?? _print;

  static void _print(String line) => debugPrint(line);

  /// The text for the on-screen overlay, or `null` when diagnostics are off
  /// or nothing has been analysed yet.
  static final ValueNotifier<String?> overlay = ValueNotifier(null);

  final Duration logEvery;

  /// Where console lines go.
  final void Function(String) log;

  final _times = <DateTime>[];
  final _micros = <int>[];
  DateTime? _lastLog;

  /// Records one analysed frame. [mode] is "gate", "enrol" or "check";
  /// [candidate] and [threshold] come from the matcher in gate mode;
  /// [note] is a free-form last line (capture progress, the decision).
  void record({
    required String mode,
    required FrameAnalysis analysis,
    required DateTime at,
    MatchCandidate? candidate,
    double? threshold,
    double? margin,
    String? note,
  }) {
    _times.add(at);
    _micros.add(analysis.micros);
    while (_times.length > 20) {
      _times.removeAt(0);
      _micros.removeAt(0);
    }
    final span = _times.last.difference(_times.first).inMilliseconds;
    final fps = span <= 0 ? 0.0 : (_times.length - 1) * 1000 / span;
    final ms = _micros.reduce((a, b) => a + b) / _micros.length / 1000;

    final head =
        '$mode ${analysis.frameWidth}x${analysis.frameHeight} '
        'fix ${analysis.rotationFix}°'
        '${analysis.calibrating ? ' (calibrating)' : ''} '
        '${fps.toStringAsFixed(1)} fps ${ms.toStringAsFixed(0)} ms';
    final best = candidate == null || threshold == null
        ? null
        : 'best ${candidate.workerId} ${candidate.score.toStringAsFixed(2)} '
              '(need ${threshold.toStringAsFixed(2)}) '
              'lead ${_lead(candidate)}'
              '${margin == null ? '' : ' (need ${margin.toStringAsFixed(2)})'}';
    final lines = <String>[head, _faceLine(analysis), ?best, ?note];
    overlay.value = lines.join('\n');

    final last = _lastLog;
    if (last == null || at.difference(last) >= logEvery) {
      _lastLog = at;
      log('[sg_vision] ${lines.join(' | ')}');
    }
  }

  static String _lead(MatchCandidate c) =>
      c.runnerUpId == null ? 'n/a' : c.margin.toStringAsFixed(2);

  static String _faceLine(FrameAnalysis a) {
    final face = a.face;
    final q = a.quality;
    if (face == null || q == null) {
      return 'no face · frame luma ${a.frameLuma.toStringAsFixed(0)}';
    }
    String signed(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}';
    return 'face ${face.score.toStringAsFixed(2)} '
        'size ${(q.interOcularFraction * 100).toStringAsFixed(1)}% '
        'yaw ${signed(q.yaw)} roll ${q.roll.toStringAsFixed(0)}° '
        'luma ${q.faceLuma.toStringAsFixed(0)} '
        'sharp ${q.sharpness.toStringAsFixed(0)} '
        '${a.issue?.name ?? 'ok'}';
  }

  /// Clears the overlay (the camera stopped).
  void clear() => overlay.value = null;
}
