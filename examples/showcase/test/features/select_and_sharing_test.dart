/// The `select-and-sharing` screen against the fake backend.
///
/// The counts asserted here are measured, and the screen's header says why
/// they are what they are: a first load is two builds for every reader
/// (pending, then the data); a refetch is two more for every reader without
/// a `buildWhen` (fetching, then idle with a newer `dataUpdatedAt`); a
/// toggle of the switch is one more for everyone; and `data builds` moves
/// only when the selected value does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/shared/api.dart';
import 'package:showcase/shared/models.dart';

import '../harness.dart';

const List<String> readers = <String>[
  'context',
  'builder',
  'mixin',
  'controller',
  'raw',
];

/// One exact text inside the reader's row.
Finder inReader(String id, String text) => factIn('reader $id', text);

void expectBuilds(String name, Map<String, int> expected) {
  for (final entry in expected.entries) {
    expect(
      inReader(entry.key, '$name=${entry.value}'),
      findsOneWidget,
      reason: '${entry.key} $name',
    );
  }
}

void expectDataBuilds(Map<String, int> expected) =>
    expectBuilds('data builds', expected);

Map<String, int> all(int value) => <String, int>{
      for (final id in readers) id: value,
    };

/// The list the cache holds right now — the thing `structuralSharing`
/// decides about.
List<Todo>? cached(Harness h) =>
    h.client.getQueryData<List<Todo>>(ShowcaseKeys.todos);

