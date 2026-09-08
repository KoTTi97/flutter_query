/// Port of `query-core/src/notifyManager.ts` at upstream `50680b98c`.
library;

import 'dart:async';

/// Schedules when a batch of notifications runs.
typedef ScheduleFunction = void Function(void Function() callback);

/// Wraps the delivery of a single notification.
typedef NotifyFunction = void Function(void Function() callback);

/// Wraps the delivery of a whole batch.
typedef BatchNotifyFunction = void Function(void Function() callback);

/// Batches cache notifications so one cascade of cache writes produces one
/// round of listener calls.
///
/// Two divergences from upstream, both decided on
/// https://github.com/KoTTi97/flutter_query/issues/19:
///
/// * The default scheduler is [scheduleMicrotask], not a zero-delay timer.
///   It is faster, it is deterministic, and `fake_async` controls it.
/// * This is an ordinary object rather than a module-level singleton, so a
///   [QueryClient] can own one and tests are hermetic. Apps that want
///   upstream's single shared queue get it by default via
///   [NotifyManager.shared].
class NotifyManager {
  NotifyManager();

  /// The process-wide instance used when a client is constructed without one.
  static final NotifyManager shared = NotifyManager();

  final List<void Function()> _queue = <void Function()>[];
  int _transactions = 0;

  ScheduleFunction _scheduleFn = scheduleMicrotask;
  NotifyFunction _notifyFn = _runCallback;
  BatchNotifyFunction _batchNotifyFn = _runCallback;

  static void _runCallback(void Function() callback) => callback();

  /// Runs [callback], holding every notification scheduled inside it until the
  /// outermost batch completes.
  T batch<T>(T Function() callback) {
    _transactions++;
    try {
      return callback();
    } finally {
      _transactions--;
      if (_transactions == 0) {
        flush();
      }
    }
  }

  /// Wraps [callback] so that calling it schedules rather than runs it.
  void Function(A) batchCalls<A>(void Function(A) callback) {
    return (A argument) => schedule(() => callback(argument));
  }

  /// Queues [callback] for the next flush, or runs it through the scheduler
  /// immediately when no batch is open.
  void schedule(void Function() callback) {
    if (_transactions > 0) {
      _queue.add(callback);
    } else {
      _scheduleFn(() => _notifyFn(callback));
    }
  }

  /// Delivers everything queued so far.
  void flush() {
    if (_queue.isEmpty) {
      return;
    }
    final pending = List<void Function()>.of(_queue);
    _queue.clear();
    _scheduleFn(() {
      _batchNotifyFn(() {
        for (final callback in pending) {
          _notifyFn(callback);
        }
      });
    });
  }

  /// Replaces how a single notification is delivered.
  void setNotifyFunction(NotifyFunction fn) => _notifyFn = fn;

  /// Replaces how a whole batch is delivered.
  void setBatchNotifyFunction(BatchNotifyFunction fn) => _batchNotifyFn = fn;

  /// Replaces when the next batch runs. The Flutter binding installs a
  /// build-phase-aware scheduler here.
  void setScheduler(ScheduleFunction fn) => _scheduleFn = fn;

  /// The scheduler in force. A caller that installs one keeps this to put back
  /// when it goes away — a stale scheduler outliving whoever set it would keep
  /// deferring notifications to a frame that never comes.
  ScheduleFunction get scheduler => _scheduleFn;
}
