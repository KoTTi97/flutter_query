/// The `offline` screen against the fake backend: the three network modes,
/// paused fetches, paused mutations, and what coming back online does by
/// itself.
///
/// The fake backend knows nothing about the online state — only the library
/// does — which is exactly what makes these tests sharp: a request that is
/// not sent while offline was held back by the `NetworkMode`, not refused by
/// a backend pretending to be unreachable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// The screen is taller than the default test view, and the scaffold's list
/// builds only what fits: without this the `Add todo` button cannot be
/// tapped.
void useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Opens the screen with the first fetch landed.
Future<void> open(WidgetTester tester, Harness h) async {
  useTallView(tester);
  await h.open(tester, '/offline');
}

/// Flips the connection switch, which is the only source of online state
/// here, and lets the client's reconnect work run.
Future<void> setOnline(WidgetTester tester, {required bool online}) async {
  await tester.tap(find.byType(SwitchListTile));
  await tester.pump();
  expect(find.text('online=$online'), findsOneWidget);
}

Future<void> pickMode(WidgetTester tester, String mode) async {
  await tester.tap(find.text(mode));
  await tester.pump();
}

Future<void> addTodo(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byTooltip('Add todo'));
  await tester.pump();
}

void main() {
  showcaseTest(
      'offline, a refetch under online pauses and sends nothing; going back '
      'online resumes it with one request, not two', (tester, h) async {
    await open(tester, h);
    expect(h.requests('GET', '/api/todos'), 1);

    await setOnline(tester, online: false);
    await tester.tap(find.byTooltip('Refetch'));
    await tester.pump();

    expect(find.text('query fetchStatus=paused'), findsOneWidget);
    expect(h.fact('todos', 'fetchStatus=paused'), findsOneWidget);
    // Not a refused request: nothing left the app at all.
    expect(h.requests('GET', '/api/todos'), 1);

    await setOnline(tester, online: true);
    await tester.pumpAndSettle();

    // The paused fetch continued; `refetchOnReconnect` found a fetch already
    // in flight and returned it rather than starting a second one.
    expect(h.requests('GET', '/api/todos'), 2);
    expect(find.text('query fetchStatus=idle'), findsOneWidget);
    expect(h.fact('todos', 'status=success'), findsOneWidget);
  });

  showcaseTest(
      'offline, a write under online is paused with no POST, and the client '
      'sends it on reconnect without being asked', (tester, h) async {
    await open(tester, h);
    await setOnline(tester, online: false);

    await addTodo(tester, 'Seal the loft hatch');

    expect(find.text('mutation status=pending'), findsOneWidget);
    expect(find.text('mutation isPaused=true'), findsOneWidget);
    expect(find.text('mutations pending=1'), findsOneWidget);
    expect(h.requests('POST', '/api/todos'), 0);

    // Nobody calls `resumePausedMutations` here: `QueryClient.mount` — which
    // the provider calls — subscribes to the online manager and does it.
    await setOnline(tester, online: true);
    await tester.pumpAndSettle();

    expect(h.requests('POST', '/api/todos'), 1);
    expect(find.text('mutation status=success'), findsOneWidget);
    expect(find.text('mutation isPaused=false'), findsOneWidget);
    expect(find.text('#4 Seal the loft hatch'), findsOneWidget);
    expect(h.backend.todos.last['text'], 'Seal the loft hatch');
  });

  showcaseTest(
      'Resume paused mutations while still offline leaves an online mutation '
      'exactly where it was', (tester, h) async {
    await open(tester, h);
    await setOnline(tester, online: false);
    await addTodo(tester, 'Order a spare battery');
    expect(find.text('mutations paused=1'), findsOneWidget);

    await tester.tap(find.byTooltip('Resume paused mutations'));
    await tester.pump(const Duration(seconds: 1));

    // `MutationCache.resumePaused` gates per mutation: one under
    // `NetworkMode.online` is skipped while offline, because continuing it
    // would only park it on the same wait and leave the caller's future
    // hanging until the network came back.
    expect(h.requests('POST', '/api/todos'), 0);
    expect(find.text('mutation isPaused=true'), findsOneWidget);
    expect(find.text('mutations paused=1'), findsOneWidget);

    // And the automatic path still works afterwards — the button changed
    // nothing, not even the mutation's ability to resume.
    await setOnline(tester, online: true);
    await tester.pumpAndSettle();
    expect(h.requests('POST', '/api/todos'), 1);
    expect(find.text('mutation status=success'), findsOneWidget);
  });

  showcaseTest('always: the fetch is not paused offline', (tester, h) async {
    await open(tester, h);
    await pickMode(tester, 'always');
    await setOnline(tester, online: false);

    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(find.byTooltip('Refetch'));
    await tester.pump();

    // The whole point of `always`: the request is out while offline. The
    // fake answers it, because a fake backend has no opinion on
    // connectivity; the end-to-end suite aborts it in the browser instead
    // and watches the failure arrive.
    expect(find.text('query fetchStatus=fetching'), findsOneWidget);
    expect(find.text('query fetchStatus=paused'), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(h.requests('GET', '/api/todos'), 2);
    expect(h.fact('todos', 'status=success'), findsOneWidget);
  });

  showcaseTest(
      'offlineFirst: the first attempt goes out offline and the retry after '
      'it pauses', (tester, h) async {
    await open(tester, h);
    await pickMode(tester, 'offlineFirst');
    await setOnline(tester, online: false);

    h.backend.failNext('GET', '/api/todos', count: 4, status: 503);
    await tester.tap(find.byTooltip('Refetch'));
    await tester.pump();

    // `canFetch` lets a non-`online` mode start; the attempt is really made.
    expect(find.text('query fetchStatus=fetching'), findsOneWidget);
    // The fake logs a request when it answers, which is a timer away even
    // with no latency.
    await tester.pump(Duration.zero);
    await tester.pump();
    expect(h.requests('GET', '/api/todos'), 2);
    expect(h.fact('todos', 'failures=1'), findsOneWidget);

    // The retry waits out its delay and then asks `_canContinue`, which is
    // false offline under any mode but `always`.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('query fetchStatus=paused'), findsOneWidget);
    expect(h.requests('GET', '/api/todos'), 2);
  });

  showcaseTest('two todos added offline are sent in the order they were made',
      (tester, h) async {
    await open(tester, h);
    await setOnline(tester, online: false);

    await addTodo(tester, 'First offline todo');
    await addTodo(tester, 'Second offline todo');

    // Both writes went to the same mutation call site, so the observer holds
    // the second and the cache holds both.
    expect(find.text('mutations pending=2'), findsOneWidget);
    expect(find.text('mutations paused=2'), findsOneWidget);
    expect(h.requests('POST', '/api/todos'), 0);

    await setOnline(tester, online: true);
    await tester.pumpAndSettle();

    expect(h.requests('POST', '/api/todos'), 2);
    // The log carries no body, so the order is read where the backend put
    // the rows: it appends each one as it answers.
    expect(
      h.backend.todos.map((todo) => todo['text']).toList(),
      <String>[
        'Update the deploy checklist',
        'Rename the columns on the board',
        'Replace the expired API token',
        'First offline todo',
        'Second offline todo',
      ],
    );
    expect(find.text('todos=5'), findsOneWidget);
  });
}
