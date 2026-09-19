/// The `mutation-cancel` screen against the fake backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:showcase/features/mutation_cancel/mutation_cancel_screen.dart';
import 'package:showcase/shared/api.dart';
import 'package:showcase/shared/models.dart';

import '../harness.dart';

/// The backend's latency for the reads; the write waits [slowWriteDelay] on
/// top of it, as `?delay` does on the server.
const Duration latency = Duration(milliseconds: 300);

const String before = 'Update the deploy checklist';
const String after = 'Rewrite the deploy checklist';

final RegExp patchPath = RegExp(r'^/api/todos/1$');

Future<void> open(WidgetTester tester, Harness h) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await h.open(tester, '/mutation-cancel');
}

Finder renameFact(String text) => factIn('rename facts', text);

/// The first todo's text as the cache holds it.
String cachedText(Harness h) => h.client
    .getQueryData<List<Todo>>(ShowcaseKeys.todos)!
    .firstWhere((todo) => todo.id == renamedTodoId)
    .text;

/// The first todo's text as the backend holds it.
String storedText(Harness h) =>
    h.backend.todos.firstWhere((todo) => todo['id'] == renamedTodoId)['text']!
        as String;

/// Types [text] and presses `Rename`, then pumps one frame — the first frame
/// after the write went out, before any answer.
Future<void> rename(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
  await tester.pump();
}

bool cancelEnabled(WidgetTester tester) =>
    tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cancel'))
        .onPressed !=
    null;

void main() {
  showcaseTest(
      'the write is sent with what onMutate kept, not what the cache says',
      (tester, h) async {
    await open(tester, h);
    expect(renameFact('status=idle'), findsOneWidget);
    expect(renameFact('text=$before'), findsOneWidget);
    expect(renameFact('from=none'), findsOneWidget);
    expect(cancelEnabled(tester), isFalse);
    h.backend.latency = latency;

    await rename(tester, after);

    // In flight: the cache already says the new text, so `from` can only
    // have come from `context.onMutateResult`.
    expect(h.requests('PATCH', patchPath), 0);
    expect(cachedText(h), after);
    expect(storedText(h), before);
    expect(renameFact('status=pending'), findsOneWidget);
    expect(renameFact('text=$after'), findsOneWidget);
    expect(renameFact('from=$before'), findsOneWidget);
    expect(cancelEnabled(tester), isTrue);

    // The write lands; `onSettled` refetches and keeps the run pending until
    // that has landed too.
    await tester.pump(latency + slowWriteDelay);
    await tester.pump(latency);
    await tester.pumpAndSettle();

    expect(renameFact('status=success'), findsOneWidget);
    expect(renameFact('error=none'), findsOneWidget);
    expect(renameFact('text=$after'), findsOneWidget);
    expect(renameFact('signalCancels=0'), findsOneWidget);
    expect(renameFact('rollbacks=0'), findsOneWidget);
    expect(renameFact('settles=1'), findsOneWidget);
    expect(storedText(h), after);
    expect(cancelEnabled(tester), isFalse);
    // What the backend's log shows of the request: `from` in its query.
    final patch = h.backend.log.singleWhere((entry) => entry.method == 'PATCH');
    expect(patch.query['from'], before);
    expect(patch.status, 200);
    expect(h.requests('GET', '/api/todos'), 2);
  });

  showcaseTest(
      'cancel fails the run: rolled back by onError, invalidated by '
      'onSettled', (tester, h) async {
    await open(tester, h);
    h.backend.latency = latency;

    await rename(tester, after);
    expect(renameFact('status=pending'), findsOneWidget);
    expect(renameFact('text=$after'), findsOneWidget);
    expect(cachedText(h), after);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pump();

    // `onError` has put the snapshot back, and `onSettled`'s invalidation is
    // out: its future is what the run still waits for.
    expect(cachedText(h), before);
    expect(renameFact('text=$before'), findsOneWidget);
    expect(renameFact('signalCancels=1'), findsOneWidget);
    expect(renameFact('rollbacks=1'), findsOneWidget);
    expect(renameFact('settles=1'), findsOneWidget);
    expect(h.fact('todos', 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(latency);
    await tester.pumpAndSettle();

    expect(renameFact('status=error'), findsOneWidget);
    expect(renameFact('error=cancelled'), findsOneWidget);
    expect(renameFact('text=$before'), findsOneWidget);
    expect(h.fact('todos', 'fetchStatus=idle'), findsOneWidget);
    expect(h.requests('GET', '/api/todos'), 2);
    final result = h.client.mutationCache.mutations.single.state;
    expect(result.error, isA<CancelledError>());

    // The signal reached dio: the time the write would have taken passes and
    // the backend never answers it (it logs an answered request only), nor
    // has it taken the text.
    await tester.pump(latency + slowWriteDelay);
    await tester.pumpAndSettle();
    expect(h.requests('PATCH', patchPath), 0);
    expect(storedText(h), before);
    expect(renameFact('text=$before'), findsOneWidget);
    expect(renameFact('settles=1'), findsOneWidget);
  });

  showcaseTest('a rename after a cancelled one goes through',
      (tester, h) async {
    await open(tester, h);

    await rename(tester, 'Never sent');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(renameFact('error=cancelled'), findsOneWidget);

    await rename(tester, after);
    // A new run, a new signal: the old one's cancellation is not inherited.
    expect(renameFact('status=pending'), findsOneWidget);
    expect(renameFact('from=$before'), findsOneWidget);
    await tester.pump(slowWriteDelay);
    await tester.pumpAndSettle();

    expect(renameFact('status=success'), findsOneWidget);
    expect(renameFact('error=none'), findsOneWidget);
    expect(renameFact('text=$after'), findsOneWidget);
    expect(renameFact('signalCancels=1'), findsOneWidget);
    expect(renameFact('rollbacks=1'), findsOneWidget);
    expect(renameFact('settles=2'), findsOneWidget);
    expect(h.requests('PATCH', patchPath), 1);
    expect(storedText(h), after);
  });
}
