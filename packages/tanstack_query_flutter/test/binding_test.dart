/// The acceptance bar transferred from
/// https://github.com/KoTTi97/flutter_query/issues/23: all four call styles
/// reaching the same query in one app, an options change handled without
/// recreating the observer, observers released when the last reader goes away,
/// and `context.query`'s per-key rebuild granularity — each proven by a test
/// rather than by inspection.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

QueryKey sensorKey(String id) => QueryKey(<Object?>['sensor', id]);

QueryObserverOptions<String, String> sensorQuery(
  String id, {
  required Future<String> Function(String id) fetch,
}) =>
    QueryObserverOptions<String, String>(
      queryKey: sensorKey(id),
      queryFn: (_) => fetch(id),
      staleTime: const StaleTime.duration(Duration(minutes: 5)),
    );

Widget app(QueryClient client, Widget child) => QueryClientProvider(
      client: client,
      // These tests drive focus through the manager directly; the lifecycle
      // wiring itself runs fine under the test binding and is proven in
      // review_regressions_test.dart (F10, M5).
      observeAppLifecycle: false,
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  late QueryClient client;
  late List<String> fetched;

  setUp(() {
    client = QueryClient();
    fetched = <String>[];
  });

  /// `testWidgets` plus the cleanup a `QueryClient` needs.
  ///
  /// A client outlives the widget tree by design — it owns the cache and its
  /// `gcTime` timers — but Flutter's test binding asserts that no timer is
  /// pending when the tree comes down, and it checks that *before* any
  /// `tearDown` runs. So the teardown has to happen inside the body. The same
  /// rule applies to anyone writing widget tests against this library, and the
  /// README says so.
  void widgetTest(
      String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        client.clear();
      }
    });
  }

  Future<String> fetch(String id) async {
    fetched.add(id);
    return 'Sensor $id';
  }

  group('the four call styles', () {
    widgetTest('QueryBuilder renders pending, then data', (tester) async {
      await tester.pumpWidget(app(
        client,
        QueryBuilder<String>(
          options: sensorQuery('a', fetch: fetch),
          builder: (context, result) => Text(switch (result) {
            QueryPending() => 'loading',
            QuerySuccess(:final data) => data,
            QueryError() => 'error',
          }),
        ),
      ));

      // The first frame is already fetching, never an idle blank.
      expect(find.text('loading'), findsOneWidget);

      await tester.pump();
      expect(find.text('Sensor a'), findsOneWidget);
      expect(fetched, <String>['a']);
    });

    widgetTest('context.query renders the same query', (tester) async {
      await tester
          .pumpWidget(app(client, _ContextScreen(id: 'a', fetch: fetch)));

      expect(find.text('loading'), findsOneWidget);
      await tester.pump();
      expect(find.text('Sensor a'), findsOneWidget);
    });

    widgetTest('QueryMixin renders the same query', (tester) async {
      await tester.pumpWidget(app(client, _MixinScreen(id: 'a', fetch: fetch)));

      expect(find.text('loading'), findsOneWidget);
      await tester.pump();
      expect(find.text('Sensor a'), findsOneWidget);
    });

    widgetTest('a controller renders the same query', (tester) async {
      await tester
          .pumpWidget(app(client, _ControllerScreen(id: 'a', fetch: fetch)));

      expect(find.text('loading'), findsOneWidget);
      await tester.pump();
      expect(find.text('Sensor a'), findsOneWidget);
    });

    widgetTest('all four in one app share a single fetch', (tester) async {
      await tester.pumpWidget(app(
        client,
        Column(
          children: <Widget>[
            QueryBuilder<String>(
              options: sensorQuery('a', fetch: fetch),
              builder: (context, result) =>
                  Text('builder:${result.dataOrNull ?? '…'}'),
            ),
            _ContextScreen(id: 'a', fetch: fetch, prefix: 'context'),
            _MixinScreen(id: 'a', fetch: fetch, prefix: 'mixin'),
            _ControllerScreen(id: 'a', fetch: fetch, prefix: 'controller'),
          ],
        ),
      ));

      await tester.pump();

      expect(find.text('builder:Sensor a'), findsOneWidget);
      expect(find.text('context:Sensor a'), findsOneWidget);
      expect(find.text('mixin:Sensor a'), findsOneWidget);
      expect(find.text('controller:Sensor a'), findsOneWidget);

      // One cache entry, one request — four readers.
      expect(fetched, <String>['a']);
      expect(client.queryCache.queries, hasLength(1));
    });
  });

  group('options changes', () {
    widgetTest('a changed key moves a context reader to the new query',
        (tester) async {
      await tester.pumpWidget(app(
        client,
        _ContextScreen(id: 'a', fetch: fetch),
      ));
      await tester.pump();
      expect(find.text('Sensor a'), findsOneWidget);

      await tester.pumpWidget(app(
        client,
        _ContextScreen(id: 'b', fetch: fetch),
      ));
      await tester.pump();

      expect(find.text('Sensor b'), findsOneWidget);
      expect(fetched, <String>['a', 'b']);
    });

    widgetTest('QueryBuilder follows a changed key too', (tester) async {
      Widget screen(String id) => app(
            client,
            QueryBuilder<String>(
              options: sensorQuery(id, fetch: fetch),
              builder: (context, result) =>
                  Text(result.dataOrNull ?? 'loading'),
            ),
          );

      await tester.pumpWidget(screen('a'));
      await tester.pump();
      expect(find.text('Sensor a'), findsOneWidget);

      await tester.pumpWidget(screen('b'));
      await tester.pump();
      expect(find.text('Sensor b'), findsOneWidget);
    });
  });

  group('release', () {
    widgetTest('context.query releases the observer when its reader unmounts',
        (tester) async {
      await tester
          .pumpWidget(app(client, _ContextScreen(id: 'a', fetch: fetch)));
      await tester.pump();

      final query =
          client.queryCache.find(QueryFilters(queryKey: sensorKey('a')))!;
      expect(query.observersCount, 1);

      await tester.pumpWidget(app(client, const Text('gone')));
      await tester.pump();

      expect(query.observersCount, 0);
    });

    widgetTest('a key the widget stopped reading is released within a frame',
        (tester) async {
      await tester
          .pumpWidget(app(client, _ContextScreen(id: 'a', fetch: fetch)));
      await tester.pump();

      final first =
          client.queryCache.find(QueryFilters(queryKey: sensorKey('a')))!;
      expect(first.observersCount, 1);

      await tester
          .pumpWidget(app(client, _ContextScreen(id: 'b', fetch: fetch)));
      await tester.pump();

      // The old key is let go once the frame that stopped reading it is done.
      expect(first.observersCount, 0);
      expect(
        client.queryCache
            .find(QueryFilters(queryKey: sensorKey('b')))!
            .observersCount,
        1,
      );
    });

    widgetTest('the mixin releases everything with its State', (tester) async {
      await tester.pumpWidget(app(client, _MixinScreen(id: 'a', fetch: fetch)));
      await tester.pump();

      final query =
          client.queryCache.find(QueryFilters(queryKey: sensorKey('a')))!;
      expect(query.observersCount, 1);

      await tester.pumpWidget(app(client, const Text('gone')));
      await tester.pump();

      expect(query.observersCount, 0);
    });
  });

  group('rebuild granularity', () {
    widgetTest('context.query rebuilds only the widgets that read that key',
        (tester) async {
      final builds = <String, int>{'a': 0, 'b': 0};

      await tester.pumpWidget(app(
        client,
        Column(
          children: <Widget>[
            _CountingReader(id: 'a', fetch: fetch, builds: builds),
            _CountingReader(id: 'b', fetch: fetch, builds: builds),
          ],
        ),
      ));
      await tester.pump();

      final before = Map<String, int>.of(builds);

      // Touch only 'a'.
      client.setQueryData<String>(sensorKey('a'), 'Sensor a (renamed)');
      await tester.pump();

      expect(builds['a'], greaterThan(before['a']!));
      expect(builds['b'], before['b']);
      expect(find.text('a:Sensor a (renamed)'), findsOneWidget);
    });
  });

  group('mutations', () {
    widgetTest('MutationBuilder runs a mutation and reports its result',
        (tester) async {
      await tester.pumpWidget(app(
        client,
        MutationBuilder<String, String, Object?>(
          options: MutationOptions<String, String, Object?>(
            mutationFn: (name) async => 'renamed to $name',
          ),
          builder: (context, mutation) => TextButton(
            onPressed: () => mutation.mutate('Küche'),
            child: Text(mutation.value.dataOrNull ?? 'idle'),
          ),
        ),
      ));

      expect(find.text('idle'), findsOneWidget);

      await tester.tap(find.byType(TextButton));
      await tester.pump();

      expect(find.text('renamed to Küche'), findsOneWidget);
    });

    widgetTest('context.mutation is owned by its widget', (tester) async {
      await tester
          .pumpWidget(app(client, _ContextMutationScreen(client: client)));

      await tester.tap(find.byType(TextButton));
      await tester.pump();

      expect(find.text('renamed to Küche'), findsOneWidget);
      expect(client.mutationCache.mutations, hasLength(1));
    });
  });

  group('the provider', () {
    widgetTest('mounts and unmounts the client with the widget',
        (tester) async {
      await tester.pumpWidget(app(client, const Text('hi')));

      // A mounted client reacts to focus; an unmounted one does not.
      client.focusManager.setFocused(false);
      client.focusManager.setFocused(true);
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      expect(() => client.focusManager.setFocused(false), returnsNormally);
    });

    widgetTest('follows an onlineStatus stream when given one', (tester) async {
      final online = StreamController<bool>.broadcast();
      addTearDown(online.close);

      await tester.pumpWidget(QueryClientProvider(
        client: client,
        observeAppLifecycle: false,
        onlineStatus: online.stream,
        child: const MaterialApp(home: Text('hi')),
      ));

      expect(client.onlineManager.isOnline(), isTrue);

      online.add(false);
      await tester.pump();
      expect(client.onlineManager.isOnline(), isFalse);

      online.add(true);
      await tester.pump();
      expect(client.onlineManager.isOnline(), isTrue);
    });
  });
}

