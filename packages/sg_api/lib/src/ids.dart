import 'dart:convert';

import 'package:crypto/crypto.dart';

final _uuidPattern = RegExp(
  '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// The API identifies every record by UUID. The app still creates some ids as
/// readable strings (`ev-123-0`, `shift-day`). This maps such a string to a
/// stable UUID (name-based, like UUIDv5) so a retried request carries the same
/// id and the server can answer idempotently. A real UUID passes through.
String uuidFor(String id) {
  if (_uuidPattern.hasMatch(id)) return id.toLowerCase();
  final hash = sha1.convert(utf8.encode('syncgate:$id')).bytes;
  final b = List<int>.of(hash.sublist(0, 16));
  b[6] = (b[6] & 0x0F) | 0x50; // version 5
  b[8] = (b[8] & 0x3F) | 0x80; // RFC 4122 variant
  String hex(int from, int to) => b
      .sublist(from, to)
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
