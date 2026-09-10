/// The `simple` screen against the fake backend.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/shared/theme.dart';

import '../harness.dart';

void main() {
  showcaseTest('the skeleton gives way to the post after one request',
      (tester, h) async {
    h.backend.latency = const Duration(milliseconds: 200);
    await h.open(tester, '/simple', settle: false);

    expect(find.byType(SkeletonBox), findsWidgets);
    expect(h.fact('post', 'status=pending'), findsOneWidget);
    expect(h.fact('post', 'fetchStatus=fetching'), findsOneWidget);

    // `pumpAndSettle` only pumps while a frame is scheduled; the backend's
    // latency is a timer, so it is stepped explicitly.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Local development: setup guide'), findsOneWidget);
    expect(find.byType(SkeletonBox), findsNothing);
    expect(h.fact('post', 'status=success'), findsOneWidget);
    expect(h.fact('post', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('post', 'fetches=1'), findsOneWidget);
    expect(h.fact('post', 'observers=1'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/1'), 1);
  });

  showcaseTest('a refetch keeps the post on screen and says it is refreshing',
      (tester, h) async {
    await h.open(tester, '/simple');
    h.backend.latency = const Duration(milliseconds: 200);

    await tester.tap(find.byTooltip('Refetch'));
    await tester.pump();

    expect(find.text('refreshing'), findsOneWidget);
    expect(find.text('Local development: setup guide'), findsOneWidget);
    expect(h.fact('post', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('refreshing'), findsNothing);
    expect(h.fact('post', 'fetches=2'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/1'), 2);
  });

  showcaseTest(
      'a refused first fetch ends in the error state after the retries',
      (tester, h) async {
    // The client's default: three retries, one, two and four seconds apart.
    h.backend.failNext('GET', '/api/posts/1', count: 4, status: 503);
    await h.open(tester, '/simple', settle: false);

    await tester.pump(const Duration(milliseconds: 500));
    expect(h.fact('post', 'failures=1'), findsOneWidget);
    expect(find.byType(SkeletonBox), findsWidgets);

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('Scripted failure 503'), findsOneWidget);
    expect(h.fact('post', 'status=error'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/1'), 4);
  });

  showcaseTest('a refused refetch keeps the stale post next to the error',
      (tester, h) async {
    await h.open(tester, '/simple');
    h.backend.failNext('GET', '/api/posts/1', count: 4, status: 500);

    await tester.tap(find.byTooltip('Refetch'));
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expect(find.text('Local development: setup guide'), findsOneWidget);
    expect(find.text('Refetch failed: Scripted failure 500'), findsOneWidget);
    expect(h.fact('post', 'status=error'), findsOneWidget);
    expect(h.fact('post', 'fetchStatus=idle'), findsOneWidget);
  });

  showcaseTest('leaving the screen releases the observer', (tester, h) async {
    await h.open(tester, '/simple');
    expect(h.client.queryCache.queries.single.observersCount, 1);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('TanStack Query Showcase'), findsOneWidget);
    expect(h.client.queryCache.queries.single.observersCount, 0);
  });
}