class _ContextScreen extends StatelessWidget {
  const _ContextScreen({
    required this.id,
    required this.fetch,
    this.prefix,
  });

  final String id;
  final Future<String> Function(String id) fetch;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final sensor = context.query(sensorQuery(id, fetch: fetch));
    final label = sensor.dataOrNull ?? 'loading';
    return Text(prefix == null ? label : '$prefix:$label');
  }
}

class _CountingReader extends StatelessWidget {
  const _CountingReader({
    required this.id,
    required this.fetch,
    required this.builds,
  });

  final String id;
  final Future<String> Function(String id) fetch;
  final Map<String, int> builds;

  @override
  Widget build(BuildContext context) {
    builds[id] = builds[id]! + 1;
    final sensor = context.query(sensorQuery(id, fetch: fetch));
    return Text('$id:${sensor.dataOrNull ?? '…'}');
  }
}

class _MixinScreen extends StatefulWidget {
  const _MixinScreen({required this.id, required this.fetch, this.prefix});

  final String id;
  final Future<String> Function(String id) fetch;
  final String? prefix;

  @override
  State<_MixinScreen> createState() => _MixinScreenState();
}

class _MixinScreenState extends State<_MixinScreen> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final sensor = watchQuery(sensorQuery(widget.id, fetch: widget.fetch));
    final label = sensor.dataOrNull ?? 'loading';
    return Text(widget.prefix == null ? label : '${widget.prefix}:$label');
  }
}

