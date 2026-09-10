/// The `prefetching` screen against the fake backend.
///
/// The screen is read whole — the list card, both debug strips, the
/// imperative-read card and its own strip — and the default 800×600 test view
/// cuts everything below the first strip off, so every test starts by making
/// the view taller. A finder skips what is scrolled out of sight.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:showcase/features/prefetching/prefetching_screen.dart';
import 'package:showcase/shared/api.dart';
import 'package:showcase/shared/theme.dart';

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

/// A view tall enough to reach the imperative-read card and the counter strip
/// under it: 800×1300 logical.
void taller(WidgetTester tester) {
  tester.view.physicalSize = Size(800, 1300) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

/// One fact of the imperative-read card, by its exact text.
Finder readFact(String text) => find.descendant(
      of: find.byKey(const ValueKey<String>('reads')),
      matching: find.text(text),
    );

/// Puts a value in the counter's cache entry, and moves the server's counter
/// past it: from here a read's answer says whether it came from the cache
/// (`0`) or from the backend (`1`).
Future<void> seedThenMoveTheServer(WidgetTester tester, Harness h) async {
  await tester.tap(find.text('Read (await)'));
  await tester.pumpAndSettle();
  expect(readFact('returned=0'), findsOneWidget);
  expect(readFact('cached=0'), findsOneWidget);
  expect(h.requests('GET', '/api/counter'), 1);

  await tester.tap(find.text('Increment on the server'));
  await tester.pumpAndSettle();
  expect(readFact('increments=1'), findsOneWidget);
  // The increment went nowhere near the cache: it still holds the old value.
  expect(readFact('cached=0'), findsOneWidget);
  expect(h.requests('GET', '/api/counter'), 1);
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

    expect(find.text('Continuous integration: setup guide'), findsOneWidget);
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
    expect(find.text('Code review: setup guide'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/3'), 1);
    expect(h.fact('post-3', 'status=success'), findsOneWidget);
    expect(h.fact('post-3', 'observers=1'), findsOneWidget);

    // Back on the list the row is marked too: the pill reads the cache, and
    // an open leaves the same entry behind as a prefetch.
    await tester.tap(find.byTooltip('Back to list'));
    await tester.pumpAndSettle();
    expect(find.text('Code review: setup guide'), findsNothing);
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
    expect(find.text('Release notes: setup guide'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/4'), 2);
    expect(h.fact('post-4', 'status=success'), findsOneWidget);
    expect(h.fact('post-4', 'failures=0'), findsOneWidget);
  });

  showcaseTest(
      'revalidateIfStale returns the cached value on the frame of the tap, '
      'and the refresh lands behind it', (tester, h) async {
    taller(tester);
    await h.open(tester, '/prefetching');
    await seedThenMoveTheServer(tester, h);

    // Any fetch this read starts takes this long, so a value on the very next
    // frame can only have come from the cache.
    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(find.text('Read (revalidateIfStale)'));
    await tester.pump();

    expect(readFact('read=revalidate'), findsOneWidget);
    expect(readFact('returned=0'), findsOneWidget);
    expect(readFact('cached=0'), findsOneWidget);
    expect(h.fact('counter', 'fetchStatus=fetching'), findsOneWidget);
    expect(h.fact('counter', 'updates=1'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // The refresh ran behind the answer: the cache holds the server's value,
    // and what the call returned is still the old one.
    expect(readFact('cached=1'), findsOneWidget);
    expect(readFact('returned=0'), findsOneWidget);
    expect(readFact('requests=2'), findsOneWidget);
    expect(h.fact('counter', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('counter', 'updates=2'), findsOneWidget);
    expect(h.requests('GET', '/api/counter'), 2);
  });

  showcaseTest('the plain read awaits the fetch and returns the new value',
      (tester, h) async {
    taller(tester);
    await h.open(tester, '/prefetching');
    await seedThenMoveTheServer(tester, h);

    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(find.text('Read (await)'));
    await tester.pump();

    // Nothing has come back: this call waits for its fetch.
    expect(readFact('read=await'), findsOneWidget);
    expect(readFact('returned=–'), findsOneWidget);
    expect(readFact('cached=0'), findsOneWidget);
    expect(h.fact('counter', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(readFact('returned=1'), findsOneWidget);
    expect(readFact('cached=1'), findsOneWidget);
    expect(readFact('requests=2'), findsOneWidget);
    expect(h.requests('GET', '/api/counter'), 2);
  });

  showcaseTest('a static read hands back the cached value and makes no request',
      (tester, h) async {
    taller(tester);
    await h.open(tester, '/prefetching');
    await seedThenMoveTheServer(tester, h);

    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(find.text('Read (static)'));
    await tester.pump();

    expect(readFact('read=static'), findsOneWidget);
    expect(readFact('returned=0'), findsOneWidget);
    expect(h.fact('counter', 'fetchStatus=idle'), findsOneWidget);

    // A static entry is never stale, so `revalidateIfStale` has nothing to
    // revalidate: no background fetch is started, then or later.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(readFact('returned=0'), findsOneWidget);
    expect(readFact('cached=0'), findsOneWidget);
    expect(readFact('requests=1'), findsOneWidget);
    expect(h.fact('counter', 'updates=1'), findsOneWidget);
    expect(h.requests('GET', '/api/counter'), 1);
  });
}
