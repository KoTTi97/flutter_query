/// The MVP acceptance suite: one widget test per row of the demo's feature
/// checklist, against the fake gateway
/// (https://github.com/KoTTi97/flutter_query/issues/24).
///
/// The rows are the behaviours `react-demo/react/README.md` lists under "What
/// each part demonstrates", itemised the way the original port design did
/// (`git show 69c71d4:flutter-port/DESIGN.md`, §3 "Feature checklist"). The
/// cases after them are regressions found by review, not checklist rows.
///
/// These run the *real* app — its screens, its `SensorApi`, its cache policy —
/// with only the transport replaced. Pointing the same app at the express
/// gateway is then a smoke test rather than a leap of faith.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_demo/main.dart';
import 'package:sensor_demo/src/api.dart';
import 'package:sensor_demo/src/models.dart';
import 'package:sensor_demo/src/queries.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

import 'fake_gateway.dart';

void main() {
  late FakeGateway gateway;
  late QueryClient client;
  late SensorApi api;

  setUp(() {
    gateway = FakeGateway();
    // The app's own defaults, so the suite runs the policy that ships.
    client = QueryClient(defaultOptions: demoDefaultOptions);
    api = SensorApi(
      dio: Dio(BaseOptions(baseUrl: 'http://gateway.test/api'))
        ..httpClientAdapter = gateway,
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
    await tester.pumpWidget(SensorDemoApp(api: api, client: client));
    await tester.pumpAndSettle();
  }

  Future<void> openDetail(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  int requestsFor(String fragment) =>
      gateway.requests.where((request) => request.contains(fragment)).length;

  demoTest('skeleton only on first load, rows afterwards', (tester) async {
    await tester.pumpWidget(SensorDemoApp(api: api, client: client));

    // First frame: the query is already fetching, so the skeleton is up.
    expect(find.byKey(const ValueKey<String>('list-skeleton')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Fensterkontakt'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('list-skeleton')), findsNothing);
  });

  demoTest('the list response seeds every per-sensor entry, stamped fresh',
      (tester) async {
    await start(tester);

    // Three rows are on screen, and not one of them fetched its own sensor:
    // the list's queryFn seeded all three.
    expect(requestsFor('GET /sensors/'), 0);
    for (final id in <String>['1', '2', '3']) {
      expect(client.getQueryData<Sensor>(SensorKeys.detail(id)), isNotNull);
    }
  });

  demoTest(
      'the header count derives from the list entry, with no extra request',
      (tester) async {
    await start(tester);

    // Two connected of three, from the same cache entry the rows use.
    expect(find.text('2 von 3 verbunden'), findsOneWidget);
    expect(requestsFor('GET /sensors'), 1);
  });

  demoTest('opening a sensor renders from the seeded entry', (tester) async {
    await start(tester);
    await openDetail(tester, 'Fensterkontakt');

    // No detail fetch: the seeded entry is fresh, so the screen is instant.
    expect(find.text('Umbenennen'), findsOneWidget);
    expect(requestsFor('GET /sensors/1'), 0);
  });

  demoTest('a filter change re-keys the list and keeps the old entry cached',
      (tester) async {
    await start(tester);

    await tester.enterText(find.byType(TextField).first, 'Thermo');
    await tester.pump(const Duration(milliseconds: 350)); // debounce
    await tester.pumpAndSettle();

    expect(find.text('Thermostat'), findsOneWidget);
    expect(find.text('Fensterkontakt'), findsNothing);
    // Two list requests — one per key — and the first entry is still cached.
    expect(requestsFor('GET /sensors?'), 0); // dio keeps params off the path
    expect(requestsFor('GET /sensors'), 2);
    expect(
      client.queryCache.findAll(QueryFilters(queryKey: SensorKeys.lists)),
      hasLength(2),
    );
  });

  demoTest('debounced search makes one request per pause, not per keystroke',
      (tester) async {
    await start(tester);
    final before = requestsFor('GET /sensors');

    final field = find.byType(TextField).first;
    await tester.enterText(field, 'T');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, 'Th');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, 'The');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(requestsFor('GET /sensors') - before, 1);
  });

  demoTest(
      'optimistic rename shows instantly and one invalidation updates both',
      (tester) async {
    gateway.writeLatency = const Duration(milliseconds: 200);
    await start(tester);
    await openDetail(tester, 'Fensterkontakt');

    await tester.enterText(find.byType(TextField).first, 'Küchenfenster');
    await tester.tap(find.text('Umbenennen'));
    await tester.pump();

    // The patch is on screen before the gateway has answered.
    expect(find.text('Küchenfenster'), findsWidgets);

    await tester.pumpAndSettle();

    // One refetch of one key reconciles the detail screen *and* the row.
    expect(requestsFor('GET /sensors/1'), 1);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Küchenfenster'), findsOneWidget);
  });

  demoTest('a rejected rename rolls back', (tester) async {
    await start(tester);
    await openDetail(tester, 'Fensterkontakt');

    await tester.enterText(find.byType(TextField).first, 'fail');
    await tester.tap(find.text('Umbenennen'));
    await tester.pumpAndSettle();

    expect(
      find.text('Gateway hat den Schreibvorgang abgelehnt'),
      findsOneWidget,
    );
    expect(
      client.getQueryData<Sensor>(SensorKeys.detail('1'))!.name,
      'Fensterkontakt',
    );
    // The field follows the rollback, as the React form does.
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Fensterkontakt',
    );
  });

  demoTest('editing again clears a failed rename banner', (tester) async {
    await start(tester);
    await openDetail(tester, 'Fensterkontakt');

    await tester.enterText(find.byType(TextField).first, 'fail');
    await tester.tap(find.text('Umbenennen'));
    await tester.pumpAndSettle();
    expect(
        find.text('Gateway hat den Schreibvorgang abgelehnt'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Neuer Name');
    await tester.pumpAndSettle();
    expect(find.text('Gateway hat den Schreibvorgang abgelehnt'), findsNothing);
  });

  demoTest('the Matter switch flips at once, then the poll confirms it',
      (tester) async {
    gateway.confirmAfter = const Duration(milliseconds: 900);
    await start(tester);
    await openDetail(tester, 'Fensterkontakt');

    await tester.tap(find.byType(Switch));
    await tester.pump();

    // The optimistic target is on screen immediately.
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.pump(const Duration(milliseconds: 100));
    // The accepted response carries pending: true, which starts the poll.
    expect(find.text('Wird vom Gerät bestätigt…'), findsOneWidget);
    // And locks the switch until the device has confirmed, as in React.
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);

    // Let the device confirm and the poll pick it up.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Bestätigter Gerätezustand'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
    // The poll ran: more than one detail request while pending.
    expect(requestsFor('GET /sensors/1'), greaterThan(0));
  });

  demoTest(
      'an optimistic delete disappears at once and springs back on failure',
      (tester) async {
    await start(tester);

    // The first delete attempt fails, by the gateway's script.
    await tester.tap(find.byTooltip('Fensterkontakt löschen'));
    await tester.pump();
    expect(find.text('Fensterkontakt'), findsNothing);

    await tester.pumpAndSettle();
    expect(
      find.text('Gateway hat das Löschen abgelehnt — nochmal versuchen'),
      findsOneWidget,
    );
    expect(find.text('Fensterkontakt'), findsOneWidget);

    // The retry goes through.
    await tester.tap(find.byTooltip('Fensterkontakt löschen'));
    await tester.pumpAndSettle();
    expect(find.text('Fensterkontakt'), findsNothing);
  });

  demoTest('creating a sensor invalidates every list', (tester) async {
    await start(tester);
    final before = requestsFor('GET /sensors');

    await tester.tap(find.byTooltip('Sensor anlegen'));
    await tester.pumpAndSettle();

    expect(find.text('Neuer Sensor'), findsOneWidget);
    expect(requestsFor('GET /sensors') - before, greaterThan(0));
  });

  demoTest('refresh is disabled while the list is fetching', (tester) async {
    gateway.listLatency = const Duration(milliseconds: 300);
    await tester.pumpWidget(SensorDemoApp(api: api, client: client));
    await tester.pump();

    // IconButton builds its own Tooltip *inside* itself, so the button is the
    // tooltip's ancestor, not its descendant.
    final refresh = find.ancestor(
      of: find.byTooltip('Neu laden'),
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

  demoTest('a gateway error is retried once, then shows a panel that can retry',
      (tester) async {
    final broken = SensorApi(
      dio: Dio(BaseOptions(baseUrl: 'http://gateway.test/api'))
        ..httpClientAdapter = _AlwaysFails(gateway),
    );
    await tester.pumpWidget(SensorDemoApp(api: broken, client: client));
    await tester.pump(const Duration(milliseconds: 100));

    // `retry: 1` from the app's defaults: the first failure is not final, one
    // more attempt is scheduled after the default one-second delay, and the
    // skeleton stays up meanwhile.
    expect(requestsFor('GET /sensors'), 1);
    expect(find.text('Nochmal versuchen'), findsNothing);

    // The toolbar spinner keeps frames coming while fetching, so settling
    // runs through the retry delay and the second failure.
    await tester.pumpAndSettle();
    expect(requestsFor('GET /sensors'), 2);
    expect(find.text('Nochmal versuchen'), findsOneWidget);
  });

  // Regressions found by review, not checklist rows.

  demoTest('a refused delete of the last visible sensor still shows its notice',
      (tester) async {
    await start(tester);
    // Filter down to one row and delete it: the optimistic patch empties the
    // list, and the empty state must not take the mutation's notice with it.
    await tester.enterText(find.byType(TextField).first, 'Thermo');
    await tester.pump(const Duration(milliseconds: 350)); // debounce
    await tester.pumpAndSettle();
    expect(find.text('Thermostat'), findsOneWidget);

    await tester.tap(find.byTooltip('Thermostat löschen'));
    await tester.pump();
    expect(find.text('Keine Sensoren gefunden.'), findsOneWidget);

    // The first delete fails, by the gateway's script.
    await tester.pumpAndSettle();
    expect(
      find.text('Gateway hat das Löschen abgelehnt — nochmal versuchen'),
      findsOneWidget,
    );
    expect(find.text('Thermostat'), findsOneWidget);
  });
}

/// A gateway that refuses everything, for the error panel. Requests still
/// land in [inner]'s log, so the suite can count the attempts.
class _AlwaysFails implements HttpClientAdapter {
  _AlwaysFails(this.inner);

  final FakeGateway inner;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    inner.requests.add('${options.method} ${options.path}');
    return ResponseBody.fromString(
      '{"message":"Gateway nicht erreichbar"}',
      503,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
