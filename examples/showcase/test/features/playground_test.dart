/// The `playground` screen against the fake backend.
///
/// Time under `testWidgets` is fake and `clock` is bound to it, so
/// `pump(Duration(seconds: 6))` really fires the retry timers and an
/// entry's gc timer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:showcase/features/playground/playground_screen.dart';
import 'package:showcase/shared/models.dart';

import '../harness.dart';

/// One fact of a reader's own group (`todos-reader`, `editor`, `backend`,
/// `add`) — scoped, because the strips show an `isStale=` of their own.
Finder reader(String group, String text) => find.descendant(
      of: find.byKey(ValueKey<String>('$group-facts')),
      matching: find.text(text),
    );

/// A segment of one knob, by its label — three knobs have a `0`.
Finder segment(String knob, String label) => find.descendant(
      of: find.byKey(ValueKey<String>(knob)),
      matching: find.text(label),
    );

/// The row of todo [id]. Its text is also in the editor's field once the
/// editor is open, so a row is found through its key, never by text alone.
Finder row(int id) => find.byKey(ValueKey<String>('todo-row-$id'));

Finder rowText(int id, String text) =>
    find.descendant(of: row(id), matching: find.text(text));

Future<void> pick(WidgetTester tester, String knob, String label) async {
  await tester.tap(segment(knob, label));
  await tester.pumpAndSettle();
}

Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}

Future<void> openEditor(WidgetTester tester, int id, String text) async {
  await tester.tap(rowText(id, text));
  await tester.pumpAndSettle();
  expect(reader('editor', 'editing=$id'), findsOneWidget);
}

/// Opens the screen on a view tall enough for the knobs, the list, an
/// editor and both strips: the scaffold's list builds only what is in view.
Future<void> open(WidgetTester tester, Harness h) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await h.open(tester, '/playground');
  expect(rowText(1, 'Update the deploy checklist'), findsOneWidget);
  // The knobs have reached the backend: the `pending` fact is gone.
  expect(reader('backend', 'latency=0ms'), findsOneWidget);
  expect(reader('backend', 'errorRate=0%'), findsOneWidget);
}

