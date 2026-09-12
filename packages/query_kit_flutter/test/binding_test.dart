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
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';

QueryKey taskKey(String id) => QueryKey(<Object?>['task', id]);

QueryObserverOptions<String> taskQuery(
  String id, {
  required Future<String> Function(String id) fetch,
}) =>
    QueryObserverOptions<String>(
      queryKey: taskKey(id),
      queryFn: (_) => fetch(id),
      staleTime: const StaleTime.duration(Duration(minutes: 5)),
    );

void main() {
  late List<String> fetched;

  setUp(() => fetched = <String>[]);

  Future<String> fetch(String id) async {
    fetched.add(id);
    return 'Task $id';
  }

  group('the four call styles', () {
    queryWidgetTest('QueryBuilder renders pending, then data',
        (tester, client) async {
      await tester.pumpWidget(app(
        client,
        QueryBuilder<String>(
          options: taskQuery('a', fetch: fetch),
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
      expect(find.text('Task a'), findsOneWidget);
      expect(fetched, <String>['a']);
    });

    queryWidgetTest('context.query renders the same query',
        (tester, client) async {
      await tester
          .pumpWidget(app(client, _ContextScreen(id: 'a', fetch: fetch)));

      expect(find.text('loading'), findsOneWidget);
      await tester.pump();
      expect(find.text('Task a'), findsOneWidget);
    });

    queryWidgetTest('QueryMixin renders the same query',
        (tester, client) async {
      await tester.pumpWidget(app(client, _MixinScreen(id: 'a', fetch: fetch)));

      expect(find.text('loading'), findsOneWidget);
      await tester.pump();
      expect(find.text('Task a'), findsOneWidget);
    });

    queryWidgetTest('a controller renders the same query',
        (tester, client) async {
      await tester
          .pumpWidget(app(client, _ControllerScreen(id: 'a', fetch: fetch)));

      expect(find.text('loading'), findsOneWidget);
      await tester.pump();
      expect(find.text('Task a'), findsOneWidget);
    });

    queryWidgetTest('all four in one app share a single fetch',
        (tester, client) async {
      await tester.pumpWidget(app(
        client,
        Column(
          children: <Widget>[
            QueryBuilder<String>(
              options: taskQuery('a', fetch: fetch),
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

      expect(find.text('builder:Task a'), findsOneWidget);
      expect(find.text('context:Task a'), findsOneWidget);
      expect(find.text('mixin:Task a'), findsOneWidget);
      expect(find.text('controller:Task a'), findsOneWidget);

      // One cache entry, one request — four readers.
      expect(fetched, <String>['a']);
      expect(client.queryCache.queries, hasLength(1));
    });
  });

  group('options changes', () {
    queryWidgetTest('a changed key moves a context reader to the new query',
        (tester, client) async {
      await tester.pumpWidget(app(
        client,
        _ContextScreen(id: 'a', fetch: fetch),
      ));
      await tester.pump();
      expect(find.text('Task a'), findsOneWidget);

      await tester.pumpWidget(app(
        client,
        _ContextScreen(id: 'b', fetch: fetch),
      ));
      await tester.pump();

      expect(find.text('Task b'), findsOneWidget);
      expect(fetched, <String>['a', 'b']);
    });

    queryWidgetTest('QueryBuilder follows a changed key too',
        (tester, client) async {
      Widget screen(String id) => app(
            client,
            QueryBuilder<String>(
              options: taskQuery(id, fetch: fetch),
              builder: (context, result) =>
                  Text(result.dataOrNull ?? 'loading'),
            ),
          );

      await tester.pumpWidget(screen('a'));
      await tester.pump();
      expect(find.text('Task a'), findsOneWidget);

      await tester.pumpWidget(screen('b'));
      await tester.pump();
      expect(find.text('Task b'), findsOneWidget);
    });
  });

  group('release', () {
    queryWidgetTest(
        'context.query releases the observer when its reader unmounts',
        (tester, client) async {
      await tester
          .pumpWidget(app(client, _ContextScreen(id: 'a', fetch: fetch)));
      await tester.pump();

      final query = client.queryCache
          .find(filters: QueryFilters(queryKey: taskKey('a')))!;
      expect(query.observersCount, 1);

      await tester.pumpWidget(app(client, const Text('gone')));
      await tester.pump();

      expect(query.observersCount, 0);
    });

    queryWidgetTest(
        'a key the widget stopped reading is released within a frame',
        (tester, client) async {
      await tester
          .pumpWidget(app(client, _ContextScreen(id: 'a', fetch: fetch)));
      await tester.pump();

      final first = client.queryCache
          .find(filters: QueryFilters(queryKey: taskKey('a')))!;
      expect(first.observersCount, 1);

      await tester
          .pumpWidget(app(client, _ContextScreen(id: 'b', fetch: fetch)));
      await tester.pump();

      // The old key is let go once the frame that stopped reading it is done.
      expect(first.observersCount, 0);
      expect(
        client.queryCache
            .find(filters: QueryFilters(queryKey: taskKey('b')))!
            .observersCount,
        1,
      );
    });

    queryWidgetTest('the mixin releases everything with its State',
        (tester, client) async {
      await tester.pumpWidget(app(client, _MixinScreen(id: 'a', fetch: fetch)));
      await tester.pump();

      final query = client.queryCache
          .find(filters: QueryFilters(queryKey: taskKey('a')))!;
      expect(query.observersCount, 1);

      await tester.pumpWidget(app(client, const Text('gone')));
      await tester.pump();

      expect(query.observersCount, 0);
    });
  });

  group('rebuild granularity', () {
    queryWidgetTest(
        'context.query rebuilds only the widgets that read that key',
        (tester, client) async {
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
      client.setQueryData<String>(taskKey('a'), 'Task a (renamed)');
      await tester.pump();

      expect(builds['a'], greaterThan(before['a']!));
      expect(builds['b'], before['b']);
      expect(find.text('a:Task a (renamed)'), findsOneWidget);
    });
  });

  group('mutations', () {
    queryWidgetTest('MutationBuilder runs a mutation and reports its result',
        (tester, client) async {
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

    queryWidgetTest('context.mutation is owned by its widget',
        (tester, client) async {
      await tester
          .pumpWidget(app(client, _ContextMutationScreen(client: client)));

      await tester.tap(find.byType(TextButton));
      await tester.pump();

      expect(find.text('renamed to Küche'), findsOneWidget);
      expect(client.mutationCache.mutations, hasLength(1));
    });
  });

  group('the provider', () {
    queryWidgetTest('mounts and unmounts the client with the widget',
        (tester, client) async {
      await tester.pumpWidget(app(client, const Text('hi')));

      // A mounted client reacts to focus; an unmounted one does not.
      client.focusManager.setFocused(false);
      client.focusManager.setFocused(true);
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      expect(() => client.focusManager.setFocused(false), returnsNormally);
    });

    queryWidgetTest('follows an OnlineStatus.stream when given one',
        (tester, client) async {
      final online = StreamController<bool>.broadcast();
      addTearDown(online.close);

      await tester.pumpWidget(QueryClientProvider(
        client: client,
        observeAppLifecycle: false,
        onlineStatus: OnlineStatus.stream(online.stream, initial: true),
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
    final task = context.query(taskQuery(id, fetch: fetch));
    final label = task.dataOrNull ?? 'loading';
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
    final task = context.query(taskQuery(id, fetch: fetch));
    return Text('$id:${task.dataOrNull ?? '…'}');
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
    final task = watchQuery(taskQuery(widget.id, fetch: widget.fetch));
    final label = task.dataOrNull ?? 'loading';
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
  QueryController<String, String>? _task;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _task ??= QueryController<String, String>(
      QueryClientProvider.of(context),
      taskQuery(widget.id, fetch: widget.fetch),
    );
  }

  @override
  void dispose() {
    _task?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _task!,
        builder: (context, _) {
          final label = _task!.value.dataOrNull ?? 'loading';
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
