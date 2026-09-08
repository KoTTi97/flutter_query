/// Regressions found by the second external review (2026-09-09), each pinned
/// by the case that reproduced it. Binding-only; the core's are in
/// `tanstack_query_core/test/port_specifics_test.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

final key = QueryKey(<Object?>['review']);

QueryClient newClient() => QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(gcTime: GcTime.never),
        mutations: MutationDefaults(gcTime: GcTime.never),
      ),
    );

QueryObserverOptions<String, String> seeded() => QueryObserverOptions(
      queryKey: key,
      enabled: Enabled.no,
      staleTime: StaleTime.infinite,
    );

Widget app(QueryClient client, Widget child) => QueryClientProvider(
      client: client,
      observeAppLifecycle: false,
      child: MaterialApp(home: Scaffold(body: child)),
    );

class _ContextReader extends StatelessWidget {
  const _ContextReader();

  @override
  Widget build(BuildContext context) =>
      Text(context.query(seeded()).dataOrNull ?? 'none');
}

class _BuilderReader extends StatelessWidget {
  const _BuilderReader();

  @override
  Widget build(BuildContext context) => QueryBuilder<String>(
        options: seeded(),
        builder: (_, result) => Text(result.dataOrNull ?? 'none'),
      );
}

class _MixinReader extends StatefulWidget {
  const _MixinReader();

  @override
  State<_MixinReader> createState() => _MixinReaderState();
}

class _MixinReaderState extends State<_MixinReader> with QueryMixin {
  @override
  Widget build(BuildContext context) =>
      Text(watchQuery(seeded()).dataOrNull ?? 'none');
}

class _InlineMutation extends StatelessWidget {
  const _InlineMutation();

  @override
  Widget build(BuildContext context) {
    // A fresh closure every build, as any inline mutation is.
    final mutation = context.mutation<String, String, void>(
      MutationOptions(mutationFn: (v) async => v),
    );
    return TextButton(
      onPressed: () => mutation.mutate('done'),
      child: Text(mutation.value.dataOrNull ?? 'idle'),
    );
  }
}

class _TwoSelects extends StatelessWidget {
  const _TwoSelects();

  @override
  Widget build(BuildContext context) {
    final upper = context.selectQuery<String, String>(
      QueryObserverOptions(
        queryKey: key,
        enabled: Enabled.no,
        select: (v) => v.toUpperCase(),
      ),
      id: 'upper',
    );
    final reversed = context.selectQuery<String, String>(
      QueryObserverOptions(
        queryKey: key,
        enabled: Enabled.no,
        select: (v) => v.split('').reversed.join(),
      ),
      id: 'reversed',
    );
    return Text('${upper.dataOrNull}/${reversed.dataOrNull}');
  }
}