void main() {
  showcaseTest(
      'error rate 100 %: a refetch fails through the retries and the list '
      'comes back at 0', (tester, h) async {
    await open(tester, h);
    expect(h.requests('GET', '/api/todos'), 1);

    await pick(tester, 'error-rate', '100 %');
    expect(h.backend.errorRate, 1);
    expect(reader('backend', 'errorRate=100%'), findsOneWidget);

    // One attempt and three retries, 300 ms apart (`playgroundRetryDelay`),
    // each refused at random by the backend — which at 100 % is every time.
    await tester.tap(find.byTooltip('Refetch'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('fetching'), findsOneWidget);
    expect(reader('todos-reader', 'failureCount=1'), findsOneWidget);
    expect(rowText(1, 'Update the deploy checklist'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    expect(reader('todos-reader', 'failureCount=2'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(reader('todos-reader', 'failureCount=3'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(reader('todos-reader', 'status=error'), findsOneWidget);
    expect(reader('todos-reader', 'failureCount=4'), findsOneWidget);
    expect(
      find.text('Refetch failed: Failed at random (errorRate)'),
      findsOneWidget,
    );
    // The stale list is still on screen next to the error.
    expect(rowText(1, 'Update the deploy checklist'), findsOneWidget);
    expect(h.fact('todos', 'status=error'), findsOneWidget);
    expect(h.requests('GET', '/api/todos'), 5);

    await pick(tester, 'error-rate', '0');
    expect(h.backend.errorRate, 0);
    await tapTooltip(tester, 'Refetch');
    expect(reader('todos-reader', 'status=success'), findsOneWidget);
    expect(reader('todos-reader', 'failureCount=0'), findsOneWidget);
    expect(find.text('Refetch failed: Failed at random (errorRate)'),
        findsNothing);
    expect(h.fact('todos', 'status=success'), findsOneWidget);
    expect(h.requests('GET', '/api/todos'), 6);
  });

  showcaseTest(
      'stale time: the client default changed under a live observer reaches '
      'it on the next build', (tester, h) async {
    await open(tester, h);
    expect(reader('todos-reader', 'isStale=true'), findsOneWidget);
    expect(h.fact('todos', 'isStale=true'), findsOneWidget);

    // No fetch: the observer re-resolved its options against the new
    // defaults and the data, seconds old, is now within the 30 s.
    await pick(tester, 'stale-time', '30 s');
    expect(
      h.client.getDefaultOptions().queries?.staleTime,
      const StaleTime.duration(Duration(seconds: 30)),
    );
    expect(reader('todos-reader', 'isStale=false'), findsOneWidget);
    expect(h.fact('todos', 'isStale=false'), findsOneWidget);
    expect(h.fact('todos', 'fetches=1'), findsOneWidget);

    await tapTooltip(tester, 'Refetch');
    expect(reader('todos-reader', 'isStale=false'), findsOneWidget);
    expect(h.fact('todos', 'fetches=2'), findsOneWidget);

    // The editor's reader is a second live observer, on another State,
    // and the knob reaches it the same way.
    await openEditor(tester, 2, 'Rename the columns on the board');
    expect(reader('editor', 'isStale=false'), findsOneWidget);

    await pick(tester, 'stale-time', '0');
    expect(reader('todos-reader', 'isStale=true'), findsOneWidget);
    expect(reader('editor', 'isStale=true'), findsOneWidget);
    expect(h.fact('todos', 'isStale=true'), findsOneWidget);
    expect(h.fact('todos', 'fetches=2'), findsOneWidget);
    expect(h.requests('GET', '/api/todos'), 2);
  });

  showcaseTest(
      'gc time 5 s: a closed editor\'s entry is collected; 5 min keeps it',
      (tester, h) async {
    await open(tester, h);
    await pick(tester, 'gc-time', '5 s');
    expect(
      h.client.getDefaultOptions().queries?.gcTime,
      const GcTime.duration(Duration(seconds: 5)),
    );

    await openEditor(tester, 1, 'Update the deploy checklist');
    expect(h.fact('todo-1', 'status=success'), findsOneWidget);
    expect(h.fact('todo-1', 'observers=1'), findsOneWidget);

    // Closing the editor removes its State and with it the observer: the
    // entry is unobserved, and its five seconds start.
    await tapTooltip(tester, 'Close editor');
    expect(reader('editor', 'editing=1'), findsNothing);
    expect(h.fact('todo-1', 'observers=0'), findsOneWidget);
    expect(h.fact('todo-1', 'status=success'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(h.fact('todo-1', 'status=absent'), findsOneWidget);
    // The list, created under the 5 min default, is untouched.
    expect(h.fact('todos', 'status=success'), findsOneWidget);

    // A fresh entry under 5 min outlives the same wait.
    await pick(tester, 'gc-time', '5 min');
    await openEditor(tester, 1, 'Update the deploy checklist');
    expect(h.fact('todo-1', 'status=success'), findsOneWidget);
    await tapTooltip(tester, 'Close editor');
    expect(h.fact('todo-1', 'observers=0'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(h.fact('todo-1', 'status=success'), findsOneWidget);
    expect(h.fact('todo-1', 'observers=0'), findsOneWidget);
  });

  showcaseTest(
      'invalidate everything refetches the list and the open editor\'s entry',
      (tester, h) async {
    await open(tester, h);
    await openEditor(tester, 3, 'Replace the expired API token');
    // Seeded from the list and dated with it, so under stale time 0 the
    // mount refetched: one fetch of its own.
    expect(h.fact('todos', 'fetches=1'), findsOneWidget);
    expect(h.fact('todo-3', 'fetches=1'), findsOneWidget);
    expect(h.requests('GET', '/api/todos'), 2);

    await tester.tap(find.text('Invalidate everything'));
    await tester.pumpAndSettle();

    expect(h.fact('todos', 'fetches=2'), findsOneWidget);
    expect(h.fact('todo-3', 'fetches=2'), findsOneWidget);
    expect(h.fact('todos', 'isStale=true'), findsOneWidget);
    expect(h.fact('todo-3', 'status=success'), findsOneWidget);
    expect(h.requests('GET', '/api/todos'), 4);
  });

  showcaseTest('add, rename and complete a todo: the list reflects each',
      (tester, h) async {
    await open(tester, h);
    expect(h.requests('GET', '/api/todos'), 1);

    await tester.enterText(
        find.widgetWithText(TextField, 'New todo'), 'Water the plants');
    await tester.tap(find.text('Add todo'));
    await tester.pumpAndSettle();
    expect(reader('add', 'adding=success'), findsOneWidget);
    expect(rowText(4, 'Water the plants'), findsOneWidget);
    expect(h.requests('POST', '/api/todos'), 1);
    expect(h.requests('GET', '/api/todos'), 2);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'New todo'))
          .controller
          ?.text,
      isEmpty,
    );

    // Opening the editor is one fetch of its own (stale time 0).
    await openEditor(tester, 4, 'Water the plants');
    expect(h.requests('GET', '/api/todos'), 3);

    await tester.enterText(
        find.widgetWithText(TextField, 'Text'), 'Water the plants twice');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(reader('editor', 'saving=success'), findsOneWidget);
    expect(rowText(4, 'Water the plants twice'), findsOneWidget);
    expect(h.requests('PATCH', '/api/todos/4'), 1);
    expect(h.requests('GET', '/api/todos'), 4);

    expect(
      find.descendant(of: row(4), matching: find.byIcon(Icons.check_circle)),
      findsNothing,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: row(4), matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue);
    expect(h.requests('PATCH', '/api/todos/4'), 2);
    expect(h.requests('GET', '/api/todos'), 5);
    // The PATCH's answer went straight into the editor's entry: no fetch.
    expect(h.fact('todo-4', 'fetches=1'), findsOneWidget);
    expect(h.client.getQueryData<Todo>(todoKey(4))?.done, isTrue);
  });

  showcaseTest(
      'leaving the screen restores the client\'s defaults and the scenario',
      (tester, h) async {
    final snapshot = h.client.getDefaultOptions();
    await open(tester, h);

    await pick(tester, 'stale-time', '30 s');
    await pick(tester, 'gc-time', '5 s');
    await pick(tester, 'latency', '300 ms');
    await pick(tester, 'error-rate', '50 %');
    expect(h.client.getDefaultOptions(), isNot(snapshot));
    expect(h.backend.latency, const Duration(milliseconds: 300));
    expect(h.backend.errorRate, 0.5);
    expect(reader('backend', 'latency=300ms'), findsOneWidget);
    expect(reader('backend', 'errorRate=50%'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('TanStack Query Showcase'), findsOneWidget);

    expect(h.client.getDefaultOptions(), snapshot);
    expect(h.backend.latency, Duration.zero);
    expect(h.backend.errorRate, 0);
  });
}
