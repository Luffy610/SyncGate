import 'package:meta/meta.dart';
import 'package:sg_domain/src/entities.dart';

/// Expected failures, returned in a `Result` and mapped to a localised
/// message by the UI (ADR-0003).
@immutable
sealed class Failure {
  const new();
}

/// PIN rejected. [attemptsLeft] is 0 when the user is locked out.
final class WrongPin extends Failure {
  const new({required this.attemptsLeft, this.lockedFor});

  final int attemptsLeft;

  /// Set when locked out: how long until the next attempt.
  final Duration? lockedFor;
}

final class LockedOut extends Failure {
  const new(this.remaining);

  final Duration remaining;
}

final class NotAllowed extends Failure {
  const new();
}

final class WorkerUnderAge extends Failure {
  const new();
}

final class DuplicateWorkerCode extends Failure {
  const new();
}

/// A third manual entry for the same worker on one day (ADR-0004 §3).
final class ManualLimitReached extends Failure {
  const new();
}

/// A mark inside the 2-minute cooldown. Nothing is stored (FR-ATT-05).
final class AlreadyMarked extends Failure {
  const new({required this.at, required this.direction});

  final DateTime at;
  final Direction direction;
}

final class DuplicateFace extends Failure {
  const new({required this.workerId});

  final String workerId;
}

final class InvalidLicenceKey extends Failure {
  const new();
}

final class NoInternet extends Failure {
  const new();
}

final class NotFound extends Failure {
  const new();
}

final class Unexpected extends Failure {
  const new([this.message]);

  final String? message;
}

/// A correction whose OUT time is not after the IN time.
final class InvalidCorrection extends Failure {
  const new();
}
