/// The `cache-inspector` screen against the fake backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:showcase/features/cache_inspector/cache_inspector_screen.dart';
import 'package:showcase/shared/models.dart';

import '../harness.dart';

/// Two tables and a growing log under the test font's square glyphs run well
/// past the default 600 px, and `FeatureScaffold`'s lazy `ListView` never
/// builds what is below the fold. A taller surface keeps every text built.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The log's lines, top to bottom — the order the events arrived in.
List<String> logLines(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: groupNamed('event log'),
      matching: find.byType(Text),
    ))
    .map((text) => text.data!)
    .toList();

/// Whether [lines] appear in the log in this order, other lines between them
/// allowed — the log carries every key's events interleaved.
bool inOrder(List<String> log, List<String> lines) {
  var at = 0;
  for (final line in lines) {
    final found = log.indexOf(line, at);
    if (found < 0) {
      return false;
    }
    at = found + 1;
  }
  return true;
}

/// One row of the entries table, by the key's `debugString`.
Finder entry(String key) => groupNamed('entry $key');

/// One fact inside that row: two rows carry the same fact names, so nothing
/// is looked up unscoped.
Finder entryFact(String key, String text) =>
    find.descendant(of: entry(key), matching: find.text(text));

Finder mutationFact(int id, String text) => factIn('mutation #$id', text);

const String postsKey = '["posts"]';
const String todosKey = '["todos"]';
const String missingKey = '["posts",999]';

Future<void> tap(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(TextButton, label).hitTestable());
  await tester.pump();
}

