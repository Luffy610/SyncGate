import 'dart:async';

/// A value that can be watched: new listeners get the current value first,
/// then every change. Backs the in-memory fakes.
class Reactive<T> {
  new(this._value);

  T _value;
  final _controller = StreamController<T>.broadcast(sync: true);

  T get value => _value;

  set value(T next) {
    _value = next;
    _controller.add(next);
  }

  Stream<T> watch() => Stream<T>.multi((listener) {
    final sub = _controller.stream.listen(listener.add);
    listener
      ..onCancel = sub.cancel
      ..add(_value);
  });
}
