/// The `optimistic-updates` screen against the fake backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/shared/api.dart';
import 'package:showcase/shared/models.dart';

import '../harness.dart';

/// The backend's latency in the held-write cases: long enough to look at
/// the screen between the write and its answer.
const Duration latency = Duration(milliseconds: 300);

/// Opens the screen on a view tall enough for the add card, the strip and
/// the list with its four rows: the scaffold's list builds only what is in
/// view, and the default 800×600 test view ends inside the add card.
Future<void> open(WidgetTester tester, Harness h) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await h.open(tester, '/optimistic-updates');
}

/// The ids the cache holds under `todos`, in order — negative for an
/// optimistic row.
List<int> cachedIds(Harness h) => h.client
    .getQueryData<List<Todo>>(ShowcaseKeys.todos)!
    .map((todo) => todo.id)
    .toList();

/// Types [text] and presses `Add`, then pumps one frame — the first frame
/// after the write went out, before any answer.
Future<void> add(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.widgetWithText(FilledButton, 'Add'));
  await tester.pump();
}

/// Switches to the cache variant. Its `QueryBuilder` is a fresh observer on
/// an entry whose default `staleTime` is zero, so it refetches on mount:
/// after this the backend has answered two GETs, not one.
Future<void> viaCache(WidgetTester tester) async {
  await tester.tap(find.text('Via cache'));
  await tester.pumpAndSettle();
}

Future<void> refuseNext(WidgetTester tester) async {
  await tester.tap(find.text('Refuse next write'));
  await tester.pumpAndSettle();
}

bool refuseTicked(WidgetTester tester) =>
    tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value ??
    false;

