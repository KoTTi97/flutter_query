/// The test harness every ported suite uses.
///
/// Decided on https://github.com/KoTTi97/flutter_query/issues/9: upstream's
/// suites are written against `await vi.advanceTimersByTimeAsync(n)`, which
/// fires timers *and* drains microtasks in between. `FakeAsync.elapse` cannot
/// be called re-entrantly, and a ported test body runs inside the zone — so the
/// body parks on `await time.advance(d)` and an outer driver owns the single
/// top-level `elapse`.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:meta/meta.dart';
import 'package:tanstack_query_core/tanstack_query_core.dart';
import 'package:test/test.dart';

/// Drives virtual time from inside a [testFakeAsync] body.
class FakeTime {
  FakeTime._();

  _AdvanceRequest? _pending;
  FakeAsync? _async;

  /// Elapses virtual time by [duration], interleaving microtask flushes —
  /// the equivalent of `await vi.advanceTimersByTimeAsync(ms)`.
  Future<void> advance(Duration duration) {
    final request = _AdvanceRequest(duration);
    _pending = request;
    return request.completer.future;
  }

  /// Lets pending microtasks run without elapsing the clock
  /// (upstream: `advanceTimersByTimeAsync(0)`).
  Future<void> flushMicrotasks() => advance(Duration.zero);

  /// Virtual now. Core code reads time through `clock`, so this matches.
  DateTime get now => clock.now();

  /// How many timers are still scheduled.
  ///
  /// Not asserted automatically: a query schedules a `gcTime` timer as a matter
  /// of course, so "no pending timers" is false for almost every honest test.
  /// Suites that care about a *specific* leak (a refetch interval that should
  /// have been cancelled) call this.
  int get pendingTimers => _async?.pendingTimers.length ?? 0;

  _AdvanceRequest? _takePending() {
    final pending = _pending;
    _pending = null;
    return pending;
  }
}

class _AdvanceRequest {
  _AdvanceRequest(this.duration);

  final Duration duration;
  final Completer<void> completer = Completer<void>();
}

/// Runs [body] inside a [FakeAsync] zone with a fake clock.
@isTest
void testFakeAsync(
  String description,
  Future<void> Function(FakeTime time) body, {
  Object? skip,
  Timeout? timeout,
}) {
  test(
    description,
    () {
      final completed = runFakeAsyncBody(body);
      expect(
        completed,
        isTrue,
        reason: 'the test body never completed — it is awaiting a future that '
            'virtual time cannot resolve (real I/O, or a timer nothing '
            'advances). Drive it with time.advance().',
      );
    },
    skip: skip,
    timeout: timeout,
  );
}

/// Runs [body] in a fake-async zone, driving every [FakeTime.advance] it asks
/// for. Returns whether the body ran to completion; rethrows what it threw.
///
/// Exposed so the deadlock guard itself can be tested.
bool runFakeAsyncBody(Future<void> Function(FakeTime time) body) {
  var completed = false;
  Object? error;
  StackTrace? stackTrace;

  fakeAsync((async) {
    final time = FakeTime._().._async = async;

    unawaited(
      body(time).then(
        (_) => completed = true,
        onError: (Object e, StackTrace s) {
          error = e;
          stackTrace = s;
        },
      ),
    );

    while (true) {
      // Run the body up to its next `advance`, or to completion.
      async.flushMicrotasks();
      if (completed || error != null) {
        break;
      }
      final request = time._takePending();
      if (request == null) {
        break;
      }
      async.elapse(request.duration);
      request.completer.complete();
    }

    async.flushMicrotasks();
  });

  final caught = error;
  if (caught != null) {
    Error.throwWithStackTrace(caught, stackTrace!);
  }
  return completed;
}

/// Like [testFakeAsync], but also collects errors reported to the zone.
@isTest
void testFakeAsyncGuarded(
  String description,
  Future<void> Function(FakeTime time, List<Object> uncaught) body, {
  Object? skip,
}) {
  test(description, () {
    final uncaught = <Object>[];
    final completed = runFakeAsyncBody((time) {
      final completer = Completer<void>();
      runZonedGuarded(
        () async {
          try {
            await body(time, uncaught);
            completer.complete();
          } catch (error, stackTrace) {
            // A failure of the body itself must fail the test rather than land
            // in the collected list.
            completer.completeError(error, stackTrace);
          }
        },
        (error, _) => uncaught.add(error),
      );
      return completer.future;
    });
    expect(
      completed,
      isTrue,
      reason: 'the test body never completed — see testFakeAsync.',
    );
  }, skip: skip);
}

int _keyCounter = 0;

/// A unique key per call, so tests never collide in a shared cache.
/// Port of upstream's `queryKey()` helper.
QueryKey queryKey() => QueryKey(<Object?>['query_${++_keyCounter}']);

/// Virtual-time sleep.
Future<void> sleep(Duration duration) => Future<void>.delayed(duration);

/// Upstream writes timings as bare millisecond numbers; this keeps ported
/// tests readable.
Duration ms(int milliseconds) => Duration(milliseconds: milliseconds);

/// A client with its own managers, so nothing leaks between tests
/// (https://github.com/KoTTi97/flutter_query/issues/19).
QueryClient testClient({
  DefaultOptions? defaultOptions,
  QueryCache? queryCache,
  MutationCache? mutationCache,
}) =>
    QueryClient(
      queryCache: queryCache,
      mutationCache: mutationCache,
      defaultOptions: defaultOptions,
      focusManager: AppFocusManager(),
      onlineManager: OnlineManager(),
      notifyManager: NotifyManager(),
    );

/// The upstream name of a cache event, so ported tests can assert on the same
/// event-sequence strings.
String eventName(QueryCacheEvent event) => switch (event) {
      QueryAdded() => 'added',
      QueryRemoved() => 'removed',
      QueryUpdated() => 'updated',
      QueryObserverAdded() => 'observerAdded',
      QueryObserverRemoved() => 'observerRemoved',
      QueryObserverResultsUpdated() => 'observerResultsUpdated',
    };
