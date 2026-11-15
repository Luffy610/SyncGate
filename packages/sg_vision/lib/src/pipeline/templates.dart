import 'dart:async';
import 'dart:typed_data';

/// Template slots per worker (ADR-0008 §2): one per enrolment angle plus one
/// adaptive slot refreshed from confident gate matches.
enum TemplateSlot { front, left, right, mask, adaptive }

/// One stored face code. Never a photo: a model-specific unit vector that
/// cannot practically be turned back into an image (NFR-SEC-02).
final class FaceTemplate {
  const new({
    required this.workerId,
    required this.slot,
    required this.vector,
    required this.modelId,
    required this.modelVersion,
    required this.quality,
    required this.createdAt,
  });

  final String workerId;
  final TemplateSlot slot;
  final Float32List vector;
  final String modelId;
  final String modelVersion;

  /// 0..1, from the capture's quality measurements.
  final double quality;
  final DateTime createdAt;

  /// Zeroes the vector (call when a template is discarded).
  void wipe() => vector.fillRange(0, vector.length, 0);
}

/// Where templates live on the phone (ADR-0008, ADR-0010). The production
/// implementation is the encrypted, non-exportable native vault; this
/// interface is what the pipeline needs from it.
abstract interface class TemplateVault {
  /// All templates, optionally only those made by [modelId]/[modelVersion].
  Future<List<FaceTemplate>> all({String? modelId, String? modelVersion});

  /// Replaces every template of [workerId] (enrolment, re-enrolment).
  Future<void> replaceWorker(String workerId, List<FaceTemplate> templates);

  /// Puts one template, replacing the same worker + slot (adaptive refresh).
  Future<void> put(FaceTemplate template);

  /// Erases [workerId]'s templates (delete, deactivation expiry).
  Future<void> removeWorker(String workerId);

  /// Fires after any change, so the gate can reload its gallery.
  Stream<void> get changes;
}

/// Keeps templates in memory only. Used in tests and the dev flavour until
/// the encrypted native vault (ADR-0010, epic E10) lands; nothing survives a
/// restart.
final class InMemoryTemplateVault implements TemplateVault {
  final _byWorker = <String, Map<TemplateSlot, FaceTemplate>>{};
  final _changes = StreamController<void>.broadcast();

  @override
  Future<List<FaceTemplate>> all({
    String? modelId,
    String? modelVersion,
  }) async => [
    for (final slots in _byWorker.values)
      for (final t in slots.values)
        if ((modelId == null || t.modelId == modelId) &&
            (modelVersion == null || t.modelVersion == modelVersion))
          t,
  ];

  @override
  Future<void> replaceWorker(
    String workerId,
    List<FaceTemplate> templates,
  ) async {
    _wipe(workerId);
    _byWorker[workerId] = {for (final t in templates) t.slot: t};
    _changes.add(null);
  }

  @override
  Future<void> put(FaceTemplate template) async {
    final slots = _byWorker.putIfAbsent(template.workerId, () => {});
    slots.remove(template.slot)?.wipe();
    slots[template.slot] = template;
    _changes.add(null);
  }

  @override
  Future<void> removeWorker(String workerId) async {
    _wipe(workerId);
    _changes.add(null);
  }

  void _wipe(String workerId) {
    final old = _byWorker.remove(workerId);
    if (old == null) return;
    for (final t in old.values) {
      t.wipe();
    }
  }

  @override
  Stream<void> get changes => _changes.stream;
}
