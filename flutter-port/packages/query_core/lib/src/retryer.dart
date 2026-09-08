import 'dart:async';

import 'cancel_token.dart';
import 'focus_manager.dart';
import 'online_manager.dart';
import 'option_values.dart';

enum RetryerStatus { pending, resolved, rejected }

/// Whether a fetch may start at all under [mode].
bool canFetch(NetworkMode? mode) =>
    (mode ?? NetworkMode.online) == NetworkMode.online
        ? onlineManager.isOnline
        : true;

/// Runs a function, retrying on failure and pausing while the app is offline or
/// in the background.
///
/// A paused retryer is not a failed one: it waits, and [resume] continues it
/// when connectivity or focus returns. Everything awaiting [future] simply
/// keeps waiting, which is what lets several observers share one in-flight
/// fetch across an offline gap.
class Retryer<TData> {
  Retryer({
    required Future<TData> Function() fn,
    required bool Function() canRun,
    Future<TData>? initialFuture,
    NetworkMode? networkMode,
    RetryOption? retry,
    RetryDelay? retryDelay,
    void Function(CancelledError error)? onCancel,
    void Function(int failureCount, Object error, StackTrace stackTrace)?
        onFail,
    void Function()? onPause,
    void Function()? onContinue,
  })  : _fn = fn,
        _canRun = canRun,
        _initialFuture = initialFuture,
        _networkMode = networkMode,
        _retry = retry,
        _retryDelay = retryDelay,
        _onCancel = onCancel,
        _onFail = onFail,
        _onPause = onPause,
        _onContinue = onContinue {
    // The future completes with an error whether or not anyone is awaiting it
    // (a fetch nobody listens to still fails). Without this, Dart reports it as
    // an unhandled error and fails tests (D13).
    _completer.future.ignore();
  }

  final Future<TData> Function() _fn;
  final bool Function() _canRun;
  final Future<TData>? _initialFuture;
  final NetworkMode? _networkMode;
  final RetryOption? _retry;
  final RetryDelay? _retryDelay;
  final void Function(CancelledError error)? _onCancel;
  final void Function(int failureCount, Object error, StackTrace stackTrace)?
      _onFail;
  final void Function()? _onPause;
  final void Function()? _onContinue;

  final Completer<TData> _completer = Completer<TData>();

  RetryerStatus _status = RetryerStatus.pending;
  int _failureCount = 0;
  bool _isRetryCancelled = false;
  Completer<void>? _pauseCompleter;

  /// The single future every caller shares — the basis of request dedup.
  Future<TData> get future => _completer.future;

  RetryerStatus get status => _status;

  bool get _isResolved => _status != RetryerStatus.pending;

  /// Whether a fetch may begin now.
  bool canStart() => canFetch(_networkMode) && _canRun();

  /// Whether a paused fetch may continue now.
  bool _canContinue() =>
      focusManager.isFocused &&
      (_networkMode == NetworkMode.always || onlineManager.isOnline) &&
      _canRun();

  /// Starts the retry loop, pausing first if conditions do not allow a fetch.
  Future<TData> start() {
    if (canStart()) {
      _run();
    } else {
      _pause().then((_) => _run()).ignore();
    }
    return future;
  }

  /// Cancels the fetch. Anything awaiting [future] receives a [CancelledError]
  /// unless the fetch already settled.
  void cancel({bool revert = false, bool silent = false}) {
    if (_isResolved) {
      return;
    }
    final error = CancelledError(revert: revert, silent: silent);
    _reject(error, StackTrace.current);
    _onCancel?.call(error);
  }

  /// Stops retrying after the current attempt — used when the last observer
  /// leaves but the in-flight request should still populate the cache.
  void cancelRetry() => _isRetryCancelled = true;

  /// Undoes [cancelRetry], so a re-subscribed observer resumes retrying.
  void continueRetry() => _isRetryCancelled = false;

  /// Continues a paused fetch. Upstream calls this `continue`, which Dart
  /// reserves.
  Future<TData> resume() {
    _releasePause();
    return future;
  }

  void _resolve(TData value) {
    if (_isResolved) {
      return;
    }
    _releasePause();
    _status = RetryerStatus.resolved;
    _completer.complete(value);
  }

  void _reject(Object error, StackTrace stackTrace) {
    if (_isResolved) {
      return;
    }
    _releasePause();
    _status = RetryerStatus.rejected;
    _completer.completeError(error, stackTrace);
  }

  void _releasePause() {
    final pause = _pauseCompleter;
    if (pause != null && !pause.isCompleted) {
      // Only actually continue when conditions allow it; otherwise the fetch
      // stays paused and a later resume tries again.
      if (_isResolved || _canContinue()) {
        pause.complete();
      }
    }
  }

  Future<void> _pause() {
    final pause = Completer<void>();
    _pauseCompleter = pause;
    _onPause?.call();
    return pause.future.then((_) {
      _pauseCompleter = null;
      if (!_isResolved) {
        _onContinue?.call();
      }
    });
  }

  void _run() {
    if (_isResolved) {
      return;
    }

    Future<TData> attempt;
    // The first attempt can adopt a future the caller already started.
    final initial = _failureCount == 0 ? _initialFuture : null;
    try {
      attempt = initial ?? _fn();
    } catch (error, stackTrace) {
      attempt = Future<TData>.error(error, stackTrace);
    }

    attempt.then<void>(
      _resolve,
      onError: (Object error, StackTrace stackTrace) {
        if (_isResolved) {
          return;
        }

        final retry = _retry ?? const RetryOption.count(3);
        final retryDelay = _retryDelay ?? RetryDelay.exponential;

        if (_isRetryCancelled || !retry.shouldRetry(_failureCount, error)) {
          _reject(error, stackTrace);
          return;
        }

        _failureCount++;
        _onFail?.call(_failureCount, error, stackTrace);

        Future<void>.delayed(
          retryDelay.delayFor(_failureCount - 1, error),
        ).then((_) => _canContinue() ? null : _pause()).then((_) {
          if (_isRetryCancelled) {
            _reject(error, stackTrace);
          } else {
            _run();
          }
        }).ignore();
      },
    ).ignore();
  }
}
