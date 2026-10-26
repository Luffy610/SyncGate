import 'package:meta/meta.dart';

/// Outcome of an operation that can fail in an expected way.
///
/// Expected failures are returned, not thrown across layers (ADR-0003).
@immutable
sealed class Result<T, F> {
  const new();

  const factory ok(T value) = Ok<T, F>;

  const factory err(F failure) = Err<T, F>;

  bool get isOk => this is Ok<T, F>;

  bool get isErr => this is Err<T, F>;

  /// The value, or `null` for a failure.
  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Err() => null,
  };

  R fold<R>(R Function(T value) onOk, R Function(F failure) onErr) =>
      switch (this) {
        Ok(:final value) => onOk(value),
        Err(:final failure) => onErr(failure),
      };

  Result<U, F> map<U>(U Function(T value) transform) => switch (this) {
    Ok(:final value) => Ok(transform(value)),
    Err(:final failure) => Err(failure),
  };
}

final class Ok<T, F> extends Result<T, F> {
  const new(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T, F> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

final class Err<T, F> extends Result<T, F> {
  const new(this.failure);

  final F failure;

  @override
  bool operator ==(Object other) =>
      other is Err<T, F> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err($failure)';
}
