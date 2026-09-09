/// Regressions found by the second, third and fourth external reviews
/// (2026-09-09), each pinned by the case that reproduced it. Binding-only; the
/// core's are in `tanstack_query_core/test/port_specifics_test.dart`.
library;

import 'dart:async';

// The core reads staleness from `package:clock`, so shifting that clock is
// how a test makes data go stale between two reads.
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

  // ---------------------------------------------------------------------------
  // Third review, 2026-09-09.

  group('B1 the bootstrap build', () {
    testWidgets(
        'a sibling initialData notifies after the first build, not in it',
        (tester) async {
      final client = newClient();
      await withClient(tester, [client], () async {
        final root = app(
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
        );
        // What `runApp` does: `Timer.run(() => attachRootWidget(…))`, whose
        // `RootWidget.attach` runs `buildScope` synchronously — in
        // `SchedulerPhase.idle`, the one build no phase accounts for. The
        // test binding already owns a root element, so the same `buildScope`
        // is run by hand, still in `idle`.
        expect(SchedulerBinding.instance.schedulerPhase, SchedulerPhase.idle);
        tester.binding
            .attachRootWidget(tester.binding.wrapWithDefaultView(root));
        tester.binding.buildOwner!.buildScope(tester.binding.rootElement!);
        expect(tester.takeException(), isNull);

        await tester.pump();
        expect(find.text('first:1'), findsOneWidget);
        expect(find.text('second:1'), findsOneWidget);
      });
    });
  });

  group('B2 a select returning a fresh but equal value', () {
    testWidgets('does not rebuild a context reader every frame',
        (tester) async {
      final client = newClient()..setQueryData<List<int>>(key, [1, 2, 3, 4]);
      final builds = <int>[];
      await withClient(tester, [client], () async {
        await tester.pumpWidget(app(client, _R3ListSelect(builds)));
        // One kick from outside — a parent rebuild, as any real screen has;
        // this used to start a rebuild on every frame, for good.
        await tester.pumpWidget(app(client, _R3ListSelect(builds)));
        final after = builds.length;
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(builds.length, after);
        expect(find.text('[2, 4]'), findsOneWidget);
      });
    });

    testWidgets('does not rebuild a mixin reader every frame', (tester) async {
      final client = newClient()..setQueryData<List<int>>(key, [1, 2, 3, 4]);
      final builds = <int>[];
      await withClient(tester, [client], () async {
        await tester.pumpWidget(app(client, _R3MixinListSelect(builds)));
        await tester.pumpWidget(app(client, _R3MixinListSelect(builds)));
        final after = builds.length;
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(builds.length, after);
      });
    });
  });

  group('M7 collisions without id', () {
    testWidgets('two selects of one key in one build are caught',
        (tester) async {
      final client = newClient()..setQueryData<String>(key, 'Ab');
      await withClient(tester, [client], () async {
        await tester.pumpWidget(app(client, const _R3TwoSelectsNoId()));
        expect(tester.takeException(), isA<FlutterError>());
      });
    });

    testWidgets('two mutations of one shape in one build are caught',
        (tester) async {
      final client = newClient();
      await withClient(tester, [client], () async {
        await tester.pumpWidget(app(client, const _R3TwoMutationsNoId()));
        expect(tester.takeException(), isA<FlutterError>());
        // With ids, the same widget is fine.
        await tester.pumpWidget(
          app(client, const _R3TwoMutationsNoId(withIds: true)),
        );
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('M4 the mixin releases a key it stopped reading', () {
    testWidgets('and its stale queryFn never runs again', (tester) async {
      final client = newClient();
      final fetched = <String>[];
      Future<String> fetch(String id) async {
        fetched.add(id);
        return 'Sensor $id';
      }

      await withClient(tester, [client], () async {
        await tester.pumpWidget(app(client, _R3MixinById('a', fetch)));
        await tester.pump();
        expect(find.text('Sensor a'), findsOneWidget);

        await tester.pumpWidget(app(client, _R3MixinById('b', fetch)));
        await tester.pump();
        await tester.pump();
        expect(find.text('Sensor b'), findsOneWidget);

        final a = client.queryCache.get<String>(QueryKey(<Object?>['m4', 'a']));
        expect(a!.observersCount, 0);

        // The old observer's `queryFn` closed over `widget.id` — which is
        // now 'b'. Left alive, a refetch of key 'a' would have fetched 'b'
        // and written "Sensor b" into a's cache entry.
        fetched.clear();
        await client.invalidateQueries(
          filters: QueryFilters(queryKey: QueryKey(<Object?>['m4', 'a'])),
        );
        await tester.pump();
        expect(fetched, isEmpty);
        expect(a.state.data, 'Sensor a');
      });
    });
  });

  group('M5 lifecycle transitions', () {
    testWidgets('detached → resumed focuses the client', (tester) async {
      final client = newClient();
      await withClient(tester, [client], () async {
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.detached);
        await tester.pumpWidget(
          QueryClientProvider(client: client, child: const SizedBox()),
        );
        tester.binding.scheduleForcedFrame();
        await tester.pump();
        expect(client.focusManager.isFocused(), isFalse);

        // Neither `onShow` nor `onHide`: only `onResume` fires for this one.
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(client.focusManager.isFocused(), isTrue);
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  });

  group('M6 a new onlineStatus stream per build', () {
    testWidgets('rebinds the subscription and nothing else', (tester) async {
      final client = newClient();
      var listens = 0;
      Stream<bool> status() {
        late StreamController<bool> controller;
        controller = StreamController<bool>(onListen: () {
          listens++;
          controller.add(false);
        });
        return controller.stream;
      }

      Widget build() => QueryClientProvider(
            client: client,
            onlineStatus: status(),
            child: const SizedBox(),
          );
      await withClient(tester, [client], () async {
        await tester.pumpWidget(build());
        await tester.pump();
        expect(client.onlineManager.isOnline(), isFalse);

        // A remount would re-read the lifecycle state and refocus the client;
        // rebinding just the stream leaves it alone.
        client.focusManager.setFocused(false);
        await tester.pumpWidget(build());
        await tester.pumpWidget(build());
        await tester.pump();
        expect(listens, 3);
        expect(client.focusManager.isFocused(), isFalse);
        expect(client.onlineManager.isOnline(), isFalse);
      });
    });
  });

  group('buildWhen on every builder', () {
    testWidgets('InfiniteQueryBuilder and MutationBuilder take one',
        (tester) async {
      final client = newClient();
      var feedBuilds = 0;
      var mutationBuilds = 0;
      await withClient(tester, [client], () async {
        await tester.pumpWidget(app(
          client,
          Column(children: [
            InfiniteQueryBuilder<int, int, InfiniteData<int, int>>(
              options: InfiniteQueryObserverOptions(
                queryKey: key,
                initialPageParam: 0,
                pageFn: (context) async => context.pageParam,
                getNextPageParam: (page, pages, param, params) => param + 1,
              ),
              // Only the page count matters to this widget.
              buildWhen: (previous, current) =>
                  previous.dataOrNull?.pages.length !=
                  current.dataOrNull?.pages.length,
              builder: (_, feed) {
                feedBuilds++;
                return Text('pages:${feed.value.dataOrNull?.pages.length}');
              },
            ),
            MutationBuilder<int, int, void>(
              options: MutationOptions(mutationFn: (v) async => v),
              buildWhen: (previous, current) => current.isSuccess,
              builder: (_, mutation) {
                mutationBuilds++;
                return TextButton(
                  onPressed: () => mutation.mutate(1),
                  child: Text('m:${mutation.value.dataOrNull}'),
                );
              },
            ),
          ]),
        ));
        await tester.pump();
        expect(find.text('pages:1'), findsOneWidget);
        final feedAfterFirstPage = feedBuilds;

        // A refetch of the held page changes the result (`dataUpdatedAt`)
        // but not the page count.
        await client.refetchQueries(filters: QueryFilters(queryKey: key));
        await tester.pump();
        expect(feedBuilds, feedAfterFirstPage);

        await tester.tap(find.byType(TextButton));
        await tester.pump(); // pending: skipped
        await tester.pump(); // success: built
        expect(find.text('m:1'), findsOneWidget);
        expect(mutationBuilds, 2);
      });
    });
  });

  group('release-mode-safe errors', () {
    testWidgets('a missing provider is a FlutterError, not a null check',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _ContextReader()));
      expect(tester.takeException(), isA<FlutterError>());
      await tester.pumpWidget(MaterialApp(
        home: QueryBuilder<String>(
          options: seeded(),
          builder: (_, r) => const SizedBox(),
        ),
      ));
      expect(tester.takeException(), isA<FlutterError>());
    });

    testWidgets('plain options on an infinite controller are refused',
        (tester) async {
      final client = newClient();
      final controller =
          InfiniteQueryController<int, int, InfiniteData<int, int>>(
        client,
        InfiniteQueryObserverOptions(
          queryKey: key,
          initialPageParam: 0,
          pageFn: (context) async => context.pageParam,
          getNextPageParam: (page, pages, param, params) => null,
        ),
      );
      expect(
        () => controller.setOptions(
          QueryObserverOptions<InfiniteData<int, int>, InfiniteData<int, int>>(
            queryKey: key,
          ),
        ),
        throwsUnsupportedError,
      );
      controller.dispose();
      client.clear();
    });
  });

  // ---------------------------------------------------------------------------
  // Fourth review, 2026-09-09.

  group('B2 a single-subscription onlineStatus stream', () {
    testWidgets('survives a client switch, which inherits the last value',
        (tester) async {
      final a = newClient();
      final b = newClient();
      // Not broadcast: a second `listen` would throw.
      final online = StreamController<bool>();
      await withClient(tester, [a, b], () async {
        await tester.pumpWidget(_provided(a, online.stream));
        online.add(false);
        await tester.pump();
        expect(a.onlineManager.isOnline(), isFalse);

        await tester.pumpWidget(_provided(b, online.stream));
        expect(tester.takeException(), isNull);
        // The stream will not repeat itself for the newcomer.
        expect(b.onlineManager.isOnline(), isFalse);

        online.add(true);
        await tester.pump();
        expect(b.onlineManager.isOnline(), isTrue);
        expect(a.onlineManager.isOnline(), isFalse);
      });
      unawaited(online.close());
    });
  });

  group('B3 the first build is the only build', () {
    testWidgets('until the result actually changes, in all three styles',
        (tester) async {
      final client = newClient();
      final builds = <String>[];
      final fetches = <String, Completer<String>>{};
      QueryObserverOptions<String, String> pending(String id) =>
          QueryObserverOptions(
            queryKey: QueryKey(<Object?>['r4', id]),
            queryFn: (_) =>
                fetches.putIfAbsent(id, Completer<String>.new).future,
          );
      await withClient(tester, [client], () async {
        await tester.pumpWidget(app(
          client,
          Column(children: [
            QueryBuilder<String>(
              options: pending('builder'),
              builder: (_, r) {
                builds.add('builder:${r.dataOrNull}');
                return const SizedBox();
              },
            ),
            _R4ContextReader(pending('context'), builds),
            _R4MixinReader(pending('mixin'), builds),
          ]),
        ));
        for (var i = 0; i < 3; i++) {
          await tester.pump();
        }
        // The subscribe started the fetch, the build read `fetching`, and the
        // observer's notification about that very fetch has nothing to add.
        expect(builds, ['builder:null', 'context:null', 'mixin:null']);

        for (final fetch in fetches.values) {
          fetch.complete('ok');
        }
        // Completed from outside a frame, the result reaches the widgets on
        // the frame after the one that runs the completion's microtasks.
        await tester.pumpAndSettle();
        expect(builds, [
          'builder:null',
          'context:null',
          'mixin:null',
          'builder:ok',
          'context:ok',
          'mixin:ok',
        ]);
      });
    });
  });

  group('B5 one mutationKey, two type triples', () {
    for (final (name, widget) in [
      ('context', const _R4KeyedMutations()),
      ('mixin', const _R4MixinKeyedMutations()),
    ]) {
      testWidgets('$name gets two controllers, not a failed cast',
          (tester) async {
        final client = newClient();
        await withClient(tester, [client], () async {
          await tester.pumpWidget(app(client, widget));
          expect(tester.takeException(), isNull);
          expect(find.text('distinct'), findsOneWidget);
        });
      });
    }
  });

  group('B6 staleness flipping between two reads of one key', () {
    for (final (name, widget) in [
      ('context', const _R4StaleBetweenReads()),
      ('mixin', const _R4MixinStaleBetweenReads()),
    ]) {
      testWidgets('$name is not mistaken for two selects', (tester) async {
        final client = newClient()..setQueryData<String>(key, 'x');
        await withClient(tester, [client], () async {
          await tester.pumpWidget(app(client, widget));
          expect(tester.takeException(), isNull);
          expect(find.text('false/true'), findsOneWidget);
        });
      });
    }
  });

  group('B8 a mutation the widget stopped reading', () {
    for (final (name, build) in [
      ('context', _R4MutationById.new),
      ('mixin', _R4MixinMutationById.new),
    ]) {
      testWidgets('$name releases it after the frame, like a query',
          (tester) async {
        final client = newClient();
        final seen = <MutationController<Object?, Object?, Object?>>[];
        await withClient(tester, [client], () async {
          await tester.pumpWidget(app(client, build('a', seen)));
          await tester.pumpWidget(app(client, build('b', seen)));
          await tester.pump();
          expect(seen, hasLength(2));
          expect(seen[0], isNot(same(seen[1])));
          expect(seen[0].isDisposed, isTrue);
          expect(seen[1].isDisposed, isFalse);
        });
      });
    }
  });

  group('A-24 QueryClientProvider.maybeOf', () {
    testWidgets('is the client, or null without a provider', (tester) async {
      final client = newClient();
      QueryClient? found;
      Widget probe() => Builder(builder: (context) {
            found = QueryClientProvider.maybeOf(context);
            return const SizedBox();
          });
      await withClient(tester, [client], () async {
        await tester.pumpWidget(MaterialApp(home: probe()));
        expect(found, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(app(client, probe()));
        expect(found, same(client));
      });
    });
  });

  group('A-25 a controller read before anyone listens', () {
    test('reports the optimistic result, as a first build would', () {
      final client = newClient();
      final controller = QueryController.of<String>(
        client,
        QueryObserverOptions(
          queryKey: key,
          queryFn: (_) => Completer<String>().future,
        ),
      );
      expect(controller.value.fetchStatus, FetchStatus.fetching);
      expect(
          controller.observer.currentQuery.state.fetchStatus, FetchStatus.idle);
      void listener() {}
      controller.addListener(listener);
      expect(controller.value.fetchStatus, FetchStatus.fetching);
      controller.removeListener(listener);
      controller.dispose();
      client.clear();
    });

    test('a query that will not fetch stays idle', () {
      final client = newClient();
      final controller = QueryController.of<String>(
        client,
        QueryObserverOptions(queryKey: key, enabled: Enabled.no),
      );
      expect(controller.value.fetchStatus, FetchStatus.idle);
      controller.dispose();
      client.clear();
    });

    test('the infinite controller agrees', () {
      final client = newClient();
      final controller =
          InfiniteQueryController<int, int, InfiniteData<int, int>>(
        client,
        InfiniteQueryObserverOptions(
          queryKey: key,
          initialPageParam: 0,
          pageFn: (context) => Completer<int>().future,
          getNextPageParam: (page, pages, param, params) => null,
        ),
      );
      expect(controller.value.fetchStatus, FetchStatus.fetching);
      controller.dispose();
      client.clear();
    });
  });

  // The API decisions that followed the fourth review (the core's
  // PORTING_NOTES, "API decisions (fourth review)"), the binding's share.

  group('A3 InfiniteQueryController.setOptions', () {
    test('accepts options that carry the paging behaviour', () async {
      final client = newClient();
      InfiniteQueryObserverOptions<int, int, InfiniteData<int, int>> options(
        int? Function(int page, List<int> pages, int param, List<int> params)
            next,
      ) =>
          InfiniteQueryObserverOptions(
            queryKey: key,
            initialPageParam: 0,
            pageFn: (context) async => context.pageParam,
            getNextPageParam: next,
          );
      final controller =
          InfiniteQueryController<int, int, InfiniteData<int, int>>(
        client,
        options((_, __, ___, ____) => null),
      );
      void listener() {}
      controller.addListener(listener);
      await pumpEventQueue();
      expect(controller.value.dataOrNull?.pages, <int>[0]);
      expect(controller.hasNextPage, isFalse);

      // Plain observer options that carry the paging behaviour — what the
      // core's own conversion produces, and the only public holder of an
      // `InfiniteQueryBehavior` is an `InfiniteQueryOptions`, so the test
      // reaches for the core's internal conversion to build them.
      int? next(int _, List<int> __, int param, List<int> ___) => param + 1;
      // ignore: invalid_use_of_internal_member
      final paged = client.infiniteObserverOptions(options(next));
      controller.setOptions(paged);
      expect(controller.hasNextPage, isTrue);
      await controller.fetchNextPage();
      expect(controller.value.dataOrNull?.pages, <int>[0, 1]);

      controller.removeListener(listener);
      // Read before anyone listens again: the optimistic value comes through
      // the plain options now.
      expect(controller.value.dataOrNull?.pages, <int>[0, 1]);
      controller.dispose();
      client.clear();
    });
  });

  group('A21 MutationOptions.simple', () {
    testWidgets('infers both types from mutationFn under strict inference',
        (tester) async {
      final client = newClient();
      final seen = <Object?>[];
      await tester.pumpWidget(app(client, _A21Reader(seen)));
      expect(seen.single, isA<MutationController<int, String, void>>());
      (seen.single as MutationController<int, String, void>).mutate('four');
      await tester.pump();
      expect(find.text('4'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      client.clear();
    });
  });
}

class _A21Reader extends StatelessWidget {
  const _A21Reader(this.seen);

  final List<Object?> seen;

  @override
  Widget build(BuildContext context) {
    // No type arguments anywhere: `simple` fixes the third to `void`, and
    // `mutationFn` supplies the other two.
    final add = context.mutation(
      MutationOptions.simple(mutationFn: (String v) async => v.length),
    );
    if (seen.isEmpty) {
      seen.add(add);
    }
    return Text('${add.value.dataOrNull}');
  }
}

Widget _provided(QueryClient client, Stream<bool> online) =>
    QueryClientProvider(
      client: client,
      observeAppLifecycle: false,
      onlineStatus: online,
      child: const SizedBox(),
    );

class _R4ContextReader extends StatelessWidget {
  const _R4ContextReader(this.options, this.builds);

  final QueryObserverOptions<String, String> options;
  final List<String> builds;

  @override
  Widget build(BuildContext context) {
    builds.add('context:${context.query(options).dataOrNull}');
    return const SizedBox();
  }
}

class _R4MixinReader extends StatefulWidget {
  const _R4MixinReader(this.options, this.builds);

  final QueryObserverOptions<String, String> options;
  final List<String> builds;

  @override
  State<_R4MixinReader> createState() => _R4MixinReaderState();
}

class _R4MixinReaderState extends State<_R4MixinReader> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    widget.builds.add('mixin:${watchQuery(widget.options).dataOrNull}');
    return const SizedBox();
  }
}

MutationOptions<String, String, void> _renameKeyed() =>
    MutationOptions(mutationKey: key, mutationFn: (v) async => v);

MutationOptions<int, int, void> _countKeyed() =>
    MutationOptions(mutationKey: key, mutationFn: (v) async => v);

class _R4KeyedMutations extends StatelessWidget {
  const _R4KeyedMutations();

  @override
  Widget build(BuildContext context) {
    final rename = context.mutation(_renameKeyed());
    final count = context.mutation(_countKeyed());
    return Text(identical(rename, count) ? 'shared' : 'distinct');
  }
}

class _R4MixinKeyedMutations extends StatefulWidget {
  const _R4MixinKeyedMutations();

  @override
  State<_R4MixinKeyedMutations> createState() => _R4MixinKeyedMutationsState();
}

class _R4MixinKeyedMutationsState extends State<_R4MixinKeyedMutations>
    with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final rename = watchMutation(_renameKeyed());
    final count = watchMutation(_countKeyed());
    return Text(identical(rename, count) ? 'shared' : 'distinct');
  }
}

/// Fresh for a second, and never fetched: the two reads differ only in what
/// the clock says.
QueryObserverOptions<String, String> _shortlyStale() => QueryObserverOptions(
      queryKey: key,
      queryFn: (_) => Completer<String>().future,
      refetchOnMount: RefetchOn.never,
      staleTime: const StaleTime.duration(Duration(seconds: 1)),
    );

/// The second read happens "a moment later" — past the stale time.
T _later<T>(T Function() read) => withClock(
      Clock.fixed(clock.now().add(const Duration(seconds: 2))),
      read,
    );

class _R4StaleBetweenReads extends StatelessWidget {
  const _R4StaleBetweenReads();

  @override
  Widget build(BuildContext context) {
    final first = context.query(_shortlyStale());
    final second = _later(() => context.query(_shortlyStale()));
    return Text('${first.isStale}/${second.isStale}');
  }
}

class _R4MixinStaleBetweenReads extends StatefulWidget {
  const _R4MixinStaleBetweenReads();

  @override
  State<_R4MixinStaleBetweenReads> createState() =>
      _R4MixinStaleBetweenReadsState();
}

class _R4MixinStaleBetweenReadsState extends State<_R4MixinStaleBetweenReads>
    with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final first = watchQuery(_shortlyStale());
    final second = _later(() => watchQuery(_shortlyStale()));
    return Text('${first.isStale}/${second.isStale}');
  }
}

MutationOptions<String, String, void> _plain() =>
    MutationOptions(mutationFn: (v) async => v);

class _R4MutationById extends StatelessWidget {
  const _R4MutationById(this.id, this.seen);

  final String id;
  final List<MutationController<Object?, Object?, Object?>> seen;

  @override
  Widget build(BuildContext context) {
    final mutation = context.mutation(_plain(), id: id);
    if (!seen.contains(mutation)) {
      seen.add(mutation);
    }
    return const SizedBox();
  }
}

class _R4MixinMutationById extends StatefulWidget {
  const _R4MixinMutationById(this.id, this.seen);

  final String id;
  final List<MutationController<Object?, Object?, Object?>> seen;

  @override
  State<_R4MixinMutationById> createState() => _R4MixinMutationByIdState();
}

class _R4MixinMutationByIdState extends State<_R4MixinMutationById>
    with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final mutation = watchMutation(_plain(), id: widget.id);
    if (!widget.seen.contains(mutation)) {
      widget.seen.add(mutation);
    }
    return const SizedBox();
  }
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

class _R3ListSelect extends StatelessWidget {
  const _R3ListSelect(this.builds);

  final List<int> builds;

  @override
  Widget build(BuildContext context) {
    builds.add(builds.length);
    final evens = context.selectQuery<List<int>, List<int>>(
      QueryObserverOptions(
        queryKey: key,
        enabled: Enabled.no,
        // The canonical selector: a fresh list every call.
        select: (list) => list.where((e) => e.isEven).toList(),
      ),
    );
    return Text('${evens.dataOrNull}');
  }
}

class _R3MixinListSelect extends StatefulWidget {
  const _R3MixinListSelect(this.builds);

  final List<int> builds;

  @override
  State<_R3MixinListSelect> createState() => _R3MixinListSelectState();
}

class _R3MixinListSelectState extends State<_R3MixinListSelect>
    with QueryMixin {
  @override
  Widget build(BuildContext context) {
    widget.builds.add(widget.builds.length);
    final evens = watchSelectQuery<List<int>, List<int>>(
      QueryObserverOptions(
        queryKey: key,
        enabled: Enabled.no,
        select: (list) => list.where((e) => e.isEven).toList(),
      ),
    );
    return Text('${evens.dataOrNull}');
  }
}

class _R3TwoSelectsNoId extends StatelessWidget {
  const _R3TwoSelectsNoId();

  @override
  Widget build(BuildContext context) {
    final upper = context.selectQuery<String, String>(QueryObserverOptions(
      queryKey: key,
      enabled: Enabled.no,
      select: (v) => v.toUpperCase(),
    ));
    final lower = context.selectQuery<String, String>(QueryObserverOptions(
      queryKey: key,
      enabled: Enabled.no,
      select: (v) => v.toLowerCase(),
    ));
    return Text('${upper.dataOrNull}/${lower.dataOrNull}');
  }
}

class _R3TwoMutationsNoId extends StatelessWidget {
  const _R3TwoMutationsNoId({this.withIds = false});

  final bool withIds;

  @override
  Widget build(BuildContext context) {
    final archive = context.mutation<String, String, void>(
      MutationOptions(mutationFn: (v) async => 'archived $v'),
      id: withIds ? 'archive' : null,
    );
    final delete = context.mutation<String, String, void>(
      MutationOptions(mutationFn: (v) async => 'deleted $v'),
      id: withIds ? 'delete' : null,
    );
    return Text('${archive.value.dataOrNull}/${delete.value.dataOrNull}');
  }
}

class _R3MixinById extends StatefulWidget {
  const _R3MixinById(this.id, this.fetch);

  final String id;
  final Future<String> Function(String id) fetch;

  @override
  State<_R3MixinById> createState() => _R3MixinByIdState();
}

class _R3MixinByIdState extends State<_R3MixinById> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final sensor = watchQuery(QueryObserverOptions<String, String>(
      queryKey: QueryKey(<Object?>['m4', widget.id]),
      // Closes over the widget, as real code does.
      queryFn: (_) => widget.fetch(widget.id),
    ));
    return Text(sensor.dataOrNull ?? 'none');
  }
}
