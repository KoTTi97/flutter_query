/// The `focus-refetch` screen against the fake backend.
///
/// Time under `testWidgets` is fake and `clock` is bound to it, so
/// `pump(Duration(seconds: 30))` really ages the data — which is what lets the
/// `when` rule ("older than ten seconds") be proven on both sides in one test.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// One entry's own facts (`serial=3`, `isStale=false`, `reader=attached`) —
/// scoped, because the other entry and both strips show an `isStale=` too.
Finder facts(String group, String text) => find.descendant(
      of: find.byKey(ValueKey<String>('$group-facts')),
      matching: find.text(text),
    );

/// A segment of one knob, by its label: three of them have a `never`.
Finder segment(String knob, String label) => find.descendant(
      of: find.byKey(ValueKey<String>(knob)),
      matching: find.text(label),
    );

Future<void> pick(WidgetTester tester, String knob, String label) async {
  await tester.tap(segment(knob, label));
  await tester.pumpAndSettle();
}

Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}

/// The app leaving the foreground and coming back, driven straight on the
/// focus manager — the same call the screen's switch and, in an app, the
/// `AppLifecycleListener` inside `QueryClientProvider` make.
Future<void> focusCycle(WidgetTester tester, Harness h) async {
  h.client.focusManager.setFocused(false);
  await tester.pumpAndSettle();
  h.client.focusManager.setFocused(true);
  await tester.pumpAndSettle();
}

/// Detaches entry B's reader and attaches a fresh one: a mount.
Future<void> reattachB(WidgetTester tester) async {
  await tapTooltip(tester, 'Detach entry B');
  expect(facts('reader-b', 'reader=detached'), findsOneWidget);
  await tapTooltip(tester, 'Attach entry B');
  expect(facts('reader-b', 'reader=attached'), findsOneWidget);
}

/// The screen is taller than the default 800×600 test window, and a `ListView`
/// only builds what is near the viewport — entry B's strip would not exist.
void useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The screen as it opens: both entries fetched once, thirty seconds of stale
/// time, so the data is fresh.
Future<void> openFresh(WidgetTester tester, Harness h) async {
  useTallWindow(tester);
  await h.open(tester, '/focus-refetch');
  expect(facts('reader-a', 'isStale=false'), findsOneWidget);
  expect(facts('reader-b', 'isStale=false'), findsOneWidget);
  expect(h.fact('focus-a', 'fetches=1'), findsOneWidget);
  expect(h.fact('focus-b', 'fetches=1'), findsOneWidget);
}

