/// The `pagination` screen against the fake backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:showcase/features/pagination/pagination_screen.dart';

import '../harness.dart';

/// The fake logs `/api/projects` without its query string, so a page's
/// requests are counted by the `page` parameter it logs alongside.
int pageRequests(Harness h, int page) => h.backend.log
    .where((entry) =>
        entry.method == 'GET' &&
        entry.path == '/api/projects' &&
        entry.query['page'] == '$page')
    .length;

final Finder nextButton = find.widgetWithText(FilledButton, 'Next page');
final Finder previousButton =
    find.widgetWithText(OutlinedButton, 'Previous page');

bool enabled(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).enabled;

/// The cache entry for [page], or null when the cache has none.
Query<Object?>? entryOf(Harness h, int page) => h.client.queryCache
    .find(filters: QueryFilters(queryKey: projectsPageKey(page)));

/// A view tall enough for the toolbar card, both strips and the rows:
/// 800×1000 logical.
void tall(WidgetTester tester) {
  tester.view.physicalSize = Size(800, 1000) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  showcaseTest('page 0 costs one request and page 1 is prefetched unobserved',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/pagination');

    expect(find.text('page=0'), findsOneWidget);
    expect(find.text('Project 0'), findsOneWidget);
    expect(find.text('Project 9'), findsOneWidget);
    expect(find.text('Project 10'), findsNothing);
    expect(find.text('isPlaceholderData=false'), findsOneWidget);
    expect(enabled(tester, previousButton), isFalse);
    expect(enabled(tester, nextButton), isTrue);
    expect(h.fact('page-0', 'status=success'), findsOneWidget);
    expect(h.fact('page-0', 'observers=1'), findsOneWidget);
    expect(pageRequests(h, 0), 1);

    // The prefetch: page 1 is in the cache with nobody reading it.
    expect(h.fact('page-1', 'status=success'), findsOneWidget);
    expect(h.fact('page-1', 'observers=0'), findsOneWidget);
    expect(h.fact('page-1', 'fetches=1'), findsOneWidget);
    expect(pageRequests(h, 1), 1);
    expect(pageRequests(h, 2), 0);
  });

  showcaseTest(
      'Next page onto the prefetched page costs no request and prefetches '
      'the page after', (tester, h) async {
    tall(tester);
    await h.open(tester, '/pagination');
    expect(h.fact('page-1', 'status=success'), findsOneWidget);

    await tester.tap(nextButton);
    await tester.pump();

    // The first frame after the tap already has page 1's rows: the entry was
    // fresh, so the observer showed its data, not a placeholder.
    expect(find.text('page=1'), findsOneWidget);
    expect(find.text('Project 10'), findsOneWidget);
    expect(find.text('Project 19'), findsOneWidget);
    expect(find.text('Project 0'), findsNothing);
    expect(find.text('isPlaceholderData=false'), findsOneWidget);
    expect(enabled(tester, previousButton), isTrue);

    await tester.pumpAndSettle();
    expect(pageRequests(h, 1), 1);
    expect(h.fact('page-1', 'observers=1'), findsOneWidget);
    expect(h.fact('page-2', 'status=success'), findsOneWidget);
    expect(h.fact('page-2', 'observers=0'), findsOneWidget);
    expect(pageRequests(h, 2), 1);
  });

  showcaseTest(
      'a page whose prefetch has not answered keeps the previous rows as a '
      'placeholder, with Next page disabled', (tester, h) async {
    tall(tester);
    h.backend.latency = const Duration(milliseconds: 300);
    await h.open(tester, '/pagination', settle: false);
    expect(h.fact('page-0', 'fetchStatus=fetching'), findsOneWidget);

    // Page 0 answers; the frame with its rows starts the prefetch of page 1
    // after itself, and the strips catch up a frame later.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump();
    expect(find.text('Project 0'), findsOneWidget);
    expect(h.fact('page-1', 'status=pending'), findsOneWidget);
    expect(h.fact('page-1', 'fetchStatus=fetching'), findsOneWidget);

    await tester.tap(nextButton);
    await tester.pump();

    // Page 1 is still in flight — the tap joined the prefetch — so page 0's
    // rows stand in for it, and nobody can skip past it.
    expect(find.text('page=1'), findsOneWidget);
    expect(find.text('isPlaceholderData=true'), findsOneWidget);
    expect(find.text('Project 0'), findsOneWidget);
    expect(find.text('Project 9'), findsOneWidget);
    expect(find.text('Project 10'), findsNothing);
    expect(find.text('loading'), findsOneWidget);
    expect(enabled(tester, nextButton), isFalse);
    expect(enabled(tester, previousButton), isTrue);
    expect(h.fact('page-1', 'fetchStatus=fetching'), findsOneWidget);
    expect(h.fact('page-1', 'observers=1'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('isPlaceholderData=false'), findsOneWidget);
    expect(find.text('Project 10'), findsOneWidget);
    expect(find.text('Project 0'), findsNothing);
    expect(find.text('loading'), findsNothing);
    expect(enabled(tester, nextButton), isTrue);
    expect(pageRequests(h, 1), 1);

    // Let the prefetch of page 2 land, so no timer outlives the test.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(h.fact('page-2', 'status=success'), findsOneWidget);
    expect(pageRequests(h, 2), 1);
  });

  showcaseTest('Previous page returns to a cached page with no request',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/pagination');
    await tester.tap(nextButton);
    await tester.pumpAndSettle();
    expect(find.text('page=1'), findsOneWidget);

    await tester.tap(previousButton);
    await tester.pump();

    expect(find.text('page=0'), findsOneWidget);
    expect(find.text('Project 0'), findsOneWidget);
    expect(find.text('Project 10'), findsNothing);
    expect(find.text('isPlaceholderData=false'), findsOneWidget);
    expect(enabled(tester, previousButton), isFalse);
    // Page 1 is cached and fresh, so the way forward is open at once.
    expect(enabled(tester, nextButton), isTrue);

    await tester.pumpAndSettle();
    expect(pageRequests(h, 0), 1);
    expect(pageRequests(h, 1), 1);
    expect(h.fact('page-0', 'observers=1'), findsOneWidget);
    expect(h.fact('page-1', 'observers=0'), findsOneWidget);

    // And forward again, still on the cache.
    await tester.tap(nextButton);
    await tester.pumpAndSettle();
    expect(find.text('Project 10'), findsOneWidget);
    expect(pageRequests(h, 1), 1);
  });

  showcaseTest(
      'on the last page Next page is disabled and nothing beyond it is '
      'prefetched', (tester, h) async {
    tall(tester);
    await h.open(tester, '/pagination');

    // 100 projects, ten a page: page 9 is the last.
    for (var page = 0; page < 9; page++) {
      expect(find.text('page=$page'), findsOneWidget);
      expect(enabled(tester, nextButton), isTrue);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
    }

    expect(find.text('page=9'), findsOneWidget);
    expect(find.text('Project 90'), findsOneWidget);
    expect(find.text('Project 99'), findsOneWidget);
    expect(find.text('hasMore=false'), findsOneWidget);
    expect(find.text('isPlaceholderData=false'), findsOneWidget);
    expect(enabled(tester, nextButton), isFalse);
    expect(enabled(tester, previousButton), isTrue);
    expect(h.fact('page-9', 'status=success'), findsOneWidget);
    expect(h.fact('page-10', 'status=absent'), findsOneWidget);
    expect(h.fact('page-10', 'fetches=0'), findsOneWidget);
    expect(pageRequests(h, 10), 0);
    // Every page fetched exactly once: nine of them by the prefetch.
    expect(h.requests('GET', '/api/projects'), 10);
  });

  showcaseTest("the placeholder is never written to the new page's cache entry",
      (tester, h) async {
    tall(tester);
    h.backend.latency = const Duration(milliseconds: 300);
    await h.open(tester, '/pagination', settle: false);

    // Page 0 answers; its frame starts the prefetch of page 1, and the strips
    // catch up a frame later.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump();
    expect(find.text('Project 0'), findsOneWidget);
    expect(h.fact('page-1', 'fetchStatus=fetching'), findsOneWidget);

    await tester.tap(nextButton);
    await tester.pump();

    // Page 0's rows stand in for page 1 …
    expect(find.text('page=1'), findsOneWidget);
    expect(find.text('isPlaceholderData=true'), findsOneWidget);
    expect(find.text('Project 0'), findsOneWidget);
    // … and page 1's own entry holds nothing at all: a placeholder is the
    // reader's, never the cache's, `keepPrevious` included.
    expect(h.fact('page-1', 'status=pending'), findsOneWidget);
    expect(h.fact('page-1', 'updates=0'), findsOneWidget);
    expect(h.fact('page-1', 'dataUpdatedAt=–'), findsOneWidget);
    expect(entryOf(h, 1)!.state.data, isNull);
    // Nor did the placeholder touch the page it was borrowed from — page 0
    // has no strip of its own from here, so it is read off the entry.
    expect(entryOf(h, 0)!.state.dataUpdateCount, 1);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('isPlaceholderData=false'), findsOneWidget);
    expect(h.fact('page-1', 'updates=1'), findsOneWidget);
    expect(entryOf(h, 1)!.state.data, isNotNull);
    expect(pageRequests(h, 1), 1);

    // Let the prefetch of page 2 land, so no timer outlives the test.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(h.fact('page-2', 'status=success'), findsOneWidget);
  });
}