void main() {
  Future<void> withClient(
    WidgetTester tester,
    List<QueryClient> clients,
    Future<void> Function() body,
  ) async {
    try {
      await body();
    } finally {
      await tester.pumpWidget(const SizedBox());
      for (final client in clients) {
        client.clear();
      }
    }
  }

  group('F01 notifications go through the scheduler', () {
    testWidgets('late initialData in a sibling never notifies during build',
        (tester) async {
      final client = newClient();
      await withClient(tester, [client], () async {
        await tester.pumpWidget(app(
          client,
          Column(children: [
            QueryBuilder<int>(
              options: QueryObserverOptions(queryKey: key, enabled: Enabled.no),
              builder: (_, r) => Text('first:${r.dataOrNull}'),
            ),
            QueryBuilder<int>(
              options: QueryObserverOptions(
                queryKey: key,
                enabled: Enabled.no,
                initialData: const InitialData.value(1),
              ),
              builder: (_, r) => Text('second:${r.dataOrNull}'),
            ),
          ]),
        ));
        expect(tester.takeException(), isNull);
        await tester.pump();
        expect(find.text('first:1'), findsOneWidget);
        expect(find.text('second:1'), findsOneWidget);
      });
    });
  });

  group('F02 observers belong to readers, the query to the cache', () {
    testWidgets('context readers may select different types from one key',
        (tester) async {
      final client = newClient()..setQueryData<String>(key, 'abc');
      await withClient(tester, [client], () async {
        await tester.pumpWidget(app(
          client,
          Column(children: [
            const _ContextReader(),
            Builder(builder: (context) {
              final length = context.selectQuery<String, int>(
                QueryObserverOptions(
                  queryKey: key,
                  enabled: Enabled.no,
                  select: (v) => v.length,
                ),
              );
              return Text('len:${length.dataOrNull}');
            }),
          ]),
        ));
        expect(tester.takeException(), isNull);
        expect(find.text('abc'), findsOneWidget);
        expect(find.text('len:3'), findsOneWidget);
        expect(client.queryCache.get<String>(key)!.observersCount, 2);
      });
    });

    testWidgets('two selects of one key in one widget, told apart by id',
        (tester) async {
      final client = newClient()..setQueryData<String>(key, 'abc');
      await withClient(tester, [client], () async {
        await tester.pumpWidget(app(client, const _TwoSelects()));
        expect(find.text('ABC/cba'), findsOneWidget);
        // And a rebuild keeps them apart, rather than flipping selectors.
        await tester.pump();
        expect(find.text('ABC/cba'), findsOneWidget);
      });
    });

    testWidgets('a mixin reads one key with two selects, told apart by id',
        (tester) async {
      final client = newClient()..setQueryData<String>(key, 'abc');
      await withClient(tester, [client], () async {
        await tester.pumpWidget(app(client, const _MixinTwoSelects()));
        expect(find.text('ABC/cba'), findsOneWidget);
      });
    });
  });

  group('F03 a replaced provider client', () {
    for (final (name, child) in [
      ('context', const _ContextReader() as Widget),
      ('builder', const _BuilderReader()),
      ('mixin', const _MixinReader()),
    ]) {
      testWidgets('$name follows it', (tester) async {
        final a = newClient()..setQueryData<String>(key, 'A');
        final b = newClient()..setQueryData<String>(key, 'B');
        await withClient(tester, [a, b], () async {
          await tester.pumpWidget(app(a, child));
          expect(find.text('A'), findsOneWidget);

          await tester.pumpWidget(app(b, child));
          await tester.pump();
          expect(find.text('B'), findsOneWidget);
          expect(a.queryCache.get<String>(key)!.observersCount, 0);
          expect(b.queryCache.get<String>(key)!.observersCount, 1);
        });
      });
    }
  });

  group('F06 mutation identity', () {
    testWidgets('an inline mutation survives its own result rebuild',
        (tester) async {
      final client = newClient();
      await withClient(tester, [client], () async {
        await tester.pumpWidget(app(client, const _InlineMutation()));
        await tester.tap(find.byType(TextButton));
        await tester.pump();
        await tester.pump();
        expect(find.text('done'), findsOneWidget);
        expect(client.mutationCache.mutations, hasLength(1));
      });
    });
  });

  group('F08 / F09 controller lifetimes', () {
    testWidgets('disposing an unlistened MutationController detaches it',
        (tester) async {
      final client = newClient();
      final mutation = MutationController<int, int, void>(
        client,
        MutationOptions(mutationFn: (v) => v),
      );
      try {
        await mutation.mutateAsync(1);
        expect(client.mutationCache.mutations.single.observers, hasLength(1));
        mutation.dispose();
        expect(client.mutationCache.mutations.single.observers, isEmpty);
      } finally {
        client.clear();
        await tester.pump();
      }
    });

    testWidgets(
        'a listener that leaves inside its first notification unsubscribes',
        (tester) async {
      final client = newClient()
        // Delivered on the spot, as the provider's scheduler does outside a
        // build; the reentrant path needs the notification to land while
        // `subscribe` is still on the stack.
        ..notifyManager.setScheduler((callback) => callback());
      final controller = QueryController<int, int>(
        client,
        QueryObserverOptions(queryKey: key, enabled: Enabled.no),
      );
      // Attach once and let go, then change the data behind the detached
      // observer: the next subscribe finds a changed result and notifies
      // synchronously.
      void noop() {}
      controller
        ..addListener(noop)
        ..removeListener(noop);
      client.setQueryData<int>(key, 5);

      late VoidCallback listener;
      listener = () => controller.removeListener(listener);
      try {
        controller.addListener(listener);
        expect(controller.observer.hasListeners, isFalse);
        expect(client.queryCache.get<int>(key)!.observersCount, 0);
      } finally {
        controller.dispose();
        client.clear();
        await tester.pump();
      }
    });
  });

  group('F10 initial lifecycle state', () {
    testWidgets('a provider mounted in a hidden app starts unfocused',
        (tester) async {
      final client = newClient();
      try {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pumpWidget(
          QueryClientProvider(client: client, child: const SizedBox()),
        );
        // A hidden app produces no frames, so nothing has mounted yet; force
        // one, as an embedder that keeps rendering while hidden would.
        tester.binding.scheduleForcedFrame();
        await tester.pump();
        expect(find.byType(QueryClientProvider), findsOneWidget);
        expect(client.focusManager.isFocused(), isFalse);

        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        expect(client.focusManager.isFocused(), isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox());
        client.clear();
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
    });
  });

  group('buildWhen', () {
    testWidgets('skips rebuilds the builder does not care about',
        (tester) async {
      final client = newClient()..setQueryData<String>(key, 'a');
      var builds = 0;
      await withClient(tester, [client], () async {
        await tester.pumpWidget(app(
          client,
          QueryBuilder<String>(
            options: seeded(),
            buildWhen: (previous, current) =>
                previous.dataOrNull != current.dataOrNull,
            builder: (_, result) {
              builds++;
              return Text(result.dataOrNull ?? 'none');
            },
          ),
        ));
        expect(builds, 1);

        // Metadata only: the result changes (`isStale`), the data does not.
        await client.invalidateQueries(
          filters: QueryFilters(queryKey: key),
          refetchType: RefetchType.none,
        );
        await tester.pump();
        expect(builds, 1);

        client.setQueryData<String>(key, 'b');
        await tester.pump();
        expect(builds, 2);
        expect(find.text('b'), findsOneWidget);
      });
    });
  });
}

class _MixinTwoSelects extends StatefulWidget {
  const _MixinTwoSelects();

  @override
  State<_MixinTwoSelects> createState() => _MixinTwoSelectsState();
}

class _MixinTwoSelectsState extends State<_MixinTwoSelects> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final upper = watchSelectQuery<String, String>(
      QueryObserverOptions(
        queryKey: key,
        enabled: Enabled.no,
        select: (v) => v.toUpperCase(),
      ),
      id: 'upper',
    );
    final reversed = watchSelectQuery<String, String>(
      QueryObserverOptions(
        queryKey: key,
        enabled: Enabled.no,
        select: (v) => v.split('').reversed.join(),
      ),
      id: 'reversed',
    );
    return Text('${upper.dataOrNull}/${reversed.dataOrNull}');
  }
}
