/// The `diagnostics` screen against the fake backend: the two errors the
/// port adds, thrown where the library says they are.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:showcase/features/diagnostics/diagnostics_screen.dart';

import '../harness.dart';

/// One fact of a card, by its group and exact text — `status=error` is said
/// by the mutation's facts and by the strip alike.
Finder factOf(String label, String text) => factIn('facts $label', text);

/// Two cards and a strip: the second card's buttons sit below the default
/// 600 px window, and a lazily built list has nothing there.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  showcaseTest(
      'a read as the entry\'s type answers, a read as another type throws '
      'QueryDataTypeError naming both', (tester, h) async {
    tall(tester);
    await h.open(tester, '/diagnostics');
    expect(find.text('counter=0'), findsOneWidget);
    expect(factOf('typed', 'read=none'), findsOneWidget);

    await tap(tester, 'Read as int');
    expect(factOf('typed', 'read=int 0'), findsOneWidget);

    await tap(tester, 'Read as String');
    expect(factOf('typed', 'read=QueryDataTypeError'), findsOneWidget);
    expect(factOf('typed', 'expected=String'), findsOneWidget);
    expect(factOf('typed', 'actual=int'), findsOneWidget);
    // Thrown from the call, synchronously: the same read by hand.
    expect(
      () => h.client.getQueryData<String>(diagnosticsCounterKey),
      throwsA(isA<QueryDataTypeError>()
          .having((e) => e.queryKey, 'queryKey', diagnosticsCounterKey)
          .having((e) => e.expected, 'expected', String)
          .having((e) => e.actual, 'actual', int)),
    );
  });

  showcaseTest('a write of another type throws too and leaves the entry alone',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/diagnostics');
    expect(h.fact('counter', 'updates=1'), findsOneWidget);

    await tap(tester, 'Write a String');

    expect(factOf('typed', 'write=QueryDataTypeError'), findsOneWidget);
    expect(factOf('typed', 'expected=String'), findsOneWidget);
    expect(factOf('typed', 'actual=int'), findsOneWidget);
    // Nothing was written: the entry still holds its one int.
    expect(h.fact('counter', 'updates=1'), findsOneWidget);
    expect(h.fact('counter', 'status=success'), findsOneWidget);
    expect(find.text('counter=0'), findsOneWidget);
    expect(h.client.getQueryData<int>(diagnosticsCounterKey), 0);
  });

  showcaseTest(
      'a mutation without a function fails with MissingMutationFunctionError '
      'and sends nothing', (tester, h) async {
    tall(tester);
    await h.open(tester, '/diagnostics');
    expect(factOf('no-function', 'status=idle'), findsOneWidget);
    expect(factOf('no-function', 'default=none'), findsOneWidget);

    await tap(tester, 'Mutate without a function');

    expect(factOf('no-function', 'status=error'), findsOneWidget);
    expect(factOf('no-function', 'error=MissingMutationFunctionError'),
        findsOneWidget);
    expect(find.textContaining('No mutationFn was provided'), findsOneWidget);
    expect(find.textContaining('setMutationDefaults'), findsOneWidget);
    expect(h.requests('POST', '/api/counter/increment'), 0);
    expect(h.backend.counter, 0);
  });

  showcaseTest(
      'a default mutationFn registered for the key is the cure: the same '
      'mutation then runs it', (tester, h) async {
    tall(tester);
    await h.open(tester, '/diagnostics');
    await tap(tester, 'Mutate without a function');
    expect(factOf('no-function', 'status=error'), findsOneWidget);

    await tap(tester, 'Register a default mutationFn');
    expect(factOf('no-function', 'default=registered'), findsOneWidget);

    await tap(tester, 'Mutate without a function');

    expect(factOf('no-function', 'status=success'), findsOneWidget);
    expect(factOf('no-function', 'data=1'), findsOneWidget);
    expect(h.requests('POST', '/api/counter/increment'), 1);
    expect(h.backend.counter, 1);
  });
}
