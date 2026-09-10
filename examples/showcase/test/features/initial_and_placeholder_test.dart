/// The `initial-and-placeholder` screen against the fake backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/shared/api.dart';
import 'package:showcase/shared/models.dart';
import 'package:showcase/shared/theme.dart';

import '../harness.dart';

/// One text inside the `detail <card>` group.
Finder detail(String card, String text) => find.descendant(
      of: find.byKey(ValueKey<String>('detail-$card')),
      matching: find.text(text),
    );

/// Cards B and C ask the backend for a slow answer on purpose (one second
/// and 750 ms), and `pumpAndSettle` does not wait on the fake's timers; this
/// lets both land.
Future<void> settleDelayed(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// One segment of card D's mode button, by its label.
Finder mode(String label) => find.descendant(
      of: find.byKey(const ValueKey<String>('lazy-seed-mode')),
      matching: find.text(label),
    );

/// Opens the screen on a view tall enough for all three cards and their
/// strips: the scaffold's list builds only what is in view, and the default
/// 800×600 test view ends inside card A. Card D sits below them, so the tests
/// that read it ask for [height] 2600.
Future<void> open(
  WidgetTester tester,
  Harness h, {
  bool settle = true,
  double height = 1800,
}) async {
  tester.view.physicalSize = Size(800, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await h.open(tester, '/initial-and-placeholder', settle: settle);
}

/// Opens the screen with card D in view and picks [label] on its mode button.
Future<void> openAndSeed(
  WidgetTester tester,
  Harness h,
  String label,
) async {
  await open(tester, h, height: 2600);
  await settleDelayed(tester);
  await tester.tap(mode(label));
  await tester.pumpAndSettle();
}

void main() {
  showcaseTest('a detail seeded from a fresh list costs no request',
      (tester, h) async {
    await open(tester, h);
    await settleDelayed(tester);
    expect(find.text('posts=30'), findsOneWidget);

    await tester.tap(find.text('Open post 2'));
    await tester.pumpAndSettle();

    expect(detail('A', 'Continuous integration: setup guide'), findsOneWidget);
    expect(detail('A', 'initialData source=list'), findsOneWidget);
    expect(h.fact('post-2', 'status=success'), findsOneWidget);
    expect(h.fact('post-2', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('post-2', 'isStale=false'), findsOneWidget);
    expect(h.fact('post-2', 'fetches=0'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/2'), 0);
    // Seeded, not fetched: the cache holds the list's copy.
    expect(h.client.getQueryData<Post>(ShowcaseKeys.post(2))?.id, 2);
  });

  showcaseTest('a seed dated older than staleTime shows at once and refetches',
      (tester, h) async {
    await open(tester, h);
    await settleDelayed(tester);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(find.text('Open post 3'));
    await tester.pump();

    // The title is there before the backend has answered.
    expect(detail('A', 'Code review: setup guide'), findsOneWidget);
    expect(detail('A', 'initialData source=list'), findsOneWidget);
    expect(h.fact('post-3', 'status=success'), findsOneWidget);
    expect(h.fact('post-3', 'fetchStatus=fetching'), findsOneWidget);
    expect(h.fact('post-3', 'isStale=true'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(detail('A', 'Code review: setup guide'), findsOneWidget);
    expect(h.fact('post-3', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('post-3', 'fetches=1'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/3'), 1);
  });

  showcaseTest('a placeholder shows while the request runs and is never cached',
      (tester, h) async {
    await open(tester, h);

    // Post 4's request is still in flight: its one-second delay is a timer
    // `pumpAndSettle` does not wait on.
    expect(detail('B', 'Loading title…'), findsOneWidget);
    expect(detail('B', 'isPlaceholderData=true'), findsOneWidget);
    expect(detail('B', 'cache=empty'), findsOneWidget);
    expect(h.client.getQueryData<Post>(ShowcaseKeys.post(4)), isNull);
    expect(h.fact('post-4', 'status=pending'), findsOneWidget);
    expect(h.fact('post-4', 'fetchStatus=fetching'), findsOneWidget);

    await settleDelayed(tester);
    expect(detail('B', 'Release notes: setup guide'), findsOneWidget);
    expect(detail('B', 'isPlaceholderData=false'), findsOneWidget);
    expect(detail('B', 'cache=post'), findsOneWidget);
    expect(h.client.getQueryData<Post>(ShowcaseKeys.post(4))?.id, 4);
    expect(h.fact('post-4', 'status=success'), findsOneWidget);
    expect(h.fact('post-4', 'fetches=1'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/4'), 1);
  });

  showcaseTest('a refetch keeps the real post, not the placeholder',
      (tester, h) async {
    await open(tester, h);
    await settleDelayed(tester);

    await tester.tap(find.byTooltip('Refetch'));
    await tester.pump();

    // Placeholder data only stands in for *no* data; a refetch has data.
    expect(detail('B', 'Release notes: setup guide'), findsOneWidget);
    expect(detail('B', 'isPlaceholderData=false'), findsOneWidget);
    expect(h.fact('post-4', 'fetchStatus=fetching'), findsOneWidget);

    await settleDelayed(tester);
    expect(detail('B', 'Release notes: setup guide'), findsOneWidget);
    expect(h.fact('post-4', 'fetches=2'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/4'), 2);
  });

  // Without an `id`, `watchQuery` identifies its observer by key, so a
  // changed key would be a *new* observer with no previous data for
  // `PlaceholderData.compute`; card C's read carries one, so the observer
  // follows the key (found here on 2026-09-09, fixed in the binding).
  group(
    'keepPreviousData through the mixin',
    () {
      showcaseTest('switching the key keeps the previous post as a placeholder',
          (tester, h) async {
        await open(tester, h);
        await settleDelayed(tester);
        expect(detail('C', 'Staging environment: setup guide'), findsOneWidget);
        expect(detail('C', 'isPlaceholderData=false'), findsOneWidget);

        await tester.tap(find.text('Post 6'));
        await tester.pump();

        // Post 6 is pending in the cache; on screen, post 5 stands in for it.
        expect(detail('C', 'Staging environment: setup guide'), findsOneWidget);
        expect(detail('C', 'isPlaceholderData=true'), findsOneWidget);
        expect(find.byType(SkeletonBox), findsNothing);
        expect(h.fact('post-6', 'status=pending'), findsOneWidget);
        expect(h.fact('post-6', 'fetchStatus=fetching'), findsOneWidget);

        await settleDelayed(tester);
        expect(detail('C', 'Feature flags: setup guide'), findsOneWidget);
        expect(detail('C', 'Staging environment: setup guide'), findsNothing);
        expect(detail('C', 'isPlaceholderData=false'), findsOneWidget);
        expect(h.fact('post-6', 'status=success'), findsOneWidget);
        expect(h.fact('post-6', 'fetches=1'), findsOneWidget);
      });
    },
  );

  showcaseTest('a switched key fetches the new post and settles on it',
      (tester, h) async {
    await open(tester, h);
    await settleDelayed(tester);
    expect(detail('C', 'Staging environment: setup guide'), findsOneWidget);

    await tester.tap(find.text('Post 6'));
    // The frame after the tap is what starts post 6's fetch; only then is
    // there a delay to step over.
    await tester.pump();
    await settleDelayed(tester);

    expect(detail('C', 'Feature flags: setup guide'), findsOneWidget);
    expect(detail('C', 'isPlaceholderData=false'), findsOneWidget);
    expect(h.fact('post-6', 'status=success'), findsOneWidget);
    expect(h.fact('post-6', 'fetches=1'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/6'), 1);
    // Post 5's entry outlives its observer; nothing fetched it twice.
    expect(h.requests('GET', '/api/posts/5'), 1);
  });

  showcaseTest('a detail opened before the list has settled seeds nothing',
      (tester, h) async {
    h.backend.latency = const Duration(milliseconds: 300);
    await open(tester, h, settle: false);
    expect(find.text('posts=30'), findsNothing);

    await tester.tap(find.text('Open post 2'));
    await tester.pump();

    // `InitialData.compute` returned null: no seed, so a fetch.
    expect(detail('A', 'initialData source=none'), findsOneWidget);
    expect(detail('A', 'Continuous integration: setup guide'), findsNothing);
    expect(h.fact('post-2', 'status=pending'), findsOneWidget);
    expect(h.fact('post-2', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await settleDelayed(tester);
    expect(detail('A', 'Continuous integration: setup guide'), findsOneWidget);
    expect(detail('A', 'initialData source=none'), findsOneWidget);
    expect(h.fact('post-2', 'status=success'), findsOneWidget);
    expect(h.fact('post-2', 'fetches=1'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/2'), 1);
  });

  showcaseTest('re-opening a post whose entry exists consults no seed',
      (tester, h) async {
    await open(tester, h);
    await settleDelayed(tester);
    await tester.tap(find.text('Open post 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open post 3'));
    await tester.pumpAndSettle();
    expect(detail('A', 'initialData source=list'), findsOneWidget);

    await tester.tap(find.text('Open post 2'));
    await tester.pumpAndSettle();

    // The entry outlived its observer (gcTime) and already holds data, so
    // `initialData` is not consulted a second time.
    expect(detail('A', 'Continuous integration: setup guide'), findsOneWidget);
    expect(detail('A', 'initialData source=unused'), findsOneWidget);
    expect(h.fact('post-2', 'fetches=0'), findsOneWidget);
    expect(h.requests('GET', RegExp(r'^/api/posts/\d+$')), 2);
  });

  // Card D: `initialDataUpdatedAtCompute`, the lazy form of the timestamp.
  // Nothing here reads a wall clock — the assertions are the callback's own
  // count, `isStale`, and whether a request was made.
  group('a lazily computed seed timestamp', () {
    showcaseTest('runs the callback once, however often the card rebuilds',
        (tester, h) async {
      await openAndSeed(tester, h, 'fresh');
      expect(detail('D', 'computeCalls=1'), findsOneWidget);

      for (var rebuild = 0; rebuild < 3; rebuild++) {
        await tester.tap(find.byTooltip('Rebuild card D'));
        await tester.pumpAndSettle();
      }

      // Every rebuild re-applies the options; the entry holds data, so the
      // callback is never consulted again.
      expect(detail('D', 'computeCalls=1'), findsOneWidget);
      expect(detail('D', 'refetched=false'), findsOneWidget);
      expect(h.requests('GET', '/api/posts/8'), 0);
    });

    showcaseTest('null dates the seed now, so the mount fetches nothing',
        (tester, h) async {
      await openAndSeed(tester, h, 'fresh');

      expect(detail('D', 'Seed · fresh timestamp'), findsOneWidget);
      expect(detail('D', 'mode=fresh'), findsOneWidget);
      expect(detail('D', 'computeCalls=1'), findsOneWidget);
      expect(detail('D', 'refetched=false'), findsOneWidget);
      expect(h.fact('lazy-seed', 'status=success'), findsOneWidget);
      expect(h.fact('lazy-seed', 'fetchStatus=idle'), findsOneWidget);
      expect(h.fact('lazy-seed', 'isStale=false'), findsOneWidget);
      expect(h.fact('lazy-seed', 'fetches=0'), findsOneWidget);
      expect(h.requests('GET', '/api/posts/8'), 0);
    });

    showcaseTest('a backdated one is stale at once and refetches on mount',
        (tester, h) async {
      await open(tester, h, height: 2600);
      await settleDelayed(tester);

      h.backend.latency = const Duration(milliseconds: 200);
      await tester.tap(mode('backdated'));
      await tester.pump();

      // The seed is on screen, and stale, before the backend has answered.
      expect(detail('D', 'Seed · backdated timestamp'), findsOneWidget);
      expect(detail('D', 'computeCalls=1'), findsOneWidget);
      expect(detail('D', 'refetched=false'), findsOneWidget);
      expect(h.fact('lazy-seed', 'status=success'), findsOneWidget);
      expect(h.fact('lazy-seed', 'isStale=true'), findsOneWidget);
      expect(h.fact('lazy-seed', 'fetchStatus=fetching'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(detail('D', 'Metrics dashboard: setup guide'), findsOneWidget);
      expect(detail('D', 'computeCalls=1'), findsOneWidget);
      expect(detail('D', 'refetched=true'), findsOneWidget);
      expect(h.fact('lazy-seed', 'fetches=1'), findsOneWidget);
      expect(h.requests('GET', '/api/posts/9'), 1);
    });

    showcaseTest('is not consulted again for an entry that already has data',
        (tester, h) async {
      await openAndSeed(tester, h, 'fresh');
      expect(detail('D', 'computeCalls=1'), findsOneWidget);

      await tester.tap(mode('backdated'));
      await settleDelayed(tester);
      expect(detail('D', 'mode=backdated'), findsOneWidget);
      expect(detail('D', 'computeCalls=1'), findsOneWidget);

      // Post 8's entry outlived its observer and still holds its seed, so
      // this is a mount without a seeding.
      await tester.tap(mode('fresh'));
      await tester.pumpAndSettle();
      expect(detail('D', 'Seed · fresh timestamp'), findsOneWidget);
      expect(detail('D', 'computeCalls=1'), findsOneWidget);
      expect(h.fact('lazy-seed', 'fetches=0'), findsOneWidget);
      expect(h.requests('GET', '/api/posts/8'), 0);
      expect(h.requests('GET', '/api/posts/9'), 1);
    });
  });
}
