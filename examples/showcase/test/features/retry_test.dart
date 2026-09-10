/// The `retry` screen against the fake backend.
///
/// Time under `testWidgets` is fake, so a retry delay is stepped by hand:
/// `pump(Duration(milliseconds: 300))` fires the fixed delay's timer, and the
/// same step under the exponential delay fires nothing, which is the whole of
/// the delay proof. `pumpAndSettle` is never used to cross a retry delay — it
/// advances the clock in hundred-millisecond steps of its own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// One of the reader's own facts (`status=error`, `failureCount=2`) — scoped,
/// because the strip shows a `status=` of its own.
Finder reader(String text) => find.descendant(
      of: find.byKey(const ValueKey<String>('reader-facts')),
      matching: find.text(text),
    );

/// A segment of one knob, by its label: `fail-next` and `retry` both have a
/// `2`, so the knob's own key comes first.
Finder segment(String knob, String label) => find.descendant(
      of: find.byKey(ValueKey<String>(knob)),
      matching: find.text(label),
    );

/// The screen is taller than the default 800×600 test window, and a
/// `ListView` only builds what is near the viewport.
void sizeUp(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> pick(WidgetTester tester, String knob, String label) async {
  await tester.tap(segment(knob, label));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}

/// Lets the attempt that is in flight resolve, in steps far too small to
/// reach any retry delay. A zero-duration `pump` is not enough: dio's own
/// pipeline hangs the response off zero-duration timers, and `FakeAsync` only
/// runs those when the clock actually moves.
Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

/// Waits out [delay] and lets the attempt it released resolve.
Future<void> step(WidgetTester tester, Duration delay) async {
  await tester.pump(delay);
  await flush(tester);
}

void main() {
  showcaseTest('never: one refused request is the error', (tester, h) async {
    sizeUp(tester);
    h.backend.failNext('GET', '/api/time', count: 1, status: 503);
    await h.open(tester, '/retry');

    expect(reader('status=error'), findsOneWidget);
    expect(reader('fetchStatus=idle'), findsOneWidget);
    expect(reader('failureCount=1'), findsOneWidget);
    expect(reader('failureReason=Scripted failure 503'), findsOneWidget);
    expect(reader('isLoadingError=true'), findsOneWidget);
    expect(reader('isRefetchError=false'), findsOneWidget);
    expect(reader('hasStaleData=false'), findsOneWidget);
    expect(reader('serial=none'), findsOneWidget);
    expect(find.text('Scripted failure 503'), findsOneWidget);

    expect(h.fact('time', 'status=error'), findsOneWidget);
    expect(h.fact('time', 'failures=1'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 1);
  });

  showcaseTest('2 times: the count climbs 1 → 2 and the third attempt succeeds',
      (tester, h) async {
    sizeUp(tester);
    await h.open(tester, '/retry');
    expect(reader('serial=1'), findsOneWidget);

    await pick(tester, 'retry', '2 times');
    await pick(tester, 'delay', '300 ms');
    await pick(tester, 'fail-next', '2');
    await tapText(tester, 'Arm');
    expect(find.text('armed=2@503'), findsOneWidget);

    final before = h.requests('GET', '/api/time');
    await tester.tap(find.byTooltip('Refetch'));
    await flush(tester);
    expect(reader('failureCount=1'), findsOneWidget);
    expect(reader('failureReason=Scripted failure 503'), findsOneWidget);
    expect(h.requests('GET', '/api/time') - before, 1);

    await step(tester, const Duration(milliseconds: 300));
    expect(reader('failureCount=2'), findsOneWidget);
    expect(h.requests('GET', '/api/time') - before, 2);

    await step(tester, const Duration(milliseconds: 300));
    expect(reader('status=success'), findsOneWidget);
    expect(reader('failureCount=0'), findsOneWidget);
    expect(reader('failureReason=none'), findsOneWidget);
    expect(reader('serial=2'), findsOneWidget);
    expect(h.requests('GET', '/api/time') - before, 3);
  });

  showcaseTest('2 times over ten refusals: three attempts, then the error',
      (tester, h) async {
    sizeUp(tester);
    // Armed before the mount, so this is a first load with nothing to show —
    // and the mount spends one attempt under the default `never`.
    h.backend.failNext('GET', '/api/time', count: 20, status: 503);
    await h.open(tester, '/retry');
    expect(reader('status=error'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 1);

    await pick(tester, 'retry', '2 times');
    await pick(tester, 'delay', '300 ms');

    // The error state's own button, which is the result's `refetch`.
    final before = h.requests('GET', '/api/time');
    await tester.tap(find.text('Retry now'));
    await flush(tester);
    expect(reader('failureCount=1'), findsOneWidget);

    await step(tester, const Duration(milliseconds: 300));
    expect(reader('failureCount=2'), findsOneWidget);

    await step(tester, const Duration(milliseconds: 300));
    expect(reader('status=error'), findsOneWidget);
    expect(reader('failureCount=3'), findsOneWidget);
    expect(reader('isLoadingError=true'), findsOneWidget);
    expect(reader('serial=none'), findsOneWidget);
    expect(h.requests('GET', '/api/time') - before, 3);
  });

  showcaseTest('a refused refetch keeps the serial next to the error',
      (tester, h) async {
    sizeUp(tester);
    await h.open(tester, '/retry');
    expect(reader('serial=1'), findsOneWidget);

    await pick(tester, 'fail-next', '2');
    await tapText(tester, 'Arm');
    expect(find.text('armed=2@503'), findsOneWidget);

    final before = h.requests('GET', '/api/time');
    await tester.tap(find.byTooltip('Refetch'));
    await flush(tester);

    expect(reader('status=error'), findsOneWidget);
    expect(reader('hasStaleData=true'), findsOneWidget);
    expect(reader('isRefetchError=true'), findsOneWidget);
    expect(reader('isLoadingError=false'), findsOneWidget);
    expect(reader('serial=1'), findsOneWidget);
    expect(find.text('Server time #1'), findsOneWidget);
    expect(find.text('Refetch failed: Scripted failure 503'), findsOneWidget);
    // `never` is still the policy, so the one refused attempt is the error.
    expect(h.requests('GET', '/api/time') - before, 1);
  });

  showcaseTest('when 5xx: a 404 is not retried, a 503 is', (tester, h) async {
    sizeUp(tester);
    await h.open(tester, '/retry');
    await pick(tester, 'retry', 'when 5xx');
    await pick(tester, 'delay', '300 ms');
    await pick(tester, 'fail-next', '10');

    await pick(tester, 'status', '404');
    await tapText(tester, 'Arm');
    expect(find.text('armed=10@404'), findsOneWidget);

    var before = h.requests('GET', '/api/time');
    await tester.tap(find.byTooltip('Refetch'));
    await flush(tester);
    expect(reader('status=error'), findsOneWidget);
    expect(reader('failureCount=1'), findsOneWidget);
    // Nothing was scheduled: the clock may move without a second attempt.
    await step(tester, const Duration(milliseconds: 400));
    expect(h.requests('GET', '/api/time') - before, 1);

    // The same policy over a 503 retries until the count reaches three.
    await pick(tester, 'status', '503');
    await tapText(tester, 'Arm');
    expect(find.text('armed=10@503'), findsOneWidget);

    before = h.requests('GET', '/api/time');
    await tester.tap(find.byTooltip('Refetch'));
    await flush(tester);
    expect(reader('failureCount=1'), findsOneWidget);

    await step(tester, const Duration(milliseconds: 300));
    expect(reader('failureCount=2'), findsOneWidget);
    await step(tester, const Duration(milliseconds: 300));
    expect(reader('failureCount=3'), findsOneWidget);
    await step(tester, const Duration(milliseconds: 300));

    expect(reader('status=error'), findsOneWidget);
    expect(reader('failureCount=4'), findsOneWidget);
    expect(h.requests('GET', '/api/time') - before, 4);
  });

  showcaseTest('retryOnMount decides whether a fresh reader retries an error',
      (tester, h) async {
    sizeUp(tester);
    h.backend.failNext('GET', '/api/time', count: 1, status: 503);
    await h.open(tester, '/retry');
    expect(reader('status=error'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 1);

    // Off: the entry has no data and ended in an error, so a mount leaves it.
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tapTooltip(tester, 'Detach reader');
    expect(reader('reader=detached'), findsOneWidget);
    await tapTooltip(tester, 'Attach reader');

    expect(reader('status=error'), findsOneWidget);
    expect(h.fact('time', 'status=error'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 1);

    // On: the same mount fetches, and the script is spent, so it succeeds.
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tapTooltip(tester, 'Detach reader');
    await tapTooltip(tester, 'Attach reader');

    expect(reader('status=success'), findsOneWidget);
    expect(reader('serial=1'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 2);
  });

  showcaseTest('exponential has not retried at 400 ms, where fixed has',
      (tester, h) async {
    sizeUp(tester);
    await h.open(tester, '/retry');
    await pick(tester, 'retry', '2 times');
    await pick(tester, 'fail-next', '2');

    await pick(tester, 'delay', 'exponential');
    await tapText(tester, 'Arm');
    var before = h.requests('GET', '/api/time');
    await tester.tap(find.byTooltip('Refetch'));
    await flush(tester);
    expect(reader('failureCount=1'), findsOneWidget);

    // The first wait is a whole second, so 400 ms buys nothing.
    await step(tester, const Duration(milliseconds: 400));
    expect(reader('failureCount=1'), findsOneWidget);
    expect(h.requests('GET', '/api/time') - before, 1);

    // Let it finish: one second to the second attempt, two to the third.
    await step(tester, const Duration(seconds: 1));
    expect(reader('failureCount=2'), findsOneWidget);
    await step(tester, const Duration(seconds: 2));
    expect(reader('status=success'), findsOneWidget);
    expect(h.requests('GET', '/api/time') - before, 3);

    // The same 400 ms under the fixed delay has already bought the retry.
    await pick(tester, 'delay', '300 ms');
    await tapText(tester, 'Arm');
    before = h.requests('GET', '/api/time');
    await tester.tap(find.byTooltip('Refetch'));
    await step(tester, const Duration(milliseconds: 400));

    expect(reader('failureCount=2'), findsOneWidget);
    expect(h.requests('GET', '/api/time') - before, 2);

    // Nothing may still be pending when the tree comes down.
    await step(tester, const Duration(milliseconds: 300));
    expect(reader('status=success'), findsOneWidget);
  });
}
