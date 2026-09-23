/// Regressions found by the second, third and fourth external reviews
/// (2026-09-09), by the fifth and sixth (2026-09-10) and by the ninth
/// (2026-09-10, consolidated 2026-09-11), each pinned by the case that
/// reproduced it. Binding-only; the core's are in
/// `query_kit/test/port_specifics_test.dart`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// The core reads staleness from `package:clock`, so shifting that clock is
// how a test makes data go stale between two reads.
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';

final key = QueryKey(<Object?>['review']);

QueryClient newClient() => QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(gcTime: GcTime.never),
        mutations: MutationDefaults(gcTime: GcTime.never),
      ),
    );

QueryObserverOptions<String> seeded() => QueryObserverOptions(
      queryKey: key,
      enabled: Enabled.no,
      staleTime: StaleTime.infinite,
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
      QuerySelectOptions(
        queryKey: key,
        enabled: Enabled.no,
        select: (v) => v.toUpperCase(),
      ),
      id: 'upper',
    );
    final reversed = context.selectQuery<String, String>(
      QuerySelectOptions(
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
  // ---- fifth and sixth reviews (2026-09-10) --------------------------------

  group('R01 an overridden queryClient that changes with the widget', () {
    queryWidgetTest('the mixin follows it across a plain widget update',
        (tester, a) async {
      final b =
          tester.adopt(QueryClient()..setQueryData<String>(key, 'from B'));
      await tester.pumpWidget(app(a, _R01Override(a)));
      await tester.pumpAndSettle();
      expect(find.text('from A'), findsOneWidget);

      // Only `widget.client` changes: not a dependency change, so
      // `didChangeDependencies` never runs and the client is reconciled at
      // the next read instead.
      await tester.pumpWidget(app(a, _R01Override(b)));
      await tester.pumpAndSettle();
      expect(find.text('from B'), findsOneWidget);
      expect(
        b.queryCache.find(filters: QueryFilters(queryKey: key))!.observersCount,
        1,
      );
      expect(
        a.queryCache.find(filters: QueryFilters(queryKey: key))!.observersCount,
        0,
      );
    }, createClient: () => QueryClient()..setQueryData<String>(key, 'from A'));

    testWidgets('a State that reads nothing needs no provider', (tester) async {
      await tester.pumpWidget(const _R01Bare());
      expect(tester.takeException(), isNull);
      expect(find.text('nothing read'), findsOneWidget);
    });
  });

  group('R02 an infinite query switching direction', () {
    queryWidgetTest('the builder sees it, though the result is unchanged',
        (tester, client) async {
      final gates = <int, Completer<String>>{};
      InfiniteQueryController<String, int, InfiniteData<String, int>>? ctl;
      String? shown;
      await tester.pumpWidget(app(
        client,
        InfiniteQueryBuilder<String, int, InfiniteData<String, int>>(
          options: InfiniteQueryObserverOptions(
            queryKey: key,
            pageFn: (context) =>
                (gates[context.pageParam] ??= Completer<String>()).future,
            initialPageParam: 0,
            getNextPageParam: (_, __, last, ___) => last + 1,
            getPreviousPageParam: (_, __, first, ___) => first - 1,
          ),
          builder: (_, q) {
            ctl = q;
            shown = 'next=${q.isFetchingNextPage} '
                'prev=${q.isFetchingPreviousPage}';
            return Text(shown!);
          },
        ),
      ));
      await tester.pump();
      gates[0]!.complete('page 0');
      await tester.pumpAndSettle();

      unawaited(ctl!.fetchNextPage());
      await tester.pump();
      expect(shown, 'next=true prev=false');

      // The pages held do not change, so the `QueryResult` does not either:
      // the direction lives on the controller, and comparing results alone
      // left the widget showing the old one.
      unawaited(ctl!.fetchPreviousPage());
      await tester.pump();
      expect(shown, 'next=false prev=true');

      for (final gate in gates.values) {
        if (!gate.isCompleted) {
          gate.complete('page');
        }
      }
      await tester.pumpAndSettle();
    });
  });

  group('R04 a GlobalKey subtree that moves', () {
    queryWidgetTest('keeps the running mutation the widget started',
        (tester, client) async {
      final gate = Completer<int>();
      final globalKey = GlobalKey();
      Widget tree({required bool right}) => app(
            client,
            Row(children: <Widget>[
              Expanded(
                child: right
                    ? const SizedBox()
                    : _R04Box(key: globalKey, gate: gate),
              ),
              Expanded(
                child: right
                    ? _R04Box(key: globalKey, gate: gate)
                    : const SizedBox(),
              ),
            ]),
          );
      await tester.pumpWidget(tree(right: false));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.text('pending=true data=null'), findsOneWidget);

      // Flutter deactivates the element and reactivates it in the same
      // frame. Treating `removeDependent` as the end of the reader threw
      // the observation away and the answer never arrived.
      await tester.pumpWidget(tree(right: true));
      await tester.pump();
      expect(find.text('pending=true data=null'), findsOneWidget);

      gate.complete(7);
      await tester.pumpAndSettle();
      expect(find.text('pending=false data=7'), findsOneWidget);
    });
  });

  group('R06 two providers on one client', () {
    queryWidgetTest('the scheduler survives the first of them leaving',
        (tester, client) async {
      final original = client.notifyManager.scheduler;
      Widget both({required bool first, required bool second}) =>
          Directionality(
            textDirection: TextDirection.ltr,
            child: Column(children: <Widget>[
              if (first)
                QueryClientProvider(
                  client: client,
                  observeAppLifecycle: false,
                  child: const SizedBox(),
                )
              else
                const SizedBox(),
              if (second)
                QueryClientProvider(
                  client: client,
                  observeAppLifecycle: false,
                  child: const SizedBox(),
                )
              else
                const SizedBox(),
            ]),
          );
      await tester.pumpWidget(both(first: true, second: true));
      expect(client.notifyManager.scheduler, isNot(original));

      // Lifetimes that overlap without nesting: a per-provider save and
      // restore put the original back while the second was still running.
      await tester.pumpWidget(both(first: false, second: true));
      expect(client.notifyManager.scheduler, isNot(original));

      await tester.pumpWidget(both(first: false, second: false));
      expect(client.notifyManager.scheduler, same(original));
    });
  });

  group('R07 a connectivity stream that is taken away', () {
    queryWidgetTest('does not pin a later client offline',
        (tester, first) async {
      final second = tester.adopt(QueryClient());
      final online = StreamController<bool>.broadcast();
      await tester.pumpWidget(QueryClientProvider(
        client: first,
        observeAppLifecycle: false,
        onlineStatus: OnlineStatus.stream(online.stream, initial: true),
        child: const SizedBox(),
      ));
      online.add(false);
      await tester.pump();
      expect(first.onlineManager.isOnline(), isFalse);

      await tester.pumpWidget(QueryClientProvider(
        client: first,
        observeAppLifecycle: false,
        child: const SizedBox(),
      ));
      await tester.pump();

      // Nothing is listening any more, so nothing could put a client back
      // online: what the old stream last said must not follow the new one.
      await tester.pumpWidget(QueryClientProvider(
        client: second,
        observeAppLifecycle: false,
        child: const SizedBox(),
      ));
      await tester.pump();
      expect(second.onlineManager.isOnline(), isTrue);
      await online.close();
    });

    queryWidgetTest(
        'OnlineStatus.stream\'s initial answers what a Stream '
        'cannot', (tester, client) async {
      final online = StreamController<bool>.broadcast();
      await tester.pumpWidget(QueryClientProvider(
        client: client,
        observeAppLifecycle: false,
        onlineStatus: OnlineStatus.stream(online.stream, initial: false),
        child: const SizedBox(),
      ));
      // Before the stream has said anything at all.
      expect(client.onlineManager.isOnline(), isFalse);
      online.add(true);
      await tester.pump();
      expect(client.onlineManager.isOnline(), isTrue);
      await online.close();
    });
  });

  group('R08 the desktop reading of AppLifecycleState.inactive', () {
    queryWidgetTest('a window losing focus is a focus event on desktop',
        (tester, client) async {
      // Reset inside the body: the binding checks the foundation debug
      // variables before any `tearDown` runs.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      var fetches = 0;
      try {
        await tester.pumpWidget(QueryClientProvider(
          client: client,
          child: MaterialApp(
            home: QueryBuilder<String>(
              options: QueryObserverOptions(
                queryKey: key,
                queryFn: (_) async => 'v${++fetches}',
                refetchOnWindowFocus: RefetchOn.always,
              ),
              builder: (_, result) => Text(result.dataOrNull ?? 'none'),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        // A test binding starts with no lifecycle state at all, so settle on
        // a known-focused baseline before measuring a transition.
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        final baseline = fetches;

        // On macOS, Windows and Linux `inactive` *is* the window losing
        // focus — the event `refetchOnWindowFocus` is named after. Counting
        // it as focused, as a phone must, turned the option off on desktop.
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        expect(fetches, baseline + 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    queryWidgetTest('a phone interruption is not', (tester, client) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var fetches = 0;
      try {
        await tester.pumpWidget(QueryClientProvider(
          client: client,
          child: MaterialApp(
            home: QueryBuilder<String>(
              options: QueryObserverOptions(
                queryKey: key,
                queryFn: (_) async => 'v${++fetches}',
                refetchOnWindowFocus: RefetchOn.always,
              ),
              builder: (_, result) => Text(result.dataOrNull ?? 'none'),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        final baseline = fetches;

        // The notification shade and the app switcher must not refetch the
        // world on the way back.
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        expect(fetches, baseline);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    queryWidgetTest('isAppShown overrides the mapping', (tester, client) async {
      final seen = <AppLifecycleState>[];
      await tester.pumpWidget(QueryClientProvider(
        client: client,
        isAppShown: (state) {
          seen.add(state);
          return false;
        },
        child: const SizedBox(),
      ));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(seen, contains(AppLifecycleState.resumed));
      expect(client.focusManager.isFocused(), isFalse);
    });
  });

  group('F01 notifications go through the scheduler', () {
    queryWidgetTest('late initialData in a sibling never notifies during build',
        (tester, client) async {
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
    }, createClient: newClient);
  });

  group('F02 observers belong to readers, the query to the cache', () {
    queryWidgetTest('context readers may select different types from one key',
        (tester, client) async {
      await tester.pumpWidget(app(
        client,
        Column(children: [
          const _ContextReader(),
          Builder(builder: (context) {
            final length = context.selectQuery<String, int>(
              QuerySelectOptions(
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
    }, createClient: () => newClient()..setQueryData<String>(key, 'abc'));

    queryWidgetTest('two selects of one key in one widget, told apart by id',
        (tester, client) async {
      await tester.pumpWidget(app(client, const _TwoSelects()));
      expect(find.text('ABC/cba'), findsOneWidget);
      // And a rebuild keeps them apart, rather than flipping selectors.
      await tester.pump();
      expect(find.text('ABC/cba'), findsOneWidget);
    }, createClient: () => newClient()..setQueryData<String>(key, 'abc'));

    queryWidgetTest('a mixin reads one key with two selects, told apart by id',
        (tester, client) async {
      await tester.pumpWidget(app(client, const _MixinTwoSelects()));
      expect(find.text('ABC/cba'), findsOneWidget);
    }, createClient: () => newClient()..setQueryData<String>(key, 'abc'));
  });

  group('F03 a replaced provider client', () {
    for (final (name, child) in [
      ('context', const _ContextReader() as Widget),
      ('builder', const _BuilderReader()),
      ('mixin', const _MixinReader()),
    ]) {
      queryWidgetTest('$name follows it', (tester, a) async {
        final b = tester.adopt(newClient()..setQueryData<String>(key, 'B'));
        await tester.pumpWidget(app(a, child));
        expect(find.text('A'), findsOneWidget);

        await tester.pumpWidget(app(b, child));
        await tester.pump();
        expect(find.text('B'), findsOneWidget);
        expect(a.queryCache.get<String>(key)!.observersCount, 0);
        expect(b.queryCache.get<String>(key)!.observersCount, 1);
      }, createClient: () => newClient()..setQueryData<String>(key, 'A'));
    }
  });

  group('F06 mutation identity', () {
    queryWidgetTest('an inline mutation survives its own result rebuild',
        (tester, client) async {
      await tester.pumpWidget(app(client, const _InlineMutation()));
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      await tester.pump();
      expect(find.text('done'), findsOneWidget);
      expect(client.mutationCache.mutations, hasLength(1));
    }, createClient: newClient);
  });

  group('F08 / F09 controller lifetimes', () {
    testWidgets('disposing an unlistened MutationController detaches it',
        (tester) async {
      final client = newClient();
      // Mid-run since the release review of 2026-09-23 (B2-2): a run holds
      // the observer attached until it settles, so per-call callbacks reach
      // a controller nobody listens to, and lets go once it has. A settled
      // run on an unlistened controller is therefore detached already; the
      // one dispose still has to detach is a run in flight.
      final settle = Completer<int>();
      final mutation = MutationController<int, int, void>(
        client,
        MutationOptions(mutationFn: (_) => settle.future),
      );
      try {
        final run = mutation.mutateAsync(1);
        await tester.pump();
        expect(client.mutationCache.mutations.single.observers, hasLength(1));
        mutation.dispose();
        expect(client.mutationCache.mutations.single.observers, isEmpty);
        settle.complete(1);
        await run;
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
      // `QueryController.observing`, whose `value` is the observer's current
      // result rather than the optimistic one. Since C49 a controller drops a
      // notification carrying what a listener arriving right now would
      // already read (`_NotifyWhenMoved`), and a controller built from
      // options reads that optimistically — straight from the cache — so the
      // fixture below could no longer produce a notification at all. The
      // reentrancy this pins is `QueryController.addListener`'s and is the
      // same for either constructor.
      final controller = QueryController<int, int>.observing(
        client,
        QueryObserver<int, int>(
          client,
          QueryObserverOptions(queryKey: key, enabled: Enabled.no),
        ),
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

  // C50: the four controllers write the same subscribe-while-listened dance,
  // and only one of its guards — `QueryController`'s drop-the-handle check,
  // F09 above — was reached by a case. These are the three others that can be
  // reached at all. The notification has to land while `subscribe` is still
  // on the stack, so each case installs the scheduler that delivers on the
  // spot — which is what the provider's own does outside a build — and puts
  // the controller in the one state whose first notification the gate cannot
  // predict: an observer that moved on while it was detached.
  //
  // `QueriesController` and `MutationStateController` have no such state, so
  // their copies of these guards are unreachable and there is no case here
  // for them; see the notes' C50 row.
  group('C50 the controller guards the suite did not reach', () {
    testWidgets(
        'a listener that subscribes another inside its first notification '
        'leaves one subscription', (tester) async {
      final client = newClient()
        ..notifyManager.setScheduler((callback) => callback());
      final controller = QueryController<int, int>.observing(
        client,
        QueryObserver<int, int>(
          client,
          QueryObserverOptions(queryKey: key, enabled: Enabled.no),
        ),
      );
      // As F09: attach and let go, then change the data behind the detached
      // observer, so the next subscribe notifies synchronously.
      void noop() {}
      controller
        ..addListener(noop)
        ..removeListener(noop);
      client.setQueryData<int>(key, 5);

      void nested() {}
      late VoidCallback listener;
      listener = () => controller.addListener(nested);
      try {
        controller.addListener(listener);
        controller
          ..removeListener(listener)
          ..removeListener(nested);
        // Two subscriptions and one handle kept would leave the observer
        // attached with nobody listening to the controller.
        expect(controller.observer.hasListeners, isFalse);
        expect(client.queryCache.get<int>(key)!.observersCount, 0);
      } finally {
        controller.dispose();
        client.clear();
        await tester.pump();
      }
    });

    testWidgets(
        'a mutation listener that subscribes another inside its first '
        'notification leaves one subscription', (tester) async {
      final client = newClient()
        ..notifyManager.setScheduler((callback) => callback());
      final settle = Completer<int>();
      final controller = MutationController<int, int, void>(
        client,
        MutationOptions(mutationFn: (_) => settle.future),
      );
      // The first notification is the run going pending, delivered on the
      // spot. Until the release review of 2026-09-23 (B2-2) the fixture let a
      // run settle while the observer was detached, so that the next
      // subscribe notified from inside `subscribe`; a run started through
      // the controller now holds its observer attached until it settles, so
      // it no longer settles detached. The original fixture still reaches
      // that path through `controller.observer.mutateAsync`, which bypasses
      // the hold — it is kept as its own case below (second pass, V-B-5).
      // This one pins that a listener added inside a notification is still
      // one subscription, which the run's own hold must not mask once it
      // lets go.
      void nested() {}
      late VoidCallback listener;
      listener = () {
        controller
          ..removeListener(listener)
          ..addListener(nested);
      };
      try {
        controller.addListener(listener);
        final run = controller.mutateAsync(1);
        await tester.pump();
        controller.removeListener(nested);
        settle.complete(7);
        await run;
        expect(client.mutationCache.mutations.single.observers, isEmpty);
      } finally {
        controller.dispose();
        client.clear();
        await tester.pump();
      }
    });

    testWidgets(
        'a mutation listener that leaves inside its first notification '
        'unsubscribes', (tester) async {
      final client = newClient()
        ..notifyManager.setScheduler((callback) => callback());
      final settle = Completer<int>();
      final controller = MutationController<int, int, void>(
        client,
        MutationOptions(mutationFn: (_) => settle.future),
      );
      // Reached through a run since B2-2 — see the case above.
      late VoidCallback listener;
      listener = () => controller.removeListener(listener);
      try {
        controller.addListener(listener);
        final run = controller.mutateAsync(1);
        await tester.pump();
        settle.complete(7);
        await run;
        expect(client.mutationCache.mutations.single.observers, isEmpty);
      } finally {
        controller.dispose();
        client.clear();
        await tester.pump();
      }
    });

    // The original C50 mutation fixture, on the path it still reaches: a
    // run through `controller.observer`, which the controller's run hold
    // does not cover, settles while the observer is detached, so the next
    // subscribe notifies from inside `subscribe` (second pass, V-B-5).
    for (final leave in [false, true]) {
      testWidgets(
          'a mutation settled detached through controller.observer: a '
          'listener that ${leave ? 'leaves' : 'subscribes another'} inside '
          'its first notification', (tester) async {
        final client = newClient()
          ..notifyManager.setScheduler((callback) => callback());
        final settle = Completer<int>();
        final controller = MutationController<int, int, void>(
          client,
          MutationOptions(mutationFn: (_) => settle.future),
        );
        void noop() {}
        controller.addListener(noop);
        final run = controller.observer.mutateAsync(1);
        await tester.pump();
        controller.removeListener(noop);
        settle.complete(7);
        await run;

        void nested() {}
        late VoidCallback listener;
        try {
          if (leave) {
            listener = () => controller.removeListener(listener);
            controller.addListener(listener);
          } else {
            listener = () => controller.addListener(nested);
            controller.addListener(listener);
            controller
              ..removeListener(listener)
              ..removeListener(nested);
          }
          expect(client.mutationCache.mutations.single.observers, isEmpty);
        } finally {
          controller.dispose();
          client.clear();
          await tester.pump();
        }
      });
    }
  });

  group('F10 initial lifecycle state', () {
    queryWidgetTest('a provider mounted in a hidden app starts unfocused',
        (tester, client) async {
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

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(client.focusManager.isFocused(), isTrue);
    }, createClient: newClient);
  });

  group('buildWhen', () {
    queryWidgetTest('skips rebuilds the builder does not care about',
        (tester, client) async {
      var builds = 0;
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
    }, createClient: () => newClient()..setQueryData<String>(key, 'a'));
  });

  // ---------------------------------------------------------------------------
  // Third review, 2026-09-09.

  group('B1 the bootstrap build', () {
    queryWidgetTest(
        'a sibling initialData notifies after the first build, not in it',
        (tester, client) async {
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
      tester.binding.attachRootWidget(tester.binding.wrapWithDefaultView(root));
      tester.binding.buildOwner!.buildScope(tester.binding.rootElement!);
      expect(tester.takeException(), isNull);

      await tester.pump();
      expect(find.text('first:1'), findsOneWidget);
      expect(find.text('second:1'), findsOneWidget);
    }, createClient: newClient);
  });

  group('B2 a select returning a fresh but equal value', () {
    queryWidgetTest('does not rebuild a context reader every frame',
        (tester, client) async {
      final builds = <int>[];
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
    },
        createClient: () =>
            newClient()..setQueryData<List<int>>(key, [1, 2, 3, 4]));

    queryWidgetTest('does not rebuild a mixin reader every frame',
        (tester, client) async {
      final builds = <int>[];
      await tester.pumpWidget(app(client, _R3MixinListSelect(builds)));
      await tester.pumpWidget(app(client, _R3MixinListSelect(builds)));
      final after = builds.length;
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(builds.length, after);
    },
        createClient: () =>
            newClient()..setQueryData<List<int>>(key, [1, 2, 3, 4]));
  });

  group('M7 collisions without id', () {
    queryWidgetTest('two selects of one key in one build are caught',
        (tester, client) async {
      await tester.pumpWidget(app(client, const _R3TwoSelectsNoId()));
      expect(tester.takeException(), isA<FlutterError>());
    }, createClient: () => newClient()..setQueryData<String>(key, 'Ab'));

    queryWidgetTest('two mutations of one shape in one build are caught',
        (tester, client) async {
      await tester.pumpWidget(app(client, const _R3TwoMutationsNoId()));
      expect(tester.takeException(), isA<FlutterError>());
      // With ids, the same widget is fine.
      await tester.pumpWidget(
        app(client, const _R3TwoMutationsNoId(withIds: true)),
      );
      expect(tester.takeException(), isNull);
    }, createClient: newClient);
  });

  group('M4 the mixin releases a key it stopped reading', () {
    queryWidgetTest('and its stale queryFn never runs again',
        (tester, client) async {
      final fetched = <String>[];
      Future<String> fetch(String id) async {
        fetched.add(id);
        return 'Task $id';
      }

      await tester.pumpWidget(app(client, _R3MixinById('a', fetch)));
      await tester.pump();
      expect(find.text('Task a'), findsOneWidget);

      await tester.pumpWidget(app(client, _R3MixinById('b', fetch)));
      await tester.pump();
      await tester.pump();
      expect(find.text('Task b'), findsOneWidget);

      final a = client.queryCache.get<String>(QueryKey(<Object?>['m4', 'a']));
      expect(a!.observersCount, 0);

      // The old observer's `queryFn` closed over `widget.id` — which is
      // now 'b'. Left alive, a refetch of key 'a' would have fetched 'b'
      // and written "Task b" into a's cache entry.
      fetched.clear();
      await client.invalidateQueries(
        filters: QueryFilters(queryKey: QueryKey(<Object?>['m4', 'a'])),
      );
      await tester.pump();
      expect(fetched, isEmpty);
      expect(a.state.data, 'Task a');
    }, createClient: newClient);
  });

  group('M5 lifecycle transitions', () {
    queryWidgetTest('detached → resumed focuses the client',
        (tester, client) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
      await tester.pumpWidget(
        QueryClientProvider(client: client, child: const SizedBox()),
      );
      tester.binding.scheduleForcedFrame();
      await tester.pump();
      expect(client.focusManager.isFocused(), isFalse);

      // Neither `onShow` nor `onHide`: only `onResume` fires for this one.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(client.focusManager.isFocused(), isTrue);
    }, createClient: newClient);
  });

  group('M6 a new OnlineStatus.stream per build', () {
    queryWidgetTest('rebinds the subscription and nothing else',
        (tester, client) async {
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
            onlineStatus: OnlineStatus.stream(status(), initial: true),
            child: const SizedBox(),
          );
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
    }, createClient: newClient);
  });

  group('buildWhen on every builder', () {
    queryWidgetTest('InfiniteQueryBuilder and MutationBuilder take one',
        (tester, client) async {
      var feedBuilds = 0;
      var mutationBuilds = 0;
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
    }, createClient: newClient);
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
          QueryObserverOptions<InfiniteData<int, int>>(
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

  group('B2 a single-subscription OnlineStatus.stream', () {
    queryWidgetTest('survives a client switch, which inherits the last value',
        (tester, a) async {
      final b = tester.adopt(newClient());
      // Not broadcast: a second `listen` would throw.
      final online = StreamController<bool>();
      addTearDown(online.close);
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
    }, createClient: newClient);
  });

  group('B3 the first build is the only build', () {
    queryWidgetTest('until the result actually changes, in all three styles',
        (tester, client) async {
      final builds = <String>[];
      final fetches = <String, Completer<String>>{};
      QueryObserverOptions<String> pending(String id) => QueryObserverOptions(
            queryKey: QueryKey(<Object?>['r4', id]),
            queryFn: (_) =>
                fetches.putIfAbsent(id, Completer<String>.new).future,
          );
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
    }, createClient: newClient);
  });

  group('B5 one mutationKey, two type triples', () {
    for (final (name, widget) in [
      ('context', const _R4KeyedMutations()),
      ('mixin', const _R4MixinKeyedMutations()),
    ]) {
      queryWidgetTest('$name gets two controllers, not a failed cast',
          (tester, client) async {
        await tester.pumpWidget(app(client, widget));
        expect(tester.takeException(), isNull);
        expect(find.text('distinct'), findsOneWidget);
      }, createClient: newClient);
    }
  });

  group('B6 staleness flipping between two reads of one key', () {
    for (final (name, widget) in [
      ('context', const _R4StaleBetweenReads()),
      ('mixin', const _R4MixinStaleBetweenReads()),
    ]) {
      queryWidgetTest('$name is not mistaken for two selects',
          (tester, client) async {
        await tester.pumpWidget(app(client, widget));
        expect(tester.takeException(), isNull);
        expect(find.text('false/true'), findsOneWidget);
      }, createClient: () => newClient()..setQueryData<String>(key, 'x'));
    }
  });

  group('B8 a mutation the widget stopped reading', () {
    for (final (name, build) in [
      ('context', _R4MutationById.new),
      ('mixin', _R4MixinMutationById.new),
    ]) {
      queryWidgetTest('$name releases it after the frame, like a query',
          (tester, client) async {
        final seen = <MutationController<Object?, Object?, Object?>>[];
        await tester.pumpWidget(app(client, build('a', seen)));
        await tester.pumpWidget(app(client, build('b', seen)));
        await tester.pump();
        expect(seen, hasLength(2));
        expect(seen[0], isNot(same(seen[1])));
        expect(seen[0].isDisposed, isTrue);
        expect(seen[1].isDisposed, isFalse);
      }, createClient: newClient);
    }
  });

  group('A-24 QueryClientProvider.maybeOf', () {
    queryWidgetTest('is the client, or null without a provider',
        (tester, client) async {
      QueryClient? found;
      Widget probe() => Builder(builder: (context) {
            found = QueryClientProvider.maybeOf(context);
            return const SizedBox();
          });
      await tester.pumpWidget(MaterialApp(home: probe()));
      expect(found, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(app(client, probe()));
      expect(found, same(client));
    }, createClient: newClient);
  });

  group('A-25 a controller read before anyone listens', () {
    test('reports the optimistic result, as a first build would', () {
      final client = newClient();
      final controller = QueryController.create<String>(
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
      final controller = QueryController.create<String>(
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
      InfiniteQueryObserverOptions<int, int> options(
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
    queryWidgetTest('infers both types from mutationFn under strict inference',
        (tester, client) async {
      final seen = <Object?>[];
      await tester.pumpWidget(app(client, _A21Reader(seen)));
      expect(seen.single, isA<MutationController<int, String, void>>());
      (seen.single as MutationController<int, String, void>).mutate('four');
      await tester.pump();
      expect(find.text('4'), findsOneWidget);
    }, createClient: newClient);
  });

  // ---- ninth review (2026-09-10, consolidated 2026-09-11) ------------------
  // Each case keeps the probe's name (deep-dive `P`, release-review `R`) next
  // to the consolidated id; the core's ninth-review rows are in
  // `port_specifics_test.dart` and `port_lifecycle_test.dart`.

  group(
      'C1 (B1, B3, B6) one type slot: an inline literal without select or '
      'type argument', () {
    // Before ADR-0001 `QueryObserverOptions<TQueryData, TData>` carried
    // `TData` only in its optional `select`, so every one of these put a
    // `Query<dynamic>` in the cache and a later typed reader threw. The plain
    // shape now has one slot, anchored by `queryFn`.
    Query<Object?>? cached(QueryClient client) =>
        client.queryCache.find(filters: QueryFilters(queryKey: key));

    testWidgets('QueryController.create', (tester) async {
      final client = QueryClient();
      final controller = QueryController.create(
        client,
        QueryObserverOptions(queryKey: key, queryFn: (_) async => 1),
      );
      try {
        expect(controller, isA<QueryController<int, int>>());
        expect(cached(client), isA<Query<int>>());
      } finally {
        controller.dispose();
        client.clear();
      }
    });

    queryWidgetTest('QueryBuilder', (tester, client) async {
      await tester.pumpWidget(app(
        client,
        QueryBuilder(
          options: QueryObserverOptions(queryKey: key, queryFn: (_) async => 1),
          builder: (_, result) => Text('v:${result.dataOrNull}'),
        ),
      ));
      expect(cached(client), isA<Query<int>>());
      await tester.pump();
      expect(find.text('v:1'), findsOneWidget);
    });

    queryWidgetTest('context.query', (tester, client) async {
      await tester.pumpWidget(app(
        client,
        Builder(
          builder: (context) => Text(
            'v:${context.query(QueryObserverOptions(queryKey: key, queryFn: (_) async => 1)).dataOrNull}',
          ),
        ),
      ));
      expect(cached(client), isA<Query<int>>());
      await tester.pump();
      expect(find.text('v:1'), findsOneWidget);
    });

    queryWidgetTest('QueryMixin.watchQuery', (tester, client) async {
      await tester.pumpWidget(app(client, const _C1MixinReader()));
      expect(cached(client), isA<Query<int>>());
      await tester.pump();
      expect(find.text('v:1'), findsOneWidget);
    });

    queryWidgetTest(
        'InfiniteQueryBuilder needs no type arguments, for a helper and for '
        'an inline plain literal', (tester, client) async {
      await tester.pumpWidget(app(
        client,
        Column(children: <Widget>[
          InfiniteQueryBuilder(
            options: _c1Feed(),
            builder: (_, feed) => Text('a:${feed.value.dataOrNull?.pages}'),
          ),
          InfiniteQueryBuilder(
            options: InfiniteQueryObserverOptions(
              queryKey: QueryKey(<Object?>['c1', 'inline']),
              pageFn: (context) async => 'p${context.pageParam}',
              initialPageParam: 0,
              getNextPageParam: (_, __, param, ___) => param + 1,
            ),
            builder: (_, feed) {
              // The slots are read off the options: TData is InfiniteData.
              expect(
                  feed,
                  isA<
                      InfiniteQueryController<String, int,
                          InfiniteData<String, int>>>());
              return Text('b:${feed.value.dataOrNull?.pages}');
            },
          ),
        ]),
      ));
      await tester.pump();
      expect(find.text('a:[[1]]'), findsOneWidget);
      expect(find.text('b:[p0]'), findsOneWidget);
      expect(client.queryCache.find(filters: QueryFilters(queryKey: key)),
          isA<Query<InfiniteData<List<int>, int>>>());
    });

    testWidgets('the backstop names the cure for a key-only literal',
        (tester) async {
      final client = QueryClient();
      try {
        // The residue no shape can type: neither a queryFn nor a type
        // argument. `strict-inference` would report the literal; the debug
        // backstop refuses it at runtime (compiled out of release).
        expect(
          // ignore: inference_failure_on_instance_creation
          () => QueryController(client, QueryObserverOptions(queryKey: key)),
          throwsA(isA<AssertionError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains('top type'), contains('dynamic'),
                contains('QueryController.create<Task>')),
          )),
        );
        // A plain infinite shape's data is always an `InfiniteData`, never a
        // top type; the infinite backstop is reachable only through a select
        // whose return type is one — `jsonDecode` returns `dynamic`.
        expect(
          () => InfiniteQueryController(
            client,
            InfiniteQuerySelectOptions(
              queryKey: key,
              pageFn: (_) async => 1,
              initialPageParam: 0,
              getNextPageParam: (_, __, ___, ____) => null,
              select: (data) => jsonDecode('${data.pages.length}'),
            ),
          ),
          throwsA(isA<AssertionError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains('top type'), contains('select')),
          )),
        );
        // Neither refusal touched the cache.
        expect(cached(client), isNull);
      } finally {
        client.clear();
      }
    });
  });

  group('C17 (P1, R8) a changed isAppShown on the same client', () {
    Widget tree(QueryClient client, bool shown) => QueryClientProvider(
          client: client,
          isAppShown: (_) => shown,
          child: const SizedBox(),
        );

    queryWidgetTest('decides the next transition without a remount',
        (tester, client) async {
      await tester.pumpWidget(tree(client, false));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(client.focusManager.isFocused(), isFalse);
      // Same client, same provider element: only the mapping changed. The
      // listener used to capture the mapping it was installed with, and
      // `didUpdateWidget` re-wired it only for a new client or a toggled
      // `observeAppLifecycle`.
      await tester.pumpWidget(tree(client, true));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(client.focusManager.isFocused(), isTrue,
          reason: 'the mapping given on the latest build decides');
    }, createClient: newClient);

    queryWidgetTest('is applied to the state the app is already in',
        (tester, client) async {
      await tester.pumpWidget(tree(client, false));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(client.focusManager.isFocused(), isFalse);
      // No transition follows the change: the class doc promises the
      // current state is mapped too, not only the transitions after it.
      await tester.pumpWidget(tree(client, true));
      expect(client.focusManager.isFocused(), isTrue);
      await tester.pumpWidget(tree(client, false));
      expect(client.focusManager.isFocused(), isFalse);
    }, createClient: newClient);
  });

  group('C18 (P3a, P3b) mutate() on a disposed MutationController', () {
    testWidgets('runs the mutation, attaches nothing, and lets it be collected',
        (tester) async {
      final client = newClient();
      var runs = 0;
      var optionCallbacks = 0;
      var callCallbacks = 0;
      final controller = MutationController<int, int, void>(
        client,
        MutationOptions<int, int, void>(
          mutationFn: (v) async {
            runs++;
            return v;
          },
          onSuccess: (_, __, ___) => optionCallbacks++,
          gcTime: const GcTimeDuration(Duration(seconds: 1)),
        ),
      );
      try {
        controller.dispose();
        expect(controller.isDisposed, isTrue);
        controller.mutate(
          1,
          callbacks: MutateCallbacks(onSuccess: (_, __, ___) {
            callCallbacks++;
          }),
        );
        await tester.pump();
        expect(runs, 1, reason: 'fire-and-forget still fires');
        final mutation = client.mutationCache.mutations.single;
        expect(mutation.state.status, MutationStatus.success);
        expect(mutation.observers, isEmpty,
            reason: 'the destroyed observer used to re-attach itself here');
        expect(optionCallbacks, 1,
            reason: "the options' callbacks belong to the mutation");
        expect(callCallbacks, 0,
            reason: 'per-call callbacks belong to a live subscription');
        expect(controller.value.isIdle, isTrue,
            reason: 'nothing lands on a disposed controller');
        await tester.pump(const Duration(seconds: 2));
        expect(client.mutationCache.mutations, isEmpty,
            reason: 'settled and unobserved: collected after gcTime');
      } finally {
        client.clear();
        await tester.pump();
      }
    });

    testWidgets('mutateAsync still completes with the data', (tester) async {
      final client = newClient();
      final controller = MutationController<int, int, void>(
        client,
        MutationOptions<int, int, void>(mutationFn: (v) async => v * 2),
      );
      try {
        controller.dispose();
        expect(await controller.mutateAsync(21), 42);
        expect(client.mutationCache.mutations.single.observers, isEmpty);
      } finally {
        client.clear();
        await tester.pump();
      }
    });

    queryWidgetTest(
        'P3b a tap handler outliving its context.mutation widget leaks nothing',
        (tester, client) async {
      MutationController<int, int, void>? captured;
      await tester.pumpWidget(app(
        client,
        Builder(builder: (context) {
          captured = context.mutation(MutationOptions<int, int, void>(
            mutationFn: (v) async => v,
            gcTime: const GcTimeDuration(Duration(seconds: 1)),
          ));
          return const SizedBox();
        }),
      ));
      // The widget goes; the handler that captured its controller fires
      // afterwards, as one does after awaiting a dialog.
      await tester.pumpWidget(app(client, const SizedBox()));
      await tester.pump();
      expect(captured!.isDisposed, isTrue);
      captured!.mutate(1);
      await tester.pump();
      expect(client.mutationCache.mutations.single.state.status,
          MutationStatus.success);
      await tester.pump(const Duration(seconds: 2));
      expect(client.mutationCache.mutations, isEmpty);
    }, createClient: newClient);
  });

  group('C23.7 the barrel hides the seam between builders and controllers', () {
    // `ObservedState` / `observedStateOf` are how a builder asks a controller
    // what its readers can see; a custom controller overrides the member
    // without naming the interface. Read from the source: Flutter has no
    // `dart:mirrors`, and the positive half — every name a consumer may
    // write — is this file's import compiling.
    test('ObservedState and observedStateOf are not exported', () {
      final barrel = File('lib/query_kit_flutter.dart').readAsStringSync();
      Set<String> hidden(String file) {
        final export =
            RegExp("export 'src/$file.dart'(?:\\s+hide\\s+([^;]+))?;")
                .firstMatch(barrel);
        expect(export, isNotNull, reason: 'src/$file.dart is exported');
        final list = export!.group(1);
        return list == null
            ? const {}
            : list.split(',').map((name) => name.trim()).toSet();
      }

      expect(hidden('query_controller'), {'ObservedState', 'observedStateOf'});
      expect(hidden('query_context'), {'QueryScope', 'QueryScopeElement'});
    });
  });

  // The three regions of the reader registry the suite did not reach before
  // C47 (https://github.com/KoTTi97/flutter_query/issues/56) moved it into
  // one `ReadSet`. Written and run green against the two copies first, so
  // they say the extraction changed nothing rather than describing it: the
  // mixin's two debug assertions (only `context`'s were exercised) and the
  // `(#infinite, …, id)` identity tuple, which nothing anywhere read.
  group('C47 the registry regions the suite did not reach', () {
    queryWidgetTest('the mixin catches two selects of one key in one build',
        (tester, client) async {
      await tester.pumpWidget(app(client, const _C47MixinTwoSelects()));
      expect(tester.takeException(), isA<FlutterError>());
    }, createClient: () => newClient()..setQueryData<String>(key, 'Ab'));

    queryWidgetTest('the mixin catches two mutations of one shape in one build',
        (tester, client) async {
      await tester.pumpWidget(app(client, const _C47MixinTwoMutations()));
      expect(tester.takeException(), isA<FlutterError>());
      // With ids, the same State is fine.
      await tester.pumpWidget(
        app(client, const _C47MixinTwoMutations(withIds: true)),
      );
      expect(tester.takeException(), isNull);
    }, createClient: newClient);

    for (final (style, reader)
        in <(String, Widget Function(int, List<Object>, Object?))>[
      (
        'context.infiniteQuery',
        (n, seen, id) => _C47InfiniteContext(n, seen, id: id)
      ),
      (
        'watchInfiniteQuery',
        (n, seen, id) => _C47InfiniteMixin(n, seen, id: id)
      ),
    ]) {
      queryWidgetTest(
          '$style with an id keeps its controller across a key '
          'change', (tester, client) async {
        final seen = <Object>[];
        await tester.pumpApp(client, reader(1, seen, 'feed'));
        await tester.pump();
        await tester.pumpApp(client, reader(2, seen, 'feed'));
        await tester.pump();

        expect(seen.first, same(seen.last));
        expect(_c47Observers(client, 1), 0);
        expect(_c47Observers(client, 2), 1);
      }, createClient: newClient);

      queryWidgetTest('$style without an id treats a new key as a new read',
          (tester, client) async {
        final seen = <Object>[];
        await tester.pumpApp(client, reader(1, seen, null));
        await tester.pump();
        await tester.pumpApp(client, reader(2, seen, null));
        await tester.pump();

        expect(seen.first, isNot(same(seen.last)));
        expect(_c47Observers(client, 1), 0);
        expect(_c47Observers(client, 2), 1);
      }, createClient: newClient);
    }
  });

  // The rebuild decision — "read the value and its `observedStateOf`, rebuild
  // only if it moved, then ask `buildWhen`" — was written once per builder
  // until C48 (https://github.com/KoTTi97/flutter_query/issues/57). Three of
  // the four copies were counted somewhere (B3 and R02 above, and
  // `buildWhen on every builder` for the infinite and the mutation one);
  // these are the gaps that probing the four copies with the branch disabled
  // exposed, written and run green against them first:
  //
  // * `QuerySelectBuilder`'s copy was reached by nothing at all;
  // * `buildWhen` was reached on the infinite and the mutation builder only.
  //   `buildWhen` above passes with the predicate disabled: a disabled query
  //   with `StaleTime.infinite` invalidated with `RefetchType.none` does not
  //   move its result, so the equality above it answers first and the
  //   predicate is never asked. A refetch that returns the same data is what
  //   moves the result (`dataUpdatedAt`) and leaves the data alone.
  group('C48 the rebuild decision in the builders the suite did not count', () {
    queryWidgetTest('a builder asks buildWhen about a result that moved',
        (tester, client) async {
      var builds = 0;
      var fetches = 0;
      await tester.pumpWidget(app(
        client,
        QueryBuilder<String>(
          options: QueryObserverOptions(
            queryKey: key,
            queryFn: (_) async {
              fetches++;
              return 'a';
            },
          ),
          buildWhen: (previous, current) =>
              previous.dataOrNull != current.dataOrNull,
          builder: (_, result) {
            builds++;
            return Text(result.dataOrNull ?? 'none');
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(builds, 2);

      // The same data, fetched again: `dataUpdatedAt` moved, the data did
      // not.
      await client.refetchQueries(filters: QueryFilters(queryKey: key));
      await tester.pumpAndSettle();
      expect(fetches, 2);
      expect(builds, 2);
    }, createClient: newClient);

    queryWidgetTest(
        'a select builder does not rebuild for the fetch it '
        'started', (tester, client) async {
      final builds = <String>[];
      final fetch = Completer<String>();
      await tester.pumpWidget(app(
        client,
        QuerySelectBuilder<String, int>(
          options: QuerySelectOptions(
            queryKey: key,
            queryFn: (_) => fetch.future,
            select: (value) => value.length,
          ),
          builder: (_, result) {
            builds.add('${result.dataOrNull}');
            return const SizedBox();
          },
        ),
      ));
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(builds, ['null']);

      fetch.complete('abcd');
      await tester.pumpAndSettle();
      expect(builds, ['null', '4']);
    }, createClient: newClient);

    queryWidgetTest('a select builder skips what its buildWhen rejects',
        (tester, client) async {
      var builds = 0;
      var fetches = 0;
      await tester.pumpWidget(app(
        client,
        QuerySelectBuilder<String, int>(
          options: QuerySelectOptions(
            queryKey: key,
            queryFn: (_) async => 'ab-${fetches++}',
            select: (value) => value.length,
          ),
          buildWhen: (previous, current) =>
              previous.dataOrNull != current.dataOrNull,
          builder: (_, result) {
            builds++;
            return Text('${result.dataOrNull}');
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(builds, 2);
      expect(find.text('4'), findsOneWidget);

      // Different data of the same selected length: the result moved, what
      // this widget shows did not.
      await client.refetchQueries(filters: QueryFilters(queryKey: key));
      await tester.pumpAndSettle();
      expect(fetches, 2);
      expect(builds, 2);
    }, createClient: newClient);
  });

  group('C49 the four styles made equal', () {
    // `buildWhen` on the two keyless reads, and the notification a controller
    // no longer passes on. Both from
    // https://github.com/KoTTi97/flutter_query/issues/55; neither was
    // reachable before, so nothing here is a rewrite of an older case.
    for (final (name, reader) in <(String, _C49QueryReader)>[
      ('QueryMixin.watchQuery', _C49MixinQuery.new),
      ('context.query', _C49ContextQuery.new),
    ]) {
      queryWidgetTest('$name skips what its buildWhen rejects',
          (tester, client) async {
        var fetches = 0;
        final builds = <String?>[];
        final options = QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) async {
            fetches++;
            return 'a';
          },
        );
        await tester.pumpApp(client, reader(options, builds));
        await tester.pumpAndSettle();
        expect(builds, <String?>[null, 'a']);

        // The same data, fetched again: `dataUpdatedAt` and `fetchStatus`
        // moved, so `QueryResult ==` says the result changed — which is
        // exactly the change `select` cannot narrow away — and the data did
        // not.
        await client.refetchQueries(filters: QueryFilters(queryKey: key));
        await tester.pumpAndSettle();
        expect(fetches, 2);
        expect(builds, <String?>[null, 'a']);
      }, createClient: newClient);
    }

    for (final (name, reader) in <(String, _C49InfiniteReader)>[
      ('QueryMixin.watchInfiniteQuery', _C49MixinInfinite.new),
      ('context.infiniteQuery', _C49ContextInfinite.new),
    ]) {
      queryWidgetTest('$name skips what its buildWhen rejects',
          (tester, client) async {
        var fetches = 0;
        final builds = <String>[];
        final options = InfiniteQueryObserverOptions<List<String>, int>(
          queryKey: key,
          initialPageParam: 0,
          pageFn: (context) async {
            fetches++;
            return <String>['p${context.pageParam}'];
          },
          getNextPageParam: (_, __, lastParam, ___) => lastParam + 1,
        );
        await tester.pumpApp(client, reader(options, builds));
        await tester.pumpAndSettle();
        expect(builds, <String>['null', '[[p0]]']);

        await client.refetchQueries(filters: QueryFilters(queryKey: key));
        await tester.pumpAndSettle();
        expect(fetches, 2);
        expect(builds, <String>['null', '[[p0]]']);
      }, createClient: newClient);
    }

    queryWidgetTest(
        'a ValueListenableBuilder over a controller does not rebuild for '
        'the fetch it started', (tester, client) async {
      final fetch = Completer<String>();
      final builds = <String?>[];
      final controller = QueryController.create<String>(
        client,
        QueryObserverOptions<String>(
            queryKey: key, queryFn: (_) => fetch.future),
      );
      try {
        await tester.pumpApp(
          client,
          ValueListenableBuilder<QueryResult<String>>(
            valueListenable: controller,
            builder: (_, result, __) {
              builds.add(result.dataOrNull);
              return Text('${result.dataOrNull}');
            },
          ),
        );
        // The builder read the optimistic result — `fetching`, because a
        // listener was about to start the fetch — and the observer's report
        // of that very fetch lands after the frame carrying the same thing.
        for (var i = 0; i < 3; i++) {
          await tester.pump();
        }
        expect(builds, <String?>[null]);

        fetch.complete('abcd');
        await tester.pumpAndSettle();
        expect(builds, <String?>[null, 'abcd']);
      } finally {
        controller.dispose();
      }
    }, createClient: newClient);

    queryWidgetTest(
        'a QueriesBuilder does not rebuild for the fetches it '
        'started', (tester, client) async {
      final fetch = Completer<String>();
      final builds = <String>[];
      await tester.pumpApp(
        client,
        QueriesBuilder<String, String>(
          queries: <QueryObserverOptions<String>>[
            QueryObserverOptions<String>(
              queryKey: key,
              queryFn: (_) => fetch.future,
            ),
          ],
          builder: (_, results) {
            builds.add('${results.single.dataOrNull}');
            return Text('${results.single.dataOrNull}');
          },
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(builds, <String>['null']);

      fetch.complete('abcd');
      await tester.pumpAndSettle();
      expect(builds, <String>['null', 'abcd']);
    }, createClient: newClient);

    queryWidgetTest(
        'a MutationController told twice in one batch notifies once',
        (tester, client) async {
      final controller = MutationController<int, int, void>(
        client,
        MutationOptions<int, int, void>(mutationFn: (v) async => v),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      try {
        // Two states inside one batch: both notifications are held to the
        // flush, and both read the same settled result when they run.
        client.notifyManager.batch(() {
          controller
            ..mutate(1)
            ..mutate(2);
        });
        await tester.pumpAndSettle();
        expect(controller.value.dataOrNull, 2);
        expect(notifications, 2);
      } finally {
        controller.dispose();
      }
    }, createClient: newClient);

    queryWidgetTest(
        'a MutationStateController told twice in one batch notifies once',
        (tester, client) async {
      final states = MutationStateController<MutationStatus>(
        client,
        select: (mutation) => mutation.state.status,
      );
      var notifications = 0;
      states.addListener(() => notifications++);
      final first = MutationController<int, int, void>(
        client,
        MutationOptions<int, int, void>(mutationFn: (v) async => v),
      );
      final second = MutationController<int, int, void>(
        client,
        MutationOptions<int, int, void>(mutationFn: (v) async => v),
      );
      try {
        client.notifyManager.batch(() {
          first.mutate(1);
          second.mutate(2);
        });
        await tester.pumpAndSettle();
        expect(states.value,
            <MutationStatus>[MutationStatus.success, MutationStatus.success]);
        expect(notifications, 2);
      } finally {
        first.dispose();
        second.dispose();
        states.dispose();
      }
    }, createClient: newClient);
  });

  group('C67 the mutation reads made equal', () {
    // `MutationBuilder` took a `buildWhen` and the two keyless mutation reads
    // did not — C49's asymmetry, one surface over
    // (https://github.com/KoTTi97/flutter_query/issues/67). Unlike the query
    // side there is no `select` to offer instead, and unlike the mutation
    // half of `NotifyGate` — which fires zero times across these three suites
    // — the predicate is asked about *every* notification: a
    // `MutationController` has no `observedState` beside its value, so
    // `ReadEntry`'s equality gate is the comparison `MutationObserver`
    // already made before it notified at all.
    for (final (name, reader) in <(String, _C67MutationReader)>[
      ('QueryMixin.watchMutation', _C67MixinMutation.new),
      ('context.mutation', _C67ContextMutation.new),
    ]) {
      queryWidgetTest('$name skips what its buildWhen rejects',
          (tester, client) async {
        final builds = <String>[];
        final asked = <String>[];
        final run = Completer<int>();
        await tester.pumpApp(client, reader(builds, asked, run.future));
        await tester.pump();
        expect(builds, <String>['idle:null']);

        await tester.tap(find.byType(TextButton));
        await tester.pump();
        // Pending is a real change — the variant, `variables` and
        // `submittedAt` all moved — so nothing but the predicate can reject
        // it, and nothing did before this ticket.
        expect(asked, <String>['idle->pending']);
        expect(builds, <String>['idle:null']);

        run.complete(2);
        await tester.pumpAndSettle();
        expect(builds, <String>['idle:null', 'success:2']);

        // Both notifications reached the predicate, and `previous` is what
        // was last *built*: the rejected pending result is not remembered, so
        // the second question is asked against the idle result on screen.
        expect(asked, <String>['idle->pending', 'idle->success']);
      }, createClient: newClient);
    }
  });

  group('C51 one OnlineStatus instead of a pair', () {
    // The `Stream<bool>` + `initialOnlineStatus` pair became one sealed value
    // (https://github.com/KoTTi97/flutter_query/issues/60). The stream form's
    // two branches were already pinned by B2, R07 and M6; these are the
    // fixed form, the value semantics the new type has to have, and the one
    // rule that could not be written before — what a swapped stream does to a
    // client that already has a verdict.
    Widget provided(QueryClient client, OnlineStatus? status) =>
        QueryClientProvider(
          client: client,
          observeAppLifecycle: false,
          onlineStatus: status,
          child: const SizedBox(),
        );

    queryWidgetTest('a fixed status is the verdict at mount',
        (tester, client) async {
      await tester
          .pumpWidget(provided(client, const OnlineStatus.fixed(false)));
      expect(client.onlineManager.isOnline(), isFalse);
    }, createClient: newClient);

    queryWidgetTest('a changed fixed status reaches the client as it stands',
        (tester, client) async {
      await tester
          .pumpWidget(provided(client, const OnlineStatus.fixed(false)));
      expect(client.onlineManager.isOnline(), isFalse);

      // No new client, and a fixed status has no stream: applying it on the
      // rebuild is the only way it can reach the client at all.
      await tester.pumpWidget(provided(client, const OnlineStatus.fixed(true)));
      await tester.pump();
      expect(client.onlineManager.isOnline(), isTrue);
    }, createClient: newClient);

    queryWidgetTest('one stream swapped for another keeps the last verdict',
        (tester, client) async {
      final first = StreamController<bool>.broadcast();
      final second = StreamController<bool>.broadcast();
      addTearDown(first.close);
      addTearDown(second.close);

      await tester.pumpWidget(
          provided(client, OnlineStatus.stream(first.stream, initial: true)));
      first.add(false);
      await tester.pump();
      expect(client.onlineManager.isOnline(), isFalse);

      // The new source has not spoken yet; rewinding to its `initial` would
      // put the client back online for anyone who builds their stream in
      // `build`, which is a new stream object every rebuild (M6).
      await tester.pumpWidget(
          provided(client, OnlineStatus.stream(second.stream, initial: true)));
      await tester.pump();
      expect(client.onlineManager.isOnline(), isFalse);

      second.add(true);
      await tester.pump();
      expect(client.onlineManager.isOnline(), isTrue);
    }, createClient: newClient);

    queryWidgetTest('an equal status does not listen to the stream twice',
        (tester, client) async {
      // Not broadcast: a second `listen` throws. The provider compares the
      // whole value now, so a status rebuilt around the same stream has to
      // compare equal or this is `Stream has already been listened to`.
      final online = StreamController<bool>();
      addTearDown(online.close);

      Widget build() =>
          provided(client, OnlineStatus.stream(online.stream, initial: true));
      await tester.pumpWidget(build());
      await tester.pumpWidget(build());
      await tester.pumpWidget(build());
      expect(tester.takeException(), isNull);

      online.add(false);
      await tester.pump();
      expect(client.onlineManager.isOnline(), isFalse);
    }, createClient: newClient);

    test('the value semantics every option with modes has', () {
      const fixed = OnlineStatus.fixed(false);
      expect(fixed, const OnlineStatus.fixed(false));
      expect(fixed.hashCode, const OnlineStatus.fixed(false).hashCode);
      expect(fixed, isNot(const OnlineStatus.fixed(true)));
      expect(fixed.initial, isFalse);
      expect(fixed.changes, isNull);
      expect(fixed.toString(), 'OnlineStatus.fixed(false)');

      final changes = const Stream<bool>.empty();
      final status = OnlineStatus.stream(changes, initial: false);
      expect(status, OnlineStatus.stream(changes, initial: false));
      expect(status.hashCode,
          OnlineStatus.stream(changes, initial: false).hashCode);
      // The assumption is part of the value: two providers differing only in
      // it tell their clients two different things at mount.
      expect(status, isNot(OnlineStatus.stream(changes, initial: true)));
      expect(status.initial, isFalse);
      expect(status.changes, same(changes));
      expect(status.toString(), contains('initial: false'));
    });
  });

  group('C59 the smaller structural points', () {
    // `QueriesBuilder` reconciled inside `build` behind an `_updating` flag
    // and now keeps its controller's lifetime where the other four builders
    // keep theirs; `QueryClientProvider` installed two InheritedWidgets for
    // one client and now installs one
    // (https://github.com/KoTTi97/flutter_query/issues/66). Behaviour is the
    // invariant, and these are the branches the suite had never reached.

    Widget collection(QueryClient? client) => QueriesBuilder<String, String>(
          client: client,
          queries: <QueryObserverOptions<String>>[seeded()],
          builder: (_, results) => Text(results.single.dataOrNull ?? 'none'),
        );

    queryWidgetTest('a QueriesBuilder follows a replaced provider client',
        (tester, a) async {
      final b = tester.adopt(newClient()..setQueryData<String>(key, 'B'));
      // F03 proved this for the context read, the builder and the mixin; the
      // collection was the one reader whose client came from `build` alone,
      // so nothing exercised the dependency change at all.
      await tester.pumpWidget(app(a, collection(null)));
      await tester.pump();
      expect(find.text('A'), findsOneWidget);

      await tester.pumpWidget(app(b, collection(null)));
      await tester.pump();
      expect(find.text('B'), findsOneWidget);
      expect(a.queryCache.get<String>(key)!.observersCount, 0);
      expect(b.queryCache.get<String>(key)!.observersCount, 1);
    }, createClient: () => newClient()..setQueryData<String>(key, 'A'));

    queryWidgetTest(
        'a QueriesBuilder keeps its controller while the client does not move',
        (tester, client) async {
      await tester.pumpWidget(app(client, collection(null)));
      await tester.pump();
      final observer = client.queryCache.get<String>(key)!.observers.single;

      // A rebuild of the same widget with an equal client is not a new
      // collection: the observers outlive it, which is what makes the list
      // reconciliation in `setQueries` worth anything.
      await tester.pumpWidget(app(client, collection(null)));
      await tester.pump();
      expect(
          client.queryCache.get<String>(key)!.observers.single, same(observer));
      expect(client.queryCache.get<String>(key)!.observersCount, 1);
    }, createClient: () => newClient()..setQueryData<String>(key, 'A'));

    // Without the `app` scaffold: `MaterialApp` rebuilds what is under it on
    // every pump, which would hide the very difference these two cases are
    // about. Under a bare provider the child is the same `const` widget, so
    // Flutter skips it and only a dependent is rebuilt.
    Widget provided(QueryClient client, Widget child) => QueryClientProvider(
          client: client,
          observeAppLifecycle: false,
          child: child,
        );

    queryWidgetTest('one scope: `of` subscribes to it, `read` does not',
        (tester, a) async {
      for (final read in <bool>[false, true]) {
        final b = tester.adopt(newClient());
        _c59Dependencies = 0;
        _c59Seen = null;
        // Told by `didChangeDependencies`, not by a build: the reader is
        // rebuilt either way when the provider above it is, and what the two
        // lookups differ in is whether the scope *notifies* them. `of`
        // subscribed to the private `_QueryClientScope`, which is gone.
        await tester.pumpWidget(provided(a, _C59ClientReader(read: read)));
        expect(_c59Dependencies, 1, reason: 'read: $read');
        expect(_c59Seen, same(a), reason: 'read: $read');

        await tester.pumpWidget(provided(b, _C59ClientReader(read: read)));
        await tester.pump();
        expect(_c59Dependencies, read ? 1 : 2, reason: 'read: $read');
        // Either way it reads the new client: what `read` gives up is being
        // told, not being right.
        expect(_c59Seen, same(b), reason: 'read: $read');

        await tester.pumpWidget(const SizedBox());
      }
    }, createClient: newClient);
  });

  // Release review, 2026-09-23 — the core's notes, "Release review
  // 2026-09-23 — client, keys and mutations".
  queryWidgetTest(
      'L4-1 a typed MutationStateController stays typed across setOptions',
      (tester, client) async {
    final gate = Completer<void>();
    final states = MutationStateController.typed(client,
        filters: const MutationFilters(status: MutationStatus.pending),
        select: (Mutation<Object?, String, Object?> m) => m.state.variables!);
    states.addListener(() {});
    final strings = MutationController<void, String, void>(
      client,
      MutationOptions<void, String, void>(mutationFn: (_) => gate.future),
    );
    final flags = MutationController<void, bool, void>(
      client,
      MutationOptions<void, bool, void>(mutationFn: (_) => gate.future),
    );
    try {
      strings.mutate('x');
      flags.mutate(true);
      await tester.pump();
      expect(states.value, <String>['x']);
      states.setOptions(filters: const MutationFilters());
      flags.mutate(false);
      await tester.pump();
      expect(states.value, <String>['x']);
      gate.complete();
      await tester.pumpAndSettle();
    } finally {
      strings.dispose();
      flags.dispose();
      states.dispose();
    }
  }, createClient: newClient);
  _releaseReview20260923();
}

/// What [_C59ClientReader] last read, and how often the scope told it its
/// dependencies changed.
int _c59Dependencies = 0;
QueryClient? _c59Seen;

class _C59ClientReader extends StatefulWidget {
  const _C59ClientReader({required this.read});

  /// `QueryClientProvider.read`, which does not subscribe, rather than `of`,
  /// which does.
  final bool read;

  @override
  State<_C59ClientReader> createState() => _C59ClientReaderState();
}

class _C59ClientReaderState extends State<_C59ClientReader> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c59Dependencies++;
  }

  @override
  Widget build(BuildContext context) {
    _c59Seen = widget.read
        ? QueryClientProvider.read(context)
        : QueryClientProvider.of(context);
    return const SizedBox();
  }
}

/// The two keyless styles reading one query with a `buildWhen`.
typedef _C49QueryReader = Widget Function(
  QueryObserverOptions<String> options,
  List<String?> builds,
);

/// The same, for an infinite query.
typedef _C49InfiniteReader = Widget Function(
  InfiniteQueryObserverOptions<List<String>, int> options,
  List<String> builds,
);

bool _dataChanged(QueryResult<String> previous, QueryResult<String> current) =>
    previous.dataOrNull != current.dataOrNull;

bool _pagesChanged(
  QueryResult<InfiniteData<List<String>, int>> previous,
  QueryResult<InfiniteData<List<String>, int>> current,
) =>
    '${previous.dataOrNull?.pages}' != '${current.dataOrNull?.pages}';

class _C49ContextQuery extends StatelessWidget {
  const _C49ContextQuery(this.options, this.builds);

  final QueryObserverOptions<String> options;
  final List<String?> builds;

  @override
  Widget build(BuildContext context) {
    final result = context.query(options, buildWhen: _dataChanged);
    builds.add(result.dataOrNull);
    return Text('${result.dataOrNull}');
  }
}

class _C49MixinQuery extends StatefulWidget {
  const _C49MixinQuery(this.options, this.builds);

  final QueryObserverOptions<String> options;
  final List<String?> builds;

  @override
  State<_C49MixinQuery> createState() => _C49MixinQueryState();
}

class _C49MixinQueryState extends State<_C49MixinQuery> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final result = watchQuery(widget.options, buildWhen: _dataChanged);
    widget.builds.add(result.dataOrNull);
    return Text('${result.dataOrNull}');
  }
}

class _C49ContextInfinite extends StatelessWidget {
  const _C49ContextInfinite(this.options, this.builds);

  final InfiniteQueryObserverOptions<List<String>, int> options;
  final List<String> builds;

  @override
  Widget build(BuildContext context) {
    final feed = context.infiniteQuery(options, buildWhen: _pagesChanged);
    builds.add('${feed.value.dataOrNull?.pages}');
    return Text('${feed.value.dataOrNull?.pages}');
  }
}

class _C49MixinInfinite extends StatefulWidget {
  const _C49MixinInfinite(this.options, this.builds);

  final InfiniteQueryObserverOptions<List<String>, int> options;
  final List<String> builds;

  @override
  State<_C49MixinInfinite> createState() => _C49MixinInfiniteState();
}

class _C49MixinInfiniteState extends State<_C49MixinInfinite> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final feed = watchInfiniteQuery(widget.options, buildWhen: _pagesChanged);
    widget.builds.add('${feed.value.dataOrNull?.pages}');
    return Text('${feed.value.dataOrNull?.pages}');
  }
}

/// The two keyless styles reading one mutation with a `buildWhen`: what each
/// build showed, and every pair the predicate was asked about.
typedef _C67MutationReader = Widget Function(
  List<String> builds,
  List<String> asked,
  Future<int> run,
);

/// `MutationOptions.simple` fixes the third type argument, so the read's
/// three types come off `mutationFn` alone — and so does the predicate's
/// `MutationResult<int, int>`. [run] is what the mutation waits on, so the
/// pending state is a state the test can stop in.
MutationOptions<int, int, void> _c67Options(Future<int> run) =>
    MutationOptions.simple(mutationFn: (int _) => run);

/// Rebuild for a finished run, never for the pending one, recording what it
/// was asked.
BuildWhen<MutationResult<int, int>> _c67Finished(List<String> asked) =>
    (previous, current) {
      asked.add('${previous.status.name}->${current.status.name}');
      return current.isSuccess;
    };

Widget _c67Tile(
  MutationController<int, int, void> add,
  List<String> builds,
) {
  builds.add('${add.value.status.name}:${add.value.dataOrNull}');
  return TextButton(
    onPressed: () => add.mutate(1),
    child: Text('${add.value.dataOrNull}'),
  );
}

class _C67ContextMutation extends StatelessWidget {
  const _C67ContextMutation(this.builds, this.asked, this.run);

  final List<String> builds;
  final List<String> asked;
  final Future<int> run;

  @override
  Widget build(BuildContext context) => _c67Tile(
        context.mutation(_c67Options(run), buildWhen: _c67Finished(asked)),
        builds,
      );
}

class _C67MixinMutation extends StatefulWidget {
  const _C67MixinMutation(this.builds, this.asked, this.run);

  final List<String> builds;
  final List<String> asked;
  final Future<int> run;

  @override
  State<_C67MixinMutation> createState() => _C67MixinMutationState();
}

class _C67MixinMutationState extends State<_C67MixinMutation> with QueryMixin {
  @override
  Widget build(BuildContext context) => _c67Tile(
        watchMutation(
          _c67Options(widget.run),
          buildWhen: _c67Finished(widget.asked),
        ),
        widget.builds,
      );
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
      onlineStatus: OnlineStatus.stream(online, initial: true),
      child: const SizedBox(),
    );

class _R4ContextReader extends StatelessWidget {
  const _R4ContextReader(this.options, this.builds);

  final QueryObserverOptions<String> options;
  final List<String> builds;

  @override
  Widget build(BuildContext context) {
    builds.add('context:${context.query(options).dataOrNull}');
    return const SizedBox();
  }
}

class _R4MixinReader extends StatefulWidget {
  const _R4MixinReader(this.options, this.builds);

  final QueryObserverOptions<String> options;
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
QueryObserverOptions<String> _shortlyStale() => QueryObserverOptions(
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
      QuerySelectOptions(
        queryKey: key,
        enabled: Enabled.no,
        select: (v) => v.toUpperCase(),
      ),
      id: 'upper',
    );
    final reversed = watchSelectQuery<String, String>(
      QuerySelectOptions(
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
      QuerySelectOptions(
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
      QuerySelectOptions(
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
    final upper = context.selectQuery<String, String>(QuerySelectOptions(
      queryKey: key,
      enabled: Enabled.no,
      select: (v) => v.toUpperCase(),
    ));
    final lower = context.selectQuery<String, String>(QuerySelectOptions(
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
    final task = watchQuery(QueryObserverOptions<String>(
      queryKey: QueryKey(<Object?>['m4', widget.id]),
      // Closes over the widget, as real code does.
      queryFn: (_) => widget.fetch(widget.id),
    ));
    return Text(task.dataOrNull ?? 'none');
  }
}

/// A `State` that reads a query from an explicitly overridden client.
class _R01Override extends StatefulWidget {
  const _R01Override(this.client);

  final QueryClient client;

  @override
  State<_R01Override> createState() => _R01OverrideState();
}

class _R01OverrideState extends State<_R01Override> with QueryMixin {
  @override
  QueryClient get queryClient => widget.client;

  @override
  Widget build(BuildContext context) {
    final result = watchQuery(QueryObserverOptions<String>(
      queryKey: key,
      queryFn: (_) async => 'fetched',
      staleTime: StaleTime.infinite,
    ));
    return Text(result.dataOrNull ?? 'none');
  }
}

/// A `State` that mixes the mixin in and never reads anything.
class _R01Bare extends StatefulWidget {
  const _R01Bare();

  @override
  State<_R01Bare> createState() => _R01BareState();
}

/// C1: reads an inline plain literal through `watchQuery`.
class _C1MixinReader extends StatefulWidget {
  const _C1MixinReader();

  @override
  State<_C1MixinReader> createState() => _C1MixinReaderState();
}

class _C1MixinReaderState extends State<_C1MixinReader> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final result = watchQuery(
        QueryObserverOptions(queryKey: key, queryFn: (_) async => 1));
    return Text('v:${result.dataOrNull}');
  }
}

/// C1: a plain infinite helper, as a screen would write one.
InfiniteQueryObserverOptions<List<int>, int> _c1Feed() =>
    InfiniteQueryObserverOptions(
      queryKey: key,
      pageFn: (context) async => <int>[context.pageParam + 1],
      initialPageParam: 0,
      getNextPageParam: (_, __, ___, ____) => null,
    );

class _R01BareState extends State<_R01Bare> with QueryMixin {
  @override
  Widget build(BuildContext context) =>
      const Text('nothing read', textDirection: TextDirection.ltr);
}

/// Runs a mutation from `context.mutation` and shows its state.
class _R04Box extends StatelessWidget {
  const _R04Box({super.key, required this.gate});

  final Completer<int> gate;

  @override
  Widget build(BuildContext context) {
    final run = context.mutation<int, int, void>(
      MutationOptions<int, int, void>(mutationFn: (_) => gate.future),
    );
    return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      Text('pending=${run.value.isPending} data=${run.value.dataOrNull}'),
      TextButton(onPressed: () => run.mutate(7), child: const Text('go')),
    ]);
  }
}

QueryKey _c47Key(int n) => QueryKey(<Object?>['c47', n]);

int _c47Observers(QueryClient client, int n) =>
    client.queryCache
        .find(filters: QueryFilters(queryKey: _c47Key(n)))
        ?.observersCount ??
    0;

InfiniteQueryObserverOptions<List<String>, int> _c47Feed(int n) =>
    InfiniteQueryObserverOptions<List<String>, int>(
      queryKey: _c47Key(n),
      initialPageParam: 0,
      pageFn: (context) async => <String>['$n.${context.pageParam}'],
      getNextPageParam: (_, __, lastParam, ___) => lastParam + 1,
      staleTime: StaleTime.infinite,
    );

class _C47InfiniteContext extends StatelessWidget {
  const _C47InfiniteContext(this.n, this.seen, {this.id});

  final int n;
  final List<Object> seen;
  final Object? id;

  @override
  Widget build(BuildContext context) {
    final feed = context.infiniteQuery(_c47Feed(n), id: id);
    seen.add(feed);
    return Text('${feed.value.dataOrNull?.pages}');
  }
}

class _C47InfiniteMixin extends StatefulWidget {
  const _C47InfiniteMixin(this.n, this.seen, {this.id});

  final int n;
  final List<Object> seen;
  final Object? id;

  @override
  State<_C47InfiniteMixin> createState() => _C47InfiniteMixinState();
}

class _C47InfiniteMixinState extends State<_C47InfiniteMixin> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final feed = watchInfiniteQuery(_c47Feed(widget.n), id: widget.id);
    widget.seen.add(feed);
    return Text('${feed.value.dataOrNull?.pages}');
  }
}

class _C47MixinTwoSelects extends StatefulWidget {
  const _C47MixinTwoSelects();

  @override
  State<_C47MixinTwoSelects> createState() => _C47MixinTwoSelectsState();
}

class _C47MixinTwoSelectsState extends State<_C47MixinTwoSelects>
    with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final upper = watchSelectQuery<String, String>(QuerySelectOptions(
      queryKey: key,
      enabled: Enabled.no,
      select: (v) => v.toUpperCase(),
    ));
    final lower = watchSelectQuery<String, String>(QuerySelectOptions(
      queryKey: key,
      enabled: Enabled.no,
      select: (v) => v.toLowerCase(),
    ));
    return Text('${upper.dataOrNull}/${lower.dataOrNull}');
  }
}

class _C47MixinTwoMutations extends StatefulWidget {
  const _C47MixinTwoMutations({this.withIds = false});

  final bool withIds;

  @override
  State<_C47MixinTwoMutations> createState() => _C47MixinTwoMutationsState();
}

class _C47MixinTwoMutationsState extends State<_C47MixinTwoMutations>
    with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final archive = watchMutation<String, String, void>(
      MutationOptions(mutationFn: (v) async => 'archived $v'),
      id: widget.withIds ? 'archive' : null,
    );
    final delete = watchMutation<String, String, void>(
      MutationOptions(mutationFn: (v) async => 'deleted $v'),
      id: widget.withIds ? 'delete' : null,
    );
    return Text('${archive.value.dataOrNull}/${delete.value.dataOrNull}');
  }
}

// ---------------------------------------------------------------------------
// Release review 2026-09-23 — binding.
// ---------------------------------------------------------------------------

QueryObserverOptions<String> _rr(String name) => QueryObserverOptions(
      queryKey: QueryKey(<Object?>[name]),
      staleTime: StaleTime.infinite,
      queryFn: (_) async => '$name-0',
    );

/// Reads `outer` in its own build and `inner<tab>` inside a nested builder
/// that re-runs on its own — through the mixin or through the outer
/// `context`.
class _RrNested extends StatefulWidget {
  const _RrNested(this.tab, {required this.mixin});
  final ValueNotifier<int> tab;
  final bool mixin;
  @override
  State<_RrNested> createState() => _RrNestedState();
}

class _RrNestedState extends State<_RrNested> with QueryMixin {
  QueryResult<String> _read(BuildContext context, String name) =>
      widget.mixin ? watchQuery(_rr(name)) : context.query(_rr(name));

  @override
  Widget build(BuildContext context) {
    final outer = _read(context, 'outer');
    return Column(children: [
      Text('outer=${outer.dataOrNull}'),
      ValueListenableBuilder<int>(
        valueListenable: widget.tab,
        // The outer `context`, not the builder's: the read belongs to this
        // State's element.
        builder: (_, tab, __) =>
            Text('inner=${_read(context, 'inner$tab').dataOrNull}'),
      ),
    ]);
  }
}

class _RrStableOptions extends StatefulWidget {
  const _RrStableOptions(this.paused, this.fetches, this.style);
  final ValueNotifier<bool> paused;
  final List<int> fetches;
  final String style;
  @override
  State<_RrStableOptions> createState() => _RrStableOptionsState();
}

class _RrStableOptionsState extends State<_RrStableOptions> {
  // Built once, the way a screen keeps its query definition in a field.
  late final QueryObserverOptions<int> plain = QueryObserverOptions(
    queryKey: QueryKey(const <Object?>['rr-stable']),
    enabled: Enabled.when((_) => !widget.paused.value),
    queryFn: (_) async => ++widget.fetches[0],
  );
  late final QuerySelectOptions<int, String> selected = QuerySelectOptions(
    queryKey: QueryKey(const <Object?>['rr-stable']),
    enabled: Enabled.when((_) => !widget.paused.value),
    queryFn: (_) async => ++widget.fetches[0],
    select: (n) => '$n',
  );
  late final InfiniteQueryObserverOptions<int, int> infinite =
      InfiniteQueryObserverOptions<int, int>(
    queryKey: QueryKey(const <Object?>['rr-stable-infinite']),
    enabled: Enabled.when((_) => !widget.paused.value),
    initialPageParam: 0,
    pageFn: (_) async => ++widget.fetches[0],
    getNextPageParam: (_, __, ___, ____) => null,
  );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: widget.paused,
        builder: (context, _, __) => switch (widget.style) {
          'QueryBuilder' => QueryBuilder<int>(
              options: plain,
              builder: (context, r) => Text('n=${r.dataOrNull}'),
            ),
          'QuerySelectBuilder' => QuerySelectBuilder<int, String>(
              options: selected,
              builder: (context, r) => Text('n=${r.dataOrNull}'),
            ),
          'InfiniteQueryBuilder' => InfiniteQueryBuilder(
              options: infinite,
              builder: (context, q) => Text('n=${q.value.dataOrNull}'),
            ),
          _ => Builder(
              builder: (context) =>
                  Text('n=${context.query(plain).dataOrNull}'),
            ),
        },
      );
}

class _RrKeyedMutations extends StatefulWidget {
  const _RrKeyedMutations({required this.mixin});
  final bool mixin;
  @override
  State<_RrKeyedMutations> createState() => _RrKeyedMutationsState();
}

class _RrKeyedMutationsState extends State<_RrKeyedMutations> with QueryMixin {
  MutationController<String, String, void> _read(
    BuildContext context,
    MutationOptions<String, String, void> options,
  ) =>
      widget.mixin ? watchMutation(options) : context.mutation(options);

  @override
  Widget build(BuildContext context) {
    // One category key for two different mutations: ordinary upstream.
    final todos = QueryKey(const <Object?>['todos']);
    _read(context,
        MutationOptions(mutationKey: todos, mutationFn: (v) async => 'add:$v'));
    _read(
        context,
        MutationOptions(
            mutationKey: todos, mutationFn: (v) async => 'remove:$v'));
    return const Text('built');
  }
}

// Release review 2026-09-23, second pass (verification of the fixes).

int _rrObservers(QueryClient client, String name) =>
    client.queryCache.get<String>(QueryKey(<Object?>[name]))?.observersCount ??
    -1;

/// One list row as its own widget: the shape the V-B-2 error points to.
class _RrRow extends StatelessWidget {
  const _RrRow(this.name);
  final String name;
  @override
  Widget build(BuildContext context) =>
      Text('$name=${context.query(_rr(name)).dataOrNull}');
}

Future<String> _rrSave(int v) async => 'saved $v';

/// Reads one keyed mutation twice in one frame through a getter (V-B-4).
/// [shape] says how the getter builds its options: `field` hands out one
/// stored object, `tearOff` builds new options around a function that
/// compares equal every time, `closure` builds new options around a new
/// function literal every time.
class _RrMutationTwice extends StatefulWidget {
  const _RrMutationTwice(this.shape, {this.nested = false});
  final String shape;

  /// Read once in `build` and once in a nested builder instead.
  final bool nested;
  @override
  State<_RrMutationTwice> createState() => _RrMutationTwiceState();
}

class _RrMutationTwiceState extends State<_RrMutationTwice> with QueryMixin {
  static final _key = QueryKey(const <Object?>['save']);
  final _field = MutationOptions<String, int, Object?>(
      mutationKey: _key, mutationFn: _rrSave);

  MutationController<String, int, Object?> get _save =>
      watchMutation(switch (widget.shape) {
        'field' => _field,
        'tearOff' => MutationOptions<String, int, Object?>(
            mutationKey: _key, mutationFn: _rrSave),
        _ => MutationOptions<String, int, Object?>(
            mutationKey: _key, mutationFn: (v) async => 'ok$v'),
      });

  @override
  Widget build(BuildContext context) {
    final a = _save;
    if (widget.nested) {
      return Builder(
          builder: (_) => Text('${a.value.status} ${identical(a, _save)}'));
    }
    final b = _save;
    return Text('${a.value.status} ${identical(a, b)}');
  }
}

// Release review 2026-09-23, third pass.

void _rrPop(String d, int v, Object? r) {}
void _rrSnack(String d, int v, Object? r) {}

/// Reads one keyed mutation twice in one build: the same tear-off as its
/// function each time, and callbacks that are the same ([sameCallbacks]) or
/// not (V3-6).
class _RrSameFnOtherCallbacks extends StatelessWidget {
  const _RrSameFnOtherCallbacks({required this.sameCallbacks});
  final bool sameCallbacks;
  static final _key = QueryKey(const <Object?>['delete']);
  @override
  Widget build(BuildContext context) {
    final pop = context.mutation(MutationOptions<String, int, Object?>(
        mutationKey: _key, mutationFn: _rrSave, onSuccess: _rrPop));
    final snack = context.mutation(MutationOptions<String, int, Object?>(
        mutationKey: _key,
        mutationFn: _rrSave,
        onSuccess: sameCallbacks ? _rrPop : _rrSnack));
    return Text('${identical(pop, snack)}');
  }
}

// Release review 2026-09-23, fourth pass.

Set<String> _rrHeld(QueryClient client) => {
      for (final q in client.queryCache.findAll())
        if (q.observersCount > 0) q.queryKey.parts.single as String,
    };

/// An inherited selection a reader depends on (V4-1).
class _RrSel extends InheritedWidget {
  const _RrSel({required this.value, required super.child});
  final int value;
  static int of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RrSel>()!.value;
  @override
  bool updateShouldNotify(_RrSel old) => old.value != value;
}

/// Rebuilds [_RrSel] around the same [child] instance: only the dependency
/// moves, the child is never handed a new widget.
class _RrSelHolder extends StatefulWidget {
  const _RrSelHolder({required this.sel, required this.child});
  final ValueNotifier<int> sel;
  final Widget child;
  @override
  State<_RrSelHolder> createState() => _RrSelHolderState();
}

class _RrSelHolderState extends State<_RrSelHolder> {
  @override
  void initState() {
    super.initState();
    widget.sel.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.sel.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _RrSel(value: widget.sel.value, child: widget.child);
}

/// Reads `w` in its own build and `inner<tick>` in a nested builder (V4-4).
class _RrOwnAndNested extends StatelessWidget {
  // Not const: every parent build hands a new instance, as an inline widget
  // does.
  // ignore: prefer_const_constructors_in_immutables
  _RrOwnAndNested(this.tick);
  final ValueNotifier<int> tick;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text('w=${context.query(_rr('w')).dataOrNull}'),
        ValueListenableBuilder<int>(
          valueListenable: tick,
          builder: (_, t, __) =>
              Text('inner$t=${context.query(_rr('inner$t')).dataOrNull}'),
        ),
      ]);
}

void _releaseReview20260923() {
  group('Release review 2026-09-23', () {
    for (final mixin in [true, false]) {
      final style = mixin ? 'watchQuery' : 'context.query';
      queryWidgetTest(
          'BIND-1: a $style read in build survives a nested builder '
          're-running alone', (tester, client) async {
        final tab = ValueNotifier<int>(0);
        addTearDown(tab.dispose);
        await tester.pumpWidget(app(client, _RrNested(tab, mixin: mixin)));
        await tester.pump();
        expect(find.text('outer=outer-0'), findsOneWidget);
        expect(find.text('inner=inner0-0'), findsOneWidget);

        // Seeded and fresh: the switch fetches nothing, so no notification
        // rebuilds the whole State behind the nested builder's back.
        client.setQueryData<String>(QueryKey(const <Object?>['inner1']), 'i1');
        tab.value = 1;
        await tester.pump();
        await tester.pump();
        expect(find.text('inner=i1'), findsOneWidget);
        final inner0 =
            client.queryCache.get<String>(QueryKey(const <Object?>['inner0']))!;
        // Documented: a nested builder's read is additive, so the key it
        // stopped reading stays until the element's own next build.
        expect(inner0.observersCount, 1);

        client.setQueryData<String>(QueryKey(const <Object?>['outer']), 'o1');
        await tester.pump();
        await tester.pump();
        expect(find.text('outer=o1'), findsOneWidget);
        // That own build was the next one: now it goes.
        expect(inner0.observersCount, 0);
        expect(find.text('inner=i1'), findsOneWidget);
      });
    }

    // Reading through the itemBuilder's own context is a debug error since
    // the second pass (V-B-2, below); the row widget it points to is what
    // keeps a visible item after a scroll.
    queryWidgetTest(
        'BIND-2: a ListView.builder row reading context.query keeps a '
        'visible item after a scroll', (tester, client) async {
      for (var i = 0; i < 50; i++) {
        client.setQueryData<String>(QueryKey(<Object?>['item$i']), 'item$i-0');
      }
      await tester.pumpWidget(app(
        client,
        ListView.builder(
          itemExtent: 100,
          itemCount: 50,
          itemBuilder: (_, i) => _RrRow('item$i'),
        ),
      ));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -150));
      await tester.pump();
      await tester.pump();
      expect(find.text('item3=item3-0'), findsOneWidget);

      client.setQueryData<String>(QueryKey(const <Object?>['item3']), 'new');
      await tester.pump();
      await tester.pump();
      expect(find.text('item3=new'), findsOneWidget);
    });

    queryWidgetTest(
        'BIND-1/2: a key switched by a parent update is still released',
        (tester, client) async {
      Widget reader(String name) => Builder(
          builder: (context) => Text('${context.query(_rr(name)).dataOrNull}'));
      await tester.pumpWidget(app(client, reader('a')));
      await tester.pump();
      await tester.pumpWidget(app(client, reader('b')));
      await tester.pump();
      await tester.pump();
      expect(find.text('b-0'), findsOneWidget);
      expect(
          client.queryCache
              .get<String>(QueryKey(const <Object?>['a']))!
              .observersCount,
          0);
    });

    for (final style in [
      'QueryBuilder',
      'QuerySelectBuilder',
      'InfiniteQueryBuilder',
      'context.query',
    ]) {
      queryWidgetTest(
          'BIND-3: $style with options kept in a field re-evaluates '
          'Enabled.when on rebuild', (tester, client) async {
        final paused = ValueNotifier<bool>(true);
        addTearDown(paused.dispose);
        final fetches = [0];
        await tester
            .pumpWidget(app(client, _RrStableOptions(paused, fetches, style)));
        await tester.pump();
        expect(fetches[0], 0);

        paused.value = false;
        await tester.pump();
        await tester.pump();
        expect(fetches[0], 1, reason: 'resumed by the rebuild');
      });
    }

    queryWidgetTest(
        'BIND-4: taking the onlineStatus away puts the client back online',
        (tester, client) async {
      final changes = StreamController<bool>.broadcast();
      addTearDown(changes.close);
      await tester.pumpWidget(app(client, const SizedBox(),
          onlineStatus: OnlineStatus.stream(changes.stream, initial: true)));
      changes.add(false);
      await tester.pump();
      expect(client.onlineManager.isOnline(), isFalse);

      await tester.pumpWidget(app(client, const SizedBox()));
      expect(client.onlineManager.isOnline(), isTrue);
    });

    queryWidgetTest(
        'BIND-4: a provider that goes away puts its client back online',
        (tester, client) async {
      await tester.pumpWidget(app(client, const SizedBox(),
          onlineStatus: const OnlineStatus.fixed(false)));
      expect(client.onlineManager.isOnline(), isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(client.onlineManager.isOnline(), isTrue);
    });

    queryWidgetTest(
        'BIND-5: naming the provider\'s own client keeps a MutationBuilder\'s '
        'controller mid-run', (tester, client) async {
      final done = Completer<int>();
      MutationController<int, int, void>? seen;
      Widget tree(QueryClient? explicit) => app(
            client,
            MutationBuilder<int, int, void>(
              client: explicit,
              options: MutationOptions(mutationFn: (_) => done.future),
              builder: (context, m) {
                seen = m;
                return Text('pending=${m.value.isPending} '
                    'data=${m.value.dataOrNull}');
              },
            ),
          );
      await tester.pumpWidget(tree(null));
      seen!.mutate(1);
      await tester.pump();
      expect(find.text('pending=true data=null'), findsOneWidget);

      await tester.pumpWidget(tree(client));
      await tester.pump();
      expect(find.text('pending=true data=null'), findsOneWidget);
      done.complete(1);
      await tester.pump();
      await tester.pump();
      expect(find.text('pending=false data=1'), findsOneWidget);
    });

    queryWidgetTest(
        'BIND-5: naming the provider\'s own client keeps a QueriesBuilder\'s '
        'observers', (tester, client) async {
      Widget tree(QueryClient? explicit) => app(
            client,
            QueriesBuilder<String, String>(
              client: explicit,
              queries: [_rr('q')],
              builder: (context, r) => Text('${r.single.dataOrNull}'),
            ),
          );
      await tester.pumpWidget(tree(null));
      await tester.pump();
      final query =
          client.queryCache.get<String>(QueryKey(const <Object?>['q']))!;
      final observer = query.observers.single;
      await tester.pumpWidget(tree(client));
      await tester.pump();
      expect(query.observers.single, same(observer));
    });

    queryWidgetTest(
        'B2-1: a provider client swap and a key change in one frame fetch '
        'on the new client only', (tester, client) async {
      final other = tester.adopt(QueryClient());
      final calls = <String>[];
      QueryObserverOptions<String> opts(String u) => QueryObserverOptions(
          queryKey: QueryKey(<Object?>['me', u]),
          queryFn: (_) async {
            calls.add(u);
            return u;
          });
      for (final queries in [false, true]) {
        calls.clear();
        Widget view(QueryClient c, String u) => app(
            c,
            queries
                ? QueriesBuilder<String, String>(
                    queries: [opts(u)],
                    builder: (_, r) => Text(r.single.dataOrNull ?? '-'))
                : QueryBuilder<String>(
                    options: opts(u),
                    builder: (_, r) => Text(r.dataOrNull ?? '-')));
        await tester.pumpWidget(view(client, 'alice$queries'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(view(other, 'bob$queries'));
        await tester.pumpAndSettle();
        expect(calls, ['alice$queries', 'bob$queries'],
            reason: 'queries: $queries');
        expect(
            client
                .getQueryData<String>(QueryKey(<Object?>['me', 'bob$queries'])),
            isNull,
            reason: 'queries: $queries');
        await tester.pumpWidget(const SizedBox());
      }
    });

    test('B2-2: per-call callbacks run on a live controller nobody listens to',
        () async {
      final client = QueryClient();
      final events = <String>[];
      final m = MutationController<int, int, void>(
          client,
          MutationOptions(
              mutationFn: (v) async => v,
              onSuccess: (_, __, ___) => events.add('options')));
      await m.mutateAsync(1,
          callbacks:
              MutateCallbacks(onSuccess: (_, __, ___) => events.add('call')));
      await Future<void>.delayed(Duration.zero);
      expect(events, ['options', 'call']);
      m.dispose();
      client.clear();
    });

    queryWidgetTest(
        'B2-2: a listened MutationController still notifies once per change',
        (tester, client) async {
      final done = Completer<int>();
      final m = MutationController<int, int, void>(
          client, MutationOptions(mutationFn: (_) => done.future));
      final seen = <bool>[];
      void listener() => seen.add(m.value.isPending);
      m.addListener(listener);
      m.mutate(1);
      await tester.pump();
      done.complete(1);
      await tester.pump();
      await tester.pump();
      expect(seen, [true, false]);
      m.removeListener(listener);
      m.dispose();
    });

    test('B2-3: options the observer refused are not kept', () {
      final client = QueryClient();
      final a = QueryKey(const <Object?>['a']);
      final b = QueryKey(const <Object?>['b']);
      client.setQueryData<int>(a, 1);
      client.queryCache.build(
          client, client.defaultQueryOptions(QueryOptions<int>(queryKey: b)));
      final c = QueryController.create<int>(
          client, QueryObserverOptions(queryKey: a, enabled: Enabled.no));
      expect(
          () => c.setOptions(QueryObserverOptions<int>(
              queryKey: b,
              enabled: Enabled.no,
              initialData:
                  InitialData.compute(() => throw StateError('seed')))),
          throwsStateError);
      expect(c.observer.options.queryKey, a);
      expect(c.value.dataOrNull, 1);
      c.dispose();
      client.clear();
    });

    queryWidgetTest('B2-4: QueriesBuilder builds once for one list change',
        (tester, client) async {
      for (final name in ['a', 'b', 'c']) {
        client.setQueryData<String>(QueryKey(<Object?>[name]), name);
      }
      var builds = 0;
      Widget tree(List<String> names) => app(
          client,
          QueriesBuilder<String, String>(
              queries: [for (final n in names) _rr(n)],
              builder: (_, r) {
                builds++;
                return Text(r.map((e) => e.dataOrNull).join());
              }));
      await tester.pumpWidget(tree(['a', 'b', 'c']));
      await tester.pumpAndSettle();
      builds = 0;
      await tester.pumpWidget(tree(['a', 'b']));
      await tester.pumpAndSettle();
      expect(find.text('ab'), findsOneWidget);
      expect(builds, 1);
    });

    for (final mixin in [true, false]) {
      queryWidgetTest(
          'B1-1: two ${mixin ? 'watchMutation' : 'context.mutation'} reads '
          'sharing a mutationKey assert instead of sharing a controller',
          (tester, client) async {
        await tester.pumpWidget(app(client, _RrKeyedMutations(mixin: mixin)));
        final error = tester.takeException();
        expect(error, isA<FlutterError>());
        expect('$error', contains('id:'));
      });
    }

    queryWidgetTest(
        'B1-2: a failing cancel of the onlineStatus subscription is reported, '
        'not thrown into the zone', (tester, client) async {
      // Single-subscription: a broadcast controller drops what its onCancel
      // returns and never hands it to `cancel()` (so the review's broadcast
      // repro failed in dart:async, whatever the provider did).
      final online = StreamController<bool>(
          onCancel: () => Future<void>.error(StateError('cancel failed')));
      await tester.pumpWidget(app(client, const SizedBox(),
          onlineStatus: OnlineStatus.stream(online.stream, initial: true)));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isA<StateError>());
    });

    queryWidgetTest(
        'B1-3: a single-subscription stream listened to twice says what to do',
        (tester, client) async {
      final online = StreamController<bool>();
      addTearDown(online.close);
      final status = OnlineStatus.stream(online.stream, initial: true);
      await tester
          .pumpWidget(app(client, const SizedBox(), onlineStatus: status));
      await tester.pumpWidget(const SizedBox());
      await tester
          .pumpWidget(app(client, const SizedBox(), onlineStatus: status));
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect('$error', contains('broadcast'));
    });

    queryWidgetTest(
        'S3: the first resumed after an unknown lifecycle state is no focus '
        'change', (tester, client) async {
      expect(tester.binding.lifecycleState, isNull);
      var fetches = 0;
      await tester.pumpWidget(app(
        client,
        Builder(
          builder: (context) => Text('${context.query(QueryObserverOptions<int>(
                queryKey: QueryKey(const <Object?>['s3']),
                queryFn: (_) async => ++fetches,
              )).dataOrNull}'),
        ),
        observeAppLifecycle: true,
      ));
      await tester.pumpAndSettle();
      expect(fetches, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(fetches, 1);
    });

    // Second pass (verification of the fixes above).

    queryWidgetTest(
        'V-B-1: a LayoutBuilder reading through its own context releases the '
        'key it stopped reading', (tester, client) async {
      final width = ValueNotifier<double>(800);
      addTearDown(width.dispose);
      await tester.pumpWidget(app(
        client,
        ValueListenableBuilder<double>(
          valueListenable: width,
          // Passed as `child`: the LayoutBuilder keeps its widget, and only
          // its constraints change.
          child: LayoutBuilder(
            builder: (context, c) => Text(c.maxWidth > 600
                ? 'wide=${context.query(_rr('wide')).dataOrNull}'
                : 'narrow=${context.query(_rr('narrow')).dataOrNull}'),
          ),
          builder: (_, w, child) =>
              Center(child: SizedBox(width: w, height: 100, child: child)),
        ),
      ));
      await tester.pump();
      expect(_rrObservers(client, 'wide'), 1);

      width.value = 300;
      await tester.pump();
      await tester.pump();
      expect(find.text('narrow=narrow-0'), findsOneWidget);
      expect(_rrObservers(client, 'narrow'), 1);
      expect(_rrObservers(client, 'wide'), 0);

      // Frames that do not re-run the builder keep what it read.
      client.setQueryData<String>(QueryKey(const <Object?>['narrow']), 'n1');
      await tester.pump();
      await tester.pump();
      expect(find.text('narrow=n1'), findsOneWidget);
      expect(_rrObservers(client, 'narrow'), 1);
    });

    queryWidgetTest(
        'V-B-1: an OrientationBuilder releases the key of the orientation it '
        'left', (tester, client) async {
      final width = ValueNotifier<double>(800);
      addTearDown(width.dispose);
      await tester.pumpWidget(app(
        client,
        ValueListenableBuilder<double>(
          valueListenable: width,
          child: OrientationBuilder(
            builder: (context, o) => Text(o == Orientation.landscape
                ? 'l=${context.query(_rr('land')).dataOrNull}'
                : 'p=${context.query(_rr('port')).dataOrNull}'),
          ),
          builder: (_, w, child) =>
              Center(child: SizedBox(width: w, height: 500, child: child)),
        ),
      ));
      await tester.pump();
      expect(_rrObservers(client, 'land'), 1);
      width.value = 300;
      await tester.pump();
      await tester.pump();
      expect(find.text('p=port-0'), findsOneWidget);
      expect(_rrObservers(client, 'land'), 0);
    });

    for (final (kind, read) in [
      ('ListView.builder', 'query'),
      ('ListView.builder', 'mutation'),
      ('GridView.builder', 'query'),
      ('PageView.builder', 'query'),
    ]) {
      queryWidgetTest(
          'V-B-2: context.$read through a $kind itemBuilder\'s own context '
          'is a debug error that names the fix', (tester, client) async {
        Widget item(BuildContext context, int i) => Text(read == 'query'
            ? '${context.query(_rr('item$i')).dataOrNull}'
            : '${context.mutation(MutationOptions<String, int, void>(mutationFn: (v) async => '$v')).value.status}');
        await tester.pumpWidget(app(
          client,
          switch (kind) {
            'GridView.builder' => GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 1),
                itemCount: 1,
                itemBuilder: item),
            'PageView.builder' =>
              PageView.builder(itemCount: 1, itemBuilder: item),
            _ => ListView.builder(itemCount: 1, itemBuilder: item),
          },
        ));
        final error = tester.takeException();
        expect(error, isA<FlutterError>());
        expect('$error', contains('widget of its own'));
        expect(_rrObservers(client, 'item0'), -1);
      });
    }

    queryWidgetTest(
        'V-B-2: a list whose rows are widgets of their own keeps the visible '
        'rows and releases the ones scrolled away', (tester, client) async {
      for (var i = 0; i < 200; i++) {
        client.setQueryData<String>(QueryKey(<Object?>['it$i']), 'v');
      }
      await tester.pumpWidget(app(
        client,
        ListView.builder(
          itemExtent: 100,
          itemCount: 200,
          itemBuilder: (_, i) => _RrRow('it$i'),
        ),
      ));
      await tester.pump();
      for (var k = 0; k < 20; k++) {
        await tester.drag(find.byType(ListView), const Offset(0, -900));
        await tester.pump();
      }
      await tester.pump();
      final visible = [
        for (var i = 0; i < 200; i++)
          if (find.text('it$i=v').evaluate().isNotEmpty) i
      ];
      expect(visible, isNotEmpty);
      final shown = visible.first;
      client.setQueryData<String>(QueryKey(<Object?>['it$shown']), 'w');
      await tester.pump();
      await tester.pump();
      expect(find.text('it$shown=w'), findsOneWidget);
      var held = 0;
      for (var i = 0; i < 200; i++) {
        if (_rrObservers(client, 'it$i') > 0) held++;
      }
      expect(held, lessThan(40), reason: 'held=$held');
    });

    queryWidgetTest(
        'V-B-3: a replacement provider on the same client keeps its offline '
        'verdict when the old one is disposed after it',
        (tester, client) async {
      Widget tree(Key k) => QueryClientProvider(
            key: k,
            client: client,
            observeAppLifecycle: false,
            onlineStatus: const OnlineStatus.fixed(false),
            child: const SizedBox(),
          );
      await tester.pumpWidget(tree(const ValueKey(1)));
      expect(client.onlineManager.isOnline(), isFalse);
      await tester.pumpWidget(tree(const ValueKey(2)));
      expect(client.onlineManager.isOnline(), isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(client.onlineManager.isOnline(), isTrue);
    });

    queryWidgetTest(
        'V-B-3: a provider moved to another parent keeps its offline verdict',
        (tester, client) async {
      Widget tree({required bool padded}) {
        // No GlobalKey: a new parent type is a new provider element.
        final child = QueryClientProvider(
          client: client,
          observeAppLifecycle: false,
          onlineStatus: const OnlineStatus.fixed(false),
          child: const SizedBox(),
        );
        return padded
            ? Padding(padding: EdgeInsets.zero, child: child)
            : Center(child: child);
      }

      await tester.pumpWidget(tree(padded: false));
      expect(client.onlineManager.isOnline(), isFalse);
      await tester.pumpWidget(tree(padded: true));
      expect(client.onlineManager.isOnline(), isFalse);
    });

    queryWidgetTest(
        'V-B-3: of two providers speaking for one client, the last to leave '
        'puts it back online', (tester, client) async {
      Widget provider({OnlineStatus? status}) => QueryClientProvider(
            client: client,
            observeAppLifecycle: false,
            onlineStatus: status,
            child: const SizedBox(),
          );
      await tester.pumpWidget(Column(children: [
        provider(status: const OnlineStatus.fixed(false)),
        provider(status: const OnlineStatus.fixed(false)),
      ]));
      expect(client.onlineManager.isOnline(), isFalse);
      // One stops speaking on a later build; one is still there.
      await tester.pumpWidget(Column(children: [
        provider(status: const OnlineStatus.fixed(false)),
        provider(),
      ]));
      expect(client.onlineManager.isOnline(), isFalse);
      await tester.pumpWidget(Column(children: [provider()]));
      expect(client.onlineManager.isOnline(), isTrue);
    });

    for (final shape in ['field', 'tearOff']) {
      queryWidgetTest(
          'V-B-4: one keyed mutation read twice in one build through a '
          'getter ($shape) is no ambiguity', (tester, client) async {
        await tester.pumpApp(client, _RrMutationTwice(shape));
        expect(tester.takeException(), isNull);
        expect(find.text('${MutationStatus.idle} true'), findsOneWidget);
      });
    }

    queryWidgetTest(
        'V-B-4: the same keyed mutation read in build and again in a nested '
        'builder is no ambiguity', (tester, client) async {
      await tester.pumpApp(
          client, const _RrMutationTwice('closure', nested: true));
      expect(tester.takeException(), isNull);
      expect(find.text('${MutationStatus.idle} true'), findsOneWidget);
    });

    queryWidgetTest(
        'V-B-4: a getter building a new function literal per read is still '
        'two mutations to the binding', (tester, client) async {
      await tester.pumpApp(client, const _RrMutationTwice('closure'));
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect('$error', contains('read it once'));
    });

    queryWidgetTest(
        'V-B-5: controller.observer.mutateAsync on an unlistened controller '
        'follows the core and skips the per-call callbacks',
        (tester, client) async {
      var calls = 0;
      final m = MutationController<int, int, void>(
          client, MutationOptions(mutationFn: (v) async => v));
      addTearDown(m.dispose);
      await m.observer.mutateAsync(1,
          callbacks: MutateCallbacks(onSuccess: (_, __, ___) => calls++));
      await tester.pump();
      expect(calls, 0);
      // The controller's own mutateAsync is what holds the run.
      await m.mutateAsync(2,
          callbacks: MutateCallbacks(onSuccess: (_, __, ___) => calls++));
      await tester.pump();
      expect(calls, 1);
    });

    // Third pass (verification of the second pass).

    queryWidgetTest(
        'V3-1: a LayoutBuilder\'s own read survives a nested builder reading '
        'through its context alone', (tester, client) async {
      final tab = ValueNotifier<int>(0);
      addTearDown(tab.dispose);
      await tester.pumpWidget(app(
        client,
        LayoutBuilder(
          builder: (context, c) => Column(children: [
            Text('outer=${context.query(_rr('outer')).dataOrNull}'),
            ValueListenableBuilder<int>(
              valueListenable: tab,
              builder: (_, t, __) =>
                  Text('inner=${context.query(_rr('inner$t')).dataOrNull}'),
            ),
          ]),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(_rrObservers(client, 'outer'), 1);

      // Seeded: the nested read notifies nothing, so only it re-runs.
      client.setQueryData<String>(QueryKey(const <Object?>['inner1']), 'i1');
      await tester.pump();
      tab.value = 1;
      await tester.pump();
      await tester.pump();
      expect(find.text('inner=i1'), findsOneWidget);
      expect(_rrObservers(client, 'outer'), 1, reason: 'released while shown');
      client.setQueryData<String>(QueryKey(const <Object?>['outer']), 'o1');
      await tester.pump();
      await tester.pump();
      expect(find.text('outer=o1'), findsOneWidget);
    });

    queryWidgetTest(
        'V3-2: rows an itemBuilder reads through an enclosing LayoutBuilder '
        'keep their subscriptions while shown', (tester, client) async {
      for (var i = 0; i < 100; i++) {
        client.setQueryData<String>(QueryKey(<Object?>['r$i']), 'r$i-0');
      }
      await tester.pumpWidget(app(
        client,
        LayoutBuilder(
          builder: (context, c) => ListView.builder(
            itemCount: 100,
            itemExtent: 50,
            itemBuilder: (_, i) =>
                Text('r$i=${context.query(_rr('r$i')).dataOrNull}'),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(_rrObservers(client, 'r5'), 1);
      await tester.drag(find.byType(ListView), const Offset(0, -50));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('r5='), findsOneWidget);
      expect(_rrObservers(client, 'r5'), 1, reason: 'visible row released');
      client.setQueryData<String>(QueryKey(const <Object?>['r5']), 'x');
      await tester.pump();
      await tester.pump();
      expect(find.text('r5=x'), findsOneWidget);
      // Additive, and bounded: gone with the LayoutBuilder.
      await tester.pumpWidget(app(client, const SizedBox()));
      await tester.pump();
      expect(_rrObservers(client, 'r5'), 0);
      expect(_rrObservers(client, 'r0'), 0);
    });

    for (final layout in [true, false]) {
      queryWidgetTest(
          'V3-5: a nested builder re-reading the keyed mutation a '
          '${layout ? 'LayoutBuilder' : 'Builder'} read does not assert',
          (tester, client) async {
        // A function literal per read: a new closure every time.
        Widget body(BuildContext context) {
          final m = context.mutation(MutationOptions<int, int, void>(
              mutationKey: QueryKey(const <Object?>['save']),
              mutationFn: (v) async => v));
          return Column(children: [
            Text('${m.value.status}'),
            Builder(
              builder: (_) => Text('${context.mutation(
                    MutationOptions<int, int, void>(
                        mutationKey: QueryKey(const <Object?>['save']),
                        mutationFn: (v) async => v),
                  ).value.status}'),
            ),
          ]);
        }

        await tester.pumpWidget(app(
            client,
            layout
                ? LayoutBuilder(builder: (context, _) => body(context))
                : Builder(builder: body)));
        expect(tester.takeException(), isNull);
      });
    }

    queryWidgetTest(
        'V3-6: one keyed mutation read twice with the same function but other '
        'callbacks asserts', (tester, client) async {
      await tester.pumpApp(
          client, const _RrSameFnOtherCallbacks(sameCallbacks: false));
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect('$error', contains('callbacks'));
    });

    queryWidgetTest(
        'V3-6: the same function and the same callbacks read twice are one '
        'mutation', (tester, client) async {
      await tester.pumpApp(
          client, const _RrSameFnOtherCallbacks(sameCallbacks: true));
      expect(tester.takeException(), isNull);
      expect(find.text('true'), findsOneWidget);
    });

    queryWidgetTest('V3-4: a provider whose initState threw speaks for nobody',
        (tester, client) async {
      final online = StreamController<bool>();
      addTearDown(online.close);
      final status = OnlineStatus.stream(online.stream, initial: true);
      await tester
          .pumpWidget(app(client, const SizedBox(), onlineStatus: status));
      await tester.pumpWidget(const SizedBox());
      await tester
          .pumpWidget(app(client, const SizedBox(), onlineStatus: status));
      expect(tester.takeException(), isA<FlutterError>());
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(client, const SizedBox(),
          onlineStatus: const OnlineStatus.fixed(false)));
      expect(client.onlineManager.isOnline(), isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(client.onlineManager.isOnline(), isTrue,
          reason: 'last speaker gone, client still offline');
    });

    // Fourth pass (verification of the third).

    for (final layout in [true, false]) {
      queryWidgetTest(
          'V4-1: a ${layout ? 'LayoutBuilder' : 'Builder'} whose key comes '
          'from another query releases the key it left',
          (tester, client) async {
        client.setQueryData<String>(QueryKey(const <Object?>['sel']), '0');
        for (var i = 0; i < 6; i++) {
          client.setQueryData<String>(QueryKey(<Object?>['item$i']), 'v$i');
        }
        Widget reader(BuildContext context) {
          final key = 'item${context.query(_rr('sel')).dataOrNull}';
          return Text('$key=${context.query(_rr(key)).dataOrNull}');
        }

        await tester.pumpWidget(app(
            client,
            layout
                ? LayoutBuilder(builder: (context, _) => reader(context))
                : Builder(builder: reader)));
        await tester.pump();
        for (var i = 1; i < 6; i++) {
          client.setQueryData<String>(QueryKey(const <Object?>['sel']), '$i');
          await tester.pump();
          await tester.pump();
          expect(find.text('item$i=v$i'), findsOneWidget);
        }
        expect(_rrHeld(client), {'sel', 'item5'});
      });
    }

    queryWidgetTest(
        'V4-1: a LayoutBuilder stops polling the key of the layout it left',
        (tester, client) async {
      final fetches = <String, int>{};
      QueryObserverOptions<String> polling(String key) => QueryObserverOptions(
            queryKey: QueryKey(<Object?>[key]),
            refetchInterval: const RefetchInterval.every(Duration(seconds: 1)),
            queryFn: (_) async {
              fetches[key] = (fetches[key] ?? 0) + 1;
              return key;
            },
          );
      final width = ValueNotifier<double>(800);
      addTearDown(width.dispose);
      await tester.pumpWidget(app(
        client,
        ValueListenableBuilder<double>(
          valueListenable: width,
          child: LayoutBuilder(
            builder: (context, c) {
              final key = c.maxWidth > 600 ? 'wide' : 'narrow';
              return Text('$key=${context.query(polling(key)).dataOrNull}');
            },
          ),
          builder: (_, w, child) =>
              Center(child: SizedBox(width: w, height: 100, child: child)),
        ),
      ));
      await tester.pump();
      width.value = 300;
      await tester.pump();
      await tester.pump();
      expect(find.text('narrow=narrow'), findsOneWidget);
      final before = fetches['wide'] ?? 0;
      for (var s = 0; s < 5; s++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(fetches['wide'] ?? 0, before);
      expect(fetches['narrow'], greaterThan(1));
      await tester.pumpWidget(const SizedBox());
    });

    for (final layout in [true, false]) {
      queryWidgetTest(
          'V4-1: a ${layout ? 'LayoutBuilder' : 'Builder'} whose key comes '
          'from an InheritedWidget: ${layout ? 'additive, as documented' : 'released'}',
          (tester, client) async {
        for (var i = 0; i < 6; i++) {
          client.setQueryData<String>(QueryKey(<Object?>['item$i']), 'v$i');
        }
        final sel = ValueNotifier<int>(0);
        addTearDown(sel.dispose);
        Widget reader(BuildContext context) {
          final key = 'item${_RrSel.of(context)}';
          return Text('$key=${context.query(_rr(key)).dataOrNull}');
        }

        await tester.pumpWidget(app(
            client,
            _RrSelHolder(
                sel: sel,
                child: layout
                    ? LayoutBuilder(builder: (context, _) => reader(context))
                    : Builder(builder: reader))));
        await tester.pump();
        for (var i = 1; i < 6; i++) {
          sel.value = i;
          await tester.pump();
          await tester.pump();
          expect(find.text('item$i=v$i'), findsOneWidget);
        }
        // Flutter gives no hook for a LayoutBuilder rebuilt by a dependency:
        // its builder's run cannot be told from a nested builder's, so the
        // reads stay additive until it unmounts or its parent rebuilds it.
        expect(_rrHeld(client),
            layout ? {for (var i = 0; i < 6; i++) 'item$i'} : {'item5'});
        await tester.pumpWidget(app(client, const SizedBox()));
        await tester.pump();
        expect(_rrHeld(client), isEmpty);
      });
    }

    queryWidgetTest(
        'V4-2: a provider whose initState threw with initial: false leaves '
        'the client online', (tester, client) async {
      final online = StreamController<bool>();
      addTearDown(online.close);
      final status = OnlineStatus.stream(online.stream, initial: false);
      await tester
          .pumpWidget(app(client, const SizedBox(), onlineStatus: status));
      await tester.pumpWidget(const SizedBox());
      expect(client.onlineManager.isOnline(), isTrue);
      await tester
          .pumpWidget(app(client, const SizedBox(), onlineStatus: status));
      expect(tester.takeException(), isA<FlutterError>());
      expect(client.onlineManager.isOnline(), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(client, const SizedBox()));
      expect(client.onlineManager.isOnline(), isTrue);
    });

    queryWidgetTest(
        'V4-2: a failing provider leaves another speaker\'s verdict alone',
        (tester, client) async {
      final online = StreamController<bool>();
      addTearDown(online.close);
      online.stream.listen((_) {});
      await tester.pumpWidget(QueryClientProvider(
        client: client,
        observeAppLifecycle: false,
        onlineStatus: const OnlineStatus.fixed(false),
        child: QueryClientProvider(
          client: client,
          observeAppLifecycle: false,
          onlineStatus: OnlineStatus.stream(online.stream, initial: true),
          child: const SizedBox(),
        ),
      ));
      expect(tester.takeException(), isA<FlutterError>());
      // The failing one applied `initial: true` before it threw; the verdict
      // that stands is not its to restore.
      await tester.pumpWidget(QueryClientProvider(
        client: client,
        observeAppLifecycle: false,
        onlineStatus: const OnlineStatus.fixed(false),
        child: const SizedBox(),
      ));
      expect(client.onlineManager.isOnline(), isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(client.onlineManager.isOnline(), isTrue);
    });

    queryWidgetTest(
        'V4-3: rows read inline with one key and function but their own '
        'scope assert', (tester, client) async {
      await tester.pumpWidget(app(
          client,
          Builder(
              builder: (context) => Column(children: [
                    for (final id in [1, 2])
                      Text(
                          '${context.mutation(MutationOptions<String, int, Object?>(
                                mutationKey:
                                    QueryKey(const <Object?>['delete']),
                                mutationFn: _rrSave,
                                scope: MutationScope('task-$id'),
                              )).value.status}'),
                  ]))));
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect('$error', contains('id:'));
    });

    queryWidgetTest(
        'V4-3: the same scope, retry and network mode read twice are one '
        'mutation', (tester, client) async {
      late MutationController<String, int, Object?> a, b;
      MutationOptions<String, int, Object?> options() => MutationOptions(
            mutationKey: QueryKey(const <Object?>['delete']),
            mutationFn: _rrSave,
            scope: const MutationScope('tasks'),
            retry: RetryPolicy.times(2),
            networkMode: NetworkMode.always,
            gcTime: const GcTime.duration(Duration(minutes: 1)),
          );
      await tester.pumpWidget(app(client, Builder(builder: (context) {
        a = context.mutation(options());
        b = context.mutation(options());
        return const SizedBox();
      })));
      expect(tester.takeException(), isNull);
      expect(identical(a, b), isTrue);
    });

    queryWidgetTest(
        'V4-4: a reader handed a new widget in the epoch its generation '
        'opened keeps its own reads through a nested-only frame',
        (tester, client) async {
      for (final k in ['w', 'inner0', 'inner1']) {
        client.setQueryData<String>(QueryKey(<Object?>[k]), '${k}0');
      }
      final tick = ValueNotifier<int>(0);
      final parent = ValueNotifier<int>(0);
      addTearDown(tick.dispose);
      addTearDown(parent.dispose);
      var show = false;
      late StateSetter setHost;
      await tester
          .pumpWidget(app(client, StatefulBuilder(builder: (context, set) {
        setHost = set;
        if (!show) return const SizedBox();
        return ValueListenableBuilder<int>(
            valueListenable: parent,
            builder: (_, __, ___) => _RrOwnAndNested(tick));
      })));
      await tester.pump();
      // What runApp's attach does: a build outside any frame, sharing its
      // epoch with the first frame, in which the parent rebuilds.
      setHost(() => show = true);
      tester.binding.buildOwner!.buildScope(tester.binding.rootElement!);
      parent.value++;
      await tester.pump();
      await tester.pump();
      tick.value = 1;
      await tester.pump();
      await tester.pump();
      expect(_rrHeld(client), contains('w'));
      client.setQueryData<String>(QueryKey(const <Object?>['w']), 'w1');
      await tester.pump();
      await tester.pump();
      expect(find.text('w=w1'), findsOneWidget);
    });
  });
}
