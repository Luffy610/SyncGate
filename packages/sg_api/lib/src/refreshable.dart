import 'dart:async';

/// A value loaded over HTTP that the UI watches. It replays the latest value
/// to each new listener, reloads when [refresh] is called (after a change the
/// app made) and polls while somebody is listening, so changes made on
/// another screen or by the nightly job show up without a restart.
///
/// A failed first load is reported as a stream error (so the app can say it is
/// not connected). A failed later poll keeps the last good value.
class Refreshable<T> {
  new(this._load, {this.interval = const Duration(seconds: 6)});

  final Future<T> Function() _load;
  final Duration interval;

  final _controller = StreamController<T>.broadcast(sync: true);
  T? _value;
  bool _hasValue = false;
  Timer? _timer;
  int _listeners = 0;
  Future<void>? _inFlight;

  /// The last loaded value, if any.
  T? get value => _value;

  Stream<T> watch() => Stream<T>.multi((listener) {
    _listeners++;
    final sub = _controller.stream.listen(
      listener.add,
      onError: listener.addError,
    );
    if (_hasValue) listener.add(_value as T);
    if (_listeners == 1) {
      _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
    }
    if (!_hasValue) unawaited(refresh());
    listener.onCancel = () {
      unawaited(sub.cancel());
      _listeners--;
      if (_listeners == 0) {
        _timer?.cancel();
        _timer = null;
      }
    };
  });

  /// Loads now. Concurrent calls share one request.
  Future<void> refresh() => _inFlight ??= _run().whenComplete(() {
    _inFlight = null;
  });

  Future<void> _run() async {
    try {
      final next = await _load();
      _value = next;
      _hasValue = true;
      _controller.add(next);
    } on Object catch (e, s) {
      if (!_hasValue) _controller.addError(e, s);
    }
  }

  /// The current value, loading it first if needed.
  Future<T> current() async {
    if (!_hasValue) await refresh();
    if (!_hasValue) return await _load();
    return _value as T;
  }

  void dispose() {
    _timer?.cancel();
    unawaited(_controller.close());
  }
}
