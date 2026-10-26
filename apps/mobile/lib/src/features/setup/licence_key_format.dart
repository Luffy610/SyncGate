import 'package:flutter/services.dart';

/// Formats a licence key as `SGT-XXXX-XXXX-XXXX` while it is typed: upper
/// case, letters and digits only, dashes inserted for the user.
class LicenceKeyFormatter extends TextInputFormatter {
  const new();

  static const _prefix = 'SGT';
  static const payloadLength = 12;

  /// The letters and digits of [text] after the `SGT` prefix.
  static String payloadOf(String text) {
    final stripped = text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    final payload = stripped.startsWith(_prefix)
        ? stripped.substring(_prefix.length)
        : stripped;
    return payload.length > payloadLength
        ? payload.substring(0, payloadLength)
        : payload;
  }

  /// A complete key such as `SGT-4F7K-2Q9M-A1B2`.
  static bool isComplete(String text) =>
      payloadOf(text).length == payloadLength;

  static String format(String text, {bool trailingDash = true}) {
    final stripped = text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    // Let the user type the prefix itself.
    if (stripped.isNotEmpty && _prefix.startsWith(stripped)) return stripped;
    final payload = payloadOf(text);
    if (payload.isEmpty) return '';
    final groups = <String>[];
    for (var i = 0; i < payload.length; i += 4) {
      groups.add(
        payload.substring(i, i + 4 > payload.length ? payload.length : i + 4),
      );
    }
    final joined = '$_prefix-${groups.join('-')}';
    final endsOnFullGroup =
        payload.length % 4 == 0 && payload.length < payloadLength;
    return trailingDash && endsOnFullGroup ? '$joined-' : joined;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final deleting = newValue.text.length < oldValue.text.length;
    final text = format(newValue.text, trailingDash: !deleting);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
