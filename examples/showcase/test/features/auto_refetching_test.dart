/// The `auto-refetching` screen against the fake backend.
///
/// Every case steps time with `tester.pump(duration)`: `pumpAndSettle` never
/// returns while a `refetchInterval` is armed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// Two cards, the strip and a bounded list are taller than the default
/// 800×600 test window, and a `ListView` only builds what is near the
/// viewport.
Future<void> openScreen(WidgetTester tester, Harness h) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await h.open(tester, '/auto-refetching');
}

/// Picks an interval. Never followed by `pumpAndSettle`: the tap may arm the
/// poll.
Future<void> pickInterval(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
    of: find.byKey(const ValueKey<String>('interval')),
    matching: find.text(label),
  ));
  await tester.pump();
}

/// One 500 ms poll window, then the frames the answer lands in.
Future<void> pollOnce(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

/// Runs a write and lets its invalidation's refetch land. The mutation's
/// `onSuccess` returns that future, so the button is disabled until it has.
Future<void> write(WidgetTester tester, String label) async {
  // The label is the button's own text; `widgetWithText` wants the exact
  // button class, and these are two different ones.
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pump();
}

int ticks(Harness h) => h.requests('GET', '/api/ticks');

void main() {
  showcaseTest('with the interval off the list is fetched once and stays',
      (tester, h) async {
    await openScreen(tester, h);

    expect(find.text('interval=off'), findsOneWidget);
    expect(find.text('ticks=0'), findsOneWidget);
    expect(h.fact('ticks', 'fetches=1'), findsOneWidget);
    expect(ticks(h), 1);

    await tester.pump(const Duration(seconds: 3));

    expect(h.fact('ticks', 'fetches=1'), findsOneWidget);
    expect(ticks(h), 1);
  });

  showcaseTest('500 ms polls, and going back to off freezes it',
      (tester, h) async {
    await openScreen(tester, h);
    expect(ticks(h), 1);

    await pickInterval(tester, '500 ms');
    expect(find.text('interval=500 ms'), findsOneWidget);

    // One request per window, on top of the one the mount already made.
    await pollOnce(tester);
    expect(ticks(h), 2);
    await pollOnce(tester);
    expect(ticks(h), 3);
    await pollOnce(tester);
    expect(ticks(h), 4);
    expect(h.fact('ticks', 'fetches=4'), findsOneWidget);

    await pickInterval(tester, 'off');
    final frozen = ticks(h);

    await tester.pump(const Duration(seconds: 3));

    expect(ticks(h), frozen);
    expect(h.fact('ticks', 'fetches=$frozen'), findsOneWidget);
  });

  showcaseTest('a tick added while polling shows up, and clearing empties it',
      (tester, h) async {
    await openScreen(tester, h);
    await pickInterval(tester, '500 ms');

    await write(tester, 'Add tick');
    expect(find.text('tick 1'), findsOneWidget);
    expect(find.text('ticks=1'), findsOneWidget);

    await write(tester, 'Add tick');
    expect(find.text('tick 2'), findsOneWidget);
    expect(find.text('ticks=2'), findsOneWidget);

    // The poll keeps the same list on screen.
    await pollOnce(tester);
    expect(find.text('tick 2'), findsOneWidget);
    expect(find.text('ticks=2'), findsOneWidget);

    await write(tester, 'Clear ticks');
    expect(find.text('ticks=0'), findsOneWidget);
    expect(find.text('tick 1'), findsNothing);
    expect(find.text('No ticks yet.'), findsOneWidget);
  });

  showcaseTest(
      'unfocused, the interval only fetches with the background flag on',
      (tester, h) async {
    await openScreen(tester, h);
    await pickInterval(tester, '500 ms');

    await tester.tap(find.text('Unfocus'));
    await tester.pump();
    expect(find.text('focused=false'), findsOneWidget);
    expect(find.text('background=false'), findsOneWidget);

    // The periodic timer fires four times over these two seconds; every one
    // of them finds the app unfocused and the flag off, and fetches nothing.
    final asleep = ticks(h);
    for (var i = 0; i < 4; i++) {
      await pollOnce(tester);
    }
    expect(ticks(h), asleep);

    await tester.tap(find.byKey(const ValueKey<String>('in-background')));
    await tester.pump();
    expect(find.text('background=true'), findsOneWidget);
    expect(find.text('focused=false'), findsOneWidget);

    await pollOnce(tester);
    expect(ticks(h), asleep + 1);
    await pollOnce(tester);
    expect(ticks(h), asleep + 2);
  });

  showcaseTest('the dynamic interval stops itself at the third tick',
      (tester, h) async {
    await openScreen(tester, h);
    await pickInterval(tester, 'dynamic');
    expect(find.text('interval=dynamic'), findsOneWidget);

    // Fewer than three ticks: it polls.
    final short = ticks(h);
    await pollOnce(tester);
    await pollOnce(tester);
    expect(ticks(h), short + 2);

    await write(tester, 'Add tick');
    await write(tester, 'Add tick');
    await write(tester, 'Add tick');
    expect(find.text('ticks=3'), findsOneWidget);
    expect(find.text('tick 3'), findsOneWidget);

    // The rule returned null when the third tick landed, so the timer is gone.
    final stopped = ticks(h);
    await tester.pump(const Duration(seconds: 3));
    expect(ticks(h), stopped);

    // Clearing puts the list back under three, and the poll starts again.
    await write(tester, 'Clear ticks');
    final restarted = ticks(h);
    await pollOnce(tester);
    await pollOnce(tester);
    expect(ticks(h), restarted + 2);
  });

  showcaseTest('leaving the screen stops the poll with the observer',
      (tester, h) async {
    await openScreen(tester, h);
    await pickInterval(tester, '500 ms');
    await pollOnce(tester);

    await tester.pageBack();
    // Safe to settle: the builder's controller was disposed with the screen,
    // which destroys the observer and its interval timer.
    await tester.pumpAndSettle();

    expect(h.client.queryCache.queries.single.observersCount, 0);
    final gone = ticks(h);
    await tester.pump(const Duration(seconds: 3));
    expect(ticks(h), gone);
  });
}
