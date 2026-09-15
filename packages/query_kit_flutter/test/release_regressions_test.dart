/// Binding regressions reproduced by the 2026-09-16 deep review.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';

void main() {
  for (final useStream in [false, true]) {
    queryWidgetTest(
        'initial offline ${useStream ? 'stream' : 'fixed'} status keeps '
        'restored writes queued until reconnect', (tester, client) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final source = useStream ? StreamController<bool>() : null;
      if (source != null) addTearDown(source.close);
      var physicallyOnline = false;
      var attempts = 0;
      var serverWrites = 0;
      final queuedWrite = client.mutationCache.build<int, int, void>(
        client,
        client.defaultMutationOptions(MutationOptions<int, int, void>(
          mutationFn: (value) {
            attempts++;
            if (!physicallyOnline) throw StateError('No connection to server');
            serverWrites++;
            return value;
          },
        )),
        state: const MutationState<int, int, void>(
          status: MutationStatus.pending,
          hasVariables: true,
          variables: 42,
          isPaused: true,
        ),
      );
      Widget view(bool online) => QueryClientProvider(
            client: client,
            onlineStatus: useStream
                ? OnlineStatus.stream(source!.stream, initial: false)
                : OnlineStatus.fixed(online),
            child: const SizedBox(),
          );

      await tester.pumpWidget(view(false));
      await tester.pumpAndSettle();
      expect(attempts, 0);
      expect(queuedWrite.state.status, MutationStatus.pending);
      expect(queuedWrite.state.isPaused, isTrue);

      physicallyOnline = true;
      if (useStream) {
        source!.add(true);
      } else {
        await tester.pumpWidget(view(true));
      }
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(serverWrites, 1);
      expect(queuedWrite.state.status, MutationStatus.success);
    });
  }

  for (final replaceClient in [false, true]) {
    queryWidgetTest(
        'changing stream initial keeps the subscription and latest verdict '
        '${replaceClient ? 'on a new client' : 'on the same client'}',
        (tester, client) async {
      final source = StreamController<bool>();
      addTearDown(source.close);
      var listens = 0;
      source.onListen = () => listens++;
      Widget view(QueryClient current, bool initial) => QueryClientProvider(
            client: current,
            observeAppLifecycle: false,
            onlineStatus: OnlineStatus.stream(source.stream, initial: initial),
            child: const SizedBox(),
          );

      await tester.pumpWidget(view(client, false));
      source.add(false);
      await tester.pump();

      final current = replaceClient ? tester.adopt(QueryClient()) : client;
      await tester.pumpWidget(view(current, true));
      expect(tester.takeException(), isNull);
      expect(listens, 1);
      expect(current.onlineManager.isOnline(), isFalse);

      // A later client must also inherit the event retained across the
      // metadata-only update, rather than the new initial assumption.
      final next = tester.adopt(QueryClient());
      await tester.pumpWidget(view(next, true));
      expect(next.onlineManager.isOnline(), isFalse);
      expect(listens, 1);
      source.add(true);
      await tester.pump();
      expect(next.onlineManager.isOnline(), isTrue);
      expect(current.onlineManager.isOnline(), isFalse);
    });
  }

  for (final reorder in [false, true]) {
    for (final seed in [false, true]) {
      queryWidgetTest(
          '${seed ? 'seeded' : 'empty'} equal collection '
          '${reorder ? 'reorder' : 'replacement'} updates the rendered refetch '
          'target', (tester, client) async {
        final a = QueryKey(['a']);
        final b = QueryKey(['b']);
        if (seed) {
          final stamp = DateTime.utc(2025);
          client.setQueryData<int>(a, 0, updatedAt: stamp);
          client.setQueryData<int>(b, 0, updatedAt: stamp);
        }
        final calls = <String>[];
        QueryObserverOptions<int> options(QueryKey key, String name) =>
            QueryObserverOptions<int>(
              queryKey: key,
              queryFn: (_) {
                calls.add(name);
                return 0;
              },
              enabled: Enabled.no,
              staleTime: StaleTime.infinite,
            );
        final oa = options(a, 'a');
        final ob = options(b, 'b');
        final initial = reorder ? [oa, ob] : [oa];
        final controller = QueriesController<int, int>(client, initial);
        var builds = 0;
        try {
          await tester.pumpApp(
            client,
            ValueListenableBuilder<List<QueryResult<int>>>(
              valueListenable: controller,
              builder: (_, results, __) {
                builds++;
                return TextButton(
                  onPressed: () => results.first.refetch(),
                  child: const Text('Refresh first'),
                );
              },
            ),
          );
          await tester.pumpAndSettle();
          final initialBuilds = builds;
          controller.setQueries(initial);
          await tester.pumpAndSettle();
          expect(builds, initialBuilds);

          controller.setQueries(reorder ? [ob, oa] : [ob]);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Refresh first'));
          await tester.pumpAndSettle();
          expect(calls, ['b']);
        } finally {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
      });
    }
  }
}
