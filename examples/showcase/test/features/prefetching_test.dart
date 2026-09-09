/// The `prefetching` screen against the fake backend.
///
/// The screen is read whole — the list card and both debug strips — and the
/// default 800×600 test view cuts the second strip off, so every test starts
/// by making the view taller. A finder skips what is scrolled out of sight.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/features/prefetching/prefetching_screen.dart';
import 'package:showcase/shared/api.dart';
import 'package:showcase/shared/theme.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

import '../harness.dart';

/// The `prefetched` pill inside post [id]'s row, and nowhere else.
Finder prefetchedPill(int id) => find.descendant(
      of: find.byKey(ValueKey<String>('post-row-$id')),
      matching: find.text('prefetched'),
    );

Query<Object?>? entryOf(Harness h, int id) => h.client.queryCache
    .find(filters: QueryFilters(queryKey: ShowcaseKeys.post(id)));

/// A view tall enough for the list card and both strips: 800×900 logical.
void tall(WidgetTester tester) {
  tester.view.physicalSize = Size(800, 900) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  showcaseTest('a prefetch is one request and marks the row, unobserved',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/prefetching');
    expect(h.requests('GET', '/api/posts'), 1);
    expect(prefetchedPill(2), findsNothing);
    expect(entryOf(h, 2), isNull);

    await tester.tap(find.byTooltip('Prefetch post 2'));
    await tester.pumpAndSettle();

    expect(h.requests('GET', '/api/posts/2'), 1);
    expect(prefetchedPill(2), findsOneWidget);
    expect(prefetchedPill(3), findsNothing);
    // Nothing observes the entry: the prefetch is the cache's alone.
    expect(entryOf(h, 2)!.observersCount, 0);
    expect(h.fact('post-2', 'status=success'), findsOneWidget);
    expect(h.fact('post-2', 'observers=0'), findsOneWidget);
    expect(h.fact('post-2', 'fetches=1'), findsOneWidget);
    // The list itself was not touched by the prefetch.
    expect(h.fact('posts', 'fetches=1'), findsOneWidget);
  });

  showcaseTest('opening a prefetched post costs no request and shows at once',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/prefetching');
    await tester.tap(find.byTooltip('Prefetch post 2'));
    await tester.pumpAndSettle();
    expect(h.requests('GET', '/api/posts/2'), 1);

    // Any fetch the open might start would take this long to land, so a
    // title on the very next frame can only have come from the cache.
    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(find.byTooltip('Open post 2'));
    await tester.pump();

    expect(find.text('Motion sensor: setup guide'), findsOneWidget);
    expect(find.byType(SkeletonBox), findsNothing);
    expect(find.text('refreshing'), findsNothing);
    expect(h.fact('post-2', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('post-2', 'observers=1'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(h.requests('GET', '/api/posts/2'), 1);
    expect(h.fact('post-2', 'fetches=1'), findsOneWidget);
  });

  showcaseTest('opening a post nobody prefetched costs one request',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/prefetching');
    h.backend.latency = const Duration(milliseconds: 200);

    await tester.tap(find.byTooltip('Open post 3'));
    await tester.pump();
    expect(find.byType(SkeletonBox), findsWidgets);
    expect(h.fact('post-3', 'status=pending'), findsOneWidget);
    expect(h.fact('post-3', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Thermostat: setup guide'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/3'), 1);
    expect(h.fact('post-3', 'status=success'), findsOneWidget);
    expect(h.fact('post-3', 'observers=1'), findsOneWidget);

    // Back on the list the row is marked too: the pill reads the cache, and
    // an open leaves the same entry behind as a prefetch.
    await tester.tap(find.byTooltip('Back to list'));
    await tester.pumpAndSettle();
    expect(find.text('Thermostat: setup guide'), findsNothing);
    expect(prefetchedPill(3), findsOneWidget);
    expect(h.fact('post-3', 'observers=0'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/3'), 1);
  });

  showcaseTest(
      'a second prefetch within staleTime is a no-op; after it, a fetch',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/prefetching');

    await tester.tap(find.byTooltip('Prefetch post 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Prefetch post 2'));
    await tester.pumpAndSettle();
    expect(h.requests('GET', '/api/posts/2'), 1);
    expect(h.fact('post-2', 'fetches=1'), findsOneWidget);
    expect(h.fact('post-2', 'isStale=false'), findsOneWidget);

    // Past the ten seconds the entry is stale, and `client.query` fetches
    // again — well within gcTime, so it is the same entry, refreshed. The
    // strip does not tick, so staleness by time is read off the entry.
    await tester.pump(const Duration(seconds: 11));
    expect(entryOf(h, 2)!.isStaleByTime(postStaleTime), isTrue);
    await tester.tap(find.byTooltip('Prefetch post 2'));
    await tester.pumpAndSettle();
    expect(h.requests('GET', '/api/posts/2'), 2);
    expect(h.fact('post-2', 'fetches=2'), findsOneWidget);
    expect(h.fact('post-2', 'updates=2'), findsOneWidget);
    expect(prefetchedPill(2), findsOneWidget);
  });

  showcaseTest(
      'a refused prefetch leaves the row unmarked and the post opens normally',
      (tester, h) async {
    // One attempt only: the prefetch options say `retry: RetryPolicy.never`.
    h.backend.failNext('GET', '/api/posts/4', status: 503);
    tall(tester);
    await h.open(tester, '/prefetching');

    await tester.tap(find.byTooltip('Prefetch post 4'));
    await tester.pumpAndSettle();

    expect(h.requests('GET', '/api/posts/4'), 1);
    expect(prefetchedPill(4), findsNothing);
    expect(find.text('Scripted failure 503'), findsNothing);
    expect(h.fact('post-4', 'status=error'), findsOneWidget);
    expect(h.fact('post-4', 'failures=1'), findsOneWidget);
    expect(h.fact('post-4', 'observers=0'), findsOneWidget);
    // The screen is untouched by the failure.
    expect(find.text('Posts'), findsOneWidget);
    expect(find.byTooltip('Open post 4'), findsOneWidget);

    // Opening it now fetches like any first open would; the scripted
    // failure was spent on the prefetch.
    await tester.tap(find.byTooltip('Open post 4'));
    await tester.pumpAndSettle();
    expect(find.text('Smoke detector: setup guide'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/4'), 2);
    expect(h.fact('post-4', 'status=success'), findsOneWidget);
    expect(h.fact('post-4', 'failures=0'), findsOneWidget);
  });
}
