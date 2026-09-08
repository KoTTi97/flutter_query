import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:meta/meta.dart';
import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

/// Drives virtual time from inside a [testFakeAsync] body.
///
/// [advance] is the equivalent of vitest's `await vi.advanceTimersByTimeAsync`:
/// it fires timers *and* lets microtasks run in between, which is what the
/// ported upstream tests rely on.
class FakeTime {
  FakeTime._();

  _AdvanceRequest? _pending;

  /// Elapses virtual time by [duration], interleaving microtask flushes.
  Future<void> advance(Duration duration) {
    final request = _AdvanceRequest(duration);
    _pending = request;
    return request.completer.future;
  }

  /// Lets pending microtasks run without elapsing the clock — the idiom for
  /// "flush notifications" (upstream: `advanceTimersByTimeAsync(0)`).
  Future<void> flushMicrotasks() => advance(Duration.zero);

  /// Virtual now. Core code reads time through `clock`, so this matches.
  DateTime get now => clock.now();

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
///
/// The body is an ordinary async function; every `await time.advance(...)`
/// suspends it and hands control back to this driver, which elapses virtual
/// time at the top level. That indirection is required because `FakeAsync`
/// forbids re-entrant `elapse` calls, and the body itself runs *inside* the
/// zone.
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
        reason:
            'the test body never completed — it is awaiting a future '
            'that virtual time cannot resolve (real I/O, or a timer nothing '
            'advances). Use time.advance() to drive it.',
      );
    },
    skip: skip,
    timeout: timeout,
  );
}

/// Runs [body] in a fake-async zone, driving every [FakeTime.advance] it asks
/// for. Returns whether the body ran to completion; rethrows whatever it threw.
///
/// Exposed so the deadlock guard itself can be tested.
bool runFakeAsyncBody(Future<void> Function(FakeTime time) body) {
  var completed = false;
  Object? error;
  StackTrace? stackTrace;

  fakeAsync((async) {
    final time = FakeTime._();

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
      // Run the body up to its next `advance` (or to completion).
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

int _keyCounter = 0;

/// A unique key per call, so tests never collide in a shared cache.
/// Port of upstream's `queryKey()` test helper.
QueryKey queryKey() => QueryKey(['query_${++_keyCounter}']);

/// Virtual-time sleep. Resolves when the fake clock passes [duration].
Future<void> sleep(Duration duration) => Future<void>.delayed(duration);

/// Milliseconds, short enough to keep ported timings readable — upstream writes
/// them as bare numbers.
Duration ms(int milliseconds) => Duration(milliseconds: milliseconds);

/// The upstream name of a cache event, so ported tests can assert on the same
/// event-sequence strings.
String eventName(QueryCacheEvent event) => switch (event) {
  QueryAdded() => 'added',
  QueryRemoved() => 'removed',
  QueryUpdated() => 'updated',
  QueryObserverAdded() => 'observerAdded',
  QueryObserverRemoved() => 'observerRemoved',
  QueryObserverResultsUpdated() => 'observerResultsUpdated',
  QueryObserverOptionsUpdated() => 'observerOptionsUpdated',
};

/// Runs [body] with the online manager forced to [online], restoring the
/// previous state afterwards. Port of `mockOnlineManagerIsOnline`.
T mockOnline<T>(bool online, T Function() body) {
  final previous = onlineManager.isOnline;
  onlineManager.setOnline(online);
  try {
    return body();
  } finally {
    onlineManager.setOnline(previous);
  }
}
