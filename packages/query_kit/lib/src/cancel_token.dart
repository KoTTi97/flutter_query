/// Cancellation. Ports `CancelledError` from `query-core/src/retryer.ts` and
/// the `AbortSignal` handed to query functions in `query-core/src/query.ts`,
/// at upstream `50680b98c`.
///
/// See https://github.com/KoTTi97/flutter_query/issues/11.
library;

import 'dart:async';

/// Thrown into a query's own result when its fetch is cancelled.
///
/// An [Exception], not an [Error]: cancelling is an expected outcome, not a
/// programming mistake.
final class CancelledError implements Exception {
  /// Creates the error a cancelled fetch resolves with. [revert] and [silent]
  /// are the two flags upstream's `cancel` options carry; both default to off.
  const CancelledError({this.revert = false, this.silent = false});

  /// Whether the query's state is restored to what it was before the fetch.
  final bool revert;

  /// Whether the cancellation is kept out of the query's error state.
  final bool silent;

  @override
  String toString() => 'CancelledError(revert: $revert, silent: $silent)';
}

/// Handed to a query function so it can abort work that is no longer wanted.
///
/// Dart has no ecosystem-wide cancellation primitive, so [onCancel] is the
/// universal interop point:
///
/// ```dart
/// queryFn: (context) {
///   final cancelToken = dio.CancelToken();
///   context.signal.onCancel(cancelToken.cancel);
///   return dio.get('/tasks', cancelToken: cancelToken);
/// }
/// ```
///
/// A client with no cancellation (such as `package:http`) simply never
/// registers a callback; the request then runs to completion and its result is
/// discarded, which is exactly what upstream does for the same case.
class QueryCancelToken {
  final Completer<void> _completer = Completer<void>();
  final List<void Function()> _callbacks = <void Function()>[];

  /// Whether [cancel] has been called. Once `true` it stays `true`: a token is
  /// never reused across fetches.
  bool get isCancelled => _completer.isCompleted;

  /// Completes when the fetch is cancelled, and never otherwise.
  Future<void> get whenCancelled => _completer.future;

  /// Runs [callback] on cancellation — immediately, if already cancelled.
  ///
  /// Callbacks run *synchronously* inside [cancel], the way a browser's
  /// `AbortController` dispatches its abort event. A microtask's delay would be
  /// long enough for an in-flight page loop to start one more page.
  void onCancel(void Function() callback) {
    if (isCancelled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
  }

  /// Throws a [CancelledError] if this token has been cancelled.
  void throwIfCancelled() {
    if (isCancelled) {
      throw const CancelledError();
    }
  }

  /// Cancels this token. Called by the library, not by query functions.
  void cancel() {
    if (_completer.isCompleted) {
      return;
    }
    _completer.complete();
    final callbacks = List<void Function()>.of(_callbacks);
    _callbacks.clear();
    for (final callback in callbacks) {
      // One callback's throw must not skip the rest, nor escape into the
      // code that cancelled; it is the callback's error, reported as such.
      try {
        callback();
      } catch (error, stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }
    }
  }
}
