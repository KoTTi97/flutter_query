/// The `dependent-queries` screen against the fake backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:showcase/shared/api.dart';

import '../harness.dart';

final RegExp anyPost = RegExp(r'^/api/posts/\d+$');
final RegExp anyComments = RegExp(r'^/api/posts/\d+/comments$');

void main() {
  showcaseTest('before a choice nothing is requested', (tester, h) async {
    await h.open(tester, '/dependent-queries');

    expect(find.text('Choose a post first.'), findsOneWidget);
    expect(h.requests('GET', anyPost), 0);
    expect(h.requests('GET', anyComments), 0);
    expect(h.client.queryCache.queries, isEmpty);
    expect(h.strip('post-1'), findsNothing);
    expect(h.strip('comments-1'), findsNothing);
  });

  showcaseTest('the post is fetched first, then the comments once',
      (tester, h) async {
    await h.open(tester, '/dependent-queries');
    h.backend.latency = const Duration(milliseconds: 200);

    await tester.tap(find.byTooltip('Choose post 2'));
    await tester.pump();

    // The post is in flight; the comments have not started — `enabled` is
    // false while the post has no data.
    expect(h.fact('post-2', 'fetchStatus=fetching'), findsOneWidget);
    expect(h.fact('comments-2', 'status=pending'), findsOneWidget);
    expect(h.fact('comments-2', 'fetchStatus=idle'), findsOneWidget);
    expect(find.text('comments enabled=false'), findsOneWidget);
    expect(find.text('waiting for the post'), findsOneWidget);
    expect(h.requests('GET', anyComments), 0);

    // The post answers. Only now does the comments query turn to fetching:
    // its request is provably not out before the post's answer is in.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('Continuous integration: setup guide'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/2'), 1);
    expect(h.requests('GET', anyComments), 0);
    expect(find.text('comments enabled=true'), findsOneWidget);
    expect(h.fact('comments-2', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(h.requests('GET', '/api/posts/2'), 1);
    expect(h.requests('GET', '/api/posts/2/comments'), 1);
    expect(h.fact('comments-2', 'status=success'), findsOneWidget);
    expect(h.fact('comments-2', 'fetches=1'), findsOneWidget);
    expect(find.text('comments count=3'), findsOneWidget);
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Ben'), findsOneWidget);
    expect(find.text('Clara'), findsOneWidget);
  });

  showcaseTest('Pause comments keeps the comments idle despite the post',
      (tester, h) async {
    await h.open(tester, '/dependent-queries');

    await tester.tap(find.text('Pause comments'));
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );

    await tester.tap(find.byTooltip('Choose post 3'));
    await tester.pumpAndSettle();
    expect(find.text('Code review: setup guide'), findsOneWidget);
    expect(h.fact('post-3', 'status=success'), findsOneWidget);
    // `Enabled.no` wins over the post having data.
    expect(h.fact('comments-3', 'status=pending'), findsOneWidget);
    expect(h.fact('comments-3', 'fetchStatus=idle'), findsOneWidget);
    expect(find.text('comments enabled=false'), findsOneWidget);
    expect(find.text('paused'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/3/comments'), 0);

    // Unticking hands the decision back to the predicate, which says yes.
    await tester.tap(find.text('Pause comments'));
    await tester.pumpAndSettle();
    expect(find.text('comments enabled=true'), findsOneWidget);
    expect(h.fact('comments-3', 'status=success'), findsOneWidget);
    expect(h.fact('comments-3', 'fetches=1'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/3/comments'), 1);
    expect(find.text('comments count=3'), findsOneWidget);

    // Pausing again disables without dropping what was fetched.
    await tester.tap(find.text('Pause comments'));
    await tester.pumpAndSettle();
    expect(find.text('comments enabled=false'), findsOneWidget);
    expect(find.text('comments count=3'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/3/comments'), 1);
  });

  showcaseTest('switching posts re-keys both queries and keeps the old entries',
      (tester, h) async {
    await h.open(tester, '/dependent-queries');

    await tester.tap(find.byTooltip('Choose post 2'));
    await tester.pumpAndSettle();
    expect(h.fact('comments-2', 'status=success'), findsOneWidget);

    await tester.tap(find.byTooltip('Choose post 3'));
    await tester.pumpAndSettle();
    expect(find.text('Code review: setup guide'), findsOneWidget);
    expect(find.text('Continuous integration: setup guide'), findsNothing);
    expect(h.strip('post-2'), findsNothing);
    expect(h.strip('comments-2'), findsNothing);
    expect(h.fact('post-3', 'status=success'), findsOneWidget);
    expect(h.fact('comments-3', 'status=success'), findsOneWidget);
    expect(h.fact('comments-3', 'observers=1'), findsOneWidget);

    expect(h.requests('GET', anyPost), 2);
    expect(h.requests('GET', anyComments), 2);
    expect(h.requests('GET', '/api/posts/3'), 1);
    expect(h.requests('GET', '/api/posts/3/comments'), 1);

    // Two posts and two comment lists: the entries the screen stopped
    // reading are still cached, with nobody observing them.
    final cache = h.client.queryCache;
    expect(
      cache.findAll(filters: QueryFilters(queryKey: ShowcaseKeys.posts)),
      hasLength(4),
    );
    for (final key in <QueryKey>[
      ShowcaseKeys.post(2),
      ShowcaseKeys.comments(2),
    ]) {
      final query = cache.find(filters: QueryFilters(queryKey: key));
      expect(query, isNotNull, reason: '${key.debugString} is cached');
      expect(query!.observersCount, 0, reason: key.debugString);
    }
  });

  showcaseTest('Clear choice releases the observers and shows the prompt',
      (tester, h) async {
    await h.open(tester, '/dependent-queries');

    await tester.tap(find.byTooltip('Choose post 2'));
    await tester.pumpAndSettle();
    expect(h.fact('post-2', 'observers=1'), findsOneWidget);
    expect(h.fact('comments-2', 'observers=1'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear choice'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a post first.'), findsOneWidget);
    expect(h.strip('post-2'), findsNothing);
    expect(h.strip('comments-2'), findsNothing);

    final cache = h.client.queryCache;
    expect(cache.queries, hasLength(2));
    for (final query in cache.queries) {
      expect(query.observersCount, 0, reason: query.queryKey.debugString);
    }
    expect(h.requests('GET', anyPost), 1);
    expect(h.requests('GET', anyComments), 1);
  });
}
