import 'dart:async';

/// Coalesces listener notifications.
///
/// Upstream schedules notifications through `setTimeout(0)` and lets the
/// framework adapter supply a batching function. Here, state changes apply
/// synchronously and only *delivery* is deferred — by default to a microtask,
/// which is the Dart equivalent of "before the next frame".
///
/// The Flutter binding replaces [deferFlush] with a scheduler-aware version so
/// a notification raised mid-build lands in a post-frame callback instead of
/// triggering `setState() called during build`.
class NotifyManager {
  int _transactions = 0;
  final List<void Function()> _queue = <void Function()>[];
  bool _flushScheduled = false;

  /// How a flush is deferred. Replaceable; must eventually call its argument.
  void Function(void Function() flush) deferFlush = scheduleMicrotask;

  /// Runs [fn], holding all notifications until the outermost batch exits.
  ///
  /// Nested batches join the outer one, so a cache operation that touches many
  /// queries notifies each listener once.
  T batch<T>(T Function() fn) {
    _transactions++;
    try {
      return fn();
    } finally {
      _transactions--;
      if (_transactions == 0) {
        _scheduleFlush();
      }
    }
  }

  /// Queues [callback] for the next flush.
  void schedule(void Function() callback) {
    _queue.add(callback);
    if (_transactions == 0) {
      _scheduleFlush();
    }
  }

  void _scheduleFlush() {
    if (_queue.isEmpty || _flushScheduled) {
      return;
    }
    _flushScheduled = true;
    deferFlush(_flush);
  }

  void _flush() {
    try {
      // A listener may schedule more work; draining here keeps that in the
      // same flush rather than deferring it another turn.
      while (_queue.isNotEmpty) {
        final callbacks = List<void Function()>.of(_queue);
        _queue.clear();
        for (final callback in callbacks) {
          callback();
        }
      }
    } finally {
      _flushScheduled = false;
    }
  }
}

/// The shared instance, as upstream.
final NotifyManager notifyManager = NotifyManager();