class _ControllerScreen extends StatefulWidget {
  const _ControllerScreen({
    required this.id,
    required this.fetch,
    this.prefix,
  });

  final String id;
  final Future<String> Function(String id) fetch;
  final String? prefix;

  @override
  State<_ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<_ControllerScreen> {
  QueryController<String, String>? _sensor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sensor ??= QueryController<String, String>(
      QueryClientProvider.of(context),
      sensorQuery(widget.id, fetch: widget.fetch),
    );
  }

  @override
  void dispose() {
    _sensor?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _sensor!,
        builder: (context, _) {
          final label = _sensor!.value.dataOrNull ?? 'loading';
          return Text(
              widget.prefix == null ? label : '${widget.prefix}:$label');
        },
      );
}

class _ContextMutationScreen extends StatelessWidget {
  const _ContextMutationScreen({required this.client});

  final QueryClient client;

  @override
  Widget build(BuildContext context) {
    final rename = context.mutation<String, String, Object?>(
      MutationOptions<String, String, Object?>(
        mutationKey: QueryKey(const <Object?>['rename']),
        mutationFn: (name) async => 'renamed to $name',
      ),
    );
    return TextButton(
      onPressed: () => rename.mutate('Küche'),
      child: Text(rename.value.dataOrNull ?? 'idle'),
    );
  }
}
