/// The `global-callbacks` screen against the fake backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:showcase/shared/api.dart';

import '../harness.dart';

/// Three strips and a growing log under the test font's square glyphs run
/// past the default 600 px, and a lazily built list would not have the
/// bottom of the screen. A taller surface keeps every text built.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The log's lines, top to bottom — the order the callbacks ran in.
List<String> logLines(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byKey(const ValueKey<String>('callback-log')),
      matching: find.byType(Text),
    ))
    .map((text) => text.data!)
    .toList();

/// The SnackBar's own text, told apart from the same words elsewhere.
Finder snackBarText(String text) =>
    find.descendant(of: find.byType(SnackBar), matching: find.text(text));

void main() {
  showcaseTest('loading the screen logs the posts query, success then settled',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/global-callbacks');

    expect(find.text('posts=30'), findsOneWidget);
    expect(logLines(tester), <String>[
      'query success posts',
      'query settled posts',
    ]);
    expect(find.text('log=2'), findsOneWidget);
    expect(h.requests('GET', '/api/posts'), 1);

    // The strips read the screen's own client: the posts entry is there
    // with its one observer, and the two on-demand queries sit idle.
    expect(h.fact('posts', 'status=success'), findsOneWidget);
    expect(h.fact('posts', 'observers=1'), findsOneWidget);
    expect(h.fact('post-999', 'status=pending'), findsOneWidget);
    expect(h.fact('post-999', 'fetchStatus=idle'), findsOneWidget);
    expect(h.fact('meta', 'status=pending'), findsOneWidget);
    expect(h.fact('meta', 'fetchStatus=idle'), findsOneWidget);
    expect(find.text('missing=not fetched yet'), findsOneWidget);
    expect(find.text('meta seen=not fetched yet'), findsOneWidget);
  });

  showcaseTest(
      'the missing post logs an error with its meta and toasts a SnackBar',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/global-callbacks');
    h.backend.latency = const Duration(milliseconds: 200);

    await tester.tap(find.text('Fetch a missing post'));
    await tester.pump();
    expect(find.text('missing=fetching'), findsOneWidget);
    expect(h.fact('post-999', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(logLines(tester), <String>[
      'query success posts',
      'query settled posts',
      'query error post-999 (meta: toast)',
      'query settled post-999',
    ]);
    expect(find.text('missing=error: Post not found'), findsOneWidget);
    expect(snackBarText('Post not found'), findsOneWidget);
    expect(h.fact('post-999', 'status=error'), findsOneWidget);
    expect(h.fact('post-999', 'fetchStatus=idle'), findsOneWidget);
    // `retry: RetryPolicy.never`: one request, not four.
    expect(h.requests('GET', '/api/posts/999'), 1);
  });

  showcaseTest('a query without the toast meta fails without a SnackBar',
      (tester, h) async {
    tall(tester);
    // The client's default retries: one attempt and three more, one, two and
    // four seconds apart.
    h.backend.failNext('GET', '/api/posts', count: 4, status: 503);
    await h.open(tester, '/global-callbacks', settle: false);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expect(logLines(tester), <String>[
      'query error posts',
      'query settled posts',
    ]);
    expect(find.text('Scripted failure 503'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(h.requests('GET', '/api/posts'), 4);
  });

  showcaseTest('the meta tag reaches the query function', (tester, h) async {
    tall(tester);
    await h.open(tester, '/global-callbacks');

    await tester.tap(find.text('Fetch with meta tag'));
    await tester.pumpAndSettle();

    expect(find.text('meta seen=showcase'), findsOneWidget);
    expect(find.text('serial=1'), findsOneWidget);
    expect(logLines(tester), <String>[
      'query success posts',
      'query settled posts',
      'query success meta',
      'query settled meta',
    ]);
    expect(h.fact('meta', 'status=success'), findsOneWidget);
    expect(h.requests('GET', '/api/time'), 1);
  });

  showcaseTest(
      'a mutation runs the cache callbacks before its own, and logs a refusal',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/global-callbacks');
    await tester.tap(find.byTooltip('Clear log'));
    await tester.pump();
    expect(find.text('log=0'), findsOneWidget);

    await tester.tap(find.text('Create todo'));
    await tester.pumpAndSettle();

    // The core's order: the cache's `onSuccess`, then the options', then the
    // cache's `onSettled`, then the options'.
    expect(logLines(tester), <String>[
      'mutation mutate',
      'mutation success',
      'option onSuccess',
      'mutation settled',
      'option onSettled',
    ]);
    expect(find.textContaining('From the callbacks screen'), findsOneWidget);
    expect(h.requests('POST', '/api/todos'), 1);
    expect(h.backend.todos.last['text'], 'From the callbacks screen');

    await tester.tap(find.byTooltip('Clear log'));
    await tester.pump();
    await tester.tap(find.text('Create failing todo'));
    await tester.pumpAndSettle();

    expect(logLines(tester), <String>[
      'mutation mutate',
      'mutation error (Requested: 500)',
      'option onError',
      'mutation settled',
      'option onSettled',
    ]);
    expect(find.text('todo=error: Requested: 500'), findsOneWidget);
    expect(h.requests('POST', '/api/todos'), 2);
    expect(h.backend.todos.last['text'], 'From the callbacks screen');
  });

  showcaseTest(
      "leaving the screen disposes its client, and the app's never saw it",
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/global-callbacks');
    await tester.tap(find.text('Fetch a missing post'));
    await tester.pumpAndSettle();
    expect(h.fact('post-999', 'status=error'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('TanStack Query Showcase'), findsOneWidget);

    // Every entry lived on the screen's own client; the app's holds none of
    // them. That the test ends without a pending timer is the other half:
    // the screen cleared its client, `gcTime` timers included.
    expect(h.client.queryCache.queries, isEmpty);
    expect(
      h.client.queryCache.find(
        filters: QueryFilters(queryKey: ShowcaseKeys.post(999)),
      ),
      isNull,
    );
    expect(h.client.mutationCache.mutations, isEmpty);
  });
}
