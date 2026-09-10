/// The `load-more` screen against the fake backend.
///
/// The list card is tall — a 360-pixel scroller with its facts and its
/// button — and the default 800×600 test view cuts it off, so every test
/// starts by making the view taller. A finder skips what is scrolled out of
/// sight.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/shared/theme.dart';

import '../harness.dart';

/// One of the list's own facts (`pages=2`, `hasNextPage=false`) — scoped,
/// because the strip's facts sit in the same screen.
Finder listFact(String text) => find.descendant(
      of: find.byKey(const ValueKey<String>('projects-facts')),
      matching: find.text(text),
    );

Finder loadMore() => find.widgetWithText(FilledButton, 'Load more');

bool loadMoreEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(loadMore()).onPressed != null;

Finder projectsList() => find.byKey(const ValueKey<String>('projects-list'));

/// How many project requests asked for [cursor] — the path is the same for
/// every page, only the query string tells them apart.
int requestsAt(Harness h, int cursor) => h.backend.log
    .where((entry) =>
        entry.method == 'GET' &&
        entry.path == '/api/projects' &&
        entry.query['cursor'] == '$cursor')
    .length;

/// A view tall enough for the strip, the facts, the list and the button.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> tapLoadMore(WidgetTester tester) async {
  await tester.tap(loadMore());
  await tester.pumpAndSettle();
}

