/// The `default-query-function` screen against the fake backend.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/features/default_query_function/default_query_function_screen.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

import '../harness.dart';

/// The screen is longer than the test window, and the scaffold's list builds
/// only what is in view: a taller window keeps every section and strip in
/// the tree, and the tests off the scroll offset.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(2400, 8400);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  showcaseTest(
      'three keyed queries fetch through the default, one request each',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/default-query-function');

    expect(h.requests('GET', '/api/posts'), 1);
    expect(h.requests('GET', '/api/posts/1'), 1);
    expect(h.requests('GET', '/api/posts/1/comments'), 1);
    expect(h.requests('GET', RegExp(r'^/api/')), 3);

    // Parsed by each query's `select`, from JSON the default fetched untyped.
    expect(find.text('#1 Window contact: setup guide'), findsOneWidget);
    expect(find.text('posts=30'), findsOneWidget);
    expect(find.text('Window contact: setup guide'), findsOneWidget);
    expect(find.text('comments=3'), findsOneWidget);
    expect(
      find.text('Anna on "Window contact: setup guide": Worked on the first '
          'try.'),
      findsOneWidget,
    );
    expect(
      find.text('Ben on "Window contact: setup guide": Connected on the '
          'second attempt.'),
      findsOneWidget,
    );
    expect(
      find.text('Clara on "Window contact: setup guide": Needs a gateway '
          'restart.'),
      findsOneWidget,
    );

    for (final label in <String>['posts', 'post-1', 'comments-1']) {
      expect(h.fact(label, 'status=success'), findsOneWidget);
      expect(h.fact(label, 'fetchStatus=idle'), findsOneWidget);
      expect(h.fact(label, 'fetches=1'), findsOneWidget);
    }
    expect(h.fact('post-999', 'status=absent'), findsOneWidget);
  });

  showcaseTest('the panel reports the defaults while the screen is up',
      (tester, h) async {
    await h.open(tester, '/default-query-function');

    expect(find.text('default queryFn=set'), findsOneWidget);
    expect(find.text('default mutationFn=set'), findsOneWidget);
    expect(h.client.getQueryDefaults(apiKey('/posts'))?.queryFn, isNotNull);
    expect(
      h.client.getMutationDefaults(createTodoKey)?.mutationFn,
      isNotNull,
    );
  });

  showcaseTest('a mutation with only a key runs the default mutationFn',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/default-query-function');
    h.backend.latency = const Duration(milliseconds: 200);

    await tester.tap(find.byTooltip('Create a todo'));
    await tester.pump();
    expect(find.text('creating…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(h.requests('POST', '/api/todos'), 1);
    // The seed holds three todos; the backend numbers the next one 4.
    expect(find.text('new todo id=4'), findsOneWidget);
    expect(find.text('Written by the default mutationFn'), findsOneWidget);
    expect(h.backend.todos.last['text'], 'Written by the default mutationFn');
  });

  showcaseTest('leaving the screen blanks the defaults for everyone else',
      (tester, h) async {
    await h.open(tester, '/default-query-function');
    expect(h.client.getQueryDefaults(apiKey('/posts'))?.queryFn, isNotNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('TanStack Query Showcase'), findsOneWidget);

    expect(h.client.getQueryDefaults(apiKey('/posts'))?.queryFn, isNull);
    expect(h.client.getMutationDefaults(createTodoKey)?.mutationFn, isNull);

    // The entry is still cached and stale, so a fetch is due — and with no
    // function anywhere in the chain it fails at once instead of fetching.
    await expectLater(
      h.client.query(QueryOptions<Object?>(queryKey: apiKey('/posts'))),
      throwsA(isA<MissingQueryFunctionError>()),
    );
    expect(h.requests('GET', '/api/posts'), 1);
  });

  showcaseTest('a key with no post behind it shows the backend\'s 404',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/default-query-function');
    expect(h.fact('post-999', 'status=absent'), findsOneWidget);

    await tester.tap(find.byTooltip('Fetch a missing post'));
    await tester.pumpAndSettle();

    expect(h.requests('GET', '/api/posts/999'), 1);
    expect(find.text('Post not found'), findsOneWidget);
    expect(h.fact('post-999', 'status=error'), findsOneWidget);
    expect(h.fact('post-999', 'fetchStatus=idle'), findsOneWidget);
  });
}
