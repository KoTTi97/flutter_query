/// The `invalidation-and-filters` screen against the fake backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/shared/api.dart';
import 'package:showcase/shared/chrome.dart';
import 'package:showcase/shared/models.dart';

import '../harness.dart';

const List<String> _labels = <String>[
  'posts',
  'post-1',
  'post-2',
  'post-3',
  'todos',
];

/// Twelve buttons, four readers and five strips: under the test font, whose
/// glyphs are squares, that is far past the default 600 px, and a lazily
/// built list would not have the strips. A taller surface keeps everything
/// built.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Opens the screen with every entry settled after exactly one fetch.
Future<void> openSettled(WidgetTester tester, Harness h) async {
  tall(tester);
  await h.open(tester, '/invalidation-and-filters');
  for (final label in _labels) {
    expect(h.fact(label, 'status=success'), findsOneWidget);
    expect(h.fact(label, 'fetches=1'), findsOneWidget);
  }
  expect(h.fact('post-3', 'observers=0'), findsOneWidget);
}

void main() {
  showcaseTest(
      'the posts prefix refetches the active entries and only marks post 3',
      (tester, h) async {
    await openSettled(tester, h);
    // Nobody observes post 3, and it has data: it counts as fresh.
    expect(h.fact('post-3', 'isStale=false'), findsOneWidget);
    expect(h.fact('todos', 'isStale=false'), findsOneWidget);

    await tester.tap(find.byTooltip('Invalidate posts prefix'));
    await tester.pumpAndSettle();

    expect(h.fact('posts', 'fetches=2'), findsOneWidget);
    expect(h.fact('post-1', 'fetches=2'), findsOneWidget);
    expect(h.fact('post-2', 'fetches=2'), findsOneWidget);
    // Marked, not fetched: the invalidation is what makes it stale.
    expect(h.fact('post-3', 'fetches=1'), findsOneWidget);
    expect(h.fact('post-3', 'isStale=true'), findsOneWidget);
    expect(h.fact('todos', 'fetches=1'), findsOneWidget);
    expect(h.fact('todos', 'isStale=false'), findsOneWidget);
    expect(h.requests('GET', '/api/posts'), 2);
    expect(h.requests('GET', '/api/posts/1'), 2);
    expect(h.requests('GET', '/api/posts/2'), 2);
    expect(h.requests('GET', '/api/posts/3'), 1);
    expect(h.requests('GET', '/api/todos'), 1);
  });

  showcaseTest('exact: true refetches the list alone', (tester, h) async {
    await openSettled(tester, h);

    await tester.tap(find.byTooltip('Invalidate posts exactly'));
    await tester.pumpAndSettle();

    expect(h.fact('posts', 'fetches=2'), findsOneWidget);
    for (final label in <String>['post-1', 'post-2', 'post-3', 'todos']) {
      expect(h.fact(label, 'fetches=1'), findsOneWidget);
    }
    expect(h.fact('post-3', 'isStale=false'), findsOneWidget);
    expect(h.requests('GET', RegExp(r'^/api/posts/\d+$')), 3);
  });

  showcaseTest('RefetchType.all refetches the unobserved post 3 as well',
      (tester, h) async {
    await openSettled(tester, h);

    await tester.tap(find.byTooltip('Invalidate inactive too'));
    await tester.pumpAndSettle();

    for (final label in <String>['posts', 'post-1', 'post-2', 'post-3']) {
      expect(h.fact(label, 'fetches=2'), findsOneWidget);
      expect(h.fact(label, 'status=success'), findsOneWidget);
    }
    expect(h.fact('post-3', 'observers=0'), findsOneWidget);
    expect(h.fact('post-3', 'updates=2'), findsOneWidget);
    expect(h.fact('todos', 'fetches=1'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/3'), 2);
  });

  showcaseTest(
      'stale: true refetches the posts and not the fresh todos, '
      'until they age', (tester, h) async {
    await openSettled(tester, h);

    await tester.tap(find.byTooltip('Refetch stale only'));
    await tester.pumpAndSettle();

    expect(h.fact('posts', 'fetches=2'), findsOneWidget);
    expect(h.fact('post-1', 'fetches=2'), findsOneWidget);
    expect(h.fact('post-2', 'fetches=2'), findsOneWidget);
    // Fresh for thirty seconds.
    expect(h.fact('todos', 'fetches=1'), findsOneWidget);
    // No observer, never invalidated: not stale either.
    expect(h.fact('post-3', 'fetches=1'), findsOneWidget);
    expect(h.requests('GET', '/api/todos'), 1);

    // Time is fake here: thirty-one seconds later the todos are stale and
    // the same filter picks them up.
    await tester.pump(const Duration(seconds: 31));
    await tester.tap(find.byTooltip('Refetch stale only'));
    await tester.pumpAndSettle();

    expect(h.fact('todos', 'fetches=2'), findsOneWidget);
    expect(h.fact('post-3', 'fetches=1'), findsOneWidget);
    expect(h.requests('GET', '/api/todos'), 2);
  });

  showcaseTest('resetting post 1 goes back to pending and refetches',
      (tester, h) async {
    await openSettled(tester, h);
    h.backend.latency = const Duration(milliseconds: 200);

    await tester.tap(find.byTooltip('Reset post 1'));
    await tester.pump();

    // The initial state, not the old data: a reset is not an invalidation.
    expect(h.fact('post-1', 'status=pending'), findsOneWidget);
    expect(h.fact('post-1', 'fetchStatus=fetching'), findsOneWidget);
    expect(h.fact('post-1', 'updates=0'), findsOneWidget);
    expect(find.text('Local development: setup guide'), findsNothing);
    expect(find.text('loading'), findsOneWidget);
    expect(find.byType(SkeletonBox), findsOneWidget);
    expect(h.fact('post-2', 'status=success'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(h.fact('post-1', 'status=success'), findsOneWidget);
    expect(h.fact('post-1', 'updates=1'), findsOneWidget);
    expect(h.fact('post-1', 'fetches=2'), findsOneWidget);
    expect(find.text('Local development: setup guide'), findsOneWidget);
    expect(find.text('loading'), findsNothing);
    expect(h.requests('GET', '/api/posts/1'), 2);
    expect(h.requests('GET', '/api/posts/2'), 1);
  });

  showcaseTest(
      'removing post 2 drops the entry while its reader keeps the last '
      'result, until it re-resolves the key', (tester, h) async {
    await openSettled(tester, h);

    await tester.tap(find.byTooltip('Remove post 2'));
    await tester.pumpAndSettle();

    // The entry is gone; the observer is still on it and reports what it
    // last saw. Nothing is fetched: an observer does not notice a removal.
    expect(h.fact('post-2', 'status=absent'), findsOneWidget);
    expect(h.fact('post-2', 'fetches=1'), findsOneWidget);
    expect(find.text('Continuous integration: setup guide'), findsOneWidget);
    expect(h.client.getQueryData<Post>(ShowcaseKeys.post(2)), isNull);
    expect(h.fact('post-1', 'status=success'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/2'), 1);

    // A prefix invalidation cannot find what is not in the cache.
    await tester.tap(find.byTooltip('Invalidate posts prefix'));
    await tester.pumpAndSettle();
    expect(h.fact('post-2', 'status=absent'), findsOneWidget);
    expect(h.fact('post-1', 'fetches=2'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/2'), 1);

    // Given its options again, the observer resolves the key afresh: a new
    // entry, empty, and a fetch for it.
    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(find.byTooltip('Re-attach post 2'));
    await tester.pump();
    expect(h.fact('post-2', 'status=pending'), findsOneWidget);
    expect(h.fact('post-2', 'fetchStatus=fetching'), findsOneWidget);
    expect(h.fact('post-2', 'observers=1'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(h.fact('post-2', 'status=success'), findsOneWidget);
    expect(h.fact('post-2', 'fetches=2'), findsOneWidget);
    expect(find.text('Continuous integration: setup guide'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/2'), 2);
  });

  showcaseTest(
      'cancelling the slow refetch leaves the list idle with its old data',
      (tester, h) async {
    await openSettled(tester, h);

    await tester.tap(find.byTooltip('Refetch posts slowly'));
    await tester.pump();
    expect(h.fact('posts', 'fetchStatus=fetching'), findsOneWidget);
    expect(h.fact('posts', 'fetches=2'), findsOneWidget);
    expect(find.text('refreshing'), findsOneWidget);
    expect(find.text('30 posts'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel posts'));
    await tester.pumpAndSettle();

    // Reverted: idle, the old data, no failure counted, no new fetch.
    expect(h.fact('posts', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('posts', 'status=success'), findsOneWidget);
    expect(h.fact('posts', 'fetches=2'), findsOneWidget);
    expect(h.fact('posts', 'updates=1'), findsOneWidget);
    expect(h.fact('posts', 'failures=0'), findsOneWidget);
    expect(find.text('refreshing'), findsNothing);
    expect(find.text('30 posts'), findsOneWidget);
    // The fake only logs what it answers, and it never answered this one.
    expect(h.requests('GET', '/api/posts'), 1);
    expect(h.backend.log.last.path, isNot('/api/posts'));

    // The two seconds the request asked for pass; the answer that would
    // have come is nobody's now.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(h.fact('posts', 'updates=1'), findsOneWidget);
    expect(h.fact('posts', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('posts', 'fetches=2'), findsOneWidget);
    expect(h.fact('posts', 'status=success'), findsOneWidget);
    expect(h.fact('posts', 'failures=0'), findsOneWidget);
    expect(h.requests('GET', '/api/posts'), 1);
  });

  showcaseTest('the errored predicate refetches post 2 alone',
      (tester, h) async {
    await openSettled(tester, h);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );

    // No retries on post 2: one refused answer is the error state.
    await tester.tap(find.byTooltip('Refetch post 2'));
    await tester.pumpAndSettle();
    expect(h.fact('post-2', 'status=error'), findsOneWidget);
    expect(h.fact('post-2', 'fetches=2'), findsOneWidget);
    expect(h.fact('post-2', 'failures=1'), findsOneWidget);
    expect(find.text('Scripted failure 500'), findsOneWidget);
    // The stale data stays next to the error.
    expect(find.text('Continuous integration: setup guide'), findsOneWidget);
    // The tick was spent by that fetch.
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    expect(h.requests('GET', '/api/posts/2'), 2);
    expect(h.backend.log.last.status, 500);

    await tester.tap(find.byTooltip('Predicate: errored'));
    await tester.pumpAndSettle();

    expect(h.fact('post-2', 'status=success'), findsOneWidget);
    expect(h.fact('post-2', 'fetches=3'), findsOneWidget);
    expect(h.fact('post-2', 'failures=0'), findsOneWidget);
    expect(find.text('Scripted failure 500'), findsNothing);
    for (final label in <String>['posts', 'post-1', 'post-3', 'todos']) {
      expect(h.fact(label, 'fetches=1'), findsOneWidget);
    }
    expect(h.requests('GET', '/api/posts/2'), 3);
    expect(h.requests('GET', '/api/posts/1'), 1);
  });

  showcaseTest('uppercasing the titles is a cache write, not a fetch',
      (tester, h) async {
    await openSettled(tester, h);
    final requestsBefore = h.backend.log.length;

    await tester.tap(find.byTooltip('Uppercase all post titles'));
    await tester.pumpAndSettle();

    expect(find.text('matched=2'), findsOneWidget);
    expect(find.text('LOCAL DEVELOPMENT: SETUP GUIDE'), findsOneWidget);
    expect(find.text('CONTINUOUS INTEGRATION: SETUP GUIDE'), findsOneWidget);
    // A manual write counts as an update, never as a fetch.
    expect(h.fact('post-1', 'updates=2'), findsOneWidget);
    expect(h.fact('post-2', 'updates=2'), findsOneWidget);
    expect(h.fact('post-1', 'fetches=1'), findsOneWidget);
    expect(h.fact('post-2', 'fetches=1'), findsOneWidget);
    expect(h.backend.log.length, requestsBefore);
    // Left out by `type: active`, the unobserved post 3 is untouched — and
    // so is the list, whose key has one part and holds another type.
    expect(h.fact('post-3', 'updates=1'), findsOneWidget);
    expect(
      h.client.getQueryData<Post>(ShowcaseKeys.post(3))?.title,
      'Code review: setup guide',
    );
    expect(
      h.client.getQueryData<List<Post>>(ShowcaseKeys.posts)?.first.title,
      'Local development: setup guide',
    );
  });

  showcaseTest('leaving the screen releases every reader', (tester, h) async {
    await openSettled(tester, h);
    expect(
      h.client.queryCache.queries.where((q) => q.observersCount == 1),
      hasLength(4),
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('TanStack Query Showcase'), findsOneWidget);
    for (final query in h.client.queryCache.queries) {
      expect(query.observersCount, 0);
    }
  });
}
