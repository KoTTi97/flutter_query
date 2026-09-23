/// Cancellation: [CancelledError] and [QueryCancelToken], the counterparts of
/// TanStack Query's `CancelledError` and the `AbortSignal` its query
/// functions receive.
library;

import 'dart:async';

/// What a cancelled fetch fails with.
///
/// A fetch is cancelled by `QueryClient.cancelQueries`, by `Query.cancel`,
/// by a newer fetch taking over (`cancelRefetch`), or when its last observer
/// unsubscribes while a query function that read its
/// [QueryFunctionContext.signal] is still running. What someone awaiting
/// that fetch (`QueryClient.query`, `QueryObserver.refetch`) sees depends
/// on [silent] and [revert]:
///
/// * a [silent] cancel that a new fetch replaced completes with the new
///   fetch's result, and otherwise throws this error; the query's state
///   records nothing;
/// * a [revert] cancel on a query that holds data completes with that data;
///   the query goes back to its previous state;
/// * in every other case the caller gets this error, and the query records
///   it unless the cancel reverted it.
///
/// An [Exception], not an [Error]: cancelling is an expected outcome, not a
/// programming mistake. A query function may also throw it itself, through
/// [QueryCancelToken.throwIfCancelled].
///
/// {@category Errors}
final class CancelledError implements Exception {
  /// Creates the error a cancelled fetch resolves with. [revert] and [silent]
  /// are the two flags a cancellation carries (as in TanStack Query's
  /// `cancel` options); both default to off.
  const CancelledError({this.revert = false, this.silent = false});

  /// Whether the query's state is restored to what it was before the fetch.
  final bool revert;

  /// Whether the cancellation is kept out of the query's error state.
  final bool silent;

  @override
  String toString() => 'CancelledError(revert: $revert, silent: $silent)';
}

/// Handed to a query function, as [QueryFunctionContext.signal], so it can
/// abort work that is no longer wanted.
///
/// Dart has no ecosystem-wide cancellation primitive, so [onCancel] is the
/// universal interop point — forward it to whatever your HTTP client uses:
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
/// discarded, as in TanStack Query. For long loops, poll [isCancelled] or
/// call [throwIfCancelled] between steps, or await [whenCancelled].
///
/// Reading `signal` matters: a query whose function never read it is not
/// cancelled when its last observer leaves — the request cannot be stopped,
/// so it is allowed to finish and its result is cached. Once the signal has
/// been read, the fetch is cancelled and the query reverts instead.
///
/// The library creates one token per fetch, shared by its retries, and
/// cancels it; a query
/// function never calls [cancel]. Tests that call a query function directly
/// create their own with the default constructor, `QueryCancelToken()`, and
/// pass it to the `QueryFunctionContext` they build.
///
/// {@category Queries}
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
  ///
  /// A callback's throw is its own, whichever path runs it: reported to the
  /// zone, never thrown into [cancel]'s caller or into the query function
  /// registering it late.
  void onCancel(void Function() callback) {
    if (isCancelled) {
      _run(callback);
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
      _run(callback);
    }
  }

  // One callback's throw must not skip the rest, nor escape into the code
  // that cancelled; it is the callback's error, reported as such.
  static void _run(void Function() callback) {
    try {
      callback();
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }
}