void main() {
  showcaseTest('via variables, a held write is a saving row, not a cache entry',
      (tester, h) async {
    await open(tester, h);
    expect(find.text('todos=3'), findsOneWidget);
    h.backend.latency = latency;

    await add(tester, 'Order new batteries');

    // The POST is in flight: the row comes from the mutation's variables,
    // and the cache still holds what the backend last said.
    expect(find.text('Order new batteries'), findsOneWidget);
    expect(find.text('saving'), findsOneWidget);
    expect(find.text('todos=3'), findsOneWidget);
    expect(find.text('pending=true'), findsOneWidget);
    expect(cachedIds(h), <int>[1, 2, 3]);
    expect(h.requests('POST', '/api/todos'), 0);

    // The POST lands; `onSettled` starts the refetch, and returning its
    // future keeps the mutation — and the row — pending until it too lands.
    await tester.pump(latency);
    await tester.pump();
    expect(h.requests('POST', '/api/todos'), 1);
    expect(find.text('saving'), findsOneWidget);
    expect(h.fact('todos', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(find.text('saving'), findsNothing);
    expect(find.text('Order new batteries'), findsOneWidget);
    expect(find.text('#4'), findsOneWidget);
    expect(find.text('todos=4'), findsOneWidget);
    expect(find.text('pending=false'), findsOneWidget);
    expect(cachedIds(h), <int>[1, 2, 3, 4]);
    expect(h.requests('POST', '/api/todos'), 1);
    expect(h.requests('GET', '/api/todos'), 2);
  });

  showcaseTest(
      'via variables, a refused write keeps its row as an error with Retry',
      (tester, h) async {
    await open(tester, h);
    await refuseNext(tester);
    expect(refuseTicked(tester), isTrue);

    await add(tester, 'Order new batteries');
    await tester.pumpAndSettle();

    expect(find.text('Order new batteries'), findsOneWidget);
    expect(find.text('Not saved: Requested: 500'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    expect(find.text('saving'), findsNothing);
    // Three real rows plus the error row; the cache was never written.
    expect(find.text('todos=3'), findsOneWidget);
    expect(find.text('pending=false'), findsOneWidget);
    expect(cachedIds(h), <int>[1, 2, 3]);
    expect(h.requests('POST', RegExp(r'^/api/todos$')), 1);
    // `onSettled` refetched even though the write failed.
    expect(h.requests('GET', '/api/todos'), 2);
    // The refusal was consumed by the write that carried it.
    expect(refuseTicked(tester), isFalse);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Not saved: Requested: 500'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
    expect(find.text('Order new batteries'), findsOneWidget);
    expect(find.text('#4'), findsOneWidget);
    expect(find.text('todos=4'), findsOneWidget);
    expect(cachedIds(h), <int>[1, 2, 3, 4]);
    expect(h.requests('POST', RegExp(r'^/api/todos$')), 2);
    expect(h.requests('GET', '/api/todos'), 3);
  });

  showcaseTest('via cache, a held write is in the cache before the answer',
      (tester, h) async {
    await open(tester, h);
    await viaCache(tester);
    expect(find.text('todos=3'), findsOneWidget);
    h.backend.latency = latency;

    await add(tester, 'Order new batteries');

    // Nothing has answered, and the cache already has four entries: the
    // optimistic one with a temporary id below zero.
    expect(h.requests('POST', '/api/todos'), 0);
    expect(cachedIds(h), <int>[1, 2, 3, -4]);
    expect(find.text('Order new batteries'), findsOneWidget);
    expect(find.text('saving'), findsOneWidget);
    expect(find.text('todos=4'), findsOneWidget);
    expect(find.text('pending=true'), findsOneWidget);

    // The POST lands, `onSettled` refetches, and the refetch replaces the
    // temporary row with the backend's.
    await tester.pump(latency);
    await tester.pump();
    expect(h.requests('POST', '/api/todos'), 1);
    expect(cachedIds(h), <int>[1, 2, 3, -4]);

    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(cachedIds(h), <int>[1, 2, 3, 4]);
    expect(find.text('saving'), findsNothing);
    expect(find.text('Order new batteries'), findsOneWidget);
    expect(find.text('#4'), findsOneWidget);
    expect(find.text('todos=4'), findsOneWidget);
    expect(find.text('pending=false'), findsOneWidget);
    expect(h.requests('GET', '/api/todos'), 3);
  });

  showcaseTest('via cache, a refused write is rolled back to the snapshot',
      (tester, h) async {
    await open(tester, h);
    await viaCache(tester);
    await refuseNext(tester);
    h.backend.latency = latency;

    await add(tester, 'Order new batteries');
    expect(find.text('Order new batteries'), findsOneWidget);
    expect(find.text('todos=4'), findsOneWidget);
    expect(cachedIds(h), <int>[1, 2, 3, -4]);

    // The refusal lands: `onError` restores the snapshot at once, while
    // `onSettled`'s refetch is still in flight.
    await tester.pump(latency);
    await tester.pump();
    expect(h.requests('POST', RegExp(r'^/api/todos$')), 1);
    expect(find.text('Order new batteries'), findsNothing);
    expect(find.text('todos=3'), findsOneWidget);
    expect(cachedIds(h), <int>[1, 2, 3]);
    expect(h.fact('todos', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(find.text('Rolled back: Requested: 500'), findsOneWidget);
    expect(find.text('Order new batteries'), findsNothing);
    expect(find.text('todos=3'), findsOneWidget);
    expect(find.text('pending=false'), findsOneWidget);
    expect(cachedIds(h), <int>[1, 2, 3]);
    expect(h.requests('GET', '/api/todos'), 3);
    expect(refuseTicked(tester), isFalse);
  });

  showcaseTest(
      "onMutate's cancelQueries stops an in-flight refetch from overwriting the row",
      (tester, h) async {
    await open(tester, h);
    await viaCache(tester);
    h.backend.latency = latency;

    await tester.tap(find.byTooltip('Refetch'));
    await tester.pump();
    expect(h.fact('todos', 'fetchStatus=fetching'), findsOneWidget);

    await add(tester, 'Order new batteries');

    // The refetch was cancelled and reverted before the write, not merely
    // outrun by it: the entry is idle while only the POST is in flight.
    expect(h.fact('todos', 'fetchStatus=idle'), findsOneWidget);
    expect(cachedIds(h), <int>[1, 2, 3, -4]);
    expect(find.text('Order new batteries'), findsOneWidget);
    expect(find.text('todos=4'), findsOneWidget);

    // The cancelled refetch's latency passes: its answer never lands (the
    // backend logs an answered request only), and the optimistic row stays.
    await tester.pump(latency);
    await tester.pump();
    expect(h.requests('GET', '/api/todos'), 2);
    expect(h.requests('POST', '/api/todos'), 1);
    expect(cachedIds(h), <int>[1, 2, 3, -4]);
    expect(find.text('Order new batteries'), findsOneWidget);
    expect(find.text('todos=4'), findsOneWidget);

    // The refetch `onSettled` started is the one that replaces the row.
    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(h.requests('GET', '/api/todos'), 3);
    expect(cachedIds(h), <int>[1, 2, 3, 4]);
    expect(find.text('#4'), findsOneWidget);
    expect(find.text('saving'), findsNothing);
  });

  showcaseTest('switching the variant hands the entry to one new observer',
      (tester, h) async {
    await open(tester, h);
    expect(h.fact('todos', 'observers=1'), findsOneWidget);

    await viaCache(tester);
    expect(find.text('Todos · via cache'), findsOneWidget);
    expect(find.text('todos=3'), findsOneWidget);
    expect(h.fact('todos', 'observers=1'), findsOneWidget);
    // One reader replaced the other on the same entry; being a new observer
    // on a stale entry, it refetched on mount.
    expect(h.requests('GET', '/api/todos'), 2);

    await tester.tap(find.text('Via variables'));
    await tester.pumpAndSettle();
    expect(find.text('Todos · via variables'), findsOneWidget);
    expect(h.fact('todos', 'observers=1'), findsOneWidget);
  });
}
