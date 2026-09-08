import 'dart:async';

/// Thrown into a fetch when it is cancelled.
///
/// [revert] restores the state captured before the fetch began; [silent]
/// suppresses propagation because a replacement fetch is already starting.
class CancelledError implements Exception {
  const CancelledError({this.revert = false, this.silent = false});

  final bool revert;
  final bool silent;

  @override
  String toString() => 'CancelledError(revert: $revert, silent: $silent)';
}

/// Signals cancellation to a running query function.
///
/// Dart futures cannot be aborted, so a query function that wants to be
/// cancellable takes this from its context and wires it to whatever its
/// transport offers (dio's `CancelToken`, an `HttpClient` abort, and so on).
///
/// Reading the token from [QueryFunctionContext] marks it *consumed*, which is
/// how the cache learns the fetch can really be aborted. That distinction
/// matters when the last observer goes away: a consumed token means the fetch
/// is cancelled and the state reverted, while an unconsumed one means the fetch
/// is left to finish so its result still lands in the cache.
class QueryCancelToken {
  final Completer<CancelledError> _cancelled = Completer<CancelledError>();
  final List<void Function(CancelledError error)> _listeners =
      <void Function(CancelledError error)>[];
  CancelledError? _reason;

  bool get isCancelled => _reason != null;

  /// Why the fetch was cancelled, or null while it is still running.
  CancelledError? get reason => _reason;

  /// Completes when cancellation happens. Never completes with an error.
  Future<CancelledError> get whenCancelled => _cancelled.future;

  /// Registers [onCancel], calling it immediately if cancellation already
  /// happened — so a late listener cannot miss the event.
  void addListener(void Function(CancelledError error) onCancel) {
    final reason = _reason;
    if (reason != null) {
      onCancel(reason);
      return;
    }
    _listeners.add(onCancel);
  }

  /// Marks the token cancelled and notifies listeners. Repeat calls are
  /// ignored, so the first reason wins.
  void cancel(CancelledError error) {
    if (_reason != null) {
      return;
    }
    _reason = error;
    for (final listener in List.of(_listeners)) {
      listener(error);
    }
    _listeners.clear();
    if (!_cancelled.isCompleted) {
      _cancelled.complete(error);
    }
  }
}