void main() {
  showcaseTest(
      'loading posts with the readers mounted logs the entry, its observer '
      'and the fetch pair, in that order', (tester, h) async {
    tall(tester);
    await h.open(tester, '/cache-inspector');
    expect(find.text('entries=0'), findsOneWidget);
    expect(find.text('The query cache is empty.'), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Load posts'));
    await tester.pumpAndSettle();

    expect(
      inOrder(logLines(tester), <String>[
        'QueryAdded $postsKey',
        'QueryObserverAdded $postsKey',
        'QueryUpdated(QueryFetchAction) $postsKey',
        'QueryUpdated(QuerySuccessAction) $postsKey',
      ]),
      isTrue,
      reason: logLines(tester).join('\n'),
    );

    expect(entryFact(postsKey, 'status=success'), findsOneWidget);
    expect(entryFact(postsKey, 'observers=1'), findsOneWidget);
    expect(entryFact(postsKey, 'fetchStatus=idle'), findsOneWidget);
    // A one-minute stale time on the readers, so a fresh entry is not stale.
    expect(entryFact(postsKey, 'isStale=false'), findsOneWidget);
    expect(entryFact(postsKey, 'dataUpdatedAt=never'), findsNothing);
    expect(find.text('entries=3'), findsOneWidget);
    expect(find.text('reader ["posts"]=30 posts'), findsOneWidget);
  });

  showcaseTest(
      'invalidating a row makes it stale and refetches it, and so does '
      'Refetch', (tester, h) async {
    tall(tester);
    await h.open(tester, '/cache-inspector');

    await tester.tap(find.widgetWithText(FilledButton, 'Load posts'));
    await tester.pumpAndSettle();
    expect(entryFact(postsKey, 'updates=1'), findsOneWidget);
    expect(entryFact(postsKey, 'isStale=false'), findsOneWidget);

    // Held open by the backend's latency, so the invalidated state is read
    // before the refetch that follows it can clear the flag again.
    h.backend.latency = const Duration(milliseconds: 200);
    await tap(tester, 'Invalidate $postsKey');
    expect(entryFact(postsKey, 'isStale=true'), findsOneWidget);
    expect(entryFact(postsKey, 'fetchStatus=fetching'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(entryFact(postsKey, 'updates=2'), findsOneWidget);
    expect(
      inOrder(logLines(tester), <String>[
        'QueryUpdated(QueryInvalidateAction) $postsKey',
        'QueryUpdated(QueryFetchAction) $postsKey',
        'QueryUpdated(QuerySuccessAction) $postsKey',
      ]),
      isTrue,
      reason: logLines(tester).join('\n'),
    );

    h.backend.latency = Duration.zero;
    await tap(tester, 'Refetch $postsKey');
    await tester.pumpAndSettle();
    expect(entryFact(postsKey, 'updates=3'), findsOneWidget);
    expect(h.requests('GET', '/api/posts'), 3);
  });

  showcaseTest('Remove drops the row and logs QueryRemoved', (tester, h) async {
    tall(tester);
    await h.open(tester, '/cache-inspector');

    await tester.tap(find.widgetWithText(FilledButton, 'Load todos'));
    await tester.pumpAndSettle();
    expect(entry(todosKey), findsOneWidget);

    await tap(tester, 'Remove $todosKey');
    await tester.pumpAndSettle();

    expect(entry(todosKey), findsNothing);
    expect(find.text('entries=0'), findsOneWidget);
    expect(logLines(tester).last, 'QueryRemoved $todosKey');
  });

  showcaseTest(
      'dropping the readers takes observers to zero and the entry is '
      'collected five seconds later', (tester, h) async {
    tall(tester);
    await h.open(tester, '/cache-inspector');

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(entryFact(postsKey, 'observers=1'), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(entryFact(postsKey, 'observers=0'), findsOneWidget);
    expect(logLines(tester).contains('QueryObserverRemoved $postsKey'), isTrue);

    // gcTime is five seconds on everything this screen makes.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(entry(postsKey), findsNothing);
    expect(find.text('entries=0'), findsOneWidget);
    expect(logLines(tester).contains('QueryRemoved $postsKey'), isTrue);
  });

  showcaseTest('the missing post lands in the cache as an error',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/cache-inspector');

    await tester.tap(find.widgetWithText(FilledButton, 'Load a missing post'));
    await tester.pumpAndSettle();

    expect(entryFact(missingKey, 'status=error'), findsOneWidget);
    expect(entryFact(missingKey, 'fetchStatus=idle'), findsOneWidget);
    expect(entryFact(missingKey, 'updates=0'), findsOneWidget);
    expect(entryFact(missingKey, 'dataUpdatedAt=never'), findsOneWidget);
    expect(logLines(tester).last, 'QueryUpdated(QueryErrorAction) $missingKey');
    // `retry: RetryPolicy.never`: one attempt, not four.
    expect(h.requests('GET', '/api/posts/999'), 1);
  });

  showcaseTest('a todo shows up in the mutations table, pending then success',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/cache-inspector');
    expect(find.text('The mutation cache is empty.'), findsOneWidget);

    h.backend.latency = const Duration(milliseconds: 200);
    await tester.tap(find.widgetWithText(FilledButton, 'Add a todo'));
    await tester.pump();

    expect(find.text('mutations=1'), findsOneWidget);
    expect(mutationFact(1, 'status=pending'), findsOneWidget);
    expect(mutationFact(1, 'isPaused=false'), findsOneWidget);
    expect(mutationFact(1, 'failureCount=0'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(mutationFact(1, 'status=success'), findsOneWidget);
    expect(
      inOrder(logLines(tester), <String>[
        'MutationAdded ["todos","create"]',
        'MutationObserverAdded ["todos","create"]',
        'MutationUpdated(MutationPendingAction) ["todos","create"]',
        'MutationUpdated(MutationSuccessAction) ["todos","create"]',
      ]),
      isTrue,
      reason: logLines(tester).join('\n'),
    );
    expect(h.requests('POST', '/api/todos'), 1);
  });

  showcaseTest('Clear log empties the log without touching the caches',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/cache-inspector');

    await tester.tap(find.widgetWithText(FilledButton, 'Load posts'));
    await tester.pumpAndSettle();
    expect(logLines(tester), isNotEmpty);

    await tester.tap(find.byTooltip('Clear log'));
    await tester.pumpAndSettle();

    expect(find.text('log=0'), findsOneWidget);
    expect(logLines(tester), <String>['Nothing yet.']);
    expect(entry(postsKey), findsOneWidget);
  });

  showcaseTest(
      'leaving the screen unsubscribes: no exception, no timer, and the '
      "app's client still works", (tester, h) async {
    tall(tester);
    await h.open(tester, '/cache-inspector');

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add a todo'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('TanStack Query Showcase'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Everything the screen made carries a five-second gc time, so a screen
    // that let go of its subscriptions and its observers leaves nothing
    // running behind it.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(h.client.queryCache.queries, isEmpty);
    expect(h.client.mutationCache.mutations, isEmpty);

    // The client the screen was borrowing is untouched by its departure. The
    // fetch is stepped with pumps rather than awaited: the fake's latency is a
    // timer, and only a pump moves the test binding's clock.
    List<Post>? posts;
    h.client
        .query<List<Post>>(
            inspectorPostsQuery(h.api, staleTime: StaleTime.zero))
        .then((data) => posts = data)
        .ignore();
    await tester.pumpAndSettle();

    expect(posts, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
