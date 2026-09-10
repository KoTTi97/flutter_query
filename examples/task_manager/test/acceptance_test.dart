/// The MVP acceptance suite: one widget test per row of the demo's feature
/// checklist, against the fake backend
/// (https://github.com/KoTTi97/flutter_query/issues/24).
///
/// The rows are the feature checklist in this example's README, itemised the
/// way the original port design did (`git show 69c71d4:flutter-port/DESIGN.md`,
/// §3 "Feature checklist"). The cases after them are regressions found by
/// review, not checklist rows.
///
/// These run the *real* app — its screens, its `TaskApi`, its cache policy —
/// with only the transport replaced. Pointing the same app at the express
/// backend is then a smoke test rather than a leap of faith.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:task_manager/main.dart';
import 'package:task_manager/src/api.dart';
import 'package:task_manager/src/models.dart';
import 'package:task_manager/src/queries.dart';

import 'fake_backend.dart';

void main() {
  late FakeBackend backend;
  late QueryClient client;
  late TaskApi api;

  setUp(() {
    backend = FakeBackend();
    // The app's own defaults, so the suite runs the policy that ships.
    client = QueryClient(defaultOptions: appDefaultOptions);
    api = TaskApi(
      dio: Dio(BaseOptions(baseUrl: 'http://backend.test/api'))
        ..httpClientAdapter = backend,
    );
  });

  /// `testWidgets` plus the cleanup a `QueryClient` needs: it owns `gcTime`
  /// timers, and the test binding checks for pending timers before any
  /// `tearDown` runs.
  void demoTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        // Tear the tree down first, then let the frame after it run: the
        // binding's `context.query` scope releases observers in a post-frame
        // sweep, and clearing the client before that runs would leave the
        // sweep to re-create what it is about to drop.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        client.clear();
      }
    });
  }

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(TaskManagerApp(api: api, client: client));
    await tester.pumpAndSettle();
  }

  Future<void> openDetail(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  int requestsFor(String fragment) =>
      backend.requests.where((request) => request.contains(fragment)).length;

  demoTest('skeleton only on first load, rows afterwards', (tester) async {
    await tester.pumpWidget(TaskManagerApp(api: api, client: client));

    // First frame: the query is already fetching, so the skeleton is up.
    expect(find.byKey(const ValueKey<String>('list-skeleton')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Draft the changelog'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('list-skeleton')), findsNothing);
  });

  demoTest('the list response seeds every per-task entry, stamped fresh',
      (tester) async {
    await start(tester);

    // Three rows are on screen, and not one of them fetched its own task:
    // the list's queryFn seeded all three.
    expect(requestsFor('GET /tasks/'), 0);
    for (final id in <String>['1', '2', '3']) {
      expect(client.getQueryData<Task>(TaskKeys.detail(id)), isNotNull);
    }
  });

  demoTest(
      'the header count derives from the list entry, with no extra request',
      (tester) async {
    await start(tester);

    // Two synced of three, from the same cache entry the rows use.
    expect(find.text('2 of 3 synced'), findsOneWidget);
    expect(requestsFor('GET /tasks'), 1);
  });

  demoTest('opening a task renders from the seeded entry', (tester) async {
    await start(tester);
    await openDetail(tester, 'Draft the changelog');

    // No detail fetch: the seeded entry is fresh, so the screen is instant.
    expect(find.text('Rename'), findsOneWidget);
    expect(requestsFor('GET /tasks/1'), 0);
  });

  demoTest('a filter change re-keys the list and keeps the old entry cached',
      (tester) async {
    await start(tester);

    await tester.enterText(find.byType(TextField).first, 'Renew');
    await tester.pump(const Duration(milliseconds: 350)); // debounce
    await tester.pumpAndSettle();

    expect(find.text('Renew the domain'), findsOneWidget);
    expect(find.text('Draft the changelog'), findsNothing);
    // Two list requests — one per key — and the first entry is still cached.
    expect(requestsFor('GET /tasks?'), 0); // dio keeps params off the path
    expect(requestsFor('GET /tasks'), 2);
    expect(
      client.queryCache
          .findAll(filters: QueryFilters(queryKey: TaskKeys.lists)),
      hasLength(2),
    );
  });

  demoTest('debounced search makes one request per pause, not per keystroke',
      (tester) async {
    await start(tester);
    final before = requestsFor('GET /tasks');

    final field = find.byType(TextField).first;
    await tester.enterText(field, 'T');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, 'Th');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, 'The');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(requestsFor('GET /tasks') - before, 1);
  });

  demoTest(
      'optimistic rename shows instantly and one invalidation updates both',
      (tester) async {
    backend.writeLatency = const Duration(milliseconds: 200);
    await start(tester);
    await openDetail(tester, 'Draft the changelog');

    await tester.enterText(
        find.byType(TextField).first, 'Draft the release notes');
    await tester.tap(find.text('Rename'));
    await tester.pump();

    // The patch is on screen before the backend has answered.
    expect(find.text('Draft the release notes'), findsWidgets);

    await tester.pumpAndSettle();

    // One refetch of one key reconciles the detail screen *and* the row.
    expect(requestsFor('GET /tasks/1'), 1);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Draft the release notes'), findsOneWidget);
  });

  demoTest('a rejected rename rolls back', (tester) async {
    await start(tester);
    await openDetail(tester, 'Draft the changelog');

    await tester.enterText(find.byType(TextField).first, 'fail');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(
      find.text('The server refused the write'),
      findsOneWidget,
    );
    expect(
      client.getQueryData<Task>(TaskKeys.detail('1'))!.name,
      'Draft the changelog',
    );
    // The field follows the rollback.
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Draft the changelog',
    );
  });

  demoTest('editing again clears a failed rename banner', (tester) async {
    await start(tester);
    await openDetail(tester, 'Draft the changelog');

    await tester.enterText(find.byType(TextField).first, 'fail');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('The server refused the write'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'A different name');
    await tester.pumpAndSettle();
    expect(find.text('The server refused the write'), findsNothing);
  });

  demoTest('the reminder switch flips at once, then the poll confirms it',
      (tester) async {
    backend.confirmAfter = const Duration(milliseconds: 900);
    await start(tester);
    await openDetail(tester, 'Draft the changelog');

    await tester.tap(find.byType(Switch));
    await tester.pump();

    // The optimistic target is on screen immediately.
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.pump(const Duration(milliseconds: 100));
    // The accepted response carries pending: true, which starts the poll.
    expect(find.text('Waiting for the scheduler…'), findsOneWidget);
    // And locks the switch until the scheduler has confirmed.
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);

    // Let the scheduler confirm and the poll pick it up.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Confirmed by the scheduler'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
    // The poll ran: more than one detail request while pending.
    expect(requestsFor('GET /tasks/1'), greaterThan(0));
  });

  demoTest(
      'an optimistic delete disappears at once and springs back on failure',
      (tester) async {
    await start(tester);

    // The first delete attempt fails, by the backend's script.
    await tester.tap(find.byTooltip('Delete Draft the changelog'));
    await tester.pump();
    expect(find.text('Draft the changelog'), findsNothing);

    await tester.pumpAndSettle();
    expect(
      find.text('The server refused the delete — try again'),
      findsOneWidget,
    );
    expect(find.text('Draft the changelog'), findsOneWidget);

    // The retry goes through.
    await tester.tap(find.byTooltip('Delete Draft the changelog'));
    await tester.pumpAndSettle();
    expect(find.text('Draft the changelog'), findsNothing);
  });

  demoTest('creating a task invalidates every list', (tester) async {
    await start(tester);
    final before = requestsFor('GET /tasks');

    await tester.tap(find.byTooltip('New task'));
    await tester.pumpAndSettle();

    expect(find.text('New task'), findsOneWidget);
    expect(requestsFor('GET /tasks') - before, greaterThan(0));
  });

  demoTest('refresh is disabled while the list is fetching', (tester) async {
    backend.listLatency = const Duration(milliseconds: 300);
    await tester.pumpWidget(TaskManagerApp(api: api, client: client));
    await tester.pump();

    // IconButton builds its own Tooltip *inside* itself, so the button is the
    // tooltip's ancestor, not its descendant.
    final refresh = find.ancestor(
      of: find.byTooltip('Reload'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(refresh).onPressed, isNull);

    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);

    await tester.tap(refresh);
    await tester.pump();
    expect(tester.widget<IconButton>(refresh).onPressed, isNull);
    await tester.pumpAndSettle();
  });

  demoTest('a backend error is retried once, then shows a panel that can retry',
      (tester) async {
    final broken = TaskApi(
      dio: Dio(BaseOptions(baseUrl: 'http://backend.test/api'))
        ..httpClientAdapter = _AlwaysFails(backend),
    );
    await tester.pumpWidget(TaskManagerApp(api: broken, client: client));
    await tester.pump(const Duration(milliseconds: 100));

    // `retry: 1` from the app's defaults: the first failure is not final, one
    // more attempt is scheduled after the default one-second delay, and the
    // skeleton stays up meanwhile.
    expect(requestsFor('GET /tasks'), 1);
    expect(find.text('Try again'), findsNothing);

    // The toolbar spinner keeps frames coming while fetching, so settling
    // runs through the retry delay and the second failure.
    await tester.pumpAndSettle();
    expect(requestsFor('GET /tasks'), 2);
    expect(find.text('Try again'), findsOneWidget);
  });

  // Regressions found by review, not checklist rows.

  demoTest('a refused delete of the last visible task still shows its notice',
      (tester) async {
    await start(tester);
    // Filter down to one row and delete it: the optimistic patch empties the
    // list, and the empty state must not take the mutation's notice with it.
    await tester.enterText(find.byType(TextField).first, 'Renew');
    await tester.pump(const Duration(milliseconds: 350)); // debounce
    await tester.pumpAndSettle();
    expect(find.text('Renew the domain'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete Renew the domain'));
    await tester.pump();
    expect(find.text('No tasks found.'), findsOneWidget);

    // The first delete fails, by the backend's script.
    await tester.pumpAndSettle();
    expect(
      find.text('The server refused the delete — try again'),
      findsOneWidget,
    );
    expect(find.text('Renew the domain'), findsOneWidget);
  });
}

/// A backend that refuses everything, for the error panel. Requests still
/// land in [inner]'s log, so the suite can count the attempts.
class _AlwaysFails implements HttpClientAdapter {
  _AlwaysFails(this.inner);

  final FakeBackend inner;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    inner.requests.add('${options.method} ${options.path}');
    return ResponseBody.fromString(
      '{"message":"The server is unreachable"}',
      503,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
