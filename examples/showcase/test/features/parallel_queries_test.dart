/// The `parallel-queries` screen against the fake backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/shared/theme.dart';

import '../harness.dart';

/// The screen fits a browser's viewport, but the test font is a square per
/// glyph, so under it the three strips wrap past the default 600 px and a
/// lazily built list would not have them. A taller surface keeps every
/// strip built.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  showcaseTest('opening the screen starts all three requests at once',
      (tester, h) async {
    tall(tester);
    h.backend.latency = const Duration(milliseconds: 300);
    await h.open(tester, '/parallel-queries', settle: false);

    // The first frame: every entry is already fetching, nothing has answered.
    for (final label in <String>['post-1', 'post-2', 'post-3']) {
      expect(h.fact(label, 'status=pending'), findsOneWidget);
      expect(h.fact(label, 'fetchStatus=fetching'), findsOneWidget);
    }
    expect(find.text('loading'), findsNWidgets(3));
    expect(find.byType(SkeletonBox), findsWidgets);
    expect(h.requests('GET', RegExp(r'^/api/posts/\d+$')), 0);

    // The count is read on the cache's events, so it lands one frame later.
    await tester.pump();
    expect(find.text('fetching=3'), findsOneWidget);

    // One latency, not three: the requests were in flight together.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('fetching=0'), findsOneWidget);
    expect(find.text('loading'), findsNothing);
    expect(find.text('Local development: setup guide'), findsOneWidget);
    expect(find.text('Continuous integration: setup guide'), findsOneWidget);
    expect(find.text('Code review: setup guide'), findsOneWidget);
    for (final id in <int>[1, 2, 3]) {
      expect(h.fact('post-$id', 'status=success'), findsOneWidget);
      expect(h.fact('post-$id', 'fetchStatus=idle'), findsOneWidget);
      expect(h.fact('post-$id', 'fetches=1'), findsOneWidget);
      expect(h.requests('GET', '/api/posts/$id'), 1);
    }
  });

  showcaseTest('refetch all bumps every entry and the count comes back to 0',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/parallel-queries');
    h.backend.latency = const Duration(milliseconds: 200);

    await tester.tap(find.byTooltip('Refetch all'));
    await tester.pump();

    expect(find.text('fetching=3'), findsOneWidget);
    expect(find.text('refreshing'), findsNWidgets(3));
    // The data stays on screen while it refreshes.
    expect(find.text('Code review: setup guide'), findsOneWidget);
    for (final id in <int>[1, 2, 3]) {
      expect(h.fact('post-$id', 'fetchStatus=fetching'), findsOneWidget);
    }

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('fetching=0'), findsOneWidget);
    expect(find.text('refreshing'), findsNothing);
    for (final id in <int>[1, 2, 3]) {
      expect(h.fact('post-$id', 'fetches=2'), findsOneWidget);
      expect(h.requests('GET', '/api/posts/$id'), 2);
    }
  });

  showcaseTest('refetch post 2 bumps only post-2', (tester, h) async {
    tall(tester);
    await h.open(tester, '/parallel-queries');
    h.backend.latency = const Duration(milliseconds: 200);

    await tester.tap(find.byTooltip('Refetch post 2'));
    await tester.pump();

    expect(find.text('fetching=1'), findsOneWidget);
    expect(find.text('refreshing'), findsOneWidget);
    expect(h.fact('post-2', 'fetchStatus=fetching'), findsOneWidget);
    expect(h.fact('post-1', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('post-3', 'fetchStatus=idle'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('fetching=0'), findsOneWidget);
    expect(h.fact('post-1', 'fetches=1'), findsOneWidget);
    expect(h.fact('post-2', 'fetches=2'), findsOneWidget);
    expect(h.fact('post-3', 'fetches=1'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/1'), 1);
    expect(h.requests('GET', '/api/posts/2'), 2);
    expect(h.requests('GET', '/api/posts/3'), 1);
  });

  showcaseTest('with post 3 slowed down the other two settle first',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/parallel-queries');

    await tester.tap(find.text('Slow post 3'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    // Changing the query function alone does not refetch.
    expect(h.fact('post-3', 'fetches=1'), findsOneWidget);

    await tester.tap(find.byTooltip('Refetch all'));
    await tester.pump();
    expect(find.text('fetching=3'), findsOneWidget);

    // Posts 1 and 2 answer at once; post 3 asked for two seconds.
    await tester.pump(const Duration(seconds: 1));
    expect(h.fact('post-1', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('post-2', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('post-3', 'fetchStatus=fetching'), findsOneWidget);
    expect(find.text('fetching=1'), findsOneWidget);
    expect(find.text('refreshing'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/3'), 1);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('fetching=0'), findsOneWidget);
    expect(h.fact('post-3', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('post-3', 'fetches=2'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/3'), 2);
    expect(h.backend.log.last.query['delay'], '2000');
  });

  showcaseTest('leaving the screen releases every observer', (tester, h) async {
    tall(tester);
    await h.open(tester, '/parallel-queries');
    final queries = h.client.queryCache.queries;
    expect(queries, hasLength(3));
    for (final query in queries) {
      expect(query.observersCount, 1);
    }

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('TanStack Query Showcase'), findsOneWidget);
    for (final query in h.client.queryCache.queries) {
      expect(query.observersCount, 0);
    }
  });
}
