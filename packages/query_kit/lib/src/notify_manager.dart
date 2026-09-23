/// Notification batching: [NotifyManager].
library;

import 'dart:async';

/// Schedules when a batch of notifications runs: given the delivery as a
/// callback, runs it now or later. The default is [scheduleMicrotask];
/// install one with [NotifyManager.setScheduler] (the Flutter binding
/// installs a build-phase-aware one).
///
/// {@category Managers}
typedef ScheduleFunction = void Function(void Function() callback);

/// Wraps the delivery of a single notification: must call the callback it
/// is given exactly once. Install one with
/// [NotifyManager.setNotifyFunction], for example to run each listener
/// inside a zone or an error boundary. The default calls it directly.
///
/// {@category Managers}
typedef NotifyFunction = void Function(void Function() callback);

/// Wraps the delivery of a whole batch: must call the callback it is given
/// exactly once. Install one with [NotifyManager.setBatchNotifyFunction] —
/// in a UI framework, to apply every update of a batch in one frame. The
/// default calls it directly.
///
/// {@category Managers}
typedef BatchNotifyFunction = void Function(void Function() callback);

/// Batches cache notifications so one cascade of cache writes produces one
/// round of listener calls.
///
/// Each client owns one, as `QueryClient.notifyManager`; most apps never
/// touch it. Two differences from TanStack Query:
///
/// * The default scheduler is [scheduleMicrotask], not a zero-delay timer.
///   It is faster, it is deterministic, and `fake_async` controls it.
/// * This is an ordinary object rather than a module-level singleton, so a
///   `QueryClient` can own one and tests are hermetic. A client constructed
///   without one creates its own; apps that want a single shared queue pass
///   [NotifyManager.shared] to every client.
///
/// A [batch] holds callbacks submitted through [schedule] or [batchCalls]
/// until the outermost batch ends, then delivers them through the scheduler.
/// Direct observer subscriptions, cache listeners and `onQueryUpdate` remain
/// synchronous per dispatch. Wrap a subscription with [batchCalls] when its
/// delivery should be deferred. A throwing callback in a queued batch is
/// reported to the zone and does not discard later callbacks in that batch.
///
/// ```dart
/// // Several writes; callbacks queued through `schedule` or `batchCalls`
/// // meanwhile are delivered in one round after the batch ends:
/// client.notifyManager.batch(() {
///   client.setQueryData<int>(QueryKey(['a']), 1);
///   client.setQueryData<int>(QueryKey(['b']), 2);
/// });
///
/// // A cache subscription whose calls are deferred and batched:
/// client.queryCache.subscribe(
///   client.notifyManager.batchCalls((QueryCacheEvent event) => log(event)),
/// );
/// ```
///
/// {@category Managers}
class NotifyManager {
  /// Creates an independent queue with the default microtask scheduler.
  NotifyManager();

  /// A process-wide instance, for batching across clients. Not the default:
  /// a client constructed without one creates its own.
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

  /// Delivers everything queued so far, through the scheduler. [batch] calls
  /// this when its outermost call ends; calling it by hand is rarely needed.
  void flush() {
    if (_queue.isEmpty) {
      return;
    }
    final pending = List<void Function()>.of(_queue);
    _queue.clear();
    _scheduleFn(() {
      _batchNotifyFn(() {
        for (final callback in pending) {
          try {
            _notifyFn(callback);
          } catch (error, stackTrace) {
            Zone.current.handleUncaughtError(error, stackTrace);
          }
        }
      });
    });
  }

  /// Replaces how a single notification is delivered; see [NotifyFunction].
  void setNotifyFunction(NotifyFunction fn) => _notifyFn = fn;

  /// Replaces how a whole batch is delivered; see [BatchNotifyFunction].
  void setBatchNotifyFunction(BatchNotifyFunction fn) => _batchNotifyFn = fn;

  /// Replaces when the next batch runs. The Flutter binding installs a
  /// build-phase-aware scheduler here.
  void setScheduler(ScheduleFunction fn) => _scheduleFn = fn;

  /// The scheduler in force. A caller that installs one keeps this to put back
  /// when it goes away — a stale scheduler outliving whoever set it would keep
  /// deferring notifications to a frame that never comes.
  ScheduleFunction get scheduler => _scheduleFn;
}