void main() {
  showcaseTest('every reader shows its selection after one request',
      (tester, h) async {
    await h.open(tester, '/select-and-sharing');

    expect(h.requests('GET', '/api/todos'), 1);
    expect(h.fact('todos', 'fetches=1'), findsOneWidget);
    expect(h.fact('todos', 'observers=5'), findsOneWidget);

    expect(inReader('context', 'count=3'), findsOneWidget);
    expect(inReader('builder', 'first=Update the deploy checklist'),
        findsOneWidget);
    expect(inReader('mixin', 'done=1'), findsOneWidget);
    expect(inReader('mixin', 'open=2'), findsOneWidget);
    expect(
        inReader('controller', 'Update the deploy checklist'), findsOneWidget);
    expect(inReader('controller', 'Rename the columns on the board'),
        findsOneWidget);
    expect(inReader('controller', 'Replace the expired API token'),
        findsOneWidget);
    expect(inReader('raw', 'length=3'), findsOneWidget);

    // Pending, then the data.
    expectBuilds('builds', all(2));
    expectDataBuilds(all(1));
  });

  showcaseTest('a refetch with equal data changes no selection',
      (tester, h) async {
    await h.open(tester, '/select-and-sharing');
    final before = cached(h);
    // A real backend never answers within the frame that shows the flip;
    // the fake would, so it is given a latency and stepped like one.
    h.backend.latency = const Duration(milliseconds: 200);

    await tester.tap(find.byTooltip('Refetch'));
    await tester.pump();

    // The flip to fetching: one rebuild for every reader without a
    // `buildWhen`, none for the one with it.
    expect(h.fact('todos', 'fetchStatus=fetching'), findsOneWidget);
    expectBuilds('builds', const <String, int>{
      'context': 3,
      'builder': 2,
      'mixin': 3,
      'controller': 3,
      'raw': 3,
    });

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(h.requests('GET', '/api/todos'), 2);
    expect(h.fact('todos', 'fetches=2'), findsOneWidget);
    expect(h.fact('todos', 'fetchStatus=idle'), findsOneWidget);
    // Shared: the cache kept the instance it had.
    expect(identical(cached(h), before), isTrue);

    // Nothing anyone selected changed.
    expectDataBuilds(all(1));
    // The landing — idle again, with a newer `dataUpdatedAt` — is the
    // second rebuild for the same readers; `buildWhen` skipped both.
    expectBuilds('builds', const <String, int>{
      'context': 4,
      'builder': 2,
      'mixin': 4,
      'controller': 4,
      'raw': 4,
    });
  });

  showcaseTest('toggling todo 1 moves only the done/open record',
      (tester, h) async {
    await h.open(tester, '/select-and-sharing');

    await tester.tap(find.byTooltip('Toggle todo 1'));
    await tester.pumpAndSettle();

    expect(h.requests('PATCH', '/api/todos/1'), 1);
    // The mutation's `onSuccess` invalidated the entry, which refetched it.
    expect(h.requests('GET', '/api/todos'), 2);
    expect(inReader('mixin', 'done=2'), findsOneWidget);
    expect(inReader('mixin', 'open=1'), findsOneWidget);

    // The count, the first text and the texts are what they were; the
    // record and the cache's own list are not.
    expectDataBuilds(const <String, int>{
      'context': 1,
      'builder': 1,
      'mixin': 2,
      'controller': 1,
      'raw': 2,
    });
    expect(inReader('builder', 'builds=2'), findsOneWidget);

    // And back: the record moves again, nothing else does.
    await tester.tap(find.byTooltip('Toggle todo 1'));
    await tester.pumpAndSettle();
    expect(inReader('mixin', 'done=1'), findsOneWidget);
    expectDataBuilds(const <String, int>{
      'context': 1,
      'builder': 1,
      'mixin': 3,
      'controller': 1,
      'raw': 3,
    });
  });

  showcaseTest('renaming todo 2 moves only the list of texts',
      (tester, h) async {
    await h.open(tester, '/select-and-sharing');

    await tester.tap(find.byTooltip('Rename todo 2'));
    await tester.pumpAndSettle();

    expect(h.requests('PATCH', '/api/todos/2'), 1);
    expect(h.requests('GET', '/api/todos'), 2);
    expect(inReader('controller', 'Renamed todo 2 x1'), findsOneWidget);
    expect(inReader('controller', 'Rename the columns on the board'),
        findsNothing);

    expectDataBuilds(const <String, int>{
      'context': 1,
      'builder': 1,
      'mixin': 1,
      'controller': 2,
      'raw': 2,
    });
    expect(inReader('builder', 'builds=2'), findsOneWidget);

    await tester.tap(find.byTooltip('Rename todo 2'));
    await tester.pumpAndSettle();
    expect(inReader('controller', 'Renamed todo 2 x2'), findsOneWidget);
    expectDataBuilds(const <String, int>{
      'context': 1,
      'builder': 1,
      'mixin': 1,
      'controller': 3,
      'raw': 3,
    });
  });

  showcaseTest(
      'with sharing off, an equal refetch moves the selection that is a new '
      'instance', (tester, h) async {
    await h.open(tester, '/select-and-sharing');

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    // The toggle rebuilt every reader once, with nothing new selected.
    expectBuilds('builds', all(3));
    expectDataBuilds(all(1));
    final before = cached(h);

    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(find.byTooltip('Refetch'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(h.fact('todos', 'fetches=2'), findsOneWidget);
    // The switch reached the cache write: an equal list, but a new instance.
    expect(cached(h), equals(before));
    expect(identical(cached(h), before), isFalse);

    // The opt-out reaches what `select` produces too, as upstream's
    // `replaceData` does — so a selection that builds a new value every time
    // counts as new. Only the controller's selector does: a list of texts.
    // The other three select an `int`, a `String` and a record, all of which
    // are `==` to the last one, so their readers stand still. (Until the
    // 2026-09-12 fidelity review the core ran every selection through
    // `replaceEqualDeep` regardless and this reader stood still too, which is
    // what made the switch invisible to all four.)
    expectDataBuilds(const <String, int>{
      'context': 1,
      'builder': 1,
      'mixin': 1,
      'controller': 2,
    });
    expectBuilds('builds', const <String, int>{
      'context': 5,
      'builder': 3,
      'mixin': 5,
      'controller': 5,
    });
  });

  // The library bug this screen found (2026-09-09): `QueryObserver.createResult`
  // ran the cache's data through `replaceEqualDeep` against the last result
  // it reported even when there was no `select`, a pass upstream's
  // `createResult` does not have (`data = state.data`), so the
  // `(_, next) => next` opt-out on the cache write never reached a reader and
  // the control's `data builds` stayed at 1 with sharing off. Fixed in the
  // core (its no-select branch now passes cached data through; PORTING_NOTES,
  // "Found by the showcase", item 2); this case is the regression and runs
  // green.
  group(
    'structural sharing off',
    () {
      showcaseTest(
          'the reader without select sees a new list on an equal refetch',
          (tester, h) async {
        await h.open(tester, '/select-and-sharing');
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(inReader('raw', 'data builds=1'), findsOneWidget);

        // The cache write is `(_, next) => next` now: the list in the cache
        // is a new instance, and an observer without `select` reports the
        // cache's data as it is — upstream's `createResult` does.
        await tester.tap(find.byTooltip('Refetch'));
        await tester.pumpAndSettle();
        expect(h.fact('todos', 'fetches=2'), findsOneWidget);
        expect(inReader('raw', 'data builds=2'), findsOneWidget);

        // Back on: the next equal refetch is reconciled with the cache
        // again.
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Refetch'));
        await tester.pumpAndSettle();
        expect(h.fact('todos', 'fetches=3'), findsOneWidget);
        expect(inReader('raw', 'data builds=2'), findsOneWidget);
      });
    },
  );

  showcaseTest('leaving the screen releases all five observers',
      (tester, h) async {
    await h.open(tester, '/select-and-sharing');
    expect(h.client.queryCache.queries.single.observersCount, 5);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('TanStack Query Showcase'), findsOneWidget);
    expect(h.client.queryCache.queries.single.observersCount, 0);
  });
}
