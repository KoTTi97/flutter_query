/// The `cancellation` screen against the fake backend.
///
/// The fake honours dio's cancel token: a request whose token is cancelled
/// before the delay is out throws `requestCancelled` and is never logged. So
/// `h.requests` is the proof of whether the transport was really stopped.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:showcase/features/cancellation/cancellation_screen.dart';
import 'package:showcase/shared/models.dart';

import '../harness.dart';

/// Two cards and three strips: taller than the default test window, and the
/// lower ones would not be built in a lazy list.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A card's fact by the group it is in: `status=` is also what a debug strip
/// says about the same entry.
Finder cardFact(String label, String text) => factIn('$label facts', text);

Finder button(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );

final RegExp search = RegExp(r'^/api/search$');

void main() {
  showcaseTest(
      'cancelling the slow fetch reverts it to idle, aborts the request '
      'and never lets the answer land', (tester, h) async {
    tall(tester);
    h.backend.latency = Duration.zero;
    await h.open(tester, '/cancellation', settle: false);
    await tester.pump();

    expect(cardFact('slow', 'fetchStatus=fetching'), findsOneWidget);
    expect(cardFact('slow', 'status=pending'), findsOneWidget);
    expect(cardFact('slow', 'posts=none'), findsOneWidget);
    expect(cardFact('slow', 'cancels=0'), findsOneWidget);

    // A second into the three, with the request provably still out.
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(button('Cancel'));
    await tester.pumpAndSettle();

    expect(cardFact('slow', 'fetchStatus=idle'), findsOneWidget);
    expect(cardFact('slow', 'cancels=1'), findsOneWidget);
    // `revert` is the default, so a first fetch goes back to pending, not to
    // an error, and holds nothing.
    expect(cardFact('slow', 'status=pending'), findsOneWidget);
    expect(cardFact('slow', 'posts=none'), findsOneWidget);
    expect(h.fact('slow', 'fetchStatus=idle'), findsOneWidget);

    // Past the moment the answer would have arrived: nothing changed, and the
    // backend never answered at all.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(cardFact('slow', 'posts=none'), findsOneWidget);
    expect(cardFact('slow', 'status=pending'), findsOneWidget);
    expect(cardFact('slow', 'cancels=1'), findsOneWidget);
    expect(h.requests('GET', '/api/posts'), 0);
  });

  showcaseTest('a silent cancel reports no error to the reader',
      (tester, h) async {
    tall(tester);
    h.backend.latency = Duration.zero;
    await h.open(tester, '/cancellation', settle: false);
    await tester.pump();
    expect(cardFact('slow', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.tap(button('Cancel silently'));
    await tester.pumpAndSettle();

    expect(cardFact('slow', 'fetchStatus=idle'), findsOneWidget);
    expect(cardFact('slow', 'cancels=1'), findsOneWidget);
    // The whole point of `silent`: the status is what it was.
    expect(cardFact('slow', 'status=pending'), findsOneWidget);
    expect(h.fact('slow', 'status=pending'), findsOneWidget);
    expect(h.fact('slow', 'failures=0'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(cardFact('slow', 'posts=none'), findsOneWidget);
    expect(h.requests('GET', '/api/posts'), 0);
  });

  showcaseTest('a cancelled entry is still pending, and starts over on demand',
      (tester, h) async {
    tall(tester);
    h.backend.latency = Duration.zero;
    await h.open(tester, '/cancellation', settle: false);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(button('Cancel'));
    await tester.pumpAndSettle();
    expect(cardFact('slow', 'status=pending'), findsOneWidget);

    await tester.tap(button('Start slow fetch'));
    await tester.pump();
    expect(cardFact('slow', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(cardFact('slow', 'status=success'), findsOneWidget);
    expect(cardFact('slow', 'posts=30'), findsOneWidget);
    expect(cardFact('slow', 'cancels=1'), findsOneWidget);
    expect(h.requests('GET', '/api/posts'), 1);
  });

  showcaseTest('two keystrokes inside the debounce send one request',
      (tester, h) async {
    tall(tester);
    h.backend.latency = Duration.zero;
    await h.open(tester, '/cancellation', settle: false);
    expect(cardFact('search', 'needle=none'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'met');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'metr');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(cardFact('search', 'needle=metr'), findsOneWidget);
    expect(cardFact('search', 'searching=true'), findsOneWidget);
    // `met` never became a needle, so its key was never observed.
    expect(h.strip('previous'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(cardFact('search', 'searching=false'), findsOneWidget);
    expect(cardFact('search', 'results=1'), findsOneWidget);
    expect(cardFact('search', 'searchCancels=0'), findsOneWidget);
    expect(find.text('Metrics dashboard: setup guide'), findsOneWidget);
    expect(h.requests('GET', search), 1);
  });

  showcaseTest(
      'a needle typed while the last one is in flight cancels it, and only '
      'the new one arrives', (tester, h) async {
    tall(tester);
    h.backend.latency = Duration.zero;
    await h.open(tester, '/cancellation', settle: false);

    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(cardFact('search', 'needle=a'), findsOneWidget);
    expect(cardFact('search', 'searching=true'), findsOneWidget);

    // 200 ms into a one-second request: `a` is still out.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), 'az');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(cardFact('search', 'needle=az'), findsOneWidget);
    expect(cardFact('search', 'searchCancels=1'), findsOneWidget);
    // The abandoned needle keeps its entry, reverted to what it was before
    // the fetch: pending, idle, holding nothing.
    expect(h.fact('previous', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('previous', 'status=pending'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(cardFact('search', 'results=0'), findsOneWidget);
    // `a` matches most of the posts; none of them is on screen, and the
    // backend answered only the second needle.
    expect(find.text('Local development: setup guide'), findsNothing);
    expect(h.requests('GET', search), 1);
  });

  showcaseTest(
      'a query function that ignores the signal is cancelled all the same, '
      'but its request is not', (tester, h) async {
    tall(tester);
    h.backend.latency = Duration.zero;
    await h.open(tester, '/cancellation', settle: false);
    await tester.pump(const Duration(seconds: 1));

    // Clear the fetch that started on mount; the switch governs the next one.
    await tester.tap(button('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    await tester.tap(button('Start slow fetch'));
    await tester.pump();
    expect(cardFact('slow', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.tap(button('Cancel'));
    await tester.pumpAndSettle();

    expect(cardFact('slow', 'fetchStatus=idle'), findsOneWidget);
    // Nothing registered an `onCancel`, so the count is the first fetch's.
    expect(cardFact('slow', 'cancels=1'), findsOneWidget);
    // The backend has not answered yet, so what follows is its answer to a
    // request the query had already given up on.
    expect(h.requests('GET', '/api/posts'), 0);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    // The token never reached dio, so the backend answered in full — while
    // the query, cancelled and reverted, threw that answer away.
    expect(h.requests('GET', '/api/posts'), 1);
    expect(cardFact('slow', 'status=pending'), findsOneWidget);
    expect(cardFact('slow', 'posts=none'), findsOneWidget);
  });

  showcaseTest(
      'leaving the screen mid-fetch lets an uncancellable answer land in '
      'the cache — the guide\'s default', (tester, h) async {
    tall(tester);
    h.backend.latency = Duration.zero;
    await h.open(tester, '/cancellation', settle: false);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(button('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(button('Start slow fetch'));
    await tester.pump();

    // The last observer goes. The query function never read the signal, so
    // the core stops only the retry loop and lets the request finish.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('TanStack Query Showcase'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final entry =
        h.client.queryCache.find(filters: QueryFilters(queryKey: slowKey))!;
    expect((entry.state.data! as List<Post>).length, 30);
    expect(h.requests('GET', '/api/posts'), 1);
  });

  showcaseTest(
      'leaving the screen mid-fetch cancels one that did read the signal',
      (tester, h) async {
    tall(tester);
    h.backend.latency = Duration.zero;
    await h.open(tester, '/cancellation', settle: false);
    await tester.pump(const Duration(seconds: 1));

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final entry =
        h.client.queryCache.find(filters: QueryFilters(queryKey: slowKey))!;
    expect(entry.state.data, isNull);
    expect(entry.state.status, QueryStatus.pending);
    expect(h.requests('GET', '/api/posts'), 0);
  });
}