void main() {
  showcaseTest('the first page arrives after one request at cursor 0',
      (tester, h) async {
    tall(tester);
    h.backend.latency = const Duration(milliseconds: 200);
    await h.open(tester, '/load-more', settle: false);
    // The strip sits above the list, so it is built before the builder
    // starts the fetch; the event reaches it after that frame.
    await tester.pump();

    expect(find.byType(SkeletonBox), findsWidgets);
    expect(listFact('pages=0'), findsOneWidget);
    expect(listFact('hasNextPage=false'), findsOneWidget);
    // The first load is not a "next page": it has no direction.
    expect(listFact('isFetchingNextPage=false'), findsOneWidget);
    expect(loadMoreEnabled(tester), isFalse);
    expect(h.fact('projects', 'status=pending'), findsOneWidget);
    expect(h.fact('projects', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonBox), findsNothing);
    expect(find.text('Project 0'), findsOneWidget);
    expect(listFact('pages=1'), findsOneWidget);
    expect(listFact('rows=10'), findsOneWidget);
    expect(listFact('hasNextPage=true'), findsOneWidget);
    expect(loadMoreEnabled(tester), isTrue);
    expect(h.fact('projects', 'status=success'), findsOneWidget);
    expect(h.fact('projects', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('projects', 'fetches=1'), findsOneWidget);
    expect(h.fact('projects', 'observers=1'), findsOneWidget);
    expect(h.requests('GET', '/api/projects'), 1);
    expect(requestsAt(h, 0), 1);
  });

  showcaseTest('Load more appends the next page and is disabled while it loads',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/load-more');
    h.backend.latency = const Duration(milliseconds: 200);

    await tester.tap(loadMore());
    await tester.pump();

    // One frame after the tap the backend has not answered: the first page
    // is still on screen, and the fetch in flight is a forward one.
    expect(listFact('pages=1'), findsOneWidget);
    expect(listFact('isFetchingNextPage=true'), findsOneWidget);
    expect(find.text('loading'), findsOneWidget);
    expect(loadMoreEnabled(tester), isFalse);
    expect(h.fact('projects', 'fetchStatus=fetching'), findsOneWidget);
    expect(h.requests('GET', '/api/projects'), 1);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(listFact('pages=2'), findsOneWidget);
    expect(listFact('rows=20'), findsOneWidget);
    expect(listFact('isFetchingNextPage=false'), findsOneWidget);
    expect(listFact('hasNextPage=true'), findsOneWidget);
    expect(loadMoreEnabled(tester), isTrue);
    expect(h.fact('projects', 'fetches=2'), findsOneWidget);
    expect(h.requests('GET', '/api/projects'), 2);
    expect(requestsAt(h, 10), 1);
  });

  showcaseTest('scrolling to the bottom loads the next page without the button',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/load-more');
    expect(listFact('pages=1'), findsOneWidget);

    // Ten rows of 48 in a 360-tall viewport: 120 pixels to the end, and the
    // listener fires once the end is within reach.
    await tester.drag(projectsList(), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(listFact('pages=2'), findsOneWidget);
    expect(listFact('rows=20'), findsOneWidget);
    expect(requestsAt(h, 10), 1);
    expect(h.requests('GET', '/api/projects'), 2);

    // The page that landed made the list longer, so the next one waits for
    // the next scroll rather than following on its own.
    await tester.pump(const Duration(seconds: 1));
    expect(h.requests('GET', '/api/projects'), 2);

    await tester.drag(projectsList(), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(listFact('pages=3'), findsOneWidget);
    expect(requestsAt(h, 20), 1);
  });

  // CI failed here twice where this machine never did: one arrival at the
  // end asked for two pages, not one. A `tester.drag` delivers a single move,
  // so it produces one scroll notification and cannot show it. A browser
  // scroll produces a stream of them — and the guard has to survive every one
  // of them, including the ones that arrive after the page has landed and
  // before its rows are laid out.
  showcaseTest('a scroll delivered in many steps still asks for one page',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/load-more');
    expect(listFact('pages=1'), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(projectsList()));
    for (var step = 0; step < 12; step++) {
      await gesture.moveBy(const Offset(0, -30));
      // A real duration, not a bare `pump`: the fake backend's response
      // hangs off a zero-duration timer, and FakeAsync runs those only when
      // the clock moves. Without it the page can never land mid-gesture,
      // which is the whole situation under test.
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // One arrival, one page. Three would mean the listener treated its own
    // notifications as fresh arrivals.
    expect(h.requests('GET', '/api/projects'), 2);
    expect(requestsAt(h, 10), 1);
    expect(requestsAt(h, 20), 0);
    expect(listFact('pages=2'), findsOneWidget);
  });

  showcaseTest(
      'after the tenth page there is no next one and nothing asks for more',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/load-more');

    for (var page = 2; page <= 10; page++) {
      await tapLoadMore(tester);
      expect(listFact('pages=$page'), findsOneWidget);
    }

    expect(listFact('rows=100'), findsOneWidget);
    expect(listFact('hasNextPage=false'), findsOneWidget);
    expect(find.text('Nothing more to load'), findsOneWidget);
    expect(loadMoreEnabled(tester), isFalse);
    expect(requestsAt(h, 90), 1);
    expect(requestsAt(h, 100), 0);
    expect(h.requests('GET', '/api/projects'), 10);

    // Neither the button nor the scroll listener has a page to ask for.
    await tester.tap(loadMore(), warnIfMissed: false);
    await tester.drag(projectsList(), const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(listFact('pages=10'), findsOneWidget);
    expect(requestsAt(h, 100), 0);
    expect(h.requests('GET', '/api/projects'), 10);
  });

  showcaseTest(
      'going to About and back shows the pages from the cache, no request',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/load-more');
    await tapLoadMore(tester);
    expect(listFact('pages=2'), findsOneWidget);
    expect(h.fact('projects', 'observers=1'), findsOneWidget);
    expect(h.requests('GET', '/api/projects'), 2);

    await tester.tap(find.text('Go to about'));
    await tester.pumpAndSettle();

    // The list is gone and with it the entry's only observer; the pages are
    // still in the cache.
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Project 0'), findsNothing);
    expect(projectsList(), findsNothing);
    expect(h.fact('projects', 'observers=0'), findsOneWidget);
    expect(h.fact('projects', 'status=success'), findsOneWidget);
    expect(h.fact('projects', 'isStale=false'), findsOneWidget);

    await tester.tap(find.text('Back to list'));
    await tester.pumpAndSettle();

    expect(find.text('Project 0'), findsOneWidget);
    expect(listFact('pages=2'), findsOneWidget);
    expect(listFact('rows=20'), findsOneWidget);
    expect(listFact('hasNextPage=true'), findsOneWidget);
    expect(h.fact('projects', 'observers=1'), findsOneWidget);
    expect(h.fact('projects', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('projects', 'fetches=2'), findsOneWidget);
    expect(h.requests('GET', '/api/projects'), 2);
  });

  showcaseTest('a refetch re-requests every held page, first to last',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/load-more');
    await tapLoadMore(tester);
    expect(listFact('pages=2'), findsOneWidget);
    h.backend.latency = const Duration(milliseconds: 100);

    await tester.tap(find.byTooltip('Refetch'));
    await tester.pump();

    // A refetch, not a page fetch: the pages stay on screen, `refreshing`
    // rather than `loading`, and `isFetchingNextPage` is false.
    expect(find.text('refreshing'), findsOneWidget);
    expect(listFact('pages=2'), findsOneWidget);
    expect(listFact('isFetchingNextPage=false'), findsOneWidget);
    expect(loadMoreEnabled(tester), isTrue);

    // One page after the other, each behind the latency.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('refreshing'), findsNothing);
    expect(listFact('pages=2'), findsOneWidget);
    expect(listFact('rows=20'), findsOneWidget);
    expect(requestsAt(h, 0), 2);
    expect(requestsAt(h, 10), 2);
    expect(h.requests('GET', '/api/projects'), 4);
    expect(h.fact('projects', 'fetches=3'), findsOneWidget);
  });

  showcaseTest('leaving the screen releases the observer', (tester, h) async {
    tall(tester);
    await h.open(tester, '/load-more');
    expect(h.client.queryCache.queries.single.observersCount, 1);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('TanStack Query Showcase'), findsOneWidget);
    expect(h.client.queryCache.queries.single.observersCount, 0);
  });
}
