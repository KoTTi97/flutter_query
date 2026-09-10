/// The `mutations` screen against the fake backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

const String increment = '/api/counter/increment';

/// Four cards and a strip: taller than the default test window, and a
/// lazily built list would not have the lower ones.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A button by its label. `byType` matches the exact class, and the screen
/// uses two of them, so this goes by the shared base.
/// One of the mutation facts, by the group it is in and its exact text —
/// `status=success` is also what the counter's strip says about the query.
Finder mutationFact(String label, String text) => find.descendant(
      of: find.byKey(ValueKey<String>('mutation-$label')),
      matching: find.text(text),
    );

Finder button(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );

void main() {
  showcaseTest(
      'mutate is pending while the request is out, then success, '
      'and the invalidated counter refetches', (tester, h) async {
    tall(tester);
    await h.open(tester, '/mutations');
    expect(find.text('counter=0'), findsOneWidget);
    expect(mutationFact('increment', 'status=idle'), findsOneWidget);
    expect(mutationFact('increment', 'submittedAt=none'), findsOneWidget);
    expect(h.requests('GET', '/api/counter'), 1);

    h.backend.latency = const Duration(milliseconds: 300);
    await tester.tap(button('Increment (mutate)'));
    await tester.pump();
    expect(mutationFact('increment', 'status=pending'), findsOneWidget);
    expect(mutationFact('increment', 'isPending=true'), findsOneWidget);
    expect(mutationFact('increment', 'submittedAt=set'), findsOneWidget);
    expect(find.text('counter=0'), findsOneWidget);
    // The count is read on the cache's events, so it lands one frame later.
    await tester.pump();
    expect(find.text('isMutating=1'), findsOneWidget);

    // One latency for the POST. The answer is in, and `onSuccess` has
    // started the counter's refetch — and returned its future, so the
    // mutation is still pending until that GET has answered too.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(h.requests('POST', increment), 1);
    expect(h.fact('counter', 'fetchStatus=fetching'), findsOneWidget);
    expect(mutationFact('increment', 'status=pending'), findsOneWidget);
    expect(find.text('counter=0'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(mutationFact('increment', 'status=success'), findsOneWidget);
    expect(mutationFact('increment', 'data=1'), findsOneWidget);
    expect(mutationFact('increment', 'isPending=false'), findsOneWidget);
    expect(find.text('isMutating=0'), findsOneWidget);
    expect(find.text('counter=1'), findsOneWidget);
    expect(h.fact('counter', 'fetches=2'), findsOneWidget);
    expect(h.requests('POST', increment), 1);
    expect(h.requests('GET', '/api/counter'), 2);

    await tester.tap(button('Reset'));
    await tester.pumpAndSettle();
    expect(mutationFact('increment', 'status=idle'), findsOneWidget);
    expect(mutationFact('increment', 'data=1'), findsNothing);
    expect(mutationFact('increment', 'submittedAt=none'), findsOneWidget);
    // Reset detaches the observer; the counter it moved stays moved.
    expect(find.text('counter=1'), findsOneWidget);
  });

  showcaseTest('mutateAsync hands its value to the caller', (tester, h) async {
    tall(tester);
    await h.open(tester, '/mutations');

    await tester.tap(button('Increment (mutate)'));
    await tester.pumpAndSettle();
    expect(mutationFact('increment', 'data=1'), findsOneWidget);

    await tester.tap(button('Increment (mutateAsync)'));
    await tester.pumpAndSettle();
    expect(find.text('mutateAsync result=2'), findsOneWidget);
    expect(mutationFact('increment', 'data=2'), findsOneWidget);
    expect(find.text('counter=2'), findsOneWidget);
    expect(h.requests('POST', increment), 2);
  });

  showcaseTest('a refused request is the error at once: no retry',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/mutations');

    await tester.tap(find.text('Fail next'));
    await tester.pump();
    await tester.tap(button('Increment (mutate)'));
    // Long enough for a retry to have shown up, had there been one.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(mutationFact('increment', 'status=error'), findsOneWidget);
    expect(mutationFact('increment', 'error=Requested: 500'), findsOneWidget);
    expect(mutationFact('increment', 'failureCount=1'), findsOneWidget);
    expect(mutationFact('increment', 'isPending=false'), findsOneWidget);
    expect(h.requests('POST', increment), 1);
    // The refused request changed nothing, and nothing invalidated the
    // counter either.
    expect(find.text('counter=0'), findsOneWidget);
    expect(h.requests('GET', '/api/counter'), 1);
    expect(h.backend.counter, 0);

    // `Fail next` was spent: the next call goes through.
    await tester.tap(button('Increment (mutate)'));
    await tester.pumpAndSettle();
    expect(mutationFact('increment', 'status=success'), findsOneWidget);
    expect(mutationFact('increment', 'failureCount=0'), findsOneWidget);
    expect(find.text('counter=1'), findsOneWidget);
  });

  showcaseTest('mutateAsync throws what the backend refused with',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/mutations');

    await tester.tap(find.text('Fail next'));
    await tester.pump();
    await tester.tap(button('Increment (mutateAsync)'));
    await tester.pumpAndSettle();

    expect(find.text('mutateAsync threw=Requested: 500'), findsOneWidget);
    expect(mutationFact('increment', 'status=error'), findsOneWidget);
    expect(h.requests('POST', increment), 1);
  });

  showcaseTest('the option callbacks run before the per-call ones',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/mutations');
    expect(find.text('log=empty'), findsOneWidget);

    await tester.tap(button('Run with callbacks'));
    await tester.pumpAndSettle();

    // The library's order: `onMutate`, the function, then the options'
    // `onSuccess` and `onSettled` (each awaited), and only then — once the
    // success has been dispatched — the callbacks passed to `mutate`.
    final lines = <String>[
      '1 onMutate',
      '2 mutationFn',
      '3 onSuccess (options)',
      '4 onSettled (options)',
      '5 onSuccess (call)',
      '6 onSettled (call)',
    ];
    for (final line in lines) {
      expect(find.text(line), findsOneWidget);
    }
    expect(find.textContaining('onError'), findsNothing);
    expect(find.text('log=empty'), findsNothing);
    expect(find.text('counter=1'), findsOneWidget);
    expect(h.requests('POST', increment), 1);
  });

  showcaseTest('two scoped mutations run one after the other',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/mutations');

    await tester.tap(button('Run two scoped'));
    await tester.pump();
    expect(mutationFact('pairs', 'first=pending'), findsOneWidget);
    expect(mutationFact('pairs', 'second=pending'), findsOneWidget);
    expect(mutationFact('pairs', 'secondPaused=true'), findsOneWidget);
    await tester.pump();
    expect(find.text('isMutating=2'), findsOneWidget);

    // Each request takes a second on the backend. After one, only the first
    // has settled — the second's request was not sent until then.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(mutationFact('pairs', 'first=success'), findsOneWidget);
    expect(mutationFact('pairs', 'second=pending'), findsOneWidget);
    expect(mutationFact('pairs', 'secondPaused=false'), findsOneWidget);
    expect(h.requests('POST', increment), 1);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(mutationFact('pairs', 'first=success'), findsOneWidget);
    expect(mutationFact('pairs', 'second=success'), findsOneWidget);
    expect(find.text('isMutating=0'), findsOneWidget);
    expect(h.requests('POST', increment), 2);
    expect(find.text('counter=2'), findsOneWidget);
  });

  showcaseTest('two unscoped mutations run at the same time',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/mutations');

    await tester.tap(button('Run two unscoped'));
    await tester.pump();
    expect(mutationFact('pairs', 'third=pending'), findsOneWidget);
    expect(mutationFact('pairs', 'fourth=pending'), findsOneWidget);

    // One second, not two: both requests were in flight together.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(mutationFact('pairs', 'third=success'), findsOneWidget);
    expect(mutationFact('pairs', 'fourth=success'), findsOneWidget);
    expect(h.requests('POST', increment), 2);
    expect(find.text('counter=2'), findsOneWidget);
  });

  showcaseTest('a mutation fired just before its reader unmounts still lands',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/mutations');

    h.backend.latency = const Duration(milliseconds: 300);
    await tester.tap(button('Fire and leave'));
    await tester.pump();
    expect(find.text('view=away'), findsOneWidget);
    expect(find.textContaining('counter='), findsNothing);
    expect(mutationFact('increment', 'status=pending'), findsNothing);
    expect(h.backend.counter, 0);
    await tester.pump();
    expect(find.text('isMutating=1'), findsOneWidget);

    // Nobody observes the mutation any more; the cache runs it to the end.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(h.backend.counter, 1);
    expect(h.requests('POST', increment), 1);
    expect(find.text('isMutating=0'), findsOneWidget);
    // Invalidated with no observer attached: stale, not refetched.
    expect(h.requests('GET', '/api/counter'), 1);

    h.backend.latency = Duration.zero;
    await tester.tap(button('Back to reader'));
    await tester.pumpAndSettle();
    expect(find.text('counter=1'), findsOneWidget);
    expect(h.requests('GET', '/api/counter'), 2);
    // A fresh reader, a fresh observer: nothing of the old run shows.
    expect(mutationFact('increment', 'status=idle'), findsOneWidget);
  });
}