void main() {
  showcaseTest(
      'always: the switch unfocuses and refocuses, and fresh data '
      'refetches anyway', (tester, h) async {
    await openFresh(tester, h);
    await pick(tester, 'on-focus-a', 'always');

    // Through the screen's own switch this time: it is what a browser test
    // has, and it is wired to the same `setFocused`.
    await tester.tap(find.byKey(const ValueKey<String>('app-focused')));
    await tester.pumpAndSettle();
    expect(facts('focus-state', 'focused=false'), findsOneWidget);
    expect(h.fact('focus-a', 'fetches=1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('app-focused')));
    await tester.pumpAndSettle();
    expect(facts('focus-state', 'focused=true'), findsOneWidget);

    // Fresh data and `always` still fetches: that is the whole difference to
    // `ifStale`.
    expect(facts('reader-a', 'isStale=false'), findsOneWidget);
    expect(h.fact('focus-a', 'fetches=2'), findsOneWidget);
    expect(h.fact('focus-a', 'updates=2'), findsOneWidget);
  });

  showcaseTest('never: no focus refetch, stale data included',
      (tester, h) async {
    await openFresh(tester, h);
    await pick(tester, 'on-focus-a', 'never');
    await pick(tester, 'stale-time', '0');
    expect(facts('reader-a', 'isStale=true'), findsOneWidget);

    await focusCycle(tester, h);

    expect(h.fact('focus-a', 'fetches=1'), findsOneWidget);
    expect(h.fact('focus-a', 'updates=1'), findsOneWidget);
    // Entry B held `ifStale` all along, so the same event did fetch for it —
    // which is what proves the event reached the cache at all.
    expect(h.fact('focus-b', 'fetches=2'), findsOneWidget);
  });

  showcaseTest(
      'ifStale: nothing while the data is fresh, a refetch once it is stale',
      (tester, h) async {
    await openFresh(tester, h);

    // `ifStale` is the default, so nothing is picked here.
    await focusCycle(tester, h);
    expect(h.fact('focus-a', 'fetches=1'), findsOneWidget);

    // Thirty seconds on, the observer's stale timer has flipped the result
    // without any fetch of its own.
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(facts('reader-a', 'isStale=true'), findsOneWidget);
    expect(h.fact('focus-a', 'fetches=1'), findsOneWidget);

    await focusCycle(tester, h);
    expect(h.fact('focus-a', 'fetches=2'), findsOneWidget);
    expect(facts('reader-a', 'isStale=false'), findsOneWidget);
  });

  showcaseTest(
      'when: a focus five seconds in does nothing, one eleven seconds in '
      'refetches', (tester, h) async {
    await openFresh(tester, h);
    await pick(tester, 'on-focus-a', 'when');
    // Entry B would answer the same events under `ifStale`; silenced, so the
    // requests below belong to entry A alone.
    await pick(tester, 'on-focus-b', 'never');

    await tester.pump(const Duration(seconds: 5));
    await focusCycle(tester, h);
    expect(h.fact('focus-a', 'fetches=1'), findsOneWidget);

    // Eleven seconds after the data arrived. The stale time is still thirty
    // seconds, so the data is fresh and only the `when` rule decides.
    await tester.pump(const Duration(seconds: 6));
    await focusCycle(tester, h);
    expect(facts('reader-a', 'isStale=false'), findsOneWidget);
    expect(h.fact('focus-a', 'fetches=2'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 3);
  });

  showcaseTest(
      'on mount: never never fetches, always always does, ifStale only when '
      'stale', (tester, h) async {
    await openFresh(tester, h);

    await pick(tester, 'on-mount-b', 'never');
    await reattachB(tester);
    expect(h.fact('focus-b', 'fetches=1'), findsOneWidget);

    await pick(tester, 'on-mount-b', 'always');
    await reattachB(tester);
    expect(h.fact('focus-b', 'fetches=2'), findsOneWidget);

    // Fresh data, so `ifStale` leaves it alone…
    await pick(tester, 'on-mount-b', 'ifStale');
    await reattachB(tester);
    expect(facts('reader-b', 'isStale=false'), findsOneWidget);
    expect(h.fact('focus-b', 'fetches=2'), findsOneWidget);

    // …and fetches once the stale time says the data is old.
    await pick(tester, 'stale-time', '0');
    await reattachB(tester);
    expect(h.fact('focus-b', 'fetches=3'), findsOneWidget);
    // Entry A never detached, and its own knob stayed at the default with
    // fresh data until the last step, so it fetched exactly once.
    expect(h.fact('focus-a', 'fetches=1'), findsOneWidget);
  });

  showcaseTest('one focus event, two answers: A always, B never',
      (tester, h) async {
    await openFresh(tester, h);
    await pick(tester, 'on-focus-a', 'always');
    await pick(tester, 'on-focus-b', 'never');

    await focusCycle(tester, h);

    expect(h.fact('focus-a', 'fetches=2'), findsOneWidget);
    expect(h.fact('focus-b', 'fetches=1'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 3);
  });

  showcaseTest(
      'leaving the screen releases both observers and the focus '
      'listener', (tester, h) async {
    await openFresh(tester, h);
    expect(h.fact('focus-a', 'observers=1'), findsOneWidget);
    expect(h.fact('focus-b', 'observers=1'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('TanStack Query Showcase'), findsOneWidget);
    for (final query in h.client.queryCache.queries) {
      expect(query.observersCount, 0);
    }
    // Nothing is left to answer a focus event; the screen unsubscribed.
    h.client.focusManager.setFocused(false);
    h.client.focusManager.setFocused(true);
    await tester.pumpAndSettle();
    expect(h.requests('GET', '/api/time'), 2);
  });
}
