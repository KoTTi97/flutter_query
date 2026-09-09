/// The `four-call-styles` screen against the fake backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// Six cards and two strips: taller than the default test window, and a
/// lazily built list would not have the lower ones.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The five reader names, in the order the screen lays them out.
const List<String> readers = <String>[
  'context',
  'builder',
  'mixin',
  'controller',
  'observer',
];

/// One reader's fact, by the group it is in and its exact text — `posts=30`
/// and `status=success` are said by five cards and by the strip, so nothing
/// here can be found by text alone.
Finder readerFact(String name, String text) => find.descendant(
      of: find.byKey(ValueKey<String>('reader-$name')),
      matching: find.text(text),
    );

Finder mutationFact(String name, String text) => find.descendant(
      of: find.byKey(ValueKey<String>('mutation-$name')),
      matching: find.text(text),
    );

Finder button(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );

/// Asserts every reader says [text].
void expectEveryReader(String text) {
  for (final name in readers) {
    expect(readerFact(name, text), findsOneWidget,
        reason: 'reader $name should say $text');
  }
}

/// How many times the card called [name] has built, read off the card.
int buildsOf(WidgetTester tester, String name) {
  final text = tester
      .widgetList<Text>(find.descendant(
        of: find.byKey(ValueKey<String>('reader-$name')),
        matching: find.byType(Text),
      ))
      .map((widget) => widget.data)
      .firstWhere((data) => data != null && data.startsWith('builds='))!;
  return int.parse(text.split('=').last);
}

Map<String, int> buildsOfAll(WidgetTester tester) => <String, int>{
      for (final name in readers) name: buildsOf(tester, name),
    };

void main() {
  showcaseTest('five readers share one request and one entry',
      (tester, h) async {
    tall(tester);
    h.backend.latency = const Duration(milliseconds: 200);
    await h.open(tester, '/four-call-styles', settle: false);

    // Every style shows the same first frame: the fetch has started and no
    // data is in yet.
    expectEveryReader('posts=…');
    expectEveryReader('status=pending');
    // A plain `ListenableBuilder` has no value to compare, so card 4 can
    // build once more than the four that do; nothing else separates them.
    for (final name in readers) {
      expect(buildsOf(tester, name), greaterThanOrEqualTo(1),
          reason: 'reader $name');
    }

    // The strip sits above the five cards, so on the very first frame it has
    // not seen them subscribe yet; one more frame and it has.
    await tester.pump();
    expect(h.fact('posts', 'fetchStatus=fetching'), findsOneWidget);
    expect(h.fact('posts', 'observers=5'), findsOneWidget);
    expect(h.fact('posts', 'fetches=1'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expectEveryReader('posts=30');
    expectEveryReader('status=success');
    expectEveryReader('fetching=false');
    // Five observers on one entry, and the core made one request for them.
    expect(h.fact('posts', 'observers=5'), findsOneWidget);
    expect(h.fact('posts', 'fetches=1'), findsOneWidget);
    expect(h.requests('GET', '/api/posts'), 1);
  });

  showcaseTest('a refetch through the controller updates all five',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/four-call-styles');
    final before = buildsOfAll(tester);

    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(button('Refetch'));
    await tester.pump();

    // The fetch is out and the data of the previous one is still on screen —
    // in all five cards, from the one refetch the controller started.
    expectEveryReader('fetching=true');
    expectEveryReader('posts=30');
    for (final name in readers) {
      expect(buildsOf(tester, name), before[name]! + 1, reason: 'reader $name');
    }
    expect(h.fact('posts', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expectEveryReader('posts=30');
    expectEveryReader('fetching=false');
    // Two builds for the refetch, the same two in every style: the fetch
    // starting, then the data landing.
    for (final name in readers) {
      expect(buildsOf(tester, name), before[name]! + 2, reason: 'reader $name');
    }
    expect(h.fact('posts', 'fetches=2'), findsOneWidget);
    expect(h.requests('GET', '/api/posts'), 2);
  });

  showcaseTest('Invalidate refetches the one entry the five share',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/four-call-styles');
    expect(h.requests('GET', '/api/posts'), 1);

    await tester.tap(button('Invalidate'));
    await tester.pumpAndSettle();

    // Five observers, still one request: invalidateQueries refetches the
    // query, not each reader.
    expect(h.requests('GET', '/api/posts'), 2);
    expect(h.fact('posts', 'fetches=2'), findsOneWidget);
    expectEveryReader('posts=30');
  });

  showcaseTest(
      'either mutation button increments the counter and the '
      'invalidation refetches it', (tester, h) async {
    tall(tester);
    await h.open(tester, '/four-call-styles');
    expect(find.text('counter=0'), findsOneWidget);
    expect(mutationFact('builder', 'status=idle'), findsOneWidget);
    expect(mutationFact('context', 'status=idle'), findsOneWidget);
    expect(h.requests('GET', '/api/counter'), 1);

    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(button('Increment (builder)'));
    await tester.pump();
    expect(mutationFact('builder', 'status=pending'), findsOneWidget);
    expect(find.text('counter=0'), findsOneWidget);

    // One latency for the POST, one for the refetch `onSuccess` started —
    // the mutation stays pending until that future completes.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(mutationFact('builder', 'status=pending'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(mutationFact('builder', 'status=success'), findsOneWidget);
    expect(mutationFact('builder', 'data=1'), findsOneWidget);
    expect(find.text('counter=1'), findsOneWidget);
    expect(h.requests('POST', '/api/counter/increment'), 1);
    expect(h.requests('GET', '/api/counter'), 2);

    // The other style runs the same options through its own controller: the
    // one that was not fired is untouched.
    await tester.tap(button('Increment (context)'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(mutationFact('context', 'status=success'), findsOneWidget);
    expect(mutationFact('context', 'data=2'), findsOneWidget);
    expect(mutationFact('builder', 'status=success'), findsOneWidget);
    expect(find.text('counter=2'), findsOneWidget);
    expect(h.requests('POST', '/api/counter/increment'), 2);
  });

  showcaseTest('leaving the screen releases all five observers',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/four-call-styles');
    final posts = h.client.queryCache.findAll().where(
          (query) => query.queryKey.debugString.contains('posts'),
        );
    expect(posts.single.observersCount, 5);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('TanStack Query Showcase'), findsOneWidget);
    // Including the hand-rolled one: its `dispose` unsubscribes *and*
    // destroys the observer, and only the destroy detaches it from the entry.
    for (final query in h.client.queryCache.findAll()) {
      expect(query.observersCount, 0,
          reason: '${query.queryKey.debugString} still has observers');
    }
  });

  showcaseTest(
      'the hand-rolled observer sees the same result as the binding\'s readers',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/four-call-styles');
    expect(readerFact('observer', 'status=success'), findsOneWidget);
    expect(readerFact('observer', 'posts=30'), findsOneWidget);

    // A refused refetch: what the four binding readers show, the bare
    // observer shows too — stale data next to an error status.
    h.backend.failNext('GET', '/api/posts', count: 4, status: 500);
    await tester.tap(button('Refetch'));
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expectEveryReader('status=error');
    expectEveryReader('posts=30');
    expect(h.fact('posts', 'status=error'), findsOneWidget);

    // And back again on a refetch that succeeds.
    await tester.tap(button('Refetch'));
    await tester.pumpAndSettle();
    expectEveryReader('status=success');
    expectEveryReader('posts=30');
  });
}
