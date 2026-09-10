import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

class _TrackedClient extends QueryClient {
  int clears = 0;
  final events = <String>[];

  @override
  void clear() {
    clears++;
    events.add('clear');
    super.clear();
  }

  @override
  void unmount() {
    events.add('unmount');
    super.unmount();
  }
}

void main() {
  late QueryClient client;
  setUp(() => client = QueryClient());

  Widget app(Widget child) => QueryClientProvider(
      client: client,
      observeAppLifecycle: false,
      child: Directionality(textDirection: TextDirection.ltr, child: child));

  void widgetTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        client.clear();
      }
    });
  }

  widgetTest('an inactive blip is not an absence at all', (tester) async {
    // `inactive` maps to focused, so a notification shade or an incoming call
    // must not raise a focus event, and must not start the background clock.
    // The threshold is an hour: every absence this test stages is "short",
    // so any refetch here would mean the blip was mistaken for an absence.
    // The above-threshold case needs virtual time and lives in the core suite.
    // Focused up front, so the provider's own mount-time focus notification
    // is not a change and the baseline below stays at the first fetch.
    final focus =
        AppFocusManager(refetchMinBackgroundDuration: const Duration(hours: 1))
          ..setFocused(true);
    final threshold = QueryClient(focusManager: focus);
    var calls = 0;
    try {
      await tester.pumpWidget(QueryClientProvider(
        client: threshold,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: QueryBuilder<int>(
            options: QueryObserverOptions<int, int>(
                queryKey: QueryKey(const ['inactive']),
                queryFn: (_) => ++calls,
                refetchOnWindowFocus: RefetchOn.always),
            builder: (_, __) => const SizedBox(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(calls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, 1, reason: 'focus never dropped, so nothing refetches');
      expect(focus.isFocused(), isTrue);
      expect(focus.shouldRefetchOnFocus, isTrue,
          reason: 'no focus event ran, so nothing was suppressed either');

      // A genuine absence does drop focus — and, being far under the hour,
      // is suppressed on return. Flutter only allows the full path.
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      expect(focus.isFocused(), isFalse);
      for (final state in const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(calls, 1, reason: 'the absence was shorter than the threshold');
      expect(focus.shouldRefetchOnFocus, isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox());
      threshold.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  });

  widgetTest(
      'owned provider creates once, replaces by key and clears after unmount',
      (tester) async {
    final clients = <_TrackedClient>[];
    var created = 0;
    QueryClient create() {
      created++;
      final c = _TrackedClient();
      clients.add(c);
      return c;
    }

    Widget owned(String key, QueryClient Function() factory) =>
        QueryClientProvider.create(
            key: ValueKey(key),
            create: factory,
            observeAppLifecycle: false,
            child: Builder(builder: (context) {
              QueryClientProvider.read(context)
                  .setQueryData(QueryKey(['seed']), 1);
              return const SizedBox();
            }));
    await tester.pumpWidget(owned('a', create));
    await tester
        .pumpWidget(owned('a', () => throw StateError('must not recreate')));
    expect(created, 1);
    expect(clients.first.clears, 0);
    await tester.pumpWidget(owned('b', create));
    expect(created, 2);
    expect(clients.first.events, ['unmount', 'clear']);
    expect(clients.first.queryCache.queries, isEmpty);
    await tester.pumpWidget(const SizedBox());
    expect(clients.last.events, ['unmount', 'clear']);
  });

  widgetTest('borrowed provider does not clear its client', (tester) async {
    final borrowed = _TrackedClient();
    await tester.pumpWidget(QueryClientProvider(
        client: borrowed, observeAppLifecycle: false, child: const SizedBox()));
    borrowed.setQueryData(QueryKey(['borrowed']), 1);
    await tester.pumpWidget(const SizedBox());
    expect(borrowed.clears, 0);
    expect(borrowed.queryCache.queries, hasLength(1));
    borrowed.clear();
  });

  widgetTest(
      'listener filters consecutive results without rebuilding its child',
      (tester) async {
    final key = QueryKey(['listener']);
    client.setQueryData(key, 1);
    final controller = QueryController.of<int>(
        client, QueryObserverOptions(queryKey: key, enabled: Enabled.no));
    final transitions = <(int?, int?)>[];
    final accepted = <int?>[];
    var builds = 0;
    await tester.pumpWidget(app(QueryListener<int, int>(
        controller: controller,
        listener: (_, result) => accepted.add(result.dataOrNull),
        listenWhen: (previous, next) {
          transitions.add((previous.dataOrNull, next.dataOrNull));
          return next.dataOrNull == 3;
        },
        child: Builder(builder: (_) {
          builds++;
          return const SizedBox();
        }))));
    expect(accepted, isEmpty);
    client.setQueryData(key, 2);
    client.setQueryData(key, 3);
    await tester.pump();
    expect(transitions, [(1, 2), (2, 3)]);
    expect(accepted, [3]);
    expect(builds, 1);
    await tester.pumpWidget(const SizedBox());
    expect(controller.isDisposed, isFalse);
    expect(controller.observer.hasListeners, isFalse);
    controller.dispose();
  });

  widgetTest('listener changes controller without delivering initial snapshots',
      (tester) async {
    QueryController<int, int> make(String id) {
      final key = QueryKey([id]);
      client.setQueryData(key, 1);
      return QueryController.of(client,
          QueryObserverOptions<int, int>(queryKey: key, enabled: Enabled.no));
    }

    final first = make('first');
    final second = make('second');
    final values = <int?>[];
    Widget view(QueryController<int, int> controller) =>
        app(QueryListener<int, int>(
            controller: controller,
            listener: (_, r) => values.add(r.dataOrNull),
            child: const SizedBox()));
    await tester.pumpWidget(view(first));
    await tester.pumpWidget(view(second));
    expect(first.observer.hasListeners, isFalse);
    client.setQueryData(QueryKey(['first']), 2);
    client.setQueryData(QueryKey(['second']), 3);
    await tester.pump();
    expect(values, [3]);
    await tester.pumpWidget(const SizedBox());
    client.setQueryData(QueryKey(['second']), 4);
    await tester.pump();
    expect(values, [3]);
    first.dispose();
    second.dispose();
  });

  widgetTest('listener side effects are safe when data changes during build',
      (tester) async {
    final key = QueryKey(['build']);
    client.setQueryData(key, 1);
    final controller = QueryController.of(client,
        QueryObserverOptions<int, int>(queryKey: key, enabled: Enabled.no));
    var effect = 0;
    var changed = false;
    await tester.pumpWidget(app(StatefulBuilder(
        builder: (context, setState) => QueryListener<int, int>(
            controller: controller,
            listener: (_, result) =>
                setState(() => effect = result.dataOrNull!),
            child: Builder(builder: (_) {
              if (!changed) {
                changed = true;
                client.setQueryData(key, 2);
              }
              return Text('$effect');
            })))));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  widgetTest('mutation listener observes the controller the UI executes',
      (tester) async {
    final response = Completer<int>();
    final controller = MutationController<int, String, void>(
        client, MutationOptions(mutationFn: (_) => response.future));
    final statuses = <bool>[];
    await tester.pumpWidget(app(MutationListener<int, String, void>(
        controller: controller,
        listener: (_, result) => statuses.add(result.isPending),
        child: const SizedBox())));
    expect(statuses, isEmpty);
    final future = controller.mutateAsync('save');
    await tester.pump();
    expect(statuses, [true]);
    response.complete(1);
    await tester.pump();
    expect(await future, 1);
    expect(statuses, [true, false]);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  widgetTest(
      'infinite listener follows paging transitions without owning controller',
      (tester) async {
    final controller =
        InfiniteQueryController<int, int, InfiniteData<int, int>>(
            client,
            InfiniteQueryObserverOptions(
                queryKey: QueryKey(['pages']),
                pageFn: (ctx) => ctx.pageParam,
                initialPageParam: 0,
                getNextPageParam: (_, __, param, ___) => param + 1));
    final lengths = <int>[];
    await tester
        .pumpWidget(app(InfiniteQueryListener<int, int, InfiniteData<int, int>>(
            controller: controller,
            listener: (_, result) {
              if (result.isSuccess) {
                lengths.add(result.dataOrNull!.pages.length);
              }
            },
            child: const SizedBox())));
    await tester.pump();
    final future = controller.fetchNextPage();
    await tester.pump();
    await future;
    expect(lengths.last, 2);
    await tester.pumpWidget(const SizedBox());
    expect(controller.isDisposed, isFalse);
    controller.dispose();
  });

  widgetTest('mutation state controller subscribes lazily and cleans up',
      (tester) async {
    final key = QueryKey(['mutations']);
    final states = MutationStateController<String?>(client,
        filters:
            MutationFilters(mutationKey: key, status: MutationStatus.pending),
        select: (m) => m.state.variables as String?);
    expect(client.mutationCache.hasListeners, isFalse);
    await tester.pumpWidget(app(ValueListenableBuilder<List<String?>>(
        valueListenable: states,
        builder: (_, values, __) => Text(values.join(',')))));
    final response = Completer<int>();
    final mutation = MutationController<int, String, void>(client,
        MutationOptions(mutationKey: key, mutationFn: (_) => response.future));
    final future = mutation.mutateAsync('saving');
    await tester.pump();
    expect(find.text('saving'), findsOneWidget);
    response.complete(1);
    await tester.pump();
    await future;
    expect(states.value, isEmpty);
    await tester.pumpWidget(const SizedBox());
    expect(client.mutationCache.hasListeners, isFalse);
    states.dispose();
    mutation.dispose();
  });

  widgetTest(
      'queries builder handles list changes and isolates partial failures',
      (tester) async {
    var calls = 0;
    QueryObserverOptions<int, int> options(int id) => QueryObserverOptions(
        queryKey: QueryKey(['query', id]),
        retry: RetryPolicy.never,
        queryFn: (_) {
          calls++;
          if (id == 3) throw StateError('failed');
          return id;
        });
    Widget view(List<int> ids, {QueryClient? explicitClient}) =>
        app(QueriesBuilder<int, int>(
            client: explicitClient,
            queries: ids.map(options).toList(),
            builder: (_, results) => Text(results
                .map((r) => r.isError ? 'error' : '${r.dataOrNull}')
                .join(','))));
    await tester.pumpWidget(view([1, 2]));
    await tester.pump();
    expect(find.text('1,2'), findsOneWidget);
    expect(calls, 2);
    await tester.pumpWidget(view([2, 1]));
    await tester.pump();
    expect(find.text('2,1'), findsOneWidget);
    expect(calls, 2);
    await tester.pumpWidget(view([2, 3]));
    await tester.pump();
    expect(find.text('2,error'), findsOneWidget);
    expect(
        client.queryCache.get<int>(QueryKey(['query', 1]))!.observersCount, 0);
    await tester.pumpWidget(view([]));
    expect(
        client.queryCache.queries.every((q) => q.observersCount == 0), isTrue);
    final other = QueryClient();
    await tester.pumpWidget(view([1], explicitClient: other));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    other.clear();
  });

  widgetTest(
      'queries controller shares duplicate keys with independent selections',
      (tester) async {
    final key = QueryKey(['duplicate']);
    var calls = 0;
    final first = QueryObserverOptions<int, int>(
        queryKey: key,
        queryFn: (_) {
          calls++;
          return 2;
        });
    final controller = QueriesController<int, int>(
        client, [first, first.copyWith(select: (value) => value * 10)]);
    expect(calls, 0);
    await tester.pumpWidget(app(ValueListenableBuilder<List<QueryResult<int>>>(
        valueListenable: controller,
        builder: (_, values, __) =>
            Text(values.map((r) => r.dataOrNull).join(',')))));
    await tester.pump();
    expect(find.text('2,20'), findsOneWidget);
    expect(calls, 1);
    final original = controller.observer.observers;
    controller.setQueries([first.copyWith(select: (v) => v + 1), first]);
    await tester.pump();
    expect(find.text('3,2'), findsOneWidget);
    expect(controller.observer.observers, original);
    await tester.pumpWidget(const SizedBox());
    expect(client.queryCache.get<int>(key)!.observersCount, 0);
    controller.dispose();
  });
}
