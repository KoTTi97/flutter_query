/// The `basic` screen against the fake backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:showcase/shared/api.dart';
import 'package:showcase/shared/models.dart';
import 'package:showcase/shared/theme.dart';

import '../harness.dart';

const String post3Title = 'Thermostat: setup guide';

Finder row(int id) => find.byKey(ValueKey<String>('post-row-$id'));

Finder cachedMarkOf(int id) =>
    find.descendant(of: row(id), matching: find.text('cached'));

void main() {
  showcaseTest('the list arrives after one request with no row marked',
      (tester, h) async {
    h.backend.latency = const Duration(milliseconds: 200);
    await h.open(tester, '/basic', settle: false);
    expect(find.byType(SkeletonBox), findsWidgets);
    // The strip sits above the list, so it is built before the list's
    // builder starts the fetch; the event reaches it after that frame.
    await tester.pump();

    expect(h.fact('posts', 'status=pending'), findsOneWidget);
    expect(h.fact('posts', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Window contact: setup guide'), findsOneWidget);
    expect(find.text(post3Title), findsOneWidget);
    expect(find.text('cached'), findsNothing);
    expect(h.fact('posts', 'status=success'), findsOneWidget);
    expect(h.fact('posts', 'fetches=1'), findsOneWidget);
    expect(h.requests('GET', '/api/posts'), 1);
    expect(h.requests('GET', RegExp(r'^/api/posts/\d+$')), 0);
  });

  showcaseTest(
      'opening a post fetches it once and marks its row on the way back',
      (tester, h) async {
    await h.open(tester, '/basic');

    await tester.tap(find.text(post3Title));
    await tester.pumpAndSettle();
    expect(find.text('Post #3'), findsOneWidget);
    expect(find.text(post3Title), findsOneWidget);
    expect(h.fact('post-3', 'status=success'), findsOneWidget);
    expect(h.fact('post-3', 'fetches=1'), findsOneWidget);
    expect(h.fact('post-3', 'observers=1'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/3'), 1);

    await tester.tap(find.byTooltip('Back to list'));
    await tester.pumpAndSettle();
    expect(find.text('Posts'), findsOneWidget);
    expect(cachedMarkOf(3), findsOneWidget);
    expect(find.text('cached'), findsOneWidget);
    expect(h.client.getQueryData<Post>(ShowcaseKeys.post(3)), isNotNull);
    expect(h.client.getQueryData<Post>(ShowcaseKeys.post(2)), isNull);
    expect(h.requests('GET', '/api/posts/3'), 1);
  });

  showcaseTest(
      'reopening a post shows it from the cache while the refetch is in flight',
      (tester, h) async {
    await h.open(tester, '/basic');
    await tester.tap(find.text(post3Title));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to list'));
    await tester.pumpAndSettle();

    h.backend.latency = const Duration(milliseconds: 300);
    await tester.tap(find.text(post3Title));
    await tester.pump();

    // One frame after the tap the backend has not answered: the title is
    // the cached one, and the refetch is what the pill reports.
    expect(find.text(post3Title), findsOneWidget);
    expect(find.byType(SkeletonBox), findsNothing);
    expect(find.text('refreshing'), findsOneWidget);
    expect(h.fact('post-3', 'fetchStatus=fetching'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/3'), 1);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('refreshing'), findsNothing);
    expect(h.fact('post-3', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('post-3', 'fetches=2'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/3'), 2);
  });

  showcaseTest('a post left alone is collected once gcTime passes',
      (tester, h) async {
    await h.open(tester, '/basic');
    await tester.tap(find.text(post3Title));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to list'));
    await tester.pumpAndSettle();
    expect(cachedMarkOf(3), findsOneWidget);

    // Nobody reads post 3 now; its ten-second gcTime is running.
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();

    expect(find.text('cached'), findsNothing);
    expect(
      h.client.queryCache
          .find(filters: QueryFilters(queryKey: ShowcaseKeys.post(3))),
      isNull,
    );
    // The list itself is untouched: the client's default gcTime is minutes.
    expect(find.text(post3Title), findsOneWidget);
    expect(h.fact('posts', 'status=success'), findsOneWidget);
  });

  showcaseTest('leaving the screen releases every observer', (tester, h) async {
    await h.open(tester, '/basic');
    await tester.tap(find.text(post3Title));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to list'));
    await tester.pumpAndSettle();
    expect(h.client.queryCache.queries, hasLength(2));
    expect(h.fact('posts', 'observers=1'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('TanStack Query Showcase'), findsOneWidget);
    for (final query in h.client.queryCache.queries) {
      expect(query.observersCount, 0, reason: '${query.queryKey}');
    }
  });
}
