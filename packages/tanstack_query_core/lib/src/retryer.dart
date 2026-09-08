/// Port of `query-core/src/retryer.ts` at upstream `50680b98c`.
library;

import 'dart:async';

import 'cancel_token.dart';
import 'focus_manager.dart';
import 'online_manager.dart';
import 'option_values.dart';

enum RetryerStatus { pending, resolved, rejected }

/// Whether a fetch may begin under [networkMode] right now.
///
/// Upstream exports the same helper from `retryer.ts`; `Query`'s reducer and
/// the observer's optimistic result both ask it, so it lives here rather than
/// being inlined at each site.
bool canFetch(NetworkMode networkMode, OnlineManager onlineManager) =>
    networkMode != NetworkMode.online || onlineManager.isOnline();

/// Runs a fetch, retries it, and pauses it while the app is backgrounded or
/// offline.
///
/// The loop is upstream's, statement for statement, including the order that
/// matters: the retry decision is taken *before* `failureCount` is incremented,
/// so `RetryPolicy.times(3)` means three retries after the first failure, and the
/// delay is computed from the pre-increment count.
class Retryer<TData> {
  Retryer({
    required this.fn,
    required this.focusManager,
    required this.onlineManager,
    required this.canRun,
    this.initialFuture,
    this.retry = const RetryTimes(3),
    this.retryDelay = RetryDelay.defaultValue,
    this.networkMode = NetworkMode.online,
    this.onFail,
    this.onPause,
    this.onContinue,
    this.onCancel,
  }) {
    // The future rejects whether or not anybody is listening; without this an
    // unhandled rejection fails the whole enclosing test file.
    // https://github.com/KoTTi97/flutter_query/issues/9
    _completer.future.ignore();
  }

  final Future<TData> Function() fn;
  final Future<TData>? initialFuture;
  final AppFocusManager focusManager;
  final OnlineManager onlineManager;
  final bool Function() canRun;
  final RetryPolicy retry;
  final RetryDelay retryDelay;
  final NetworkMode networkMode;
  final void Function(int failureCount, Object error, StackTrace stackTrace)?
      onFail;
  final void Function()? onPause;
  final void Function()? onContinue;
  final void Function(CancelledError error)? onCancel;

  final Completer<TData> _completer = Completer<TData>();
  Completer<void>? _pauseCompleter;
  RetryerStatus _status = RetryerStatus.pending;
  bool _isRetryCancelled = false;
  int _failureCount = 0;

  Future<TData> get future => _completer.future;
  RetryerStatus get status => _status;
  bool get isResolved => _status != RetryerStatus.pending;

  /// Whether the fetch may begin right now.
  bool canStart() => _canFetch() && canRun();

  /// Starts the loop, pausing first if it cannot start yet.
  Future<TData> start() {
    if (canStart()) {
      _attempt().ignore();
    } else {
      _pause().then((_) => _attempt()).ignore();
    }
    return future;
  }

  /// Aborts the fetch. The error travels to the query, never to the caller.
  void cancel({bool revert = false, bool silent = false}) {
    if (!isResolved) {
      final error = CancelledError(revert: revert, silent: silent);
      _reject(error, StackTrace.current);
      onCancel?.call(error);
    }
  }

  /// Stops the loop from making another attempt, letting the in-flight request
  /// finish and populate the cache.
  void cancelRetry() => _isRetryCancelled = true;

  void continueRetry() => _isRetryCancelled = false;

  /// Releases a paused fetch, if it may now continue.
  Future<TData> continueFetch() {
    _tryContinue();
    return future;
  }

  bool _canFetch() => canFetch(networkMode, onlineManager);

  bool _canContinue() =>
      focusManager.isFocused() &&
      (networkMode == NetworkMode.always || onlineManager.isOnline()) &&
      canRun();

  void _tryContinue() {
    final pauseCompleter = _pauseCompleter;
    if (pauseCompleter != null &&
        !pauseCompleter.isCompleted &&
        (isResolved || _canContinue())) {
      pauseCompleter.complete();
    }
  }

  Future<void> _pause() async {
    final pauseCompleter = Completer<void>();
    _pauseCompleter = pauseCompleter;
    onPause?.call();
    await pauseCompleter.future;
    _pauseCompleter = null;
    if (!isResolved) {
      onContinue?.call();
    }
  }

  void _resolve(TData data) {
    if (!isResolved) {
      _tryContinue();
      _status = RetryerStatus.resolved;
      _completer.complete(data);
    }
  }

  void _reject(Object error, StackTrace stackTrace) {
    if (!isResolved) {
      _tryContinue();
      _status = RetryerStatus.rejected;
      _completer.completeError(error, stackTrace);
    }
  }

  Future<void> _attempt() async {
    if (isResolved) {
      return;
    }

    final initial = _failureCount == 0 ? initialFuture : null;

    try {
      final data = await (initial ?? fn());
      _resolve(data);
    } catch (error, stackTrace) {
      if (isResolved) {
        return;
      }

      if (_isRetryCancelled ||
          !retry.shouldRetry(_failureCount, error, stackTrace)) {
        _reject(error, stackTrace);
        return;
      }

      final delay = retryDelay.resolve(_failureCount, error);
      _failureCount++;
      onFail?.call(_failureCount, error, stackTrace);

      await Future<void>.delayed(delay);

      // The wait is long enough for the fetch to have been cancelled. Upstream
      // omits this check and a cancelled retry can still flip its query from
      // `idle` to `paused` on the way out; leaving a known state corruption in
      // for the sake of matching would be the wrong kind of fidelity.
      if (isResolved) {
        return;
      }

      if (!_canContinue()) {
        await _pause();
      }

      if (_isRetryCancelled) {
        _reject(error, stackTrace);
      } else {
        await _attempt();
      }
    }
  }
}
