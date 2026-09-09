/// Port of `query-core/src/retryer.ts` at upstream `50680b98c`.
library;

import 'dart:async';

import 'cancel_token.dart';
import 'focus_manager.dart';
import 'online_manager.dart';
import 'option_values.dart';
import 'timers.dart';

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
  bool _isRetryCancelledImmediately = false;
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
      _reject(error, stackTrace: StackTrace.current);
      onCancel?.call(error);
    }
  }

  /// Stops the loop from making another attempt, letting the in-flight request
  /// finish and populate the cache. A backoff delay already running is waited
  /// out first, as upstream does, unless [immediately] is set — then the loop
  /// rejects with the last error as soon as nothing is in flight, and a fetch
  /// that is *paused* (offline, unfocused, or queued behind its scope) rejects
  /// with a [CancelledError] on the spot: nothing is in flight to wait for,
  /// and nothing else would ever release it once its owner is gone.
  void cancelRetry({bool immediately = false}) {
    _isRetryCancelled = true;
    if (immediately) {
      _isRetryCancelledImmediately = true;
      _wakeDelay();
      final pause = _pauseCompleter;
      if (pause != null && !pause.isCompleted) {
        _reject(const CancelledError(), stackTrace: StackTrace.current);
      }
    }
  }

  void continueRetry() {
    _isRetryCancelled = false;
    _isRetryCancelledImmediately = false;
  }

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
    // A throw here rejects, and rejecting releases the pause.
    _hook(onPause);
    await pauseCompleter.future;
    _pauseCompleter = null;
    if (!isResolved) {
      _hook(onContinue);
    }
  }

  /// Runs one of the owner's hooks. They dispatch into the query or mutation,
  /// and a dispatch reaches listeners — user code. Left unguarded, a throw
  /// escaped into `_attempt`'s ignored future and the completer was never
  /// settled: a fetch pending forever, with nothing reported anywhere
  /// (fourth review, 2026-09-09). The throw is the fetch's error instead, the
  /// policy a throwing retry callback already follows. Returns whether the
  /// hook completed.
  bool _hook(void Function()? hook) {
    try {
      hook?.call();
      return true;
    } catch (error, stackTrace) {
      _reject(error, stackTrace: stackTrace);
      return false;
    }
  }

  void _resolve(TData data) {
    if (!isResolved) {
      _tryContinue();
      _wakeDelay();
      _status = RetryerStatus.resolved;
      _completer.complete(data);
    }
  }

  void _reject(Object error, {required StackTrace stackTrace}) {
    if (!isResolved) {
      _tryContinue();
      _wakeDelay();
      _status = RetryerStatus.rejected;
      _completer.completeError(error, stackTrace);
    }
  }

  Timer? _delayTimer;
  Completer<void>? _delayCompleter;

  /// Upstream's `sleep`, with an off switch: the timer is dropped and the
  /// wait ends early when the fetch is resolved or its retries are cancelled
  /// for good. Left alone, a 30-second backoff would outlive the cache it was
  /// fetching for, and Flutter's widget tests assert that no timer does.
  Future<void> _sleep(Duration delay) {
    final completer = Completer<void>();
    _delayCompleter = completer;
    _delayTimer = Timer(clampTimerDuration(delay), () {
      _delayTimer = null;
      _delayCompleter = null;
      completer.complete();
    });
    return completer.future;
  }

  void _wakeDelay() {
    _delayTimer?.cancel();
    _delayTimer = null;
    final completer = _delayCompleter;
    _delayCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// Upstream's recursive `run`, written as a loop: a mutation retrying
  /// forever while offline would otherwise stack one async frame per attempt.
  Future<void> _attempt() async {
    while (true) {
      if (isResolved) {
        return;
      }

      final initial = _failureCount == 0 ? initialFuture : null;

      final Object error;
      final StackTrace stackTrace;
      try {
        final data = await (initial ?? fn());
        _resolve(data);
        return;
      } catch (caught, trace) {
        error = caught;
        stackTrace = trace;
      }

      if (isResolved) {
        return;
      }

      // The retry policy and the delay are user code. Upstream lets a throw
      // here escape as an unhandled rejection and leaves the fetch pending
      // forever; a fetch that can never settle is worse than one that fails,
      // so the throw becomes the fetch's error.
      final Duration delay;
      try {
        if (_isRetryCancelled ||
            !retry.shouldRetry(_failureCount, error, stackTrace)) {
          _reject(error, stackTrace: stackTrace);
          return;
        }
        delay = retryDelay.resolve(_failureCount, error);
      } catch (policyError, policyStackTrace) {
        _reject(policyError, stackTrace: policyStackTrace);
        return;
      }

      _failureCount++;
      if (!_hook(() => onFail?.call(_failureCount, error, stackTrace))) {
        return;
      }

      await _sleep(delay);

      // The wait is long enough for the fetch to have been cancelled. Upstream
      // omits this check and a cancelled retry can still flip its query from
      // `idle` to `paused` on the way out; leaving a known state corruption in
      // for the sake of matching would be the wrong kind of fidelity.
      if (isResolved) {
        return;
      }

      // An immediate cancel woke the delay early to reject, not to pause:
      // checked before the pause, or an offline mutation removed from its
      // cache would park here until the network came back.
      if (_isRetryCancelledImmediately) {
        _reject(error, stackTrace: stackTrace);
        return;
      }

      if (!_canContinue()) {
        await _pause();
      }

      if (_isRetryCancelled) {
        _reject(error, stackTrace: stackTrace);
        return;
      }
    }
  }
}
