/// The `four-call-styles` screen against the fake backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// Eight cards and three strips: taller than the default test window, and a
/// lazily built list would not have the lower ones.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 4800);
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
Finder readerFact(String name, String text) => factIn('reader $name', text);

/// One fact of the listener card, by its exact text. `child-builds=1` is in
/// the same group, said by the child the listener hands back.
Finder listenerFact(String text) => factIn('listener', text);

Finder mutationFact(String name, String text) => factIn('mutation $name', text);

/// One fact of card 8's reader called [name]: `pages=1` is said by all three
/// and `status=success` by the strip too.
Finder infiniteFact(String name, String text) => factIn('infinite $name', text);

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
        of: groupNamed('reader $name'),
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

  showcaseTest(
      'the listener says nothing on mount, and the first fetch landing '
      'is its one call', (tester, h) async {
    tall(tester);
    h.backend.latency = const Duration(milliseconds: 200);
    await h.open(tester, '/four-call-styles', settle: false);

    // Mounted with the fetch already in flight, and told nothing about it:
    // the current result is a snapshot, not a transition.
    expect(listenerFact('listener-calls=0'), findsOneWidget);
    expect(listenerFact('listener-skips=0'), findsOneWidget);
    expect(listenerFact('last=none'), findsOneWidget);
    expect(listenerFact('child-builds=1'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // The baseline every test below counts from: the data arriving is the
    // first transition after mount, and it changed the posts.
    expect(listenerFact('listener-calls=1'), findsOneWidget);
    expect(listenerFact('listener-skips=0'), findsOneWidget);
    expect(
      listenerFact('last=pending/fetching:none->success/idle:30'),
      findsOneWidget,
    );
    expect(
      listenerFact('#1 pending/fetching:none->success/idle:30'),
      findsOneWidget,
    );
    // It borrowed a controller that already existed: no sixth observer.
    expect(h.fact('posts', 'observers=5'), findsOneWidget);
    expect(listenerFact('child-builds=1'), findsOneWidget);
  });

  showcaseTest('a refetch that returns the same posts is refused by listenWhen',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/four-call-styles');
    expect(listenerFact('listener-calls=1'), findsOneWidget);
    final before = buildsOfAll(tester);

    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(button('Refetch'));
    await tester.pump();

    // The fetch starting is a transition — every reader rebuilt for it — and
    // listenWhen refused it, because the posts are the same 30.
    expect(buildsOf(tester, 'context'), before['context']! + 1);
    expect(listenerFact('listener-calls=1'), findsOneWidget);
    expect(listenerFact('listener-skips=1'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // And the landing is refused too: dataUpdatedAt moved, the data did not.
    expect(listenerFact('listener-calls=1'), findsOneWidget);
    expect(listenerFact('listener-skips=2'), findsOneWidget);
    expect(
      listenerFact('last=pending/fetching:none->success/idle:30'),
      findsOneWidget,
    );
    // Two refusals and two rebuilds of the card around it, and the child it
    // was handed did not build again.
    expect(listenerFact('child-builds=1'), findsOneWidget);
    for (final name in readers) {
      expect(buildsOf(tester, name), before[name]! + 2, reason: 'reader $name');
    }
  });

  showcaseTest('a change of the data raises exactly one call',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/four-call-styles');
    expect(listenerFact('listener-calls=1'), findsOneWidget);

    await tester.tap(button('Drop a post'));
    await tester.pumpAndSettle();

    expectEveryReader('posts=29');
    expect(listenerFact('listener-calls=2'), findsOneWidget);
    expect(listenerFact('listener-skips=0'), findsOneWidget);
    expect(
      listenerFact('last=success/idle:30->success/idle:29'),
      findsOneWidget,
    );
    expect(
      listenerFact('#2 success/idle:30->success/idle:29'),
      findsOneWidget,
    );
    // Nothing was fetched for it: a cache write is a change of data too.
    expect(h.requests('GET', '/api/posts'), 1);

    // The refetch that puts the post back is one call again, and the line it
    // logs starts at the fetching state the refusal before it saw — the
    // refused transition advanced the comparison, it did not discard it.
    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(button('Refetch'));
    await tester.pump();
    expect(listenerFact('listener-calls=2'), findsOneWidget);
    expect(listenerFact('listener-skips=1'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(listenerFact('listener-calls=3'), findsOneWidget);
    expect(listenerFact('listener-skips=1'), findsOneWidget);
    expect(
      listenerFact('#3 success/fetching:29->success/idle:30'),
      findsOneWidget,
    );
    expectEveryReader('posts=30');
  });

  showcaseTest('the child never rebuilds from a controller event',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/four-call-styles');
    expect(listenerFact('child-builds=1'), findsOneWidget);
    final before = buildsOfAll(tester);

    // Everything on the screen that moves the query: a refetch through the
    // controller, an invalidation through the client, and a cache write.
    await tester.tap(button('Refetch'));
    await tester.pumpAndSettle();
    await tester.tap(button('Invalidate'));
    await tester.pumpAndSettle();
    await tester.tap(button('Drop a post'));
    await tester.pumpAndSettle();

    // The events provably flowed — the readers rebuilt for every one of them
    // and the listener both refused and accepted transitions.
    for (final name in readers) {
      expect(buildsOf(tester, name), greaterThan(before[name]!),
          reason: 'reader $name');
    }
    expect(listenerFact('listener-calls=2'), findsOneWidget);
    expect(listenerFact('listener-skips=4'), findsOneWidget);
    // And the child of the listener stayed where it was.
    expect(listenerFact('child-builds=1'), findsOneWidget);
  });

  showcaseTest(
      'two plain writes are two transitions to the listener, two batched '
      'ones are one', (tester, h) async {
    tall(tester);
    await h.open(tester, '/four-call-styles');
    expect(listenerFact('listener-calls=1'), findsOneWidget);

    await tester.tap(button('Drop two posts'));
    await tester.pumpAndSettle();

    // Each write was delivered as it happened: 30 -> 29, then 29 -> 28.
    expectEveryReader('posts=28');
    expect(listenerFact('listener-calls=3'), findsOneWidget);
    expect(
      listenerFact('#3 success/idle:29->success/idle:28'),
      findsOneWidget,
    );

    await tester.tap(button('Drop two posts, batched'));
    await tester.pumpAndSettle();

    // The batch held both notifications, and each carries the latest value:
    // one transition, straight from 28 to 26.
    expectEveryReader('posts=26');
    expect(listenerFact('listener-calls=4'), findsOneWidget);
    expect(
      listenerFact('#4 success/idle:28->success/idle:26'),
      findsOneWidget,
    );
    expect(h.requests('GET', '/api/posts'), 1);
  });

  showcaseTest(
      'the mutation listener hears one call per state change and nothing on '
      'mount', (tester, h) async {
    tall(tester);
    await h.open(tester, '/four-call-styles');
    expect(mutationFact('controller', 'status=idle'), findsOneWidget);
    expect(mutationFact('controller', 'mutation-listener-calls=0'),
        findsOneWidget);
    expect(mutationFact('controller', 'mutation-last=none'), findsOneWidget);

    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(button('Increment (controller)'));
    await tester.pump();
    // The first transition, delivered off the build phase a microtask later.
    await tester.pump();
    expect(mutationFact('controller', 'status=pending'), findsOneWidget);
    expect(mutationFact('controller', 'mutation-listener-calls=1'),
        findsOneWidget);
    expect(mutationFact('controller', 'mutation-last=idle->pending'),
        findsOneWidget);

    // One latency for the POST, one for the refetch `onSuccess` awaits.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(mutationFact('controller', 'status=success'), findsOneWidget);
    expect(mutationFact('controller', 'data=1'), findsOneWidget);
    expect(mutationFact('controller', 'mutation-listener-calls=2'),
        findsOneWidget);
    expect(mutationFact('controller', 'mutation-last=pending->success'),
        findsOneWidget);
    expect(find.text('counter=1'), findsOneWidget);
    // The other two panels ran nothing.
    expect(mutationFact('builder', 'status=idle'), findsOneWidget);
    expect(mutationFact('context', 'status=idle'), findsOneWidget);
  });

  showcaseTest(
      'the infinite shapes: three readers share one entry, and Load next '
      'reaches all three through the mixin\'s controller', (tester, h) async {
    tall(tester);
    await h.open(tester, '/four-call-styles');

    for (final name in <String>['context', 'mixin', 'observer']) {
      expect(infiniteFact(name, 'pages=1'), findsOneWidget, reason: name);
      expect(infiniteFact(name, 'status=success'), findsOneWidget,
          reason: name);
    }
    expect(h.fact('styles', 'observers=3'), findsOneWidget);
    expect(h.fact('styles', 'fetches=1'), findsOneWidget);
    expect(h.requests('GET', '/api/projects'), 1);
    // Nothing on mount; the first page landing is the first call.
    expect(infiniteFact('mixin', 'infinite-listener-calls=1'), findsOneWidget);
    expect(infiniteFact('mixin', 'infinite-last=none->1'), findsOneWidget);

    await tester.tap(button('Load next'));
    await tester.pumpAndSettle();

    for (final name in <String>['context', 'mixin', 'observer']) {
      expect(infiniteFact(name, 'pages=2'), findsOneWidget, reason: name);
    }
    expect(h.fact('styles', 'fetches=2'), findsOneWidget);
    expect(h.requests('GET', '/api/projects'), 2);
    // The page fetch starting moved `fetchStatus`, not the page count, and
    // was refused; its landing is the one call.
    expect(infiniteFact('mixin', 'infinite-listener-calls=2'), findsOneWidget);
    expect(infiniteFact('mixin', 'infinite-last=1->2'), findsOneWidget);
  });
}
